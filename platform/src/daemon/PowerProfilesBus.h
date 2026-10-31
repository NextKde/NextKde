#pragma once

#include <QDBusConnection>
#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <QVariant>
#include <QObject>
#include <functional>

namespace KosPlatform {

// powerprofilesctl remains the transport when it is installed. These helpers
// are the fallback for daemons that implement the same API on D-Bus only,
// notably Fedora's tuned-ppd.
bool powerProfilesCommandAvailable();

struct PowerProfileSnapshot {
    bool ok = false;
    bool timedOut = false;
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

// Completion is delivered on context's thread. Destroying context cancels delivery.
// The deadline bounds the whole operation, including endpoint fallback and Set.
using PowerProfileCompletion = std::function<void(PowerProfileSnapshot)>;
void requestPowerProfiles(const QDBusConnection &bus, QObject *context,
                          PowerProfileCompletion completion, const QString &profile = {});

} // namespace KosPlatform
