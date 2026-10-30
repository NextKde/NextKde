#include "PlatformServer.h"
#include "PlatformNetworkBackend.h"
#include "KeepAwakeLease.h"
#include "PlatformProcess.h"
#include "PlatformDbus.h"
#include "../windowanimation/NativeGenie.h"

#include <QByteArray>
#include <QClipboard>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QList>
#include <QProcess>
#include <QStandardPaths>
#include <QStringList>
#include <QTimer>
#include <functional>

namespace KosPlatform {
using namespace Detail;

namespace {

constexpr int kProtocolVersion = 1;

// Bound unparsed input per peer; image payloads never travel inline.
constexpr qsizetype kMaxClientBufferBytes = 1024 * 1024;

// Disconnect slow consumers instead of accumulating an unbounded backlog.
constexpr qint64 kMaxClientWriteBytes = 8 * 1024 * 1024;

// Cache transient failures briefly to avoid spawning one helper per poll.
constexpr int kFailureCacheTtlMs = 5000;

QString runtimeSocketPath()
{
    // KOS_PLATFORM_SOCKET lets a development daemon listen beside the
    // installed one (see kosctl dev); the installed layout never sets it.
    const QString overridePath = qEnvironmentVariable("KOS_PLATFORM_SOCKET");
    if (!overridePath.isEmpty())
        return overridePath;
    const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (!runtime.isEmpty())
        return runtime + QStringLiteral("/kos-platform.sock");
    return QDir::tempPath() + QStringLiteral("/kos-platform-")
        + QString::number(QCoreApplication::applicationPid()) + QStringLiteral(".sock");
}

QJsonObject errorObject(const QString &code, const QString &message, bool retryable)
{
    return QJsonObject{{QStringLiteral("code"), code},
                       {QStringLiteral("message"), message},
                       {QStringLiteral("retryable"), retryable}};
}

} // namespace

PlatformServer::PlatformServer(QObject *parent)
    : QObject(parent), m_socketPath(runtimeSocketPath())
{
    qDBusRegisterMetaType<NmSettings>();
    QTimer::singleShot(0, this, [] {
        QString error;
        if (!KOS::WindowAnimation::migrate(error))
            qWarning().noquote() << "Dock animation migration:" << error;
    });
    // KDED starts the AppMenu registrar only while a menu view exists. Plasma's
    // applet normally owns this queueable marker service; own it here so the
    // Bar can receive menus without running a separate Plasma panel applet.
    QDBusConnection::sessionBus().interface()->registerService(
        QStringLiteral("org.kde.kappmenuview"),
        QDBusConnectionInterface::QueueService,
        QDBusConnectionInterface::DontAllowReplacement);
    connect(&m_server, &QLocalServer::newConnection,
            this, &PlatformServer::acceptConnections);
    const QString wlPaste = QStandardPaths::findExecutable(QStringLiteral("wl-paste"));
    const QString cliphist = QStandardPaths::findExecutable(QStringLiteral("cliphist"));
    if (wlPaste.isEmpty() || cliphist.isEmpty()) {
        QStringList missing;
        if (wlPaste.isEmpty())
            missing.append(QStringLiteral("wl-paste (wl-clipboard)"));
        if (cliphist.isEmpty())
            missing.append(QStringLiteral("cliphist"));
        qInfo().noquote() << "Clipboard history disabled; optional tools missing:"
                          << missing.join(QStringLiteral(", "));
    } else {
        startClipboardHistoryWatcher(m_textHistoryWatcher,
            {wlPaste, QStringLiteral("--type"), QStringLiteral("text"),
             QStringLiteral("--watch"), cliphist, QStringLiteral("store")});
        startClipboardHistoryWatcher(m_imageHistoryWatcher,
            {wlPaste, QStringLiteral("--type"), QStringLiteral("image"),
             QStringLiteral("--watch"), cliphist, QStringLiteral("store")});
    }
    // The wl-paste watcher already forks `cliphist store` on every new entry;
    // hooking QClipboard::dataChanged catches the same moment without parsing
    // wl-paste output, so the list cache can stay cheap and still drop stale
    // answers as soon as the clipboard moves.
    if (QClipboard *clipboard = QGuiApplication::clipboard()) {
        connect(clipboard, &QClipboard::dataChanged, this, [this] {
            invalidateReplies(QStringLiteral("clipboard.history.list"));
        });
    }
    const QString pactl = QStandardPaths::findExecutable(QStringLiteral("pactl"));
    if (!pactl.isEmpty())
        startAudioEventWatcher(pactl);
    // Two concurrent copies at most: more would thrash the same disk anyway,
    // and the pool queue keeps additional requests waiting off the event loop.
    m_copyPool.setMaxThreadCount(2);
    // network.refresh/network.details run their synchronous NM D-Bus walks
    // here; a dedicated pool keeps them from queueing behind file.copy work
    // (and vice versa).
    m_dbusPool.setMaxThreadCount(2);
}

PlatformServer::~PlatformServer()
{
    // QLocalServer owns accepted sockets and is destroyed after the tracking
    // containers below. Disconnect first so socket destruction cannot call
    // clientDisconnected() after those containers have already been freed.
    qDeleteAll(m_keepAwakeLeases);
    m_keepAwakeLeases.clear();
    for (QLocalSocket *socket : m_buffers.keys())
        QObject::disconnect(socket, nullptr, this, nullptr);
}

bool PlatformServer::listen()
{
    QLocalServer::removeServer(m_socketPath);
    if (!m_server.listen(m_socketPath)) {
        qWarning() << "Unable to listen on" << m_socketPath << m_server.errorString();
        return false;
    }
    // QLocalServer follows the platform's default umask, which is commonly
    // 0666.  The platform socket carries clipboard paths and power controls,
    // so it must never be readable by another local user.
    QFile::setPermissions(m_socketPath, QFileDevice::ReadOwner
        | QFileDevice::WriteOwner);
    return true;
}

void PlatformServer::acceptConnections()
{
    while (m_server.hasPendingConnections()) {
        auto *socket = m_server.nextPendingConnection();
        m_buffers.insert(socket, {});
        connect(socket, &QLocalSocket::readyRead, this, &PlatformServer::readClient);
        connect(socket, &QLocalSocket::disconnected, this, &PlatformServer::clientDisconnected);
    }
}

void PlatformServer::readClient()
{
    auto *socket = qobject_cast<QLocalSocket *>(sender());
    if (!socket)
        return;
    QByteArray &buffer = m_buffers[socket];
    buffer.append(socket->readAll());
    // A newline-free client would otherwise grow this buffer forever; the
    // cap bounds per-connection memory and rejects the peer explicitly.
    if (buffer.size() > kMaxClientBufferBytes) {
        QJsonObject response{{QStringLiteral("version"), kProtocolVersion},
                              {QStringLiteral("ok"), false},
                              {QStringLiteral("error"), errorObject(
                                   QStringLiteral("request-too-large"),
                                   QStringLiteral("请求超出大小限制"), false)}};
        writeClientMessage(socket, response);
        // Emits disconnected() -> clientDisconnected(), which removes the
        // buffer and schedules the socket for deletion.
        socket->disconnectFromServer();
        return;
    }
    // Detach complete lines before dispatch: a nested D-Bus event loop can
    // accept/disconnect sockets and invalidate references into m_buffers.
    const qsizetype lastNewline = buffer.lastIndexOf('\n');
    if (lastNewline < 0)
        return;
    const QByteArray batch = buffer.left(lastNewline + 1);
    buffer.remove(0, lastNewline + 1);
    const QPointer<QLocalSocket> guardedSocket(socket);
    qsizetype offset = 0;
    while (true) {
        if (!guardedSocket || !m_buffers.contains(guardedSocket.data()))
            return;
        const qsizetype newline = batch.indexOf('\n', offset);
        if (newline < 0)
            break;
        const QByteArray line = batch.mid(offset, newline - offset).trimmed();
        offset = newline + 1;
        if (line.isEmpty())
            continue;
        QJsonParseError error;
        const QJsonDocument document = QJsonDocument::fromJson(line, &error);
        if (error.error != QJsonParseError::NoError || !document.isObject()) {
            QJsonObject response{{QStringLiteral("version"), kProtocolVersion},
                                  {QStringLiteral("ok"), false},
                                  {QStringLiteral("error"), errorObject(
                                       QStringLiteral("invalid-json"),
                                       QStringLiteral("请求不是有效 JSON"), false)}};
            if (!writeClientMessage(socket, response))
                return;
            continue;
        }
        handleRequest(socket, document.object());
        if (!guardedSocket || guardedSocket->property("kosBackpressureClosing").toBool())
            return;
    }
}

void PlatformServer::clientDisconnected()
{
    auto *socket = qobject_cast<QLocalSocket *>(sender());
    if (!socket)
        return;
    delete m_keepAwakeLeases.take(socket);
    m_windowSubscribers.remove(socket);
    m_buffers.remove(socket);
    for (auto it = m_inFlightReplies.begin(); it != m_inFlightReplies.end(); ++it) {
        auto &pending = it.value();
        pending.removeIf([socket](const PendingReply &entry) {
            return !entry.socket || entry.socket.data() == socket;
        });
        // Keep the key until its worker completes, even with no listeners.
    }
    socket->deleteLater();
}

QString PlatformServer::requestId(const QJsonObject &request) const
{
    return request.value(QStringLiteral("requestId")).toString();
}

QString PlatformServer::operation(const QJsonObject &request) const
{
    return request.value(QStringLiteral("operation")).toString();
}

void PlatformServer::kickStuckClient(QLocalSocket *socket)
{
    if (!socket || socket->property("kosBackpressureClosing").toBool())
        return;
    socket->setProperty("kosBackpressureClosing", true);
    // Deferred on purpose: abort() emits disconnected() synchronously, and a
    // caller deeper in the stack (readClient's reference into m_buffers, the
    // subscriber iteration in broadcastKWinEvent) must not see the socket torn
    // down mid-dispatch. The connection is bound to `socket` as its context,
    // so a peer that disconnects first cancels the kick rather than aborting a
    // deleted object.
    QTimer::singleShot(0, socket, [socket]() { socket->abort(); });
}

bool PlatformServer::writeClientMessage(QLocalSocket *socket, const QJsonObject &message)
{
    if (!socket || socket->state() != QLocalSocket::ConnectedState
            || socket->property("kosBackpressureClosing").toBool())
        return false;
    const QByteArray bytes = QJsonDocument(message).toJson(QJsonDocument::Compact) + '\n';
    // Include this message in the limit, including malformed-request replies.
    if (bytes.size() > kMaxClientWriteBytes
            || socket->bytesToWrite() > kMaxClientWriteBytes - bytes.size()) {
        kickStuckClient(socket);
        return false;
    }
    if (socket->write(bytes) != bytes.size()) {
        kickStuckClient(socket);
        return false;
    }
    socket->flush();
    return true;
}

void PlatformServer::respond(QLocalSocket *socket, const QJsonObject &request,
                              bool ok, const QJsonObject &result,
                              const QString &code, const QString &message,
                              bool retryable)
{
    QJsonObject response{{QStringLiteral("version"), kProtocolVersion},
                         {QStringLiteral("requestId"), requestId(request)},
                         {QStringLiteral("ok"), ok}};
    if (ok)
        response.insert(QStringLiteral("result"), result);
    else
        response.insert(QStringLiteral("error"), errorObject(code, message, retryable));
    writeClientMessage(socket, response);
}

void PlatformServer::sendEvent(QLocalSocket *socket, const QJsonObject &event)
{
    QString eventName = event.value(QStringLiteral("type")).toString();
    if (eventName == QStringLiteral("snapshot"))
        eventName = QStringLiteral("window.snapshot");
    else if (eventName == QStringLiteral("action"))
        eventName = QStringLiteral("window.action");
    QJsonObject message{{QStringLiteral("version"), kProtocolVersion},
                        {QStringLiteral("event"), eventName},
                        {QStringLiteral("payload"), event}};
    writeClientMessage(socket, message);
}

void PlatformServer::broadcastKWinEvent(const QJsonObject &event)
{
    const QString type = event.value(QStringLiteral("type")).toString();
    if (type == QStringLiteral("snapshot"))
        m_latestWindowSnapshot = event;
    else if (type == QStringLiteral("desktops"))
        m_latestDesktopSnapshot = event;
    for (auto *socket : std::as_const(m_windowSubscribers))
        sendEvent(socket, event);
}

void PlatformServer::runCommand(QLocalSocket *socket, const QJsonObject &request,
                                const QString &program, const QStringList &arguments,
                                std::function<QJsonObject(const QByteArray &, int)> parser,
                                int timeoutMs, const QString &cacheKey, int cacheTtlMs,
                                std::function<void()> failedToStart)
{
    // With a cacheKey the response is shared: a poll that lands while the
    // same operation is still running queues onto it instead of spawning a
    // second copy of the same command.
    if (!cacheKey.isEmpty()
        && (serveCachedReply(socket, request, cacheKey)
            || queueIfInFlight(cacheKey, socket, request)))
        return;
    if (timeoutMs < 0)
        timeoutMs = kDefaultCommandTimeoutMs;
    const QPointer<QLocalSocket> guardedSocket(socket);
    auto *process = new QProcess(this);
    process->setProgram(program);
    process->setArguments(arguments);
    // Interactive GUI helpers can live for the whole session. No caller
    // parses their output, so do not retain unbounded diagnostic buffers.
    if (timeoutMs == 0)
        process->setProcessChannelMode(QProcess::ForwardedChannels);
    const auto replied = std::make_shared<bool>(false);
    const auto timedOut = std::make_shared<bool>(false);
    // timeoutMs == 0 opts out (interactive tools whose lifetime is the user's
    // session, not the request). Everything else gets a kill watchdog so a
    // wedged helper fails instead of stacking up one process per poll.
    if (timeoutMs > 0) {
        QPointer<QProcess> processGuard(process);
        QTimer::singleShot(timeoutMs, process, [processGuard, timedOut]() {
            if (processGuard && processGuard->state() != QProcess::NotRunning) {
                *timedOut = true;
                processGuard->kill();
            }
        });
    }
    connect(process, &QProcess::finished, this,
            [this, guardedSocket, request, process, parser, replied, timedOut,
             cacheKey, cacheTtlMs](int exitCode, QProcess::ExitStatus exitStatus) {
        if (*replied)
            return;
        *replied = true;
        const QByteArray output = process->readAllStandardOutput();
        const QByteArray error = process->readAllStandardError();
        const bool ok = exitStatus == QProcess::NormalExit && exitCode == 0;
        const QString code = *timedOut ? QStringLiteral("command-timeout")
                                       : QStringLiteral("command-failed");
        const QString message = *timedOut ? QStringLiteral("平台命令执行超时")
                                          : QStringLiteral("平台命令执行失败");
        QJsonObject result;
        if (ok)
            result = parser ? parser(output, exitCode) : parseOutput(output, exitCode);
        if (cacheKey.isEmpty()) {
            if (ok)
                respond(guardedSocket.data(), request, true, result);
            else {
                Q_UNUSED(error);
                respond(guardedSocket.data(), request, false, {}, code, message, true);
            }
        } else {
            completeInFlight(cacheKey, ok, result, code, message, true, cacheTtlMs);
        }
        process->deleteLater();
    });
    connect(process, &QProcess::errorOccurred, this,
            [this, guardedSocket, request, process, replied, timedOut,
             cacheKey, cacheTtlMs, failedToStart](QProcess::ProcessError error) {
        if (*replied)
            return;
        *replied = true;
        if (error == QProcess::FailedToStart && failedToStart && cacheKey.isEmpty()) {
            process->deleteLater();
            failedToStart();
            return;
        }
        // A watchdog kill arrives here as Crashed, ahead of finished() --
        // surface the timeout instead of a generic failure.
        const QString code = *timedOut ? QStringLiteral("command-timeout")
                                       : QStringLiteral("command-unavailable");
        const QString message = *timedOut ? QStringLiteral("平台命令执行超时")
                                          : QStringLiteral("平台命令不可用");
        if (cacheKey.isEmpty())
            respond(guardedSocket.data(), request, false, {}, code, message, true);
        else
            completeInFlight(cacheKey, false, {}, code, message, true, cacheTtlMs);
        process->deleteLater();
    });
    process->start();
}

bool PlatformServer::serveCachedReply(QLocalSocket *socket, const QJsonObject &request,
                                      const QString &key)
{
    const auto it = m_replyCache.find(key);
    if (it == m_replyCache.end())
        return false;
    if (QDateTime::currentMSecsSinceEpoch() >= it->expiresAt) {
        m_replyCache.erase(it);
        return false;
    }
    if (it->ok)
        respond(socket, request, true, it->result);
    else
        respond(socket, request, false, {}, it->code, it->message, it->retryable);
    return true;
}

void PlatformServer::storeReply(const QString &key, int ttlMs, bool ok,
                                const QJsonObject &result, const QString &code,
                                const QString &message, bool retryable)
{
    if (ttlMs <= 0)
        return;
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    // Device/profile keys may never be requested again. Expiration must also
    // reclaim those entries, rather than only running on a cache hit.
    for (auto it = m_replyCache.begin(); it != m_replyCache.end();) {
        if (it->expiresAt <= now)
            it = m_replyCache.erase(it);
        else
            ++it;
    }
    constexpr qsizetype maxCachedReplies = 256;
    if (!m_replyCache.contains(key) && m_replyCache.size() >= maxCachedReplies) {
        auto oldest = m_replyCache.begin();
        for (auto it = m_replyCache.begin(); it != m_replyCache.end(); ++it) {
            if (it->expiresAt < oldest->expiresAt)
                oldest = it;
        }
        m_replyCache.erase(oldest);
    }
    CachedReply entry;
    entry.ok = ok;
    entry.result = result;
    entry.code = code;
    entry.message = message;
    entry.retryable = retryable;
    entry.expiresAt = now
        + (ok ? ttlMs : qMin(ttlMs, static_cast<int>(kFailureCacheTtlMs)));
    m_replyCache.insert(key, entry);
}

void PlatformServer::invalidateReplies(const QString &keyPrefix)
{
    for (auto it = m_replyCache.begin(); it != m_replyCache.end();) {
        if (it.key().startsWith(keyPrefix))
            it = m_replyCache.erase(it);
        else
            ++it;
    }
}

bool PlatformServer::queueIfInFlight(const QString &key, QLocalSocket *socket,
                                     const QJsonObject &request)
{
    const bool alreadyRunning = m_inFlightReplies.contains(key);
    qsizetype total = 0;
    qsizetype peerTotal = 0;
    for (auto it = m_inFlightReplies.cbegin(); it != m_inFlightReplies.cend(); ++it) {
        total += it->size();
        for (const PendingReply &entry : *it) {
            if (entry.socket.data() == socket)
                ++peerTotal;
        }
    }
    if (peerTotal >= 32 || total >= 256
        || (!alreadyRunning && m_inFlightReplies.size() >= 64)) {
        respond(socket, request, false, {}, QStringLiteral("busy"),
                QStringLiteral("平台请求队列已满"), true);
        return true; // Answered; the caller must not start another worker.
    }
    QList<PendingReply> &pending = m_inFlightReplies[key];
    pending.append({QPointer<QLocalSocket>(socket), request});
    return alreadyRunning;
}

void PlatformServer::completeInFlight(const QString &key, bool ok,
                                      const QJsonObject &result,
                                      const QString &code, const QString &message,
                                      bool retryable, int ttlMs)
{
    storeReply(key, ttlMs, ok, result, code, message, retryable);
    const QList<PendingReply> pending = m_inFlightReplies.take(key);
    for (const PendingReply &entry : pending) {
        if (ok)
            respond(entry.socket.data(), entry.request, true, result);
        else
            respond(entry.socket.data(), entry.request, false, {},
                    code, message, retryable);
    }
}

void PlatformServer::handleRequest(QLocalSocket *socket, const QJsonObject &request)
{
    if (request.value(QStringLiteral("version")).toInt(kProtocolVersion) != kProtocolVersion) {
        respond(socket, request, false, {}, QStringLiteral("unsupported-version"),
                QStringLiteral("不支持的协议版本"), false);
        return;
    }
    const QString op = operation(request);
    if (op.isEmpty()) {
        respond(socket, request, false, {}, QStringLiteral("missing-operation"),
                QStringLiteral("缺少 operation"), false);
        return;
    }
    if (op == QStringLiteral("platform.ping")) {
        respond(socket, request, true, QJsonObject{
            {QStringLiteral("ready"), true},
            {QStringLiteral("capabilities"), QJsonArray{
                QStringLiteral("input.clipboard-anchor"),
                QStringLiteral("wallpaper.plasma.proxy"),
                QStringLiteral("wallpaper.plasma.restore"),
                QStringLiteral("wallpaper.preview.desktop"),
#ifdef KOS_SPATIAL_ENABLED
                QStringLiteral("spatial.resources"),
#endif
                QStringLiteral("session.visibility"),
                QStringLiteral("keepawake"),
            }},
        });
        return;
    }
    if (op == QStringLiteral("keepawake.get") || op == QStringLiteral("keepawake.set")) {
        auto *lease = m_keepAwakeLeases.value(socket);
        const auto state = [lease] {
            return QJsonObject{{"available", KeepAwakeLease::available()},
                               {"enabled", lease && lease->enabled()},
                               {"pending", lease && !lease->enabled()}};
        };
        if (op == QStringLiteral("keepawake.get")) {
            respond(socket, request, true, state());
            return;
        }
        const auto enabled = request.value("payload").toObject().value("enabled");
        if (!enabled.isBool()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-payload"),
                    QStringLiteral("enabled 必须为布尔值"));
            return;
        }
        if (lease && !lease->enabled()) {
            respond(socket, request, false, {}, QStringLiteral("busy"),
                    QStringLiteral("保持唤醒正在切换"), true);
            return;
        }
        if (!enabled.toBool()) {
            delete m_keepAwakeLeases.take(socket);
            respond(socket, request, true, {{"available", KeepAwakeLease::available()}, {"enabled", false}});
            return;
        }
        if (lease) {
            respond(socket, request, true, state());
            return;
        }
        if (!KeepAwakeLease::available()) {
            respond(socket, request, false, {}, QStringLiteral("unavailable"),
                    QStringLiteral("KDE 电源管理或锁屏服务不可用"), true);
            return;
        }
        lease = new KeepAwakeLease(this);
        m_keepAwakeLeases.insert(socket, lease);
        const QPointer<QLocalSocket> guarded(socket);
        connect(lease, &KeepAwakeLease::finished, this,
            [this, guarded, request, lease](bool ok, const QString &message) {
                if (!guarded || m_keepAwakeLeases.value(guarded.data()) != lease)
                    return;
                if (!ok) {
                    m_keepAwakeLeases.remove(guarded.data());
                    lease->deleteLater();
                }
                respond(guarded.data(), request, ok, {{"available", KeepAwakeLease::available()}, {"enabled", ok}},
                        ok ? QString() : QStringLiteral("inhibit-failed"), message, !ok);
            });
        connect(lease, &KeepAwakeLease::invalidated, this,
            [this, guarded, request, lease] {
                if (!guarded || m_keepAwakeLeases.value(guarded.data()) != lease)
                    return;
                m_keepAwakeLeases.remove(guarded.data());
                if (!lease->enabled())
                    respond(guarded.data(), request, false, {}, QStringLiteral("unavailable"),
                            QStringLiteral("KDE 服务已重启，请重试"), true);
                lease->deleteLater();
            });
        lease->start();
        return;
    }
    if (op == QStringLiteral("session.visibility")) {
        const auto call = QDBusMessage::createMethodCall("org.freedesktop.ScreenSaver",
            "/ScreenSaver", "org.freedesktop.ScreenSaver", "GetActive");
        auto *watcher = new QDBusPendingCallWatcher(
            QDBusConnection::sessionBus().asyncCall(call, 2000), this);
        const QPointer<QLocalSocket> guarded(socket);
        connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, guarded, request](QDBusPendingCallWatcher *completed) {
                const QDBusMessage reply = completed->reply();
                const bool valid = reply.type() == QDBusMessage::ReplyMessage && !reply.arguments().isEmpty();
                respond(guarded.data(), request, valid,
                    {{"locked", valid && reply.arguments().first().toBool()}},
                    valid ? QString() : QStringLiteral("session-state-unavailable"),
                    valid ? QString() : QStringLiteral("锁屏状态暂不可用"), false);
                completed->deleteLater();
            });
        return;
    }
#ifdef KOS_SPATIAL_ENABLED
    if (op == QStringLiteral("spatial.status")) {
        respond(socket, request, true, m_aiWorker.status());
        return;
    }
    if (op == QStringLiteral("spatial.cancel")) {
        m_aiWorker.cancel();
        respond(socket, request, true, {});
        return;
    }
    if (op == QStringLiteral("spatial.initialize") || op == QStringLiteral("spatial.inspect")
        || op == QStringLiteral("spatial.clear")) {
        if (op == QStringLiteral("spatial.clear")) m_aiWorker.cancel();
        const QPointer<QLocalSocket> guarded(socket);
        m_aiWorker.resourceOperation(op, request.value("payload").toObject().value("kind").toString(),
            [this, guarded, request, op](bool ok, const QJsonObject &result,
                                       const QString &code, const QString &message, bool retryable) {
                respond(guarded.data(), request, ok, result, code, message, retryable);
                if (op == QStringLiteral("spatial.clear")) m_aiWorker.cancel();
            });
        return;
    }
    if (op == QStringLiteral("depth.generate")) {
        runDepthGenerate(socket, request);
        return;
    }
#endif
    if (handleClipboard(socket, request) || handleApplication(socket, request)
        || handleFileOperation(socket, request)
        || handleKWin(socket, request) || handleAppMenu(socket, request)
        || handleInput(socket, request)
        || handleAudioOperation(socket, request)
        || handlePowerOperation(socket, request)
        || handleNetworkOperation(socket, request)
        || handleBluetoothOperation(socket, request)
        || handleDisplayOperation(socket, request)
        || handleThemeOperation(socket, request)
        || handleDesktopOperation(socket, request)
        || handleTrayOperation(socket, request)
        || handleStateOperation(socket, request)
        || handleWallpaperOperation(socket, request))
        return;
    respond(socket, request, false, {}, QStringLiteral("unknown-operation"),
            QStringLiteral("未知的平台操作"), false);
}

} // namespace KosPlatform
