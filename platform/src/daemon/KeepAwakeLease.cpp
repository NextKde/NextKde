#include "KeepAwakeLease.h"

#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QUuid>

namespace KosPlatform {
namespace {
const QString powerService = QStringLiteral("org.freedesktop.PowerManagement");
const QString powerPath = QStringLiteral("/org/freedesktop/PowerManagement/Inhibit");
const QString powerInterface = QStringLiteral("org.freedesktop.PowerManagement.Inhibit");
const QString screenService = QStringLiteral("org.freedesktop.ScreenSaver");
const QString screenPath = QStringLiteral("/ScreenSaver");
}

KeepAwakeLease::KeepAwakeLease(QObject *parent)
    : QObject(parent)
    , m_connectionName(QStringLiteral("kos-keepawake-") + QUuid::createUuid().toString(QUuid::Id128))
    , m_bus(QDBusConnection::connectToBus(QDBusConnection::SessionBus, m_connectionName))
{
    auto *watcher = new QDBusServiceWatcher(
        powerService, m_bus, QDBusServiceWatcher::WatchForOwnerChange, this);
    watcher->addWatchedService(screenService);
    connect(watcher, &QDBusServiceWatcher::serviceOwnerChanged, this,
        [this](const QString &, const QString &oldOwner, const QString &) {
            if (!oldOwner.isEmpty() && m_valid) {
                m_valid = false;
                // Cookies belong to the old service owner, never its replacement.
                m_powerCookie.reset();
                m_screenCookie.reset();
                emit invalidated();
            }
        });
}

KeepAwakeLease::~KeepAwakeLease()
{
    // Explicitly release confirmed cookies; disconnect also covers a request
    // that reached KDE but whose reply was lost or was still in flight.
    if (m_screenCookie) {
        auto call = QDBusMessage::createMethodCall(screenService, screenPath, screenService,
                                                 QStringLiteral("UnInhibit"));
        call << *m_screenCookie;
        m_bus.send(call);
    }
    if (m_powerCookie) {
        auto call = QDBusMessage::createMethodCall(powerService, powerPath, powerInterface,
                                                 QStringLiteral("UnInhibit"));
        call << *m_powerCookie;
        m_bus.send(call);
    }
    QDBusConnection::disconnectFromBus(m_connectionName);
}

bool KeepAwakeLease::available()
{
    auto *bus = QDBusConnection::sessionBus().interface();
    return bus && bus->isServiceRegistered(powerService).value()
        && bus->isServiceRegistered(screenService).value();
}

void KeepAwakeLease::start()
{
    if (!m_bus.isConnected()) {
        emit finished(false, QStringLiteral("无法连接会话 D-Bus"));
        return;
    }
    inhibit(false);
}

void KeepAwakeLease::inhibit(bool screenSaver)
{
    auto call = QDBusMessage::createMethodCall(
        screenSaver ? screenService : powerService,
        screenSaver ? screenPath : powerPath,
        screenSaver ? screenService : powerInterface, QStringLiteral("Inhibit"));
    call << QStringLiteral("NextKde") << QStringLiteral("保持唤醒");
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(call, 2000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
        [this, screenSaver](QDBusPendingCallWatcher *completed) {
            const QDBusPendingReply<uint> reply = *completed;
            completed->deleteLater();
            if (!m_valid)
                return;
            if (reply.isError()) {
                emit finished(false, QStringLiteral("无法开启保持唤醒：") + reply.error().message());
                return;
            }
            if (!screenSaver) {
                m_powerCookie = reply.value();
                inhibit(true);
            } else {
                m_screenCookie = reply.value();
                m_enabled = true;
                emit finished(true, {});
            }
        });
}

} // namespace KosPlatform
