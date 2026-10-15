#include "PlatformServer.h"
#include "../kwin/KWinBridge.h"
#include "PlatformDbus.h"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QJsonValue>
#include <QUuid>
#include <cmath>

namespace KosPlatform {
using namespace Detail;

namespace {

bool finiteNumber(const QJsonValue &value, double minimum, double maximum)
{
    if (!value.isDouble())
        return false;
    const double number = value.toDouble();
    return std::isfinite(number) && number >= minimum && number <= maximum;
}

bool validRect(const QJsonValue &value)
{
    if (!value.isObject())
        return false;
    const QJsonObject rect = value.toObject();
    return finiteNumber(rect.value(QStringLiteral("x")), -1000000.0, 1000000.0)
        && finiteNumber(rect.value(QStringLiteral("y")), -1000000.0, 1000000.0)
        && finiteNumber(rect.value(QStringLiteral("width")), 1.0, 1000000.0)
        && finiteNumber(rect.value(QStringLiteral("height")), 1.0, 1000000.0);
}

bool validLayoutPayload(const QJsonObject &payload)
{
    const QString outputName = payload.value(QStringLiteral("outputName")).toString();
    const QString dockPosition = payload.value(QStringLiteral("dockPosition")).toString();
    return !outputName.isEmpty() && outputName.size() <= 255
        && validRect(payload.value(QStringLiteral("outputRect")))
        && validRect(payload.value(QStringLiteral("dockRect")))
        && finiteNumber(payload.value(QStringLiteral("barReservedHeight")), 0.0, 4096.0)
        && finiteNumber(payload.value(QStringLiteral("workspaceGap")), 0.0, 512.0)
        && (dockPosition == QStringLiteral("bottom")
            || dockPosition == QStringLiteral("left")
            || dockPosition == QStringLiteral("right"));
}

} // namespace

bool PlatformServer::handleKWin(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    if (op == QStringLiteral("kwin.subscribe")) {
        m_windowSubscribers.insert(socket);
        respond(socket, request, true, QJsonObject{{QStringLiteral("subscribed"), true}});
        // A subscriber commonly appears after a Shell reload. KWin emits
        // snapshots only on state changes, so replay the cached authoritative
        // state now instead of leaving the Dock empty until the next change.
        if (!m_latestWindowSnapshot.isEmpty())
            sendEvent(socket, m_latestWindowSnapshot);
        if (!m_latestDesktopSnapshot.isEmpty())
            sendEvent(socket, m_latestDesktopSnapshot);
        return true;
    }
    if (op == QStringLiteral("kwin.layout.update")) {
        const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();
        if (!validLayoutPayload(payload)) {
            respond(socket, request, false, {}, QStringLiteral("invalid-payload"),
                    QStringLiteral("窗口布局参数无效"), false);
            return true;
        }
        QJsonObject command = payload;
        command.insert(QStringLiteral("action"), QStringLiteral("update-layout"));
        if (!enqueueKWinCommand(command)) {
            respond(socket, request, false, {}, QStringLiteral("kwin-unavailable"),
                    QStringLiteral("KWin 平台桥不可用"), true);
            return true;
        }
        respond(socket, request, true);
        return true;
    }
    if (op == QStringLiteral("kwin.command")) {
        if (!enqueueKWinCommand(request.value(QStringLiteral("payload")).toObject())) {
            respond(socket, request, false, {}, QStringLiteral("kwin-unavailable"),
                    QStringLiteral("KWin 平台桥不可用"), true);
            return true;
        }
        respond(socket, request, true);
        return true;
    }
    if (op == QStringLiteral("kwin.animation.update-targets")
        || op == QStringLiteral("kwin.animation.prepare-launch")) {
        const QString payload = request.value(QStringLiteral("payload")).toObject()
                                     .value(QStringLiteral("payload")).toString();
        if (payload.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-payload"),
                    QStringLiteral("动画参数无效"), false);
            return true;
        }
        QDBusInterface effect(QStringLiteral("org.kde.KWin"),
                              QStringLiteral("/KOSDockWindowAnimation"),
                              QStringLiteral("org.kos.KWin.DockWindowAnimation"));
        effect.setTimeout(kDbusCallTimeoutMs);
        if (!effect.isValid()) {
            respond(socket, request, false, {}, QStringLiteral("kwin-effect-unavailable"),
                    QStringLiteral("Dock 窗口动画特效不可用"), true);
            return true;
        }
        const QString method = op.endsWith(QStringLiteral("update-targets"))
            ? QStringLiteral("updateTargets") : QStringLiteral("prepareLaunch");
        const QDBusMessage reply = effect.call(method, payload);
        if (reply.type() == QDBusMessage::ErrorMessage) {
            respond(socket, request, false, {}, QStringLiteral("kwin-effect-failed"),
                    QStringLiteral("Dock 窗口动画特效调用失败"), true);
            return true;
        }
        respond(socket, request, true, QJsonObject{{QStringLiteral("accepted"), true}});
        return true;
    }
    return false;
}

bool PlatformServer::handleInput(QLocalSocket *socket, const QJsonObject &request)
{
    if (operation(request) == QStringLiteral("input.clipboard-anchor")) {
        // No synchronous introspection or cache: each opening needs a fresh
        // compositor snapshot, and an unavailable effect must not stall the daemon.
        QDBusMessage message = QDBusMessage::createMethodCall(
            QStringLiteral("org.kde.KWin"), QStringLiteral("/KOSContextMenuInput"),
            QStringLiteral("org.kos.KWin.ContextMenuInput"), QStringLiteral("clipboardAnchor"));
        message.setArguments({request.value(QStringLiteral("payload")).toObject()
            .value(QStringLiteral("expectedWindowId")).toString()});
        auto *watcher = new QDBusPendingCallWatcher(
            QDBusConnection::sessionBus().asyncCall(message, 150), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this,
                [this, guardedSocket = QPointer<QLocalSocket>(socket), request, watcher] {
            const QDBusMessage reply = watcher->reply();
            watcher->deleteLater();
            if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().isEmpty()) {
                respond(guardedSocket.data(), request, true,
                        QJsonObject{{QStringLiteral("available"), false}});
                return;
            }
            respond(guardedSocket.data(), request, true,
                    QJsonObject::fromVariantMap(variantMapFromDbusValue(reply.arguments().first())));
        });
        return true;
    }
    if (operation(request) != QStringLiteral("input.paste"))
        return false;

    const QString expectedWindowId = request.value(QStringLiteral("payload")).toObject()
        .value(QStringLiteral("expectedWindowId")).toString();
    if (QUuid(expectedWindowId).isNull()) {
        respond(socket, request, false, {}, QStringLiteral("invalid-paste-target"),
                QStringLiteral("粘贴目标窗口无效；内容已保留在剪贴板"), false);
        return true;
    }

    // Only a compositor-side effect may synthesise a key without uinput
    // privileges, so the chord is delegated to the KWin effect that already
    // owns this session-bus endpoint. Keeping it here means the Shell never has
    // to ship a separate injection helper.
    QDBusInterface effect(QStringLiteral("org.kde.KWin"),
                          QStringLiteral("/KOSContextMenuInput"),
                          QStringLiteral("org.kos.KWin.ContextMenuInput"));
    effect.setTimeout(kDbusCallTimeoutMs);
    if (!effect.isValid()) {
        respond(socket, request, false, {}, QStringLiteral("input-bridge-unavailable"),
                QStringLiteral("按键注入桥接尚未加载"), true);
        return true;
    }

    const QDBusMessage reply = effect.call(QStringLiteral("paste"), expectedWindowId);
    if (reply.type() == QDBusMessage::ErrorMessage) {
        respond(socket, request, false, {}, QStringLiteral("input-injection-failed"),
                QStringLiteral("无法注入粘贴按键"), true);
        return true;
    }

    if (reply.arguments().isEmpty() || !reply.arguments().first().toBool()) {
        respond(socket, request, false, {}, QStringLiteral("paste-target-changed"),
                QStringLiteral("焦点已改变，未自动粘贴；内容已保留在剪贴板"), false);
        return true;
    }

    respond(socket, request, true, QJsonObject{{QStringLiteral("injected"), true}});
    return true;
}

} // namespace KosPlatform
