#include "PowerProfilesBus.h"

#include "PlatformDbus.h"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusVariant>
#include <QJsonArray>
#include <QStandardPaths>

namespace KosPlatform {
namespace {

struct Endpoint {
    const char *service;
    const char *path;
    const char *interface;
};

// Newer UPower name first. tuned-ppd and power-profiles-daemon each own one
// or both; the first name that answers is the one a later Set uses.
constexpr Endpoint kEndpoints[] = {
    {"org.freedesktop.UPower.PowerProfiles",
     "/org/freedesktop/UPower/PowerProfiles",
     "org.freedesktop.UPower.PowerProfiles"},
    {"net.hadess.PowerProfiles",
     "/net/hadess/PowerProfiles",
     "net.hadess.PowerProfiles"},
};

bool knownPowerProfile(const QString &profile)
{
    return profile == QLatin1String("power-saver")
        || profile == QLatin1String("balanced")
        || profile == QLatin1String("performance");
}

void appendKnown(const QString &name, QStringList *profiles)
{
    if (knownPowerProfile(name) && !profiles->contains(name))
        profiles->append(name);
}

bool decodeArgument(QDBusArgument argument, QStringList *profiles)
{
    if (argument.currentType() != QDBusArgument::ArrayType)
        return false;
    profiles->clear();
    argument.beginArray();
    while (!argument.atEnd()) {
        QVariantMap row;
        argument >> row;
        // a{sv} values arrive as QDBusVariant on some Qt builds and as the
        // inner string on others. unwrap is a no-op for a plain string.
        appendKnown(Detail::unwrapDbusValue(row.value(QStringLiteral("Profile"))).toString(),
                    profiles);
    }
    argument.endArray();
    return true;
}

} // namespace

bool powerProfilesCommandAvailable()
{
    return !QStandardPaths::findExecutable(QStringLiteral("powerprofilesctl")).isEmpty();
}

bool decodePowerProfileList(const QVariant &value, QStringList *profiles)
{
    if (!profiles)
        return false;
    const QVariant unwrapped = Detail::unwrapDbusValue(value);
    if (unwrapped.metaType() == QMetaType::fromType<QDBusArgument>())
        return decodeArgument(qvariant_cast<QDBusArgument>(unwrapped), profiles);
    // canConvert<QVariantList>() is true for unrelated types such as QString.
    if (unwrapped.metaType() != QMetaType::fromType<QVariantList>())
        return false;
    profiles->clear();
    for (const QVariant &entry : unwrapped.toList())
        appendKnown(Detail::variantMapFromDbusValue(entry).value(QStringLiteral("Profile")).toString(),
                    profiles);
    return true;
}

QString normalizePowerDegradation(const QString &value)
{
    const QString text = value.trimmed();
    return text.isEmpty() || text == QLatin1String("no") ? QString() : text;
}

QJsonObject powerProfileObject(const PowerProfileSnapshot &snapshot)
{
    QJsonArray profiles;
    for (const QString &name : snapshot.profiles)
        profiles.append(name);
    return {{QStringLiteral("profiles"), profiles},
            {QStringLiteral("activeProfile"), snapshot.activeProfile},
            {QStringLiteral("degraded"), snapshot.degraded}};
}

PowerProfileSnapshot readPowerProfiles(const QDBusConnection &bus)
{
    PowerProfileSnapshot snapshot;
    for (const Endpoint &endpoint : kEndpoints) {
        if (!Detail::dbusServiceRegistered(bus, QString::fromUtf8(endpoint.service)))
            continue;
        const QVariant profilesValue = Detail::dbusGetProperty(
            bus, QString::fromUtf8(endpoint.service), QString::fromUtf8(endpoint.path),
            QString::fromUtf8(endpoint.interface), QStringLiteral("Profiles"));
        const QVariant activeValue = Detail::dbusGetProperty(
            bus, QString::fromUtf8(endpoint.service), QString::fromUtf8(endpoint.path),
            QString::fromUtf8(endpoint.interface), QStringLiteral("ActiveProfile"));
        QStringList profiles;
        if (!profilesValue.isValid() || !activeValue.isValid()
            || !decodePowerProfileList(profilesValue, &profiles))
            continue;
        const QVariant degraded = Detail::dbusGetProperty(
            bus, QString::fromUtf8(endpoint.service), QString::fromUtf8(endpoint.path),
            QString::fromUtf8(endpoint.interface), QStringLiteral("PerformanceDegraded"));
        snapshot.ok = true;
        snapshot.service = QString::fromUtf8(endpoint.service);
        snapshot.path = QString::fromUtf8(endpoint.path);
        snapshot.interface = QString::fromUtf8(endpoint.interface);
        snapshot.profiles = profiles;
        snapshot.activeProfile = activeValue.toString();
        snapshot.degraded = degraded.isValid()
            ? normalizePowerDegradation(degraded.toString()) : QString();
        return snapshot;
    }
    return snapshot;
}

bool writePowerProfile(const QDBusConnection &bus, const QString &profile)
{
    if (!knownPowerProfile(profile))
        return false;
    const PowerProfileSnapshot snapshot = readPowerProfiles(bus);
    if (!snapshot.ok)
        return false;
    // The list watchdog is two seconds. Setting waits longer because a
    // policy agent may prompt before ActiveProfile changes; this matches
    // the powerprofilesctl set timeout in the daemon.
    QDBusInterface properties(snapshot.service, snapshot.path,
                              QStringLiteral("org.freedesktop.DBus.Properties"), bus);
    properties.setTimeout(10000);
    const QDBusMessage reply = properties.call(
        QStringLiteral("Set"), snapshot.interface, QStringLiteral("ActiveProfile"),
        QVariant::fromValue(QDBusVariant(profile)));
    return reply.type() == QDBusMessage::ReplyMessage;
}

} // namespace KosPlatform
