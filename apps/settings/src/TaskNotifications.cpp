#include "TaskNotifications.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDebug>
#include <QVariantMap>
#include <QProcess>
#include <QCoreApplication>
#include <QLocale>
#include "../../../shared/i18n/SystemLanguage.h"

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

TaskNotifications::TaskNotifications(QObject* parent) : QObject(parent)
{
    QDBusConnection::sessionBus().connect("org.freedesktop.Notifications", "/org/freedesktop/Notifications",
        "org.freedesktop.Notifications", "ActionInvoked", this, SLOT(notificationAction(uint,QString)));
}
void TaskNotifications::notificationAction(uint id, const QString& action)
{
    if (id == m_updateNotification && action == "default")
        QProcess::startDetached(QCoreApplication::applicationDirPath() + "/kos-settings", {"--page=9"});
}
void TaskNotifications::sendUpdates(int count)
{
    const bool chinese = Kos::I18n::isChinese();
    const bool portuguese = Kos::I18n::isPortuguese();
    auto message = QDBusMessage::createMethodCall("org.freedesktop.Notifications", "/org/freedesktop/Notifications",
        "org.freedesktop.Notifications", "Notify");
    const auto title = chinese ? QString("应用更新") : portuguese ? QString("Atualizações de aplicativos") : QString("Application updates");
    const auto body = chinese ? QString("%1 个应用有更新，点击查看。").arg(count)
        : portuguese ? QString("%1 aplicativo(s) com atualizações. Clique para ver.").arg(count)
        : QString("%1 application(s) have updates. Click to review.").arg(count);
    message.setArguments({QString("NextKde"), m_updateNotification, QString("system-software-update"), title, body,
        QStringList{"default", chinese ? "查看更新" : portuguese ? "Ver atualizações" : "View updates"},
        QVariantMap{{"desktop-entry", "kos-settings"}}, -1});
    auto* watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message, 5000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
        const QDBusPendingReply<uint> reply = *watcher;
        if (!reply.isError()) { m_updateNotification = reply.value(); emit updatesDelivered(); }
        watcher->deleteLater();
    });
}
