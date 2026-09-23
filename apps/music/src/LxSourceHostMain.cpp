#include <QCoreApplication>
#include <QCryptographicHash>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QHash>
#include <QJSEngine>
#include <QJSValue>
#include <QJSValueIterator>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSocketNotifier>
#include <QUrl>
#include <QUrlQuery>
#include <QUuid>

#include <cstdio>
#include <memory>
#include <utility>

#include <unistd.h>
#include <fcntl.h>

namespace {

constexpr int requestTimeoutMs = 30000;
constexpr qsizetype maximumResponseBytes = 8 * 1024 * 1024;

QJSValue errorValue(QJSEngine *engine, const QString &message)
{
    return engine->newErrorObject(QJSValue::GenericError, message);
}

QJsonValue scriptValueToJson(const QJSValue &value)
{
    return QJsonValue::fromVariant(value.toVariant());
}

class LxBridge final : public QObject {
    Q_OBJECT

public:
    explicit LxBridge(QObject *parent = nullptr)
        : QObject(parent)
    {
    }

    void reset(QJSEngine *engine)
    {
        for (QNetworkReply *reply : std::as_const(m_replies)) {
            if (reply)
                reply->abort();
        }
        m_replies.clear();
        m_callbacks.clear();
        m_requestHandler = {};
        m_engine = engine;
    }

    Q_INVOKABLE QString request(const QString &urlText, const QJSValue &options,
                                const QJSValue &callback)
    {
        if (!m_engine || !callback.isCallable())
            return {};
        const QUrl url(urlText);
        if (!url.isValid()
            || (url.scheme() != QLatin1String("http")
                && url.scheme() != QLatin1String("https"))) {
            callback.call({errorValue(m_engine, QStringLiteral("URL is not allowed"))});
            return {};
        }

        const QString requestId = QUuid::createUuid().toString(QUuid::WithoutBraces);
        QNetworkRequest request(url);
        request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                             QNetworkRequest::NoLessSafeRedirectPolicy);
        request.setTransferTimeout(requestTimeoutMs);

        const QJSValue headers = options.property(QStringLiteral("headers"));
        if (headers.isObject()) {
            QJSValueIterator iterator(headers);
            while (iterator.hasNext()) {
                iterator.next();
                request.setRawHeader(iterator.name().toUtf8(),
                                     iterator.value().toString().toUtf8());
            }
        }
        if (!request.hasRawHeader("User-Agent")) {
            request.setRawHeader(
                "User-Agent",
                "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 KOS-Music/1.0");
        }

        QByteArray body;
        const QJSValue bodyValue = options.property(QStringLiteral("body"));
        if (!bodyValue.isUndefined() && !bodyValue.isNull()) {
            if (bodyValue.isString())
                body = bodyValue.toString().toUtf8();
            else
                body = QJsonDocument::fromVariant(bodyValue.toVariant()).toJson(
                    QJsonDocument::Compact);
        } else {
            const QJSValue form = options.property(QStringLiteral("form"));
            if (form.isObject()) {
                QUrlQuery query;
                QJSValueIterator iterator(form);
                while (iterator.hasNext()) {
                    iterator.next();
                    query.addQueryItem(iterator.name(), iterator.value().toString());
                }
                body = query.toString(QUrl::FullyEncoded).toUtf8();
                request.setHeader(QNetworkRequest::ContentTypeHeader,
                                  QStringLiteral("application/x-www-form-urlencoded"));
            }
        }

        const QString method = options.property(QStringLiteral("method"))
                                   .toString().trimmed().toUpper();
        QNetworkReply *reply = method == QLatin1String("POST")
            ? m_network.post(request, body) : m_network.get(request);
        m_callbacks.insert(requestId, callback);
        m_replies.insert(requestId, reply);
        connect(reply, &QNetworkReply::finished, this, [this, requestId, reply] {
            finishNetworkRequest(requestId, reply);
        });
        return requestId;
    }

    Q_INVOKABLE void abortRequest(const QString &requestId)
    {
        if (QNetworkReply *reply = m_replies.take(requestId)) {
            m_callbacks.remove(requestId);
            reply->abort();
            reply->deleteLater();
        }
    }

    Q_INVOKABLE bool on(const QString &eventName, const QJSValue &handler)
    {
        if (eventName != QLatin1String("request") || !handler.isCallable())
            return false;
        m_requestHandler = handler;
        return true;
    }

    Q_INVOKABLE bool send(const QString &eventName, const QJSValue &data)
    {
        if (eventName == QLatin1String("inited")) {
            emit initialized(scriptValueToJson(data).toObject());
            return true;
        }
        return eventName == QLatin1String("updateAlert");
    }

    Q_INVOKABLE QString md5(const QJSValue &value) const
    {
        QByteArray bytes;
        if (value.isString())
            bytes = value.toString().toUtf8();
        else
            bytes = QJsonDocument::fromVariant(value.toVariant()).toJson(QJsonDocument::Compact);
        return QString::fromLatin1(QCryptographicHash::hash(bytes, QCryptographicHash::Md5)
                                       .toHex());
    }

    Q_INVOKABLE void settle(const QString &requestId, bool succeeded,
                            const QJSValue &value)
    {
        if (!succeeded) {
            const QString message = value.property(QStringLiteral("message")).toString();
            emit resolutionFinished(requestId, {},
                                    message.isEmpty() ? value.toString() : message);
            return;
        }
        QString url;
        if (value.isString())
            url = value.toString();
        else if (value.isObject())
            url = value.property(QStringLiteral("url")).toString();
        const QUrl parsed(url);
        if (!parsed.isValid()
            || (parsed.scheme() != QLatin1String("http")
                && parsed.scheme() != QLatin1String("https"))) {
            emit resolutionFinished(requestId, {},
                                    QStringLiteral("The source returned an invalid audio URL"));
            return;
        }
        emit resolutionFinished(requestId, url, {});
    }

    bool hasRequestHandler() const
    {
        return m_requestHandler.isCallable();
    }

    QJSValue requestHandler() const
    {
        return m_requestHandler;
    }

signals:
    void initialized(const QJsonObject &data);
    void resolutionFinished(const QString &requestId, const QUrl &url,
                            const QString &errorMessage);

private:
    void finishNetworkRequest(const QString &requestId, QNetworkReply *reply)
    {
        m_replies.remove(requestId);
        const QJSValue callback = m_callbacks.take(requestId);
        if (!m_engine || !callback.isCallable()) {
            reply->deleteLater();
            return;
        }

        if (reply->error() != QNetworkReply::NoError) {
            callback.call({errorValue(m_engine, reply->errorString())});
            reply->deleteLater();
            return;
        }
        const QByteArray bytes = reply->read(maximumResponseBytes + 1);
        if (bytes.size() > maximumResponseBytes) {
            callback.call({errorValue(m_engine, QStringLiteral("Response is too large"))});
            reply->deleteLater();
            return;
        }

        QJSValue response = m_engine->newObject();
        response.setProperty(QStringLiteral("statusCode"), reply->attribute(
                                 QNetworkRequest::HttpStatusCodeAttribute).toInt());
        response.setProperty(QStringLiteral("statusMessage"), reply->attribute(
                                 QNetworkRequest::HttpReasonPhraseAttribute).toString());
        response.setProperty(QStringLiteral("bytes"), static_cast<double>(bytes.size()));
        QJSValue headers = m_engine->newObject();
        for (const auto &header : reply->rawHeaderPairs())
            headers.setProperty(QString::fromUtf8(header.first), QString::fromUtf8(header.second));
        response.setProperty(QStringLiteral("headers"), headers);

        QJSValue body = QString::fromUtf8(bytes);
        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(bytes, &parseError);
        if (parseError.error == QJsonParseError::NoError) {
            const QVariant parsed = document.isArray()
                ? QVariant(document.array().toVariantList())
                : QVariant(document.object().toVariantMap());
            body = m_engine->toScriptValue(parsed);
        }
        response.setProperty(QStringLiteral("body"), body);
        callback.call({QJSValue(QJSValue::NullValue), response, body});
        reply->deleteLater();
    }

    QJSEngine *m_engine = nullptr;
    QNetworkAccessManager m_network;
    QHash<QString, QJSValue> m_callbacks;
    QHash<QString, QNetworkReply *> m_replies;
    QJSValue m_requestHandler;
};

class SourceHost final : public QObject {
    Q_OBJECT

public:
    explicit SourceHost(QObject *parent = nullptr)
        : QObject(parent)
        , m_inputNotifier(STDIN_FILENO, QSocketNotifier::Read, this)
        , m_bridge(this)
    {
        const int inputFlags = fcntl(STDIN_FILENO, F_GETFL, 0);
        if (inputFlags >= 0)
            fcntl(STDIN_FILENO, F_SETFL, inputFlags | O_NONBLOCK);
        m_input.open(stdin, QIODevice::ReadOnly, QFileDevice::DontCloseHandle);
        m_output.open(stdout, QIODevice::WriteOnly, QFileDevice::DontCloseHandle);
        connect(&m_inputNotifier, &QSocketNotifier::activated,
                this, &SourceHost::readCommands);
        connect(&m_bridge, &LxBridge::initialized, this, &SourceHost::sourceInitialized);
        connect(&m_bridge, &LxBridge::resolutionFinished, this,
                [this](const QString &id, const QUrl &url, const QString &error) {
            if (error.isEmpty())
                reply(id, true, QJsonObject{{QStringLiteral("url"), url.toString()}});
            else
                reply(id, false, {}, error);
        });
    }

private slots:
    void readCommands()
    {
        m_inputBuffer += m_input.readAll();
        while (true) {
            const qsizetype newline = m_inputBuffer.indexOf('\n');
            if (newline < 0)
                break;
            const QByteArray line = m_inputBuffer.left(newline).trimmed();
            m_inputBuffer.remove(0, newline + 1);
            if (!line.isEmpty())
                handleCommand(line);
        }
    }

    void sourceInitialized(const QJsonObject &data)
    {
        if (m_pendingLoadId.isEmpty())
            return;
        const QString id = std::exchange(m_pendingLoadId, {});
        reply(id, true, data);
    }

private:
    void handleCommand(const QByteArray &line)
    {
        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(line, &parseError);
        const QJsonObject command = document.object();
        const QString id = command.value(QStringLiteral("id")).toString();
        if (parseError.error != QJsonParseError::NoError || id.isEmpty()) {
            reply(id, false, {}, QStringLiteral("Invalid host command"));
            return;
        }
        const QString operation = command.value(QStringLiteral("op")).toString();
        if (operation == QLatin1String("load")) {
            loadSource(id, command.value(QStringLiteral("script")).toString(),
                       command.value(QStringLiteral("info")).toObject());
        } else if (operation == QLatin1String("resolve")) {
            resolve(id, command.value(QStringLiteral("request")).toObject());
        } else {
            reply(id, false, {}, QStringLiteral("Unknown host operation"));
        }
    }

    void loadSource(const QString &id, const QString &script, const QJsonObject &info)
    {
        m_bridge.reset(nullptr);
        m_engine = std::make_unique<QJSEngine>();
        m_bridge.reset(m_engine.get());
        m_engine->globalObject().setProperty(QStringLiteral("__bridge"),
                                              m_engine->newQObject(&m_bridge));
        const QString prelude = QStringLiteral(R"JS(
            var globalThis = this;
            globalThis.window = globalThis;
            globalThis.console = { log(){}, info(){}, warn(){}, error(){},
                group(){}, groupEnd(){}, debug(){} };
            const __events = { request: "request", inited: "inited", updateAlert: "updateAlert" };
            globalThis.lx = {
                EVENT_NAMES: __events,
                version: "2.12.6",
                env: "desktop",
                request(url, options, callback) {
                    const id = __bridge.request(String(url), options || {}, callback);
                    return () => __bridge.abortRequest(id);
                },
                on(name, handler) {
                    if (!__bridge.on(String(name), handler))
                        return Promise.reject(new Error("Unsupported event: " + name));
                    return Promise.resolve();
                },
                send(name, data) {
                    if (!__bridge.send(String(name), data || {}))
                        return Promise.reject(new Error("Unsupported event: " + name));
                    return Promise.resolve();
                },
                utils: {
                    crypto: { md5(value) { return __bridge.md5(value); } },
                    buffer: {
                        from(value) { return value; },
                        bufToString(value) {
                            if (typeof value === "string") return value;
                            if (Array.isArray(value)) return String.fromCharCode(...value);
                            return String(value ?? "");
                        }
                    }
                }
            };
            globalThis.__kosSettle = function(promise, requestId) {
                Promise.resolve(promise).then(
                    value => __bridge.settle(requestId, true, value),
                    error => __bridge.settle(requestId, false, error));
            };
        )JS");
        QJSValue result = m_engine->evaluate(prelude, QStringLiteral("kos-lx-prelude.js"));
        if (result.isError()) {
            reply(id, false, {}, result.toString());
            return;
        }
        m_engine->globalObject().property(QStringLiteral("lx"))
            .setProperty(QStringLiteral("currentScriptInfo"),
                         m_engine->toScriptValue(info.toVariantMap()));
        m_pendingLoadId = id;
        result = m_engine->evaluate(script, info.value(QStringLiteral("fileName")).toString());
        if (result.isError()) {
            if (m_pendingLoadId != id)
                return;
            m_pendingLoadId.clear();
            const QString message = QStringLiteral("%1:%2: %3")
                .arg(result.property(QStringLiteral("fileName")).toString())
                .arg(result.property(QStringLiteral("lineNumber")).toInt())
                .arg(result.toString());
            reply(id, false, {}, message);
        }
    }

    void resolve(const QString &id, const QJsonObject &request)
    {
        if (!m_engine || !m_bridge.hasRequestHandler()) {
            reply(id, false, {}, QStringLiteral("The source is not ready"));
            return;
        }
        QJSValue result = m_bridge.requestHandler().call(
            {m_engine->toScriptValue(request.toVariantMap())});
        if (result.isError()) {
            reply(id, false, {}, result.toString());
            return;
        }
        m_engine->globalObject().property(QStringLiteral("__kosSettle"))
            .call({result, id});
    }

    void reply(const QString &id, bool ok, const QJsonValue &result = {},
               const QString &error = {})
    {
        QJsonObject object{{QStringLiteral("id"), id}, {QStringLiteral("ok"), ok}};
        if (ok)
            object.insert(QStringLiteral("result"), result);
        else
            object.insert(QStringLiteral("error"), error);
        m_output.write(QJsonDocument(object).toJson(QJsonDocument::Compact));
        m_output.write("\n");
        m_output.flush();
    }

    QFile m_input;
    QFile m_output;
    QSocketNotifier m_inputNotifier;
    QByteArray m_inputBuffer;
    std::unique_ptr<QJSEngine> m_engine;
    LxBridge m_bridge;
    QString m_pendingLoadId;
};

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    const QString nodeHost = QDir(QCoreApplication::applicationDirPath())
                                 .filePath(QStringLiteral("kos-music-lx-source-host.js"));
    if (!QFileInfo::exists(nodeHost)) {
        std::fprintf(stderr, "LX source runtime is missing: %s\n",
                     qPrintable(nodeHost));
        return 127;
    }
    const QByteArray encodedPath = QFile::encodeName(nodeHost);
    execlp("node", "node", encodedPath.constData(), static_cast<char *>(nullptr));
    std::perror("Unable to start the Node.js LX source runtime");
    return 127;
}

#include "LxSourceHostMain.moc"
