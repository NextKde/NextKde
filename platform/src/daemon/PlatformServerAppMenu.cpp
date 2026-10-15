#include "PlatformServer.h"
#include "PlatformDbus.h"

#include <QDBusArgument>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusVariant>
#include <QDateTime>
#include <QJsonArray>
#include <QStringList>
#include <QVariant>

namespace KosPlatform {
using namespace Detail;

namespace {

QJsonObject menuItemFromArgument(const QDBusArgument &argument)
{
    qint32 id = 0;
    QVariantMap properties;
    argument.beginStructure();
    argument >> id >> properties;
    const QVariant type = unwrapDbusValue(properties.value(QStringLiteral("type")));
    const QVariant label = unwrapDbusValue(properties.value(QStringLiteral("label")));
    const QVariant visible = unwrapDbusValue(properties.value(QStringLiteral("visible")));
    const QVariant enabled = unwrapDbusValue(properties.value(QStringLiteral("enabled")));
    const QVariant childrenDisplay = unwrapDbusValue(properties.value(QStringLiteral("children-display")));
    const QVariant toggleType = unwrapDbusValue(properties.value(QStringLiteral("toggle-type")));
    const QVariant toggleState = unwrapDbusValue(properties.value(QStringLiteral("toggle-state")));
    QJsonArray children;
    argument.beginArray();
    while (!argument.atEnd()) {
        // DBusMenuLayoutItem encodes children as `av`: each child structure is
        // wrapped in a D-Bus variant. Reading it as a structure directly
        // corrupts QDBusArgument's iterator and aborts the daemon.
        QVariant child;
        argument >> child;
        const QDBusArgument childArgument = qvariant_cast<QDBusArgument>(unwrapDbusValue(child));
        children.append(menuItemFromArgument(childArgument));
    }
    argument.endArray();
    argument.endStructure();
    const bool hasChildren = !children.isEmpty()
        || childrenDisplay.toString() == QStringLiteral("submenu");
    const bool checkable = toggleType.isValid() && !toggleType.toString().isEmpty();
    const bool checked = toggleState.isValid() && toggleState.toInt() == 1;
    return QJsonObject{{QStringLiteral("id"), id},
                       {QStringLiteral("label"), label.toString().remove(QLatin1Char('_'))},
                       {QStringLiteral("icon"), QString()},
                       {QStringLiteral("separator"), type.toString() == QStringLiteral("separator")},
                       {QStringLiteral("visible"), !visible.isValid() || visible.toBool()},
                       {QStringLiteral("enabled"), !enabled.isValid() || enabled.toBool()},
                       {QStringLiteral("hasChildren"), hasChildren},
                       {QStringLiteral("checkable"), checkable},
                       {QStringLiteral("checked"), checked},
                       {QStringLiteral("children"), children}};
}

bool validAppMenuAddress(const QString &service, const QString &path)
{
    return !service.isEmpty() && service.size() <= 255
        && !path.isEmpty() && path.startsWith(QLatin1Char('/')) && path.size() <= 1024;
}

} // namespace

bool PlatformServer::handleAppMenu(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    if (!op.startsWith(QStringLiteral("appmenu.")))
        return false;

    if (op == QStringLiteral("appmenu.active")) {
        QDBusInterface bridge(QStringLiteral("org.kde.KWin"),
                              QStringLiteral("/KOSContextMenuInput"),
                              QStringLiteral("org.kos.KWin.ContextMenuInput"));
        bridge.setTimeout(kDbusCallTimeoutMs);
        if (!bridge.isValid()) {
            respond(socket, request, false, {}, QStringLiteral("appmenu-bridge-unavailable"),
                    QStringLiteral("全局菜单桥接尚未加载"), true);
            return true;
        }
        // Async: a wedged KWin bridge must not stall every other socket
        // client; the pending call is still bounded by the interface timeout.
        const QDBusPendingCall pending = bridge.asyncCall(
            QStringLiteral("activeApplicationMenu"));
        auto *watcher = new QDBusPendingCallWatcher(pending, this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this,
                [this, guardedSocket = QPointer<QLocalSocket>(socket),
                 request, watcher] {
            const QDBusMessage reply = watcher->reply();
            watcher->deleteLater();
            if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().isEmpty()) {
                respond(guardedSocket.data(), request, false, {}, QStringLiteral("appmenu-bridge-failed"),
                        QStringLiteral("无法读取活动窗口菜单"), true);
                return;
            }
            const QVariantMap address = variantMapFromDbusValue(reply.arguments().first());
            respond(guardedSocket.data(), request, true,
                    QJsonObject{{QStringLiteral("available"),
                                 address.value(QStringLiteral("available")).toBool()},
                                {QStringLiteral("service"),
                                 address.value(QStringLiteral("service")).toString()},
                                {QStringLiteral("path"),
                                 address.value(QStringLiteral("path")).toString()}});
        });
        return true;
    }

    const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();
    const QString service = payload.value(QStringLiteral("service")).toString();
    const QString path = payload.value(QStringLiteral("path")).toString();
    if (!validAppMenuAddress(service, path)) {
        respond(socket, request, false, {}, QStringLiteral("invalid-appmenu-address"),
                QStringLiteral("应用菜单地址无效"), false);
        return true;
    }

    QDBusInterface menu(service, path, QStringLiteral("com.canonical.dbusmenu"));
    // Third-party apps own this dbusmenu service and can hang; bound every
    // call on it.
    menu.setTimeout(kDbusCallTimeoutMs);
    if (!menu.isValid()) {
        respond(socket, request, false, {}, QStringLiteral("appmenu-unavailable"),
                QStringLiteral("应用未提供全局菜单"), true);
        return true;
    }
    const int id = payload.value(QStringLiteral("id")).toInt();
    if (op == QStringLiteral("appmenu.layout")) {
        // The root needs one additional level so top-level labels such as
        // File and Edit are identified as submenus rather than actions.
        const int depth = qBound(1, payload.value(QStringLiteral("depth")).toInt(1), 5);
        // A hung third-party app must not stall the daemon's event loop, so
        // the layout read stays async; the interface timeout still bounds
        // the pending call.
        const QDBusPendingCall pending = menu.asyncCall(
            QStringLiteral("GetLayout"), id, depth,
            QStringList{QStringLiteral("label"), QStringLiteral("visible"),
                        QStringLiteral("enabled"), QStringLiteral("type"),
                        QStringLiteral("children-display"), QStringLiteral("toggle-type"),
                        QStringLiteral("toggle-state"), QStringLiteral("icon-name")});
        auto *watcher = new QDBusPendingCallWatcher(pending, this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this,
                [this, guardedSocket = QPointer<QLocalSocket>(socket),
                 request, watcher] {
            const QDBusMessage reply = watcher->reply();
            watcher->deleteLater();
            if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().size() < 2) {
                respond(guardedSocket.data(), request, false, {}, QStringLiteral("appmenu-layout-failed"),
                        QStringLiteral("无法读取应用菜单"), true);
                return;
            }
            const QDBusArgument root = qvariant_cast<QDBusArgument>(reply.arguments().at(1));
            const QJsonObject parent = menuItemFromArgument(root);
            const QJsonArray items = parent.value(QStringLiteral("children")).toArray();
            respond(guardedSocket.data(), request, true,
                    QJsonObject{{QStringLiteral("parent"), parent},
                                {QStringLiteral("items"), items}});
        });
        return true;
    }
    if (op == QStringLiteral("appmenu.open") || op == QStringLiteral("appmenu.close")
        || op == QStringLiteral("appmenu.trigger")) {
        const QString event = op == QStringLiteral("appmenu.open") ? QStringLiteral("opened")
            : op == QStringLiteral("appmenu.close") ? QStringLiteral("closed")
            : QStringLiteral("clicked");
        const quint32 timestamp = static_cast<quint32>(QDateTime::currentMSecsSinceEpoch());

        if (op == QStringLiteral("appmenu.open")) {
            // Give Qt / KDE applications an opportunity to populate lazy dynamic submenus.
            menu.call(QStringLiteral("AboutToShow"), id);
        }

        // com.canonical.dbusmenu Event signature is (isvu): the data argument
        // MUST be typed as a D-Bus variant. Sending a bare QVariantMap produces
        // (isa{sv}u), which Qt's QDBusMenuAdaptor rejects as an unknown method.
        const QDBusVariant dbusData(QVariantMap{{QStringLiteral("timestamp"), timestamp}});
        const QDBusMessage reply = menu.call(QStringLiteral("Event"), id, event,
            QVariant::fromValue(dbusData), timestamp);
        if (reply.type() == QDBusMessage::ErrorMessage) {
            respond(socket, request, false, {}, QStringLiteral("appmenu-event-failed"),
                    QStringLiteral("应用菜单操作失败"), true);
            return true;
        }
        respond(socket, request, true);
        return true;
    }
    respond(socket, request, false, {}, QStringLiteral("unknown-appmenu-operation"),
            QStringLiteral("未知的应用菜单操作"), false);
    return true;
}

} // namespace KosPlatform
