#include "TaskNotifications.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDebug>
#include <QVariantMap>

void TaskNotifications::send(const QString& summary, const QString& body)
{
    auto message = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.Notifications"),
        QStringLiteral("/org/freedesktop/Notifications"),
        QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("Notify"));
    message.setArguments({QStringLiteral("NextKde Settings"), uint(0), QStringLiteral("system-software-install"),
        summary, body.toHtmlEscaped(), QStringList{},
        QVariantMap{{QStringLiteral("desktop-entry"), QStringLiteral("kos-settings")}}, -1});
    auto* watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message, 5000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [watcher] {
        const QDBusPendingReply<uint> reply = *watcher;
        if (reply.isError()) qWarning() << "Application task notification unavailable:" << reply.error().message();
        watcher->deleteLater();
    });
}
