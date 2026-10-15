#include "PlatformServer.h"
#include "PlatformDbus.h"
#include "PlatformNetworkBackend.h"
#include "PlatformProcess.h"

#include <QDBusConnection>
#include <QDBusObjectPath>
#include <QDateTime>
#include <QStringList>

namespace KosPlatform {
using namespace Detail;

void PlatformServer::watchNmPath(const QString &path)
{
    if (path.isEmpty() || path == QStringLiteral("/"))
        return;
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (m_nmWatchedPaths.contains(path)) {
        // Re-confirmation: refresh the age so pruneStaleDbusWatches keeps it.
        m_nmWatchedPaths.insert(path, now);
        return;
    }
    m_nmWatchedPaths.insert(path, now);
    QDBusConnection::systemBus().connect(QString::fromLatin1(kNmService), path,
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("PropertiesChanged"),
        this, SLOT(nmPropertiesChanged(QString,QVariantMap,QStringList)));
}

void PlatformServer::unwatchNmPath(const QString &path)
{
    if (m_nmWatchedPaths.remove(path) == 0)
        return;
    QDBusConnection::systemBus().disconnect(QString::fromLatin1(kNmService), path,
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("PropertiesChanged"),
        this, SLOT(nmPropertiesChanged(QString,QVariantMap,QStringList)));
}

void PlatformServer::watchBluezManager()
{
    if (m_bluezManagerWatched)
        return;
    m_bluezManagerWatched = true;
    QDBusConnection bus = QDBusConnection::systemBus();
    bus.connect(QString::fromLatin1(kBluezService), QStringLiteral("/"),
        QStringLiteral("org.freedesktop.DBus.ObjectManager"),
        QStringLiteral("InterfacesAdded"),
        this, SLOT(bluezInterfacesAdded(QDBusObjectPath,QVariantMap)));
    bus.connect(QString::fromLatin1(kBluezService), QStringLiteral("/"),
        QStringLiteral("org.freedesktop.DBus.ObjectManager"),
        QStringLiteral("InterfacesRemoved"),
        this, SLOT(bluezInterfacesRemoved(QDBusObjectPath,QStringList)));
}

void PlatformServer::watchBluezPath(const QString &path)
{
    if (path.isEmpty() || path == QStringLiteral("/")
        || m_bluezWatchedPaths.contains(path))
        return;
    m_bluezWatchedPaths.insert(path);
    QDBusConnection::systemBus().connect(QString::fromLatin1(kBluezService), path,
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("PropertiesChanged"),
        this, SLOT(bluezPropertiesChanged(QString,QVariantMap,QStringList)));
}

void PlatformServer::watchBrightnessPath(const QString &service, const QString &path)
{
    const QString key = service + QLatin1Char(' ') + path;
    if (service.isEmpty() || path.isEmpty())
        return;
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (m_brightnessWatched.contains(key)) {
        m_brightnessWatched.insert(key, now);
        return;
    }
    m_brightnessWatched.insert(key, now);
    QDBusConnection::sessionBus().connect(service, path,
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("PropertiesChanged"),
        this, SLOT(brightnessPropertiesChanged(QString,QVariantMap,QStringList)));
}

void PlatformServer::unwatchBrightnessPath(const QString &key)
{
    if (m_brightnessWatched.remove(key) == 0)
        return;
    const qsizetype cut = key.indexOf(QLatin1Char(' '));
    if (cut <= 0)
        return;
    QDBusConnection::sessionBus().disconnect(key.left(cut), key.mid(cut + 1),
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("PropertiesChanged"),
        this, SLOT(brightnessPropertiesChanged(QString,QVariantMap,QStringList)));
}

void PlatformServer::pruneStaleDbusWatches()
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    // Collect before removing: unwatch* mutate the maps being walked.
    QStringList expired;
    for (auto it = m_nmWatchedPaths.cbegin(); it != m_nmWatchedPaths.cend(); ++it) {
        if (now - it.value() > kDbusStaleWatchMs)
            expired.append(it.key());
    }
    for (const QString &path : std::as_const(expired))
        unwatchNmPath(path);
    expired.clear();
    for (auto it = m_brightnessWatched.cbegin(); it != m_brightnessWatched.cend(); ++it) {
        if (now - it.value() > kDbusStaleWatchMs)
            expired.append(it.key());
    }
    for (const QString &key : std::as_const(expired))
        unwatchBrightnessPath(key);
}

void PlatformServer::watchNightLight()
{
    if (m_nightLightWatched)
        return;
    m_nightLightWatched = true;
    QDBusConnection::sessionBus().connect(QStringLiteral("org.kde.KWin"),
        QStringLiteral("/org/kde/KWin/NightLight"),
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("PropertiesChanged"),
        this, SLOT(nightLightPropertiesChanged(QString,QVariantMap,QStringList)));
}

void PlatformServer::nmPropertiesChanged(const QString &, const QVariantMap &,
                                         const QStringList &)
{
    invalidateReplies(QStringLiteral("network."));
}

void PlatformServer::bluezPropertiesChanged(const QString &, const QVariantMap &,
                                            const QStringList &)
{
    invalidateReplies(QStringLiteral("bluetooth."));
}

void PlatformServer::bluezInterfacesAdded(const QDBusObjectPath &path,
                                          const QVariantMap &)
{
    // A new adapter or device object is also a new path worth watching.
    watchBluezPath(path.path());
    invalidateReplies(QStringLiteral("bluetooth."));
}

void PlatformServer::bluezInterfacesRemoved(const QDBusObjectPath &path,
                                            const QStringList &)
{
    // The object is gone; let the next list call re-subscribe if it returns.
    // Unlink the match rule too: dropping only the set entry left the
    // subscription behind on the system bus.
    if (m_bluezWatchedPaths.remove(path.path()) > 0) {
        QDBusConnection::systemBus().disconnect(QString::fromLatin1(kBluezService),
            path.path(),
            QStringLiteral("org.freedesktop.DBus.Properties"),
            QStringLiteral("PropertiesChanged"),
            this, SLOT(bluezPropertiesChanged(QString,QVariantMap,QStringList)));
    }
    invalidateReplies(QStringLiteral("bluetooth."));
}

void PlatformServer::brightnessPropertiesChanged(const QString &, const QVariantMap &,
                                                 const QStringList &)
{
    invalidateReplies(QStringLiteral("display.brightness."));
}

void PlatformServer::nightLightPropertiesChanged(const QString &, const QVariantMap &,
                                                 const QStringList &)
{
    invalidateReplies(QStringLiteral("nightlight."));
}

} // namespace KosPlatform
