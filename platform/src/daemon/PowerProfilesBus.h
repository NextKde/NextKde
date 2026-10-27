#pragma once

#include <QDBusConnection>
#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <QVariant>

namespace KosPlatform {

// powerprofilesctl remains the transport when it is installed. These helpers
// are the fallback for daemons that implement the same API on D-Bus only,
// notably Fedora's tuned-ppd.
bool powerProfilesCommandAvailable();

struct PowerProfileSnapshot {
    bool ok = false;
    QString service;
    QString path;
    QString interface;
    QStringList profiles;
    QString activeProfile;
    QString degraded;
};

// Accepts the Profiles property as a QDBusArgument array of dicts or as a
// QVariantList of maps. Unknown names are dropped. Returns false when the
// value is not an array.
bool decodePowerProfileList(const QVariant &value, QStringList *profiles);

// powerprofilesctl prints "Degraded: no" when performance is not limited.
QString normalizePowerDegradation(const QString &value);

QJsonObject powerProfileObject(const PowerProfileSnapshot &snapshot);

PowerProfileSnapshot readPowerProfiles(const QDBusConnection &bus);
bool writePowerProfile(const QDBusConnection &bus, const QString &profile);

} // namespace KosPlatform
