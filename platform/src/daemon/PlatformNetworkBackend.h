#pragma once

#include <QDBusConnection>
#include <QDBusObjectPath>
#include <QJsonObject>
#include <QMap>
#include <QVariantMap>
#include <QStringList>

// Implementation-only contracts; not part of the JSONL protocol.
namespace KosPlatform {

using NmSettings = QMap<QString, QVariantMap>;

// One connect request: the settings dict already carries every secret, so the
// runner treats this as opaque data. The map never lands in a log or an argv
// -- it goes straight into AddConnection.
struct NmConnectRequest {
    QString device;
    QString savedProfileUuid;
    NmSettings settings;
    QString replaceProfileId;
};

namespace Detail {

struct NetworkWorkerResult {
    bool ok = false;
    bool retryable = true;
    QString code;
    QString message;
    QJsonObject result;
    QJsonObject detailsPrefill;
    QString detailsKey;
    QStringList watchPaths;
};

inline constexpr auto kNmRootPath = "/org/freedesktop/NetworkManager";

inline constexpr auto kNmService = "org.freedesktop.NetworkManager";

NetworkWorkerResult networkConnectWorker(const QString &device,
                                         const QString &savedProfileUuid,
                                         const NmSettings &settings,
                                         const QString &replaceProfileId);

NetworkWorkerResult networkDetailsWorker(const QString &device);

NetworkWorkerResult networkRefreshWorker();

NmSettings nmEnterpriseSettings(const QString &profile, const QString &ssid,
                                 const QString &identity, const QString &password,
                                 const QString &eapMethod, const QString &phase2,
                                 const QString &anonymous);

QVariantMap nmGetAll(const QDBusConnection &bus, const QString &path,
                     const QString &interface);

QList<QDBusObjectPath> nmGetDevices(const QDBusConnection &bus);

NmSettings nmWifiSettings(const QString &ssid, const QString &password);

} // namespace Detail
} // namespace KosPlatform
