#include "PlatformDbus.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusVariant>
#include <QMetaType>
#include <QThread>
#include <QVariant>
#include <atomic>

namespace KosPlatform::Detail {

QVariant unwrapDbusValue(const QVariant &value)
{
    return value.metaType() == QMetaType::fromType<QDBusVariant>()
        ? qvariant_cast<QDBusVariant>(value).variant() : value;
}

QVariantMap variantMapFromDbusValue(const QVariant &value)
{
    const QVariant unwrapped = unwrapDbusValue(value);
    if (unwrapped.metaType() == QMetaType::fromType<QDBusArgument>()) {
        QVariantMap map;
        QDBusArgument argument = qvariant_cast<QDBusArgument>(unwrapped);
        argument >> map;
        return map;
    }
    return unwrapped.toMap();
}

// One bounded round-trip for every property of an interface; GetAll keeps a
// status read at O(objects) calls instead of one call per property.
QVariantMap dbusGetAll(const QDBusConnection &bus, const QString &service,
                       const QString &path, const QString &interface)
{
    QDBusInterface properties(service, path,
                              QStringLiteral("org.freedesktop.DBus.Properties"), bus);
    properties.setTimeout(kDbusCallTimeoutMs);
    const QDBusMessage reply = properties.call(QStringLiteral("GetAll"), interface);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
        return {};
    const QVariant first = reply.arguments().constFirst();
    if (first.metaType() == QMetaType::fromType<QDBusArgument>()) {
        QVariantMap map;
        QDBusArgument argument = qvariant_cast<QDBusArgument>(first);
        argument >> map;
        return map;
    }
    return first.toMap();
}

// bus.interface()->isServiceRegistered() rides the shared
// QDBusConnectionInterface, whose timeout cannot be narrowed without
// touching every other bus call. A per-call temporary interface keeps this
// lookup bounded at kDbusCallTimeoutMs instead.
bool dbusServiceRegistered(const QDBusConnection &bus, const QString &service)
{
    QDBusInterface lookup(QStringLiteral("org.freedesktop.DBus"),
                          QStringLiteral("/org/freedesktop/DBus"),
                          QStringLiteral("org.freedesktop.DBus"), bus);
    lookup.setTimeout(kDbusCallTimeoutMs);
    const QDBusMessage reply = lookup.call(QStringLiteral("NameHasOwner"), service);
    return reply.type() == QDBusMessage::ReplyMessage
        && !reply.arguments().isEmpty()
        && reply.arguments().constFirst().toBool();
}

// Properties.Get of a single property, bounded like every other round-trip.
QVariant dbusGetProperty(const QDBusConnection &bus, const QString &service,
                         const QString &path, const QString &interface,
                         const QString &property)
{
    QDBusInterface target(service, path,
                          QStringLiteral("org.freedesktop.DBus.Properties"), bus);
    target.setTimeout(kDbusCallTimeoutMs);
    const QDBusMessage reply =
        target.call(QStringLiteral("Get"), interface, property);
    if (reply.type() == QDBusMessage::ReplyMessage
        && reply.arguments().size() == 1)
        return unwrapDbusValue(reply.arguments().constFirst());
    return {};
}

// PID of the process behind a bus name, for /proc lookups. Returns 0 when
// the name has vanished from the bus.
uint dbusUnixProcessId(const QDBusConnection &bus, const QString &service)
{
    QDBusInterface lookup(QStringLiteral("org.freedesktop.DBus"),
                          QStringLiteral("/org/freedesktop/DBus"),
                          QStringLiteral("org.freedesktop.DBus"), bus);
    lookup.setTimeout(kDbusCallTimeoutMs);
    const QDBusMessage reply =
        lookup.call(QStringLiteral("GetConnectionUnixProcessID"), service);
    return reply.type() == QDBusMessage::ReplyMessage
            && !reply.arguments().isEmpty()
        ? reply.arguments().constFirst().toUInt() : 0U;
}

QString dbusPathOf(const QVariant &value)
{
    return value.metaType() == QMetaType::fromType<QDBusObjectPath>()
        ? qvariant_cast<QDBusObjectPath>(value).path() : QString();
}

// QDBusConnection::systemBus() is bound to the calling thread, so pool
// workers open a per-call private connection instead. The name embeds the
// worker tag, the thread id plus this worker's serial so two queued workers
// sharing a pool thread can never collide on the registry entry.
QString workerBusName(const QString &tag)
{
    static std::atomic<quint64> serial{0};
    return QStringLiteral("kos-%1-%2-%3")
        .arg(tag)
        .arg(quintptr(QThread::currentThreadId()), 0, 16)
        .arg(serial.fetch_add(1, std::memory_order_relaxed));
}

} // namespace KosPlatform::Detail
