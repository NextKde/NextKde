#include "sourcehost/plugin_runtime.h"
#include "platform/windows_crypto.h"

#include <QFile>
#include <QFileInfo>
#include <QCryptographicHash>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QJsonParseError>
#include <QJsonValue>
#include <QHttpMultiPart>
#include <QNetworkAccessManager>
#include <QNetworkProxy>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QRandomGenerator>
#include <QScopeGuard>
#include <QSet>
#include <QUrl>
#include <QUrlQuery>
#include <QTimer>

#include <quickjs.h>
#include <zlib.h>

#ifdef Q_OS_WIN
#include <windows.h>
#include <bcrypt.h>
#include <wincrypt.h>
#endif

#include <chrono>
#include <exception>
#include <functional>
#include <memory>
#include <optional>
#include <utility>
#include <vector>

static void initializeBrowserResources() {
    Q_INIT_RESOURCE(sourcehost_browser);
}

namespace listenfree::sourcehost {

namespace {

constexpr qsizetype MaxPluginBytes = 1024 * 1024;
constexpr qsizetype MaxPendingPluginRequests = 256;
constexpr qsizetype MaxUrlBytes = 2048;
constexpr qsizetype MaxNetworkUrlBytes = 64 * 1024;
constexpr qsizetype MaxPendingNetworkRequests = 64;
constexpr qsizetype MaxNetworkRequestBytes = 8 * 1024 * 1024;
constexpr qsizetype MaxNetworkResponseBytes = 8 * 1024 * 1024;
constexpr qsizetype MaxProtocolFrameBytes = 1024 * 1024 + 4;

#ifdef Q_OS_WIN
using platform::aesEncryptBytes;
using platform::rsaEncryptBytes;
#endif

class QuickJsEngine final {
public:
    struct Callbacks {
        std::function<void(const QString&, const QString&)> eventSent;
        std::function<void(const QString&, const QString&)> requestResolved;
        std::function<void(const QString&, const QString&)> requestRejected;
        std::function<QString(const QString&, const QString&, const QString&)> requestStarted;
        std::function<void(const QString&)> requestAborted;
        std::function<void(const QString&)> timerStarted;
        std::function<void(const QString&, const QString&, bool)> timerFinished;
    };

    explicit QuickJsEngine(QObject* timerOwner, Callbacks callbacks)
        : callbacks_(std::move(callbacks)), timerOwner_(timerOwner) {
        runtime_ = JS_NewRuntime();
        if (!runtime_) return;
        JS_SetMemoryLimit(runtime_, 96U * 1024U * 1024U);
        JS_SetMaxStackSize(runtime_, 1024U * 1024U);
        JS_SetCanBlock(runtime_, false);
        JS_SetInterruptHandler(runtime_, &QuickJsEngine::interrupt, this);
        JS_SetHostPromiseRejectionTracker(runtime_, &QuickJsEngine::promiseRejectionTracker,
                                          this);
        context_ = JS_NewContext(runtime_);
        if (!context_) return;
        JS_SetContextOpaque(context_, this);
        valid_ = installBridge();
    }

    ~QuickJsEngine() {
        clearTimers();
        clearUnhandledRejections();
        if (context_) JS_FreeContext(context_);
        if (runtime_) JS_FreeRuntime(runtime_);
    }

    QuickJsEngine(const QuickJsEngine&) = delete;
    QuickJsEngine& operator=(const QuickJsEngine&) = delete;

    bool isValid() const { return valid_; }
    QString initializationError() const { return initializationError_; }
    bool hasPendingTasks() const { return !timers_.isEmpty(); }
    void setRequestContext(const QString& id) { requestContext_ = id; }
    void markInitialized() { scriptInitialized_ = true; }
    bool failureIsFatal() const { return executionInterrupted_ || jobLimitExceeded_ ||
        rejectionLimitExceeded_ || rejectionTrackerFailed_; }
    void cancelRequestTimers(const QString& id) {
        const auto ids = timers_.keys();
        for (const auto timerId : ids)
            if (timers_.value(timerId).requestId == id) removeTimer(timerId);
    }

    bool evaluate(const QString& script, const QString& filename, QString* error) {
        if (!context_) {
            if (error) *error = QStringLiteral("Unable to create JavaScript runtime.");
            return false;
        }
        const QByteArray source = script.toUtf8();
        const QByteArray sourceName = filename.toUtf8();
        beginExecution();
        JSValue result = JS_Eval(context_, source.constData(), static_cast<size_t>(source.size()),
                                 sourceName.constData(), JS_EVAL_TYPE_GLOBAL);
        return finishExecution(result, nullptr, error);
    }

    bool setScriptInfo(const QJsonObject& metadata, QString* error) {
        beginExecution();
        const QByteArray json = QJsonDocument(metadata).toJson(QJsonDocument::Compact);
        JSValue value = JS_ParseJSON(context_, json.constData(), static_cast<size_t>(json.size()),
                                     "currentScriptInfo");
        if (JS_IsException(value)) {
            if (error) *error = takeException(context_);
            endExecution();
            return false;
        }
        JSValue global = JS_GetGlobalObject(context_);
        JSValue lx = JS_GetPropertyStr(context_, global, "lx");
        const int result = JS_IsObject(lx)
                               ? JS_SetPropertyStr(context_, lx, "currentScriptInfo", value)
                               : -1;
        if (!JS_IsObject(lx)) JS_FreeValue(context_, value);
        JS_FreeValue(context_, lx);
        JS_FreeValue(context_, global);
        if (result < 0) {
            if (error) *error = takeException(context_);
            endExecution();
            return false;
        }
        endExecution();
        return true;
    }

    bool hasDispatch(QString* error) {
        if (!context_) return false;
        beginExecution();
        JSValue global = JS_GetGlobalObject(context_);
        JSValue dispatch = JS_GetPropertyStr(context_, global, "__lf_dispatch");
        if (JS_IsException(dispatch)) {
            JS_FreeValue(context_, dispatch);
            JS_FreeValue(context_, global);
            if (error) *error = takeException(context_);
            endExecution();
            return false;
        }
        const bool callable = JS_IsFunction(context_, dispatch);
        JS_FreeValue(context_, dispatch);
        JS_FreeValue(context_, global);
        const bool jobsSucceeded = pumpJobs(error);
        endExecution();
        return callable && jobsSucceeded;
    }

    bool dispatch(const QString& requestId, const QString& eventJson, QString* error) {
        bool accepted = false;
        if (!callGlobal(QStringLiteral("__lf_dispatch"), {requestId, eventJson}, &accepted, error)) {
            return false;
        }
        return accepted;
    }

    bool completeNetworkRequest(const QString& requestId, const QString& errorMessage,
                                const QString& packetJson, QString* error) {
        return callGlobal(QStringLiteral("__lf_request_complete"),
                          {requestId, errorMessage, packetJson}, nullptr, error);
    }

    bool dropNetworkRequest(const QString& requestId, QString* error) {
        return callGlobal(QStringLiteral("__lf_request_drop"), {requestId}, nullptr, error);
    }

    QString lastEventName(QString* error) {
        if (!context_) return {};
        beginExecution();
        JSValue global = JS_GetGlobalObject(context_);
        JSValue lastEvent = JS_GetPropertyStr(context_, global, "__lf_last_event");
        if (JS_IsException(lastEvent)) {
            JS_FreeValue(context_, lastEvent);
            JS_FreeValue(context_, global);
            if (error) *error = takeException(context_);
            endExecution();
            return {};
        }
        JSValue name = JS_IsObject(lastEvent)
                           ? JS_GetPropertyStr(context_, lastEvent, "name")
                           : JS_UNDEFINED;
        QString result;
        if (JS_IsException(name)) {
            if (error) *error = takeException(context_);
        } else if (JS_IsString(name)) {
            result = toQString(context_, name);
        }
        JS_FreeValue(context_, name);
        JS_FreeValue(context_, lastEvent);
        JS_FreeValue(context_, global);
        if ((error == nullptr || error->isEmpty()) && !pumpJobs(error)) result.clear();
        endExecution();
        return result;
    }

private:
    static constexpr int MaxPendingJobsPerTurn = 1024;
    static constexpr qsizetype MaxUnhandledRejections = 32;

    static QuickJsEngine* self(JSContext* context) {
        return static_cast<QuickJsEngine*>(JS_GetContextOpaque(context));
    }

    static QString toQString(JSContext* context, JSValueConst value, bool* ok = nullptr) {
        size_t size = 0;
        const char* text = JS_ToCStringLen(context, &size, value);
        if (!text) {
            if (ok) *ok = false;
            return {};
        }
        const QString result = QString::fromUtf8(text, static_cast<qsizetype>(size));
        JS_FreeCString(context, text);
        if (ok) *ok = true;
        return result;
    }

    static JSValue fromQString(JSContext* context, const QString& value) {
        const QByteArray encoded = value.toUtf8();
        return JS_NewStringLen(context, encoded.constData(), static_cast<size_t>(encoded.size()));
    }

    static QString takeException(JSContext* context) {
        JSValue exception = JS_GetException(context);
        QString message = toQString(context, exception).left(4096);
        QString stackText;
        if (JS_IsObject(exception)) {
            JSValue stack = JS_GetPropertyStr(context, exception, "stack");
            if (JS_IsException(stack)) {
                JS_FreeValue(context, stack);
                JSValue nested = JS_GetException(context);
                JS_FreeValue(context, nested);
            } else {
                if (JS_IsString(stack)) stackText = toQString(context, stack).left(4096);
                JS_FreeValue(context, stack);
            }
        }
        JS_FreeValue(context, exception);
        if (!stackText.isEmpty() && stackText != message) {
            if (!message.isEmpty()) message += QStringLiteral(" | ");
            message += stackText.left(qMax(0, 4096 - message.size()));
        }
        return message.isEmpty() ? QStringLiteral("JavaScript execution failed.") : message.left(4096);
    }

    static bool strings(JSContext* context, int argc, JSValueConst* argv, int count,
                        QString* output) {
        if (argc < count) {
            JS_ThrowTypeError(context, "missing bridge argument");
            return false;
        }
        for (int index = 0; index < count; ++index) {
            bool ok = false;
            output[index] = toQString(context, argv[index], &ok);
            if (!ok) return false;
        }
        return true;
    }

    static JSValue sendEvent(JSContext* context, JSValueConst, int argc, JSValueConst* argv) {
        QString values[2];
        if (!strings(context, argc, argv, 2, values)) return JS_EXCEPTION;
        self(context)->callbacks_.eventSent(values[0], values[1]);
        return JS_UNDEFINED;
    }

    static JSValue resolveRequest(JSContext* context, JSValueConst, int argc, JSValueConst* argv) {
        QString values[2];
        if (!strings(context, argc, argv, 2, values)) return JS_EXCEPTION;
        self(context)->callbacks_.requestResolved(values[0], values[1]);
        return JS_UNDEFINED;
    }

    static JSValue rejectRequest(JSContext* context, JSValueConst, int argc, JSValueConst* argv) {
        QString values[2];
        if (!strings(context, argc, argv, 2, values)) return JS_EXCEPTION;
        self(context)->callbacks_.requestRejected(values[0], values[1]);
        return JS_UNDEFINED;
    }

    static JSValue startRequest(JSContext* context, JSValueConst, int argc, JSValueConst* argv) {
        QString values[3];
        if (!strings(context, argc, argv, 3, values)) return JS_EXCEPTION;
        const QString error = self(context)->callbacks_.requestStarted(values[0], values[1], values[2]);
        if (!error.isEmpty()) {
            const QByteArray encoded = error.toUtf8();
            return JS_ThrowTypeError(context, "%s", encoded.constData());
        }
        return JS_UNDEFINED;
    }

    static JSValue abortRequest(JSContext* context, JSValueConst, int argc, JSValueConst* argv) {
        QString value;
        if (!strings(context, argc, argv, 1, &value)) return JS_EXCEPTION;
        self(context)->callbacks_.requestAborted(value);
        return JS_UNDEFINED;
    }

    struct TimerEntry {
        QTimer* timer{nullptr};
        JSValue callback{JS_UNDEFINED};
        std::vector<JSValue> arguments;
        QString requestId;
    };

    static JSValue setTimeout(JSContext* context, JSValueConst, int argc, JSValueConst* argv) {
        auto* engine = self(context);
        if (argc < 1 || !JS_IsFunction(context, argv[0]))
            return JS_ThrowTypeError(context, "setTimeout requires a function");
        if (engine->timers_.size() >= 64)
            return JS_ThrowRangeError(context, "too many pending timers");
        int32_t delay = 0;
        if (argc > 1 && JS_ToInt32(context, &delay, argv[1]) < 0) return JS_EXCEPTION;
        const int id = ++engine->nextTimerId_;
        TimerEntry entry;
        entry.timer = new QTimer(engine->timerOwner_);
        entry.timer->setSingleShot(true);
        entry.callback = JS_DupValue(context, argv[0]);
        entry.requestId = engine->requestContext_;
        for (int index = 2; index < argc; ++index)
            entry.arguments.push_back(JS_DupValue(context, argv[index]));
        QObject::connect(entry.timer, &QTimer::timeout, engine->timerOwner_,
                         [engine, id] { engine->fireTimer(id); });
        engine->timers_.insert(id, std::move(entry));
        engine->timers_[id].timer->start(qMax(0, delay));
        return JS_NewInt32(context, id);
    }

    static JSValue clearTimeout(JSContext* context, JSValueConst, int argc, JSValueConst* argv) {
        int32_t id = 0;
        if (argc > 0 && JS_ToInt32(context, &id, argv[0]) < 0) return JS_EXCEPTION;
        self(context)->removeTimer(id);
        return JS_UNDEFINED;
    }

    void removeTimer(int id) {
        if (!timers_.contains(id)) return;
        TimerEntry entry = timers_.take(id);
        entry.timer->stop();
        entry.timer->deleteLater();
        JS_FreeValue(context_, entry.callback);
        for (auto& argument : entry.arguments) JS_FreeValue(context_, argument);
    }

    void clearTimers() {
        for (auto it = timers_.begin(); it != timers_.end(); ++it) {
            it->timer->stop();
            delete it->timer;
            JS_FreeValue(context_, it->callback);
            for (auto& argument : it->arguments) JS_FreeValue(context_, argument);
        }
        timers_.clear();
    }

    void fireTimer(int id) {
        if (!timers_.contains(id)) return;
        TimerEntry entry = timers_.take(id);
        entry.timer->deleteLater();
        const auto previousContext = requestContext_;
        requestContext_ = entry.requestId;
        callbacks_.timerStarted(entry.requestId);
        beginExecution();
        JSValue result = JS_Call(context_, entry.callback, JS_UNDEFINED,
                                 static_cast<int>(entry.arguments.size()), entry.arguments.data());
        JS_FreeValue(context_, entry.callback);
        for (auto& argument : entry.arguments) JS_FreeValue(context_, argument);
        QString error;
        finishExecution(result, nullptr, &error);
        const bool fatal = failureIsFatal();
        requestContext_ = previousContext;
        callbacks_.timerStarted(previousContext);
        // Defer terminal delivery until JS_Call has released all engine values.
        // The callback may unload this engine; no engine pointer crosses turns.
        const auto report = callbacks_.timerFinished;
        QTimer::singleShot(0, timerOwner_, [report, requestId = entry.requestId, error, fatal] {
            report(requestId, error, fatal);
        });
    }

    static JSValue md5(JSContext* context, JSValueConst, int argc, JSValueConst* argv) {
        QString value;
        if (!strings(context, argc, argv, 1, &value)) return JS_EXCEPTION;
        return fromQString(context, QString::fromLatin1(
                                        QCryptographicHash::hash(QByteArray::fromBase64(value.toLatin1()), QCryptographicHash::Md5).toHex()));
    }

    static JSValue aesEncrypt(JSContext* context, JSValueConst, int argc, JSValueConst* argv) {
        QString values[4];
        if (!strings(context, argc, argv, 4, values)) return JS_EXCEPTION;
#ifdef Q_OS_WIN
        const QByteArray encrypted = aesEncryptBytes(QByteArray::fromBase64(values[0].toLatin1()),
                                                     QByteArray::fromBase64(values[2].toLatin1()),
                                                     QByteArray::fromBase64(values[3].toLatin1()), values[1]);
        return fromQString(context, encrypted.isEmpty() ? QString() : QString::fromLatin1(encrypted.toBase64()));
#else
        return fromQString(context, {});
#endif
    }

    static JSValue rsaEncrypt(JSContext* context, JSValueConst, int argc, JSValueConst* argv) {
        QString values[2];
        if (!strings(context, argc, argv, 2, values)) return JS_EXCEPTION;
#ifdef Q_OS_WIN
        const QByteArray encrypted = rsaEncryptBytes(QByteArray::fromBase64(values[0].toLatin1()), values[1]);
        return fromQString(context, encrypted.isEmpty() ? QString() : QString::fromLatin1(encrypted.toBase64()));
#else
        return fromQString(context, {});
#endif
    }

    static JSValue randomBytes(JSContext* context, JSValueConst, int argc, JSValueConst* argv) {
        int64_t size = -1;
        if (argc < 1 || JS_ToInt64(context, &size, argv[0]) < 0) return JS_EXCEPTION;
        if (size < 0 || size > 1024 * 1024) return JS_ThrowRangeError(context, "invalid random byte count");
        QByteArray bytes(static_cast<qsizetype>(size), Qt::Uninitialized);
        for (qsizetype i = 0; i < bytes.size(); ++i) {
            bytes[i] = static_cast<char>(QRandomGenerator::system()->generate() & 0xffU);
        }
        return fromQString(context, QString::fromLatin1(bytes.toBase64()));
    }

    static JSValue deflate(JSContext* context, JSValueConst, int argc, JSValueConst* argv) {
        QString base64;
        if (!strings(context, argc, argv, 1, &base64)) return JS_EXCEPTION;
        const QByteArray input = QByteArray::fromBase64(base64.toLatin1());
        uLongf outputSize = ::compressBound(static_cast<uLong>(input.size()));
        QByteArray output(static_cast<qsizetype>(outputSize), Qt::Uninitialized);
        if (::compress2(reinterpret_cast<Bytef*>(output.data()), &outputSize,
                        reinterpret_cast<const Bytef*>(input.constData()),
                        static_cast<uLong>(input.size()), Z_DEFAULT_COMPRESSION) != Z_OK) {
            return JS_ThrowTypeError(context, "deflate failed");
        }
        output.resize(static_cast<qsizetype>(outputSize));
        return fromQString(context, QString::fromLatin1(output.toBase64()));
    }

    static JSValue inflate(JSContext* context, JSValueConst, int argc, JSValueConst* argv) {
        QString base64;
        if (!strings(context, argc, argv, 1, &base64)) return JS_EXCEPTION;
        const QByteArray input = QByteArray::fromBase64(base64.toLatin1());
        uLongf outputSize = 64U * 1024U;
        while (outputSize <= static_cast<uLong>(MaxPluginBytes)) {
            QByteArray output(static_cast<qsizetype>(outputSize), Qt::Uninitialized);
            uLongf actualSize = outputSize;
            const int result = ::uncompress(reinterpret_cast<Bytef*>(output.data()), &actualSize,
                                             reinterpret_cast<const Bytef*>(input.constData()),
                                             static_cast<uLong>(input.size()));
            if (result == Z_OK) {
                output.resize(static_cast<qsizetype>(actualSize));
                return fromQString(context, QString::fromLatin1(output.toBase64()));
            }
            if (result != Z_BUF_ERROR || outputSize == static_cast<uLong>(MaxPluginBytes)) break;
            outputSize = qMin(static_cast<uLong>(MaxPluginBytes), outputSize * 2U);
        }
        return JS_ThrowTypeError(context, "inflate failed or output exceeds the limit");
    }

    enum BridgeFunction {
        SendEvent,
        ResolveRequest,
        RejectRequest,
        StartRequest,
        AbortRequest,
        SetTimeout,
        ClearTimeout,
        Md5,
        AesEncrypt,
        RsaEncrypt,
        RandomBytes,
        Deflate,
        Inflate,
    };

    static JSValue guardedBridgeCall(JSContext* context, JSValueConst thisValue,
                                     int argc, JSValueConst* argv, int function) noexcept {
        try {
            switch (function) {
            case SendEvent: return sendEvent(context, thisValue, argc, argv);
            case ResolveRequest: return resolveRequest(context, thisValue, argc, argv);
            case RejectRequest: return rejectRequest(context, thisValue, argc, argv);
            case StartRequest: return startRequest(context, thisValue, argc, argv);
            case AbortRequest: return abortRequest(context, thisValue, argc, argv);
            case SetTimeout: return setTimeout(context, thisValue, argc, argv);
            case ClearTimeout: return clearTimeout(context, thisValue, argc, argv);
            case Md5: return md5(context, thisValue, argc, argv);
            case AesEncrypt: return aesEncrypt(context, thisValue, argc, argv);
            case RsaEncrypt: return rsaEncrypt(context, thisValue, argc, argv);
            case RandomBytes: return randomBytes(context, thisValue, argc, argv);
            case Deflate: return deflate(context, thisValue, argc, argv);
            case Inflate: return inflate(context, thisValue, argc, argv);
            default: return JS_ThrowInternalError(context, "unknown native bridge function");
            }
        } catch (const std::exception& error) {
            return JS_ThrowInternalError(context, "native bridge failure: %s", error.what());
        } catch (...) {
            return JS_ThrowInternalError(context, "native bridge failure");
        }
    }

    static int interrupt(JSRuntime*, void* opaque) {
        auto* engine = static_cast<QuickJsEngine*>(opaque);
        if (!engine->executionActive_ || std::chrono::steady_clock::now() < engine->deadline_) return 0;
        engine->executionInterrupted_ = true;
        return 1;
    }

    static void promiseRejectionTracker(JSContext* context, JSValueConst promise,
                                        JSValueConst reason, bool isHandled,
                                        void* opaque) noexcept {
        auto* engine = static_cast<QuickJsEngine*>(opaque);
        try {
            const auto key = reinterpret_cast<quintptr>(JS_VALUE_GET_PTR(promise));
            if (isHandled) {
                const auto it = engine->unhandledRejections_.find(key);
                if (it != engine->unhandledRejections_.end()) {
                    JS_FreeValue(context, it->promise);
                    engine->unhandledRejections_.erase(it);
                }
                return;
            }
            const auto existing = engine->unhandledRejections_.find(key);
            if (existing != engine->unhandledRejections_.end()) return;
            if (engine->unhandledRejections_.size() >= MaxUnhandledRejections) {
                engine->rejectionLimitExceeded_ = true;
                return;
            }

            QString message;
            JSValue stringValue = JS_ToString(context, reason);
            const auto freeString = qScopeGuard([context, &stringValue] {
                JS_FreeValue(context, stringValue);
            });
            if (JS_IsException(stringValue)) {
                JSValue conversionError = JS_GetException(context);
                JS_FreeValue(context, conversionError);
                message = QStringLiteral("JavaScript promise rejected with a non-string value.");
            } else {
                bool converted = false;
                message = toQString(context, stringValue, &converted).left(4096);
                if (!converted) {
                    JSValue conversionError = JS_GetException(context);
                    JS_FreeValue(context, conversionError);
                    message = QStringLiteral("JavaScript promise rejection could not be converted.");
                }
            }
            JSValue rootedPromise = JS_DupValue(context, promise);
            try {
                engine->unhandledRejections_.insert(
                    key, UnhandledRejection{rootedPromise, std::move(message)});
            } catch (...) {
                JS_FreeValue(context, rootedPromise);
                throw;
            }
        } catch (...) {
            engine->rejectionTrackerFailed_ = true;
        }
    }

    void clearUnhandledRejections() {
        if (context_) {
            for (auto& rejection : unhandledRejections_) {
                JS_FreeValue(context_, rejection.promise);
            }
        }
        unhandledRejections_.clear();
        rejectionLimitExceeded_ = false;
        rejectionTrackerFailed_ = false;
    }

    void beginExecution() {
        if (executionDepth_++ == 0) {
            executionActive_ = true;
            executionInterrupted_ = false;
            jobLimitExceeded_ = false;
            deadline_ = std::chrono::steady_clock::now() + std::chrono::seconds(1);
        }
    }

    void endExecution() {
        if (executionDepth_ > 0 && --executionDepth_ == 0) executionActive_ = false;
    }

    bool pumpJobs(QString* error) {
        const auto reportUnhandledRejection = [this, error] {
            if (rejectionTrackerFailed_) {
                if (error) *error = QStringLiteral("Promise rejection tracking failed.");
                return false;
            }
            if (rejectionLimitExceeded_) {
                if (error) *error = QStringLiteral("Too many unhandled Promise rejections.");
                return false;
            }
            if (unhandledRejections_.isEmpty()) return true;
            // Match LX preload onError: update checks and other background
            // rejections after `inited` do not invalidate a registered source.
            if (scriptInitialized_) {
                clearUnhandledRejections();
                return true;
            }
            if (error) {
                *error = QStringLiteral("Unhandled Promise rejection: %1")
                             .arg(unhandledRejections_.constBegin()->message);
            }
            return false;
        };
        for (int count = 0; count < MaxPendingJobsPerTurn; ++count) {
            JSContext* jobContext = nullptr;
            const int result = JS_ExecutePendingJob(runtime_, &jobContext);
            if (result == 0) return reportUnhandledRejection();
            if (result < 0) {
                if (error) *error = takeException(jobContext ? jobContext : context_);
                return false;
            }
        }
        if (JS_IsJobPending(runtime_)) {
            jobLimitExceeded_ = true;
            if (error) *error = QStringLiteral("JavaScript Promise job limit exceeded.");
            return false;
        }
        return reportUnhandledRejection();
    }

    bool callGlobal(const QString& name, const QStringList& arguments, bool* booleanResult,
                    QString* error) {
        if (!context_) {
            if (error) *error = QStringLiteral("JavaScript runtime is unavailable.");
            return false;
        }
        beginExecution();
        JSValue global = JS_GetGlobalObject(context_);
        const QByteArray encodedName = name.toUtf8();
        JSValue function = JS_GetPropertyStr(context_, global, encodedName.constData());
        if (JS_IsException(function)) {
            JS_FreeValue(context_, function);
            JS_FreeValue(context_, global);
            if (error) *error = takeException(context_);
            endExecution();
            return false;
        }
        if (!JS_IsFunction(context_, function)) {
            JS_FreeValue(context_, function);
            JS_FreeValue(context_, global);
            endExecution();
            if (error) *error = QStringLiteral("JavaScript bridge function is unavailable: %1.").arg(name);
            return false;
        }
        std::vector<JSValue> values;
        values.reserve(static_cast<size_t>(arguments.size()));
        for (const auto& argument : arguments) {
            JSValue value = fromQString(context_, argument);
            if (JS_IsException(value)) {
                for (auto& previous : values) JS_FreeValue(context_, previous);
                JS_FreeValue(context_, value);
                JS_FreeValue(context_, function);
                JS_FreeValue(context_, global);
                if (error) *error = takeException(context_);
                endExecution();
                return false;
            }
            values.push_back(value);
        }
        JSValue result = JS_Call(context_, function, global, static_cast<int>(values.size()), values.data());
        for (auto& value : values) JS_FreeValue(context_, value);
        JS_FreeValue(context_, function);
        JS_FreeValue(context_, global);
        return finishExecution(result, booleanResult, error);
    }

    bool finishExecution(JSValue result, bool* booleanResult, QString* error) {
        QString scriptError;
        if (JS_IsException(result)) {
            scriptError = takeException(context_);
        } else if (booleanResult) {
            const int converted = JS_ToBool(context_, result);
            if (converted < 0) scriptError = takeException(context_);
            else *booleanResult = converted != 0;
        }
        JS_FreeValue(context_, result);
        // A callback may settle a request and then throw. Browser event loops
        // still run its microtasks; otherwise that completed request hangs.
        // Fatal resource exhaustion must never get another execution budget.
        QString jobError;
        const bool jobsSucceeded = !failureIsFatal() && pumpJobs(&jobError);
        if (error) *error = jobError.isEmpty() ? scriptError : jobError;
        endExecution();
        return scriptError.isEmpty() && jobsSucceeded;
    }

    bool installBridge() {
        JSValue bridge = JS_NewObject(context_);
        if (JS_IsException(bridge)) {
            initializationError_ = takeException(context_);
            return false;
        }
        struct FunctionEntry { const char* name; int function; int arguments; };
        const FunctionEntry functions[] = {
            {"sendEvent", SendEvent, 2},
            {"resolveRequest", ResolveRequest, 2},
            {"rejectRequest", RejectRequest, 2},
            {"startRequest", StartRequest, 3},
            {"abortRequest", AbortRequest, 1},
            {"setTimeout", SetTimeout, 2},
            {"clearTimeout", ClearTimeout, 1},
            {"md5", Md5, 1},
            {"aesEncrypt", AesEncrypt, 4},
            {"rsaEncrypt", RsaEncrypt, 2},
            {"randomBytes", RandomBytes, 1},
            {"deflate", Deflate, 1},
            {"inflate", Inflate, 1},
        };
        for (const auto& function : functions) {
            JSValue callback = JS_NewCFunctionMagic(
                context_, &QuickJsEngine::guardedBridgeCall, function.name,
                function.arguments, JS_CFUNC_generic_magic, function.function);
            if (JS_IsException(callback) ||
                JS_SetPropertyStr(context_, bridge, function.name, callback) < 0) {
                if (JS_IsException(callback)) JS_FreeValue(context_, callback);
                JS_FreeValue(context_, bridge);
                initializationError_ = takeException(context_);
                return false;
            }
        }
        JSValue global = JS_GetGlobalObject(context_);
        if (JS_IsException(global)) {
            JS_FreeValue(context_, bridge);
            JS_FreeValue(context_, global);
            initializationError_ = takeException(context_);
            return false;
        }
        const int installed = JS_SetPropertyStr(context_, global, "__lf_bridge", bridge);
        JS_FreeValue(context_, global);
        if (installed < 0) {
            initializationError_ = takeException(context_);
            return false;
        }
        return true;
    }

    Callbacks callbacks_;
    QObject* timerOwner_{nullptr};
    QHash<int, TimerEntry> timers_;
    int nextTimerId_{0};
    QString requestContext_;
    bool scriptInitialized_{false};
    bool executionInterrupted_{false};
    bool jobLimitExceeded_{false};
    struct UnhandledRejection {
        JSValue promise{JS_UNDEFINED};
        QString message;
    };
    JSRuntime* runtime_{nullptr};
    JSContext* context_{nullptr};
    QString initializationError_;
    std::chrono::steady_clock::time_point deadline_{};
    QHash<quintptr, UnhandledRejection> unhandledRejections_;
    int executionDepth_{0};
    bool valid_{false};
    bool executionActive_{false};
    bool rejectionLimitExceeded_{false};
    bool rejectionTrackerFailed_{false};
};

const QString bootstrapScript = QStringLiteral(R"JS(
(function () {
    const root = this
    // Legacy sources execute in a browser preload and access the same global
    // object through window, self, and globalThis.
    root.globalThis = root
    root.window = root
    root.self = root
    // LX scripts routinely log from request callbacks. Logging must not turn a
    // recoverable network failure into a ReferenceError or leak signed URLs.
    root.console = Object.fromEntries(['log', 'info', 'warn', 'error', 'debug', 'trace',
        'time', 'timeLog', 'timeEnd', 'clear', 'assert', 'count', 'countReset',
        'dir', 'dirxml', 'table', 'group', 'groupCollapsed', 'groupEnd',
        'profile', 'profileEnd', 'timeStamp'].map(name => [name, () => {}]))
    root.setTimeout = (callback, delay, ...args) => __lf_bridge.setTimeout(callback, delay, ...args)
    root.clearTimeout = id => __lf_bridge.clearTimeout(id)
    const handlers = Object.create(null)
    const eventNames = { request: 'request', inited: 'inited', updateAlert: 'updateAlert' }
    let updateAlertSent = false
    root.lx = {
        version: '2.0.0',
        env: 'desktop',
        EVENT_NAMES: eventNames,
        currentScriptInfo: {},
        on(name, handler) {
            if (!(name in eventNames) || typeof handler !== 'function') {
                return Promise.reject(new Error('unsupported event handler'))
            }
            handlers[name] = handler
            return Promise.resolve(true)
        },
        send(name, data) {
            if (!(name in eventNames)) return Promise.reject(new Error('unsupported event'))
            if (name === eventNames.updateAlert) {
                if (updateAlertSent) return Promise.reject(new Error('The update alert can only be called once.'))
                if (!data || typeof data !== 'object' || typeof data.log !== 'string') {
                    return Promise.reject(new Error('log is required.'))
                }
                updateAlertSent = true
                data = {
                    log: data.log.length > 1024 ? data.log.substring(0, 1024) + '...' : data.log,
                    updateUrl: typeof data.updateUrl === 'string' && data.updateUrl.length <= 1024 &&
                               /^https?:\/\/[^\s]+$/.test(data.updateUrl) ? data.updateUrl : undefined
                }
            }
            root.__lf_last_event = { name, data: data === undefined ? null : data }
            if (__lf_bridge && typeof __lf_bridge.sendEvent === 'function') {
                __lf_bridge.sendEvent(name, JSON.stringify(data === undefined ? null : data))
            }
            return Promise.resolve(true)
        },
        request(url, options, callback) {
            if (typeof url !== 'string' || typeof callback !== 'function') {
                throw new Error('invalid request arguments')
            }
            const requestId = 'http-' + (++root.__lf_request_sequence)
            root.__lf_request_callbacks[requestId] = callback
            try {
                __lf_bridge.startRequest(requestId, url, JSON.stringify(options || {}, (key, value) =>
                    value && value.type === 'Buffer' && Array.isArray(value.data)
                        ? {__lf_base64: root.Buffer.from(value.data).toString('base64')} : value))
            } catch (error) {
                delete root.__lf_request_callbacks[requestId]
                throw error
            }
            return function () {
                delete root.__lf_request_callbacks[requestId]
                __lf_bridge.abortRequest(requestId)
            }
        }
    }
    root.__lf_request_sequence = 0
    root.__lf_request_callbacks = Object.create(null)
    const fromBase64 = value => root.Buffer.from(value, 'base64')
    root.lx.utils = {
        crypto: {
            md5(value) { return __lf_bridge.md5(root.Buffer.from(value).__lf_base64) },
            randomBytes(size) { return fromBase64(__lf_bridge.randomBytes(size)) },
            aesEncrypt(value, mode, key, iv) {
                const result = __lf_bridge.aesEncrypt(root.Buffer.from(value).__lf_base64, mode,
                    root.Buffer.from(key).__lf_base64, iv == null ? '' : root.Buffer.from(iv).__lf_base64)
                if (!result) throw new Error('aesEncrypt failed')
                return fromBase64(result)
            },
            rsaEncrypt(value, key) {
                if (typeof key !== 'string') {
                    throw new Error('invalid RSA arguments')
                }
                const result = __lf_bridge.rsaEncrypt(root.Buffer.from(value).__lf_base64, key)
                if (!result) throw new Error('rsaEncrypt failed')
                return fromBase64(result)
            }
        },
        buffer: {
            from(value, encoding) { return root.Buffer.from(value, encoding) },
            bufToString(value, encoding) {
                return root.Buffer.from(value, 'binary').toString(encoding || 'utf8')
            }
        },
        zlib: {
            inflate(value) {
                try {
                    return Promise.resolve(fromBase64(__lf_bridge.inflate(root.Buffer.from(value).__lf_base64)))
                } catch (error) { return Promise.reject(error) }
            },
            deflate(value) {
                try {
                    return Promise.resolve(fromBase64(__lf_bridge.deflate(root.Buffer.from(value).__lf_base64)))
                } catch (error) { return Promise.reject(error) }
            }
        }
    }
    root.__lf_request_complete = function (requestId, error, packetJson) {
        const callback = root.__lf_request_callbacks[requestId]
        delete root.__lf_request_callbacks[requestId]
        if (typeof callback !== 'function') return false
        if (error) {
            callback(new Error(error), null, null)
            return true
        }
        let packet
        try { packet = JSON.parse(packetJson) } catch (parseError) {
            callback(parseError, null, null)
            return false
        }
        if (packet.response && typeof packet.response.rawBase64 === 'string') {
            packet.response.raw = root.Buffer.from(packet.response.rawBase64, 'base64')
        }
        if (packet.response) packet.response.body = packet.body
        callback(null, packet.response || null, packet.body)
        return true
    }
    root.__lf_request_drop = function (requestId) {
        if (typeof root.__lf_request_callbacks[requestId] !== 'function') return false
        delete root.__lf_request_callbacks[requestId]
        return true
    }
    root.__lf_dispatch = function (requestId, json) {
        let request
        try { request = JSON.parse(json) } catch (error) {
            __lf_bridge.rejectRequest(requestId, String(error))
            return false
        }
        const handler = handlers[eventNames.request]
        if (typeof handler !== 'function') {
            __lf_bridge.rejectRequest(requestId, 'request handler is not registered')
            return false
        }
        let result
        try { result = handler(request) } catch (error) {
            __lf_bridge.rejectRequest(requestId, String(error && error.message || error))
            return false
        }
        Promise.resolve(result).then(
            value => __lf_bridge.resolveRequest(requestId, JSON.stringify(value)),
            error => __lf_bridge.rejectRequest(requestId, String(error && error.message || error)))
        return true
    }
})()
)JS");

QJsonObject errorPayload(const QString& code, const QString& message) {
    return {{QStringLiteral("code"), code}, {QStringLiteral("message"), message}};
}

bool containsString(const QJsonArray& values, const QString& expected) {
    for (const auto& value : values) {
        if (value.toString() == expected) return true;
    }
    return false;
}



std::optional<QByteArray> decodePluginSource(const QByteArray& encoded, QString* error) {
    if (!encoded.startsWith("gz_")) return encoded;

    const QByteArray compressed = QByteArray::fromBase64(encoded.mid(3));
    if (compressed.isEmpty()) {
        if (error) *error = QStringLiteral("Compressed plugin payload is not valid base64.");
        return std::nullopt;
    }

    // The legacy desktop API stores zlib.deflate output after the `gz_` marker.
    // Decode into a bounded buffer so a malformed or adversarial script cannot
    // turn the SourceHost into an unbounded decompressor.
    constexpr uLong MaxOutput = static_cast<uLong>(MaxPluginBytes);
    uLong outputSize = 64U * 1024U;
    while (outputSize <= MaxOutput) {
        QByteArray output(static_cast<qsizetype>(outputSize), Qt::Uninitialized);
        uLong actualSize = outputSize;
        const int result = ::uncompress(reinterpret_cast<Bytef*>(output.data()), &actualSize,
                                        reinterpret_cast<const Bytef*>(compressed.constData()),
                                        static_cast<uLong>(compressed.size()));
        if (result == Z_OK) {
            output.resize(static_cast<qsizetype>(actualSize));
            return output;
        }
        if (result != Z_BUF_ERROR || outputSize == MaxOutput) break;
        outputSize = qMin(MaxOutput, outputSize * 2U);
    }
    if (error) *error = QStringLiteral("Compressed plugin payload is invalid or exceeds the 1 MiB limit.");
    return std::nullopt;
}

QJsonObject parseScriptMetadata(const QByteArray& source) {
    const QString text = QString::fromUtf8(source);
    const auto headerMatch = QRegularExpression(QStringLiteral(R"(^/\*[\s\S]*?\*/)"))
                                 .match(text);
    QJsonObject metadata;
    const QRegularExpression entry(QStringLiteral(R"(^\s?\*\s?@(\w+)\s+(.+)$)"));
    if (headerMatch.hasMatch()) {
        const QStringList lines = headerMatch.captured(0).split(QRegularExpression(QStringLiteral("\\r?\\n")));
        for (const auto& line : lines) {
            const auto match = entry.match(line);
            if (!match.hasMatch()) continue;
            const QString key = match.captured(1);
            const QString value = match.captured(2).trimmed();
            if (key == QStringLiteral("name")) metadata.insert(key, value.left(24));
            else if (key == QStringLiteral("description")) metadata.insert(key, value.left(36));
            else if (key == QStringLiteral("author")) metadata.insert(key, value.left(56));
            else if (key == QStringLiteral("homepage")) metadata.insert(key, value.left(1024));
            else if (key == QStringLiteral("version")) metadata.insert(key, value.left(36));
        }
    }
    for (const auto& key : {QStringLiteral("name"), QStringLiteral("description"),
                            QStringLiteral("author"), QStringLiteral("homepage"),
                            QStringLiteral("version")}) {
        if (!metadata.contains(key)) metadata.insert(key, QString());
    }
    metadata.insert(QStringLiteral("rawScript"), text);
    return metadata;
}

} // namespace

class PluginRuntime::Impl final {
public:
    explicit Impl(PluginRuntime& owner)
        : owner_(owner), network_(std::make_unique<QNetworkAccessManager>(&owner)), loadDeadline_(&owner) {
        loadDeadline_.setSingleShot(true);
        QObject::connect(&loadDeadline_, &QTimer::timeout, &owner_, [this] {
            if (loadingRequest_.isEmpty()) return;
            const auto id = loadingRequest_;
            reset();
            respondError(id, QStringLiteral("plugin.init-timeout"), QStringLiteral("音源初始化超时"));
        });
    }

    void handle(const SourceMessage& request) {
        switch (request.type) {
        case MessageType::LoadPlugin: load(request); break;
        case MessageType::UnloadPlugin: unload(request); break;
        case MessageType::Initialize: initialize(request); break;
        case MessageType::ResolveMusicUrl: resolve(request); break;
        case MessageType::ResolveLyric: resolve(request); break;
        case MessageType::ResolvePic: resolve(request); break;
        case MessageType::Cancel: cancel(request); break;
        default: respondError(request.requestId, QStringLiteral("plugin.unsupported-message"),
                               QStringLiteral("The plugin runtime does not handle this message."));
        }
    }

private:
    struct PendingRequest {
        QString source;
        QString action;
        QString type;
        QTimer* deadline{nullptr};
    };

    PendingRequest takePending(const QString& id) {
        auto request = pending_.take(id);
        if (request.deadline) {
            request.deadline->stop();
            request.deadline->deleteLater();
            request.deadline = nullptr;
        }
        return request;
    }

    void clearPending() {
        for (const auto& request : std::as_const(pending_)) {
            if (!request.deadline) continue;
            request.deadline->stop();
            request.deadline->deleteLater();
        }
        pending_.clear();
    }

    struct PendingTerminal {
        quint64 generation{0};
        QString requestId;
        QString value;
        bool resolved{false};
    };

    void queueTerminal(const QString& requestId, const QString& value, bool resolved) {
        if (!pending_.contains(requestId) || queuedTerminalRequestIds_.contains(requestId)) return;
        queuedTerminalRequestIds_.insert(requestId);
        pendingTerminals_.push_back({runtimeGeneration_, requestId, value, resolved});
    }

    void drainTerminals() {
        if (drainingTerminals_) return;
        drainingTerminals_ = true;
        const auto finishDrain = qScopeGuard([this] { drainingTerminals_ = false; });
        while (!pendingTerminals_.isEmpty()) {
            PendingTerminal terminal = pendingTerminals_.takeFirst();
            queuedTerminalRequestIds_.remove(terminal.requestId);
            if (terminal.generation != runtimeGeneration_) continue;
            if (terminal.resolved) handleResolved(terminal.requestId, terminal.value);
            else handleRejected(terminal.requestId, terminal.value);
        }
    }

    QString startNetworkRequest(const QString& requestId, const QString& url,
                                const QString& optionsJson) {
        if (!engine_ || pendingNetwork_.size() >= MaxPendingNetworkRequests) {
            return QStringLiteral("request capacity exceeded");
        }
        if (requestId.isEmpty() || requestId.toUtf8().size() > 256) {
            return QStringLiteral("invalid network request id");
        }
        if (pendingNetwork_.contains(requestId)) {
            return QStringLiteral("duplicate network request id");
        }
        const QUrl parsedUrl(url);
        if (!parsedUrl.isValid() ||
            (parsedUrl.scheme() != QStringLiteral("http") && parsedUrl.scheme() != QStringLiteral("https")) ||
            parsedUrl.host().isEmpty() || url.toUtf8().size() > MaxNetworkUrlBytes) {
            return QStringLiteral("invalid request URL");
        }
        if (optionsJson.toUtf8().size() > MaxNetworkRequestBytes) {
            return QStringLiteral("request options exceed the 8 MiB limit");
        }

        QJsonParseError parseError;
        const QJsonDocument optionsDocument = QJsonDocument::fromJson(optionsJson.toUtf8(), &parseError);
        const QJsonObject options = parseError.error == QJsonParseError::NoError && optionsDocument.isObject()
                                        ? optionsDocument.object()
                                        : QJsonObject{};
        QNetworkRequest networkRequest(parsedUrl);
        const QJsonObject headers = options.value(QStringLiteral("headers")).toObject();
        if (headers.size() > 128) {
            return QStringLiteral("request header count exceeded");
        }
        qsizetype headerBytes = 0;
        for (auto it = headers.begin(); it != headers.end(); ++it) {
            if (!it.value().isString()) continue;
            const QByteArray name = it.key().toUtf8();
            const QByteArray value = it.value().toString().toUtf8();
            headerBytes += name.size() + value.size();
            if (headerBytes > 64 * 1024 || name.contains('\r') || name.contains('\n') ||
                value.contains('\r') || value.contains('\n')) {
                return QStringLiteral("request headers are invalid or too large");
            }
            networkRequest.setRawHeader(name, value);
        }

        const int requestedTimeout = options.value(QStringLiteral("timeout")).toInt();
        const int timeout = requestedTimeout > 0 ? qMin(requestedTimeout, PluginOperationTimeoutMs)
                                                : PluginOperationTimeoutMs;
        networkRequest.setTransferTimeout(timeout);
        QByteArray body;
        QHttpMultiPart* multiPart = nullptr;
        if (options.value(QStringLiteral("body")).isString()) {
            body = options.value(QStringLiteral("body")).toString().toUtf8();
        } else if (options.value(QStringLiteral("body")).isObject()) {
            const auto bodyObject = options.value(QStringLiteral("body")).toObject();
            const auto encoded = bodyObject.value(QStringLiteral("__lf_base64")).toString();
            if (bodyObject.value(QStringLiteral("__lf_base64")).isString()) {
                body = QByteArray::fromBase64(encoded.toLatin1(), QByteArray::AbortOnBase64DecodingErrors);
            } else {
                // Legacy LX sources commonly pass a plain object for JSON bodies.
                body = QJsonDocument(bodyObject).toJson(QJsonDocument::Compact);
            }
        } else if (options.value(QStringLiteral("form")).isObject()) {
            const QJsonObject form = options.value(QStringLiteral("form")).toObject();
            for (auto it = form.begin(); it != form.end(); ++it) {
                if (!body.isEmpty()) body += '&';
                body += QUrl::toPercentEncoding(it.key()) + '=' +
                        QUrl::toPercentEncoding(it.value().toVariant().toString());
            }
            if (!networkRequest.hasRawHeader("Content-Type")) {
                networkRequest.setHeader(QNetworkRequest::ContentTypeHeader,
                                         QStringLiteral("application/x-www-form-urlencoded"));
            }
        } else if (options.value(QStringLiteral("formData")).isObject()) {
            const QJsonObject formData = options.value(QStringLiteral("formData")).toObject();
            if (formData.size() > 64) {
                return QStringLiteral("multipart field limit exceeded");
            }
            multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);
            qsizetype totalBytes = 0;
            for (auto it = formData.begin(); it != formData.end(); ++it) {
                if (it.key().isEmpty() || it.key().size() > 256 || it.key().contains(QLatin1Char('"')) ||
                    it.key().contains(QLatin1Char('\r')) || it.key().contains(QLatin1Char('\n'))) {
                    delete multiPart;
                    return QStringLiteral("invalid multipart field name");
                }
                QByteArray value;
                if (it.value().isObject() &&
                    it.value().toObject().value(QStringLiteral("__lf_base64")).isString()) {
                    value = QByteArray::fromBase64(
                        it.value().toObject().value(QStringLiteral("__lf_base64")).toString().toLatin1(),
                        QByteArray::AbortOnBase64DecodingErrors);
                } else if (it.value().isString()) {
                    value = it.value().toString().toUtf8();
                } else if (it.value().isBool()) {
                    value = it.value().toBool() ? QByteArrayLiteral("true") : QByteArrayLiteral("false");
                } else if (it.value().isDouble()) {
                    value = QByteArray::number(it.value().toDouble(), 'g', 16);
                } else {
                    value = QJsonDocument(QJsonObject{{QStringLiteral("value"), it.value()}})
                                .toJson(QJsonDocument::Compact);
                }
                totalBytes += value.size();
                if (totalBytes > MaxNetworkResponseBytes) {
                    delete multiPart;
                    return QStringLiteral("multipart body exceeds the 8 MiB limit");
                }
                QHttpPart part;
                part.setRawHeader("Content-Disposition",
                                  QByteArrayLiteral("form-data; name=\"") + it.key().toUtf8() +
                                      QByteArrayLiteral("\""));
                part.setBody(value);
                multiPart->append(part);
            }
        }
        if (!multiPart && body.size() > MaxNetworkRequestBytes) {
            return QStringLiteral("request body exceeds the 8 MiB limit");
        }

        const QByteArray method = options.value(QStringLiteral("method")).toString(QStringLiteral("get"))
                                      .toUpper()
                                      .toUtf8();
        static const QRegularExpression methodPattern(QStringLiteral("^[A-Z][A-Z0-9-]{0,31}$"));
        if (!methodPattern.match(QString::fromLatin1(method)).hasMatch()) {
            delete multiPart;
            return QStringLiteral("request method is invalid");
        }
        QNetworkReply* reply = nullptr;
        if (multiPart && method == "POST") reply = network_->post(networkRequest, multiPart);
        else if (multiPart && method == "PUT") reply = network_->put(networkRequest, multiPart);
        else if (multiPart) {
            delete multiPart;
            return QStringLiteral("multipart requires POST or PUT");
        } else if (method == "GET") reply = network_->get(networkRequest);
        else if (method == "POST") reply = network_->post(networkRequest, body);
        else if (method == "PUT") reply = network_->put(networkRequest, body);
        else reply = network_->sendCustomRequest(networkRequest, method, body);
        if (!reply) {
            delete multiPart;
            return QStringLiteral("unable to create network request");
        }
        if (multiPart) multiPart->setParent(reply);
        reply->setReadBufferSize(MaxNetworkResponseBytes + 1);
        connect(reply, &QNetworkReply::readyRead, &owner_, [reply] {
            if (reply->bytesAvailable() <= MaxNetworkResponseBytes) return;
            reply->setProperty("listenfreeResponseLimitExceeded", true);
            reply->abort();
        });
        pendingNetwork_.insert(requestId, reply);
        if (!activePluginRequest_.isEmpty()) {
            pluginNetworkRequests_[activePluginRequest_].insert(requestId);
            networkPluginRequests_.insert(requestId, activePluginRequest_);
        }
        connect(reply, &QNetworkReply::finished, &owner_, [this, requestId, reply] {
            finishNetworkRequest(requestId, reply);
        });
        return {};
    }

    void abortNetworkRequest(const QString& requestId) {
        const auto it = pendingNetwork_.find(requestId);
        if (it == pendingNetwork_.end()) return;
        QNetworkReply* reply = it.value();
        pendingNetwork_.erase(it);
        const QString pluginRequestId = networkPluginRequests_.take(requestId);
        if (!pluginRequestId.isEmpty()) {
            auto parentIt = pluginNetworkRequests_.find(pluginRequestId);
            if (parentIt != pluginNetworkRequests_.end()) {
                parentIt.value().remove(requestId);
                if (parentIt.value().isEmpty()) pluginNetworkRequests_.erase(parentIt);
            }
        }
        if (reply) {
            QObject::disconnect(reply, nullptr, &owner_, nullptr);
            reply->abort();
            reply->deleteLater();
        }
    }

    void finishNetworkRequest(const QString& requestId, QNetworkReply* reply) {
        if (!pendingNetwork_.remove(requestId)) return;
        const QString pluginRequestId = networkPluginRequests_.take(requestId);
        if (!pluginRequestId.isEmpty()) {
            auto parentIt = pluginNetworkRequests_.find(pluginRequestId);
            if (parentIt != pluginNetworkRequests_.end()) {
                parentIt.value().remove(requestId);
                if (parentIt.value().isEmpty()) pluginNetworkRequests_.erase(parentIt);
            }
        }
        const QByteArray raw = reply->readAll();
        if (reply->property("listenfreeResponseLimitExceeded").toBool() ||
            raw.size() > MaxNetworkResponseBytes) {
            completeNetworkRequestForPlugin(
                requestId, pluginRequestId,
                QStringLiteral("response exceeds the 8 MiB limit"), {});
            reply->deleteLater();
            return;
        }
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto networkError = reply->error();
        // Qt classifies HTTP 4xx/5xx as reply errors. Needle (LX) delivers
        // these as responses; plugins need their body to handle fallback and
        // rate limiting. Transport/TLS/truncated-body errors remain errors.
        const bool httpError = status >= 400 &&
            ((networkError >= QNetworkReply::ContentAccessDenied && networkError <= QNetworkReply::UnknownContentError) ||
             (networkError >= QNetworkReply::InternalServerError && networkError <= QNetworkReply::UnknownServerError));
        if (networkError != QNetworkReply::NoError && !httpError) {
            completeNetworkRequestForPlugin(requestId, pluginRequestId, reply->errorString(), {});
            reply->deleteLater();
            return;
        }

        QJsonValue body = QString::fromUtf8(raw);
        QJsonParseError parseError;
        const QJsonValue parsedBody = QJsonValue::fromJson(raw, &parseError);
        if (parseError.error == QJsonParseError::NoError) {
            body = parsedBody;
        }
        QJsonObject response;
        response.insert(QStringLiteral("statusCode"), reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt());
        response.insert(QStringLiteral("statusMessage"), reply->attribute(QNetworkRequest::HttpReasonPhraseAttribute).toString());
        QJsonObject responseHeaders;
        const auto headers = reply->rawHeaderPairs();
        for (const auto& header : headers) responseHeaders.insert(QString::fromLatin1(header.first).toLower(), QString::fromLatin1(header.second));
        response.insert(QStringLiteral("headers"), responseHeaders);
        response.insert(QStringLiteral("bytes"), raw.size());
        response.insert(QStringLiteral("rawBase64"), QString::fromLatin1(raw.toBase64()));
        completeNetworkRequestForPlugin(
            requestId, pluginRequestId, {},
            QJsonObject{{QStringLiteral("response"), response},
                        {QStringLiteral("body"), body}});
        reply->deleteLater();
    }

    void completeNetworkRequestForPlugin(const QString& requestId,
                                         const QString& pluginRequestId,
                                         const QString& error,
                                         const QJsonObject& packet) {
        const QString previousActiveRequest = activePluginRequest_;
        activePluginRequest_ = pluginRequestId;
        if (engine_) engine_->setRequestContext(pluginRequestId);
        completeNetworkRequest(requestId, error, packet);
        activePluginRequest_ = previousActiveRequest;
        if (engine_) engine_->setRequestContext(previousActiveRequest);
    }

    void completeNetworkRequest(const QString& requestId, const QString& error, const QJsonObject& packet) {
        if (!engine_) return;
        const QString packetJson = QString::fromUtf8(QJsonDocument(packet).toJson(QJsonDocument::Compact));
        QString scriptError;
        engine_->completeNetworkRequest(requestId, error, packetJson, &scriptError);
        finishAsyncTurn(scriptError, engine_->failureIsFatal());
    }

    void finishAsyncTurn(const QString& scriptError, bool fatal) {
        if (!scriptError.isEmpty() && (!initialized_ || fatal)) {
            failRuntime(scriptError);
            return;
        }
        drainTerminals();
        if (initialized_ && !loadingRequest_.isEmpty())
            finishLoad(std::exchange(loadingRequest_, {}));
    }

    bool abortPluginNetworkRequests(const QString& pluginRequestId, QString* error) {
        if (engine_) engine_->cancelRequestTimers(pluginRequestId);
        const auto networkIds = pluginNetworkRequests_.take(pluginRequestId);
        for (const auto& networkId : networkIds) {
            if (engine_ && !engine_->dropNetworkRequest(networkId, error)) return false;
            abortNetworkRequest(networkId);
        }
        return true;
    }

    bool rejectPendingRequests(const QString& code, const QString& message) {
        QStringList requestIds = pending_.keys();
        if (!loadingRequest_.isEmpty()) {
            loadDeadline_.stop();
            respondError(std::exchange(loadingRequest_, {}), code, message);
        }
        for (const auto& requestId : requestIds) {
            if (!pending_.contains(requestId)) continue;
            QString cleanupError;
            if (!abortPluginNetworkRequests(requestId, &cleanupError)) {
                failRuntime(cleanupError);
                return false;
            }
            takePending(requestId);
            respondError(requestId, code, message);
        }
        return true;
    }

    void failRuntime(const QString& message) {
        const QString boundedMessage = message.isEmpty()
                                           ? QStringLiteral("Plugin JavaScript runtime failed.")
                                           : message.left(4096);
        QStringList requestIds = pending_.keys();
        if (!loadingRequest_.isEmpty()) requestIds.append(loadingRequest_);
        reset();
        if (requestIds.isEmpty()) requestIds.append(QString{});
        for (const auto& requestId : requestIds) {
            respondError(requestId, QStringLiteral("plugin.runtime-failed"), boundedMessage);
        }
    }

    bool respond(const QString& requestId, MessageType type, QJsonObject payload) {
        SourceMessage response;
        response.type = type;
        response.requestId = requestId;
        response.payload = std::move(payload);
        const bool responseFits = SourceProtocol::encode(response).size() <= MaxProtocolFrameBytes;
        if (!responseFits) {
            response.type = MessageType::Error;
            response.payload = errorPayload(
                QStringLiteral("plugin.response-too-large"),
                QStringLiteral("Plugin response exceeds the 1 MiB protocol limit."));
        }
        emit owner_.responseReady(response);
        return responseFits;
    }

    void respondError(const QString& requestId, const QString& code, const QString& message) {
        respond(requestId, MessageType::Error, errorPayload(code, message));
    }

    void reset() {
        loadDeadline_.stop();
        loadingRequest_.clear();
        ++runtimeGeneration_;
        pendingTerminals_.clear();
        queuedTerminalRequestIds_.clear();
        clearPending();
        for (auto reply : std::as_const(pendingNetwork_)) {
            if (!reply) continue;
            QObject::disconnect(reply, nullptr, &owner_, nullptr);
            reply->abort();
            reply->deleteLater();
        }
        pendingNetwork_.clear();
        pluginNetworkRequests_.clear();
        networkPluginRequests_.clear();
        activePluginRequest_.clear();
        network_->setProxy(QNetworkProxy(QNetworkProxy::NoProxy));
        initialized_ = false;
        initPayload_ = {};
        updateAlert_ = {};
        engine_.reset();
    }

    void load(const SourceMessage& request) {
        const QString path = request.payload.value(QStringLiteral("path")).toString();
        const QFileInfo info(path);
        if (path.isEmpty() || !info.exists() || !info.isFile()) {
            respondError(request.requestId, QStringLiteral("plugin.file-not-found"),
                         QStringLiteral("Plugin file does not exist."));
            return;
        }
        if (info.size() > MaxPluginBytes) {
            respondError(request.requestId, QStringLiteral("plugin.file-too-large"),
                         QStringLiteral("Plugin file exceeds the 1 MiB limit."));
            return;
        }
        QFile file(info.absoluteFilePath());
        if (!file.open(QIODevice::ReadOnly)) {
            respondError(request.requestId, QStringLiteral("plugin.file-open-failed"), file.errorString());
            return;
        }
        const QByteArray encodedSource = file.readAll();
        QString sourceError;
        const auto source = decodePluginSource(encodedSource, &sourceError);
        if (!source) {
            respondError(request.requestId, QStringLiteral("plugin.decode-failed"), sourceError);
            return;
        }

        rejectPendingRequests(QStringLiteral("plugin.reloaded"),
                              QStringLiteral("Plugin was replaced while the request was pending."));
        reset();
        const QJsonObject proxy = request.payload.value(QStringLiteral("proxy")).toObject();
        if (!proxy.isEmpty()) {
            const QString host = proxy.value(QStringLiteral("host")).toString();
            const int port = proxy.value(QStringLiteral("port")).toInt();
            if (host.isEmpty() || host.size() > 253 || port < 1 || port > 65535) {
                respondError(request.requestId, QStringLiteral("plugin.invalid-proxy"),
                             QStringLiteral("Proxy host or port is invalid."));
                return;
            }
            network_->setProxy(QNetworkProxy(QNetworkProxy::HttpProxy, host,
                                             static_cast<quint16>(port)));
        }
        const auto generation = runtimeGeneration_;
        engine_ = std::make_unique<QuickJsEngine>(&owner_, QuickJsEngine::Callbacks{
            [this](const QString& name, const QString& json) { handleEvent(name, json); },
            [this](const QString& id, const QString& json) { queueTerminal(id, json, true); },
            [this](const QString& id, const QString& message) { queueTerminal(id, message, false); },
            [this](const QString& id, const QString& url, const QString& options) {
                return startNetworkRequest(id, url, options);
            },
            [this](const QString& id) { abortNetworkRequest(id); },
            [this, generation](const QString& id) {
                if (generation == runtimeGeneration_) activePluginRequest_ = id;
            },
            [this, generation](const QString&, const QString& error, bool fatal) {
                if (generation == runtimeGeneration_) finishAsyncTurn(error, fatal);
            },
        });
        if (!engine_->isValid()) {
            const QString runtimeError = engine_->initializationError();
            reset();
            respondError(request.requestId, QStringLiteral("plugin.runtime-failed"),
                         runtimeError.isEmpty()
                             ? QStringLiteral("Unable to create JavaScript runtime.")
                             : runtimeError);
            return;
        }
        QString scriptError;
        QFile browserScript(QStringLiteral(":/sourcehost/browser.js"));
        if (!browserScript.open(QIODevice::ReadOnly) ||
            !engine_->evaluate(QString::fromUtf8(browserScript.readAll()),
                               QStringLiteral("sourcehost/browser.js"), &scriptError) ||
            !engine_->evaluate(bootstrapScript, QStringLiteral("sourcehost/lx-compat.js"), &scriptError)) {
            reset();
            respondError(request.requestId, QStringLiteral("plugin.bootstrap-failed"), scriptError);
            return;
        }
        if (!engine_->setScriptInfo(parseScriptMetadata(*source), &scriptError)) {
            reset();
            respondError(request.requestId, QStringLiteral("plugin.script-failed"), scriptError);
            return;
        }
        const bool evaluated = engine_->evaluate(QString::fromUtf8(*source),
                                                 info.absoluteFilePath(), &scriptError);
        // LX marks a source ready when it sends `inited`. Its browser preload
        // ignores script errors raised after that event, so a late exception
        // must not discard an already registered request handler.
        if (!evaluated && (!initialized_ || engine_->failureIsFatal())) {
            reset();
            respondError(request.requestId, QStringLiteral("plugin.script-failed"), scriptError);
            return;
        }
        QString dispatchError;
        if (!engine_->hasDispatch(&dispatchError)) {
            reset();
            if (!dispatchError.isEmpty()) {
                respondError(request.requestId, QStringLiteral("plugin.script-failed"),
                             dispatchError);
            } else {
                respondError(request.requestId, QStringLiteral("plugin.init-missing"),
                             QStringLiteral("Plugin request dispatcher is unavailable."));
            }
            return;
        }
        if (!initialized_ && (!pendingNetwork_.isEmpty() || engine_->hasPendingTasks())) {
            loadingRequest_ = request.requestId;
            loadDeadline_.start(PluginOperationTimeoutMs);
            return;
        }
        finishLoad(request.requestId);
    }

    void finishLoad(const QString& requestId) {
        loadDeadline_.stop();
        if (!initialized_ ||
            !initPayload_.value(QStringLiteral("status")).toBool(true)) {
            QString diagnosticError;
            const QString diagnosticEvent = engine_->lastEventName(&diagnosticError);
            reset();
            if (!diagnosticError.isEmpty()) {
                respondError(requestId, QStringLiteral("plugin.script-failed"),
                             diagnosticError);
                return;
            }
            respondError(requestId, QStringLiteral("plugin.init-missing"),
                         diagnosticEvent.isEmpty()
                             ? QStringLiteral("Plugin did not report a successful inited event.")
                             : QStringLiteral("Plugin did not report a successful inited event; last event: %1.")
                                   .arg(diagnosticEvent.left(32)));
            return;
        }
        QJsonObject responsePayload{
            {QStringLiteral("ok"), true},
            {QStringLiteral("sources"), initPayload_.value(QStringLiteral("sources"))}};
        if (!updateAlert_.isEmpty()) {
            responsePayload.insert(QStringLiteral("updateAlert"), updateAlert_);
        }
        if (!respond(requestId, MessageType::Result, std::move(responsePayload))) {
            reset();
        }
    }

    void unload(const SourceMessage& request) {
        rejectPendingRequests(QStringLiteral("plugin.unloaded"),
                              QStringLiteral("Plugin was unloaded."));
        reset();
        respond(request.requestId, MessageType::Result, {{QStringLiteral("ok"), true}});
    }

    void initialize(const SourceMessage& request) {
        if (!engine_ || !initialized_) {
            respondError(request.requestId, QStringLiteral("plugin.not-loaded"),
                         QStringLiteral("No initialized plugin is loaded."));
            return;
        }
        respond(request.requestId, MessageType::Result, initPayload_);
    }

    void cancel(const SourceMessage& request) {
        const QString targetId = request.payload.value(QStringLiteral("requestId")).toString().isEmpty()
                                     ? request.requestId
                                     : request.payload.value(QStringLiteral("requestId")).toString();
        if (targetId == loadingRequest_) {
            reset();
            respond(request.requestId, MessageType::Result,
                    {{QStringLiteral("ok"), true}, {QStringLiteral("cancelled"), targetId}});
            return;
        }
        QString cleanupError;
        if (!abortPluginNetworkRequests(targetId, &cleanupError)) {
            failRuntime(cleanupError);
            return;
        }
        takePending(targetId);
        respond(request.requestId, MessageType::Result,
                {{QStringLiteral("ok"), true}, {QStringLiteral("cancelled"), targetId}});
        drainTerminals();
    }

    void resolve(const SourceMessage& request) {
        if (!engine_ || !initialized_) {
            respondError(request.requestId, QStringLiteral("plugin.not-loaded"),
                         QStringLiteral("No initialized plugin is loaded."));
            return;
        }
        if (pending_.size() >= MaxPendingPluginRequests) {
            respondError(request.requestId, QStringLiteral("plugin.too-many-requests"),
                         QStringLiteral("Too many plugin requests are pending."));
            return;
        }
        const QString source = request.payload.value(QStringLiteral("source")).toString();
        const QString type = request.payload.value(QStringLiteral("type")).toString();
        const QString action = request.type == MessageType::ResolveLyric
                                   ? QStringLiteral("lyric")
                                   : request.type == MessageType::ResolvePic ? QStringLiteral("pic")
                                                                              : QStringLiteral("musicUrl");
        const QJsonObject musicInfo = request.payload.value(QStringLiteral("musicInfo")).toObject();
        const QJsonObject sourceInfo = initPayload_.value(QStringLiteral("sources")).toObject()
                                           .value(source).toObject();
        if (sourceInfo.isEmpty() || !containsString(sourceInfo.value(QStringLiteral("actions")).toArray(), action) ||
            (action == QStringLiteral("musicUrl") &&
             !containsString(sourceInfo.value(QStringLiteral("qualitys")).toArray(), type)) ||
            musicInfo.isEmpty()) {
            respondError(request.requestId, QStringLiteral("plugin.invalid-request"),
                         QStringLiteral("Source, quality or musicInfo is not supported."));
            return;
        }
        auto* deadline = new QTimer(&owner_);
        deadline->setSingleShot(true);
        pending_.insert(request.requestId, {source, action, type, deadline});
        QObject::connect(deadline, &QTimer::timeout, &owner_, [this, id = request.requestId] {
            handleRejected(id, QStringLiteral("音源解析超时"));
        });
        deadline->start(PluginOperationTimeoutMs);
        QJsonObject info;
        info.insert(QStringLiteral("type"), type);
        info.insert(QStringLiteral("musicInfo"), musicInfo);
        QJsonObject event;
        event.insert(QStringLiteral("source"), source);
        event.insert(QStringLiteral("action"), action);
        event.insert(QStringLiteral("info"), info);
        const QString previousActiveRequest = activePluginRequest_;
        activePluginRequest_ = request.requestId;
        engine_->setRequestContext(request.requestId);
        QString scriptError;
        const bool accepted = engine_->dispatch(
            request.requestId,
            QString::fromUtf8(QJsonDocument(event).toJson(QJsonDocument::Compact)), &scriptError);
        activePluginRequest_ = previousActiveRequest;
        engine_->setRequestContext(previousActiveRequest);
        if (!accepted) {
            if (!scriptError.isEmpty()) {
                failRuntime(scriptError);
                return;
            }
        }
        drainTerminals();
        if (!accepted && pending_.contains(request.requestId)) {
            handleRejected(request.requestId, QStringLiteral("Plugin rejected the request."));
        }
    }

    void handleEvent(const QString& name, const QString& json) {
        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(json.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) return;
        if (name == QStringLiteral("inited") && !initialized_) {
            initialized_ = true;
            initPayload_ = document.object();
            if (engine_) engine_->markInitialized();
        } else if (name == QStringLiteral("updateAlert") && updateAlert_.isEmpty()) {
            const auto payload = document.object();
            const auto log = payload.value(QStringLiteral("log")).toString();
            if (!log.isEmpty() && log.size() <= 1027) {
                updateAlert_.insert(QStringLiteral("log"), log);
                const auto updateUrl = payload.value(QStringLiteral("updateUrl")).toString();
                const QUrl parsedUrl(updateUrl);
                if (updateUrl.size() <= 1024 && parsedUrl.isValid() &&
                    (parsedUrl.scheme() == QStringLiteral("http") ||
                     parsedUrl.scheme() == QStringLiteral("https")) &&
                    !parsedUrl.host().isEmpty()) {
                    updateAlert_.insert(QStringLiteral("updateUrl"), updateUrl);
                }
                respond({}, MessageType::UpdateAlert, updateAlert_);
            }
        }
    }

    void handleResolved(const QString& requestId, const QString& json) {
        if (!pending_.contains(requestId)) return;
        QString cleanupError;
        if (!abortPluginNetworkRequests(requestId, &cleanupError)) {
            failRuntime(cleanupError);
            return;
        }
        const auto pending = takePending(requestId);
        QJsonParseError parseError;
        const QJsonValue value = QJsonValue::fromJson(json.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError) {
            respondError(requestId, QStringLiteral("plugin.invalid-response"),
                         QStringLiteral("Plugin returned invalid JSON."));
            return;
        }
        if (pending.action == QStringLiteral("lyric")) {
            if (!value.isObject()) {
                respondError(requestId, QStringLiteral("plugin.invalid-lyric"),
                             QStringLiteral("Plugin returned invalid lyric data."));
                return;
            }
            const QJsonObject lyric = value.toObject();
            const QString lyricText = lyric.value(QStringLiteral("lyric")).toString();
            if (!lyric.value(QStringLiteral("lyric")).isString() || lyricText.size() > 51200) {
                respondError(requestId, QStringLiteral("plugin.invalid-lyric"),
                             QStringLiteral("Plugin returned invalid lyric data."));
                return;
            }
            auto boundedOptional = [](const QJsonValue& candidate, int maxLength) {
                return candidate.isString() && candidate.toString().size() < maxLength
                           ? candidate.toString()
                           : QString();
            };
            respond(requestId, MessageType::Result,
                    {{QStringLiteral("source"), pending.source},
                     {QStringLiteral("action"), pending.action},
                     {QStringLiteral("data"), QJsonObject{
                                                   {QStringLiteral("lyric"), lyricText},
                                                   {QStringLiteral("tlyric"), boundedOptional(lyric.value(QStringLiteral("tlyric")), 5120)},
                                                   {QStringLiteral("rlyric"), boundedOptional(lyric.value(QStringLiteral("rlyric")), 5120)},
                                                   {QStringLiteral("lxlyric"), boundedOptional(lyric.value(QStringLiteral("lxlyric")), 8192)}}}});
            return;
        }
        const QString url = value.isString() ? value.toString() : QString{};
        const QUrl parsed(url);
        if (url.isEmpty() || url.size() > MaxUrlBytes ||
            (parsed.scheme() != QStringLiteral("http") && parsed.scheme() != QStringLiteral("https")) ||
            parsed.host().isEmpty()) {
            respondError(requestId, QStringLiteral("plugin.invalid-url"),
                         QStringLiteral("Plugin returned an invalid media URL."));
            return;
        }
        const QJsonValue data = pending.action == QStringLiteral("pic")
                                    ? QJsonValue(url)
                                    : QJsonValue(QJsonObject{{QStringLiteral("type"), pending.type},
                                                             {QStringLiteral("url"), url}});
        respond(requestId, MessageType::Result,
                {{QStringLiteral("source"), pending.source},
                 {QStringLiteral("action"), pending.action},
                 {QStringLiteral("data"), data}});
    }

    void handleRejected(const QString& requestId, const QString& message) {
        if (!pending_.contains(requestId)) return;
        QString cleanupError;
        if (!abortPluginNetworkRequests(requestId, &cleanupError)) {
            failRuntime(cleanupError);
            return;
        }
        takePending(requestId);
        respondError(requestId, QStringLiteral("plugin.request-failed"), message);
    }

    PluginRuntime& owner_;
    std::unique_ptr<QNetworkAccessManager> network_;
    std::unique_ptr<QuickJsEngine> engine_;
    QJsonObject initPayload_;
    QJsonObject updateAlert_;
    QString loadingRequest_;
    QTimer loadDeadline_;
    QHash<QString, PendingRequest> pending_;
    QHash<QString, QNetworkReply*> pendingNetwork_;
    QHash<QString, QSet<QString>> pluginNetworkRequests_;
    QHash<QString, QString> networkPluginRequests_;
    QList<PendingTerminal> pendingTerminals_;
    QSet<QString> queuedTerminalRequestIds_;
    QString activePluginRequest_;
    quint64 runtimeGeneration_{0};
    bool initialized_{false};
    bool drainingTerminals_{false};
};

PluginRuntime::PluginRuntime(QObject* parent) : QObject(parent), impl_(std::make_unique<Impl>(*this)) {
    initializeBrowserResources();
    // The dispatch function is resolved after each load; keeping this signal
    // connection local ensures all script callbacks stay on the SourceHost
    // event-loop thread.
}

PluginRuntime::~PluginRuntime() = default;

void PluginRuntime::handle(const SourceMessage& request) {
    impl_->handle(request);
}

} // namespace listenfree::sourcehost
