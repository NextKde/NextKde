#pragma once

#include <QDBusConnection>
#include <QDBusArgument>
#include <QDBusObjectPath>
#include <QVariantMap>
#include <QStringList>

// Implementation-only contracts; not part of the JSONL protocol.
namespace KosPlatform::Detail {

struct ScopedBusConnection {
    explicit ScopedBusConnection(const QString &name) : name(name) {}
    ~ScopedBusConnection() { QDBusConnection::disconnectFromBus(name); }
    QString name;
};

inline constexpr auto kBluezService = "org.bluez";

// Watches not re-confirmed by reads expire after five minutes.
inline constexpr qint64 kDbusStaleWatchMs = 5 * 60 * 1000;

// Every synchronous D-Bus round trip is bounded.
inline constexpr int kDbusCallTimeoutMs = 2000;

QVariantMap dbusGetAll(const QDBusConnection &bus, const QString &service,
                       const QString &path, const QString &interface);

QVariant dbusGetProperty(const QDBusConnection &bus, const QString &service,
                         const QString &path, const QString &interface,
                         const QString &property);

QString dbusPathOf(const QVariant &value);

bool dbusServiceRegistered(const QDBusConnection &bus, const QString &service);

uint dbusUnixProcessId(const QDBusConnection &bus, const QString &service);

QVariant unwrapDbusValue(const QVariant &value);

QVariantMap variantMapFromDbusValue(const QVariant &value);

QString workerBusName(const QString &tag);

} // namespace KosPlatform::Detail
