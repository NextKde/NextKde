#include "PlatformDbus.h"
#include "PlatformNetworkBackend.h"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDateTime>
#include <QList>
#include <QStringList>
#include <QThread>
#include <QUuid>
#include <QVariant>

namespace KosPlatform {
using namespace Detail;

namespace {

constexpr int kNetworkConnectWaitMs = 30000;

constexpr auto kNmSettingsPath = "/org/freedesktop/NetworkManager/Settings";

constexpr auto kNmSettingsInterface = "org.freedesktop.NetworkManager.Settings";

constexpr auto kNmConnectionInterface =
    "org.freedesktop.NetworkManager.Settings.Connection";

constexpr auto kNmDeviceInterface = "org.freedesktop.NetworkManager.Device";

struct NmConnectionTarget {
    QString settingsPath;
    QString uuid;
    QString error;
};

// NMDeviceState: 30 = disconnected, 100 = activated, 120 = failed, 40-110 =
// the transition states in between.

QString nmDevicePathByInterface(const QDBusConnection &bus, const QString &device)
{
    const QList<QDBusObjectPath> devicePaths = nmGetDevices(bus);
    for (const QDBusObjectPath &devicePath : devicePaths) {
        const QVariantMap props = nmGetAll(bus, devicePath.path(),
                                           QString::fromLatin1(kNmDeviceInterface));
        if (props.value(QStringLiteral("Interface")).toString() == device)
            return devicePath.path();
    }
    return {};
}

// The generic 2 s bound applies to cheap reads; AddConnection + ActivateConnection
// are control-plane calls that must outlive an activation handshake, so they get
// the connect budget instead.
QDBusMessage nmCallBounded(const QDBusConnection &bus, const QString &path,
                           const QString &interface, const QString &method,
                           const QVariantList &arguments, int timeoutMs)
{
    QDBusInterface iface(QString::fromLatin1(kNmService), path,
                         interface, bus);
    iface.setTimeout(timeoutMs);
    return iface.callWithArgumentList(QDBus::BlockWithGui, method, arguments);
}

// The outer map must carry maps as values, not variants: AddConnection
// expects a{sa{sv}}. QVariantMap supplies the variants in each inner map.
NmSettings nmConnectionSettings(const QString &id, const QString &type,
                                 const QVariantMap &section)
{
    QVariantMap connection{{QStringLiteral("id"), id},
                           {QStringLiteral("type"), type},
                           {QStringLiteral("uuid"),
                            QUuid::createUuid().toString(QUuid::WithoutBraces)}};
    NmSettings settings{{QStringLiteral("connection"), connection}};
    for (auto it = section.constBegin(); it != section.constEnd(); ++it) {
        settings.insert(it.key(), it.value().toMap());
    }
    return settings;
}

// Poll the specific activation returned by ActivateConnection. Device.State
// can still describe the previous connection while switching networks.
bool nmWaitConnectionActivated(const QDBusConnection &bus, const QString &activePath,
                           int timeoutMs)
{
    const qint64 deadline = QDateTime::currentMSecsSinceEpoch() + timeoutMs;
    while (QDateTime::currentMSecsSinceEpoch() < deadline) {
        const QVariantMap props = nmGetAll(bus, activePath,
            QStringLiteral("org.freedesktop.NetworkManager.Connection.Active"));
        if (props.isEmpty())
            return false;
        const uint state = props.value(QStringLiteral("State")).toUInt();
        if (state == 2)
            return true;
        if (state >= 3)
            return false;
        QThread::msleep(250);
    }
    return false;
}

// Find a saved profile by UUID (savedProfileUuid flow) or by the profile id
// the enterprise op owns. Returns a target with error set when the lookup
// itself failed (as opposed to "not found", which is a valid answer).
NmConnectionTarget nmFindConnection(const QDBusConnection &bus,
                                    const QString &uuid, const QString &id)
{
    if (!uuid.isEmpty()) {
        const QDBusMessage reply = nmCallBounded(bus, QString::fromLatin1(kNmSettingsPath),
            QString::fromLatin1(kNmSettingsInterface), QStringLiteral("GetConnectionByUuid"),
            {uuid}, kDbusCallTimeoutMs);
        if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
            return {{}, {}, QStringLiteral("lookup")};
        return {qvariant_cast<QDBusObjectPath>(reply.arguments().first()).path(), uuid, {}};
    }
    const QDBusMessage reply = nmCallBounded(bus, QString::fromLatin1(kNmSettingsPath),
        QString::fromLatin1(kNmSettingsInterface), QStringLiteral("ListConnections"),
        {}, kDbusCallTimeoutMs);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
        return {QString(), QString(), QStringLiteral("list")};
    const QList<QDBusObjectPath> paths =
        qdbus_cast<QList<QDBusObjectPath>>(reply.arguments().constFirst());
    for (const QDBusObjectPath &path : paths) {
        const QDBusMessage settings = nmCallBounded(bus, path.path(),
            QString::fromLatin1(kNmConnectionInterface), QStringLiteral("GetSettings"),
            {}, kDbusCallTimeoutMs);
        if (settings.type() != QDBusMessage::ReplyMessage || settings.arguments().isEmpty())
            return {{}, {}, QStringLiteral("settings")};
        const QVariantMap connection = qdbus_cast<NmSettings>(settings.arguments().first())
            .value(QStringLiteral("connection"));
        const QString foundUuid = connection.value(QStringLiteral("uuid")).toString();
        const QString foundId = connection.value(QStringLiteral("id")).toString();
        if (!id.isEmpty() && foundId == id)
            return {path.path(), foundUuid, {}};
    }
    return {};
}

bool nmDeleteConnection(const QDBusConnection &bus, const QString &settingsPath)
{
    const QDBusMessage reply = nmCallBounded(bus, settingsPath,
        QString::fromLatin1(kNmConnectionInterface), QStringLiteral("Delete"),
        {}, kDbusCallTimeoutMs);
    return reply.type() == QDBusMessage::ReplyMessage;
}

} // namespace

namespace Detail {

// The settings dict for a WPA-PSK / open join. `key-mgmt` is omitted for open
// networks -- NM treats a missing wireless-security section as open.
NmSettings nmWifiSettings(const QString &ssid, const QString &password)
{
    QVariantMap wireless{{QStringLiteral("ssid"), ssid.toUtf8()},
                         {QStringLiteral("mode"), QStringLiteral("infrastructure")}};
    QVariantMap sections{{QStringLiteral("802-11-wireless"), wireless},
                         {QStringLiteral("ipv4"),
                          QVariantMap{{QStringLiteral("method"), QStringLiteral("auto")}}},
                         {QStringLiteral("ipv6"),
                          QVariantMap{{QStringLiteral("method"), QStringLiteral("auto")}}}};
    if (!password.isEmpty()) {
        sections.insert(QStringLiteral("802-11-wireless-security"),
                        QVariantMap{{QStringLiteral("key-mgmt"), QStringLiteral("wpa-psk")},
                                    {QStringLiteral("psk"), password}});
    }
    return nmConnectionSettings(ssid, QStringLiteral("802-11-wireless"), sections);
}

// The settings dict for a WPA-Enterprise join. `eap` is a string list (as), so
// it stays a QStringList; the anonymous identity is optional.
NmSettings nmEnterpriseSettings(const QString &profile, const QString &ssid,
                                 const QString &identity, const QString &password,
                                 const QString &eapMethod, const QString &phase2,
                                 const QString &anonymous)
{
    QVariantMap wireless{{QStringLiteral("ssid"), ssid.toUtf8()},
                         {QStringLiteral("mode"), QStringLiteral("infrastructure")}};
    QVariantMap eap{{QStringLiteral("eap"), QStringList{eapMethod}},
                    {QStringLiteral("identity"), identity},
                    {QStringLiteral("password"), password},
                    {QStringLiteral("phase2-auth"), phase2}};
    if (!anonymous.isEmpty())
        eap.insert(QStringLiteral("anonymous-identity"), anonymous);
    QVariantMap sections{{QStringLiteral("802-11-wireless"), wireless},
        {QStringLiteral("802-11-wireless-security"),
         QVariantMap{{QStringLiteral("key-mgmt"), QStringLiteral("wpa-eap")}}},
        {QStringLiteral("802-1x"), eap},
        {QStringLiteral("ipv4"),
         QVariantMap{{QStringLiteral("method"), QStringLiteral("auto")}}},
        {QStringLiteral("ipv6"),
         QVariantMap{{QStringLiteral("method"), QStringLiteral("auto")}}}};
    return nmConnectionSettings(profile, QStringLiteral("802-11-wireless"), sections);
}

// Runs the whole connect on m_dbusPool: resolve the device, optionally drop a
// same-named stale profile, add the connection, activate it, and poll the
// device to the settled state nmcli --wait used to report.
NetworkWorkerResult networkConnectWorker(const QString &device,
                                         const QString &savedProfileUuid,
                                         const NmSettings &settings,
                                         const QString &replaceProfileId)
{
    const ScopedBusConnection guard(workerBusName(QStringLiteral("net")));
    const QDBusConnection bus = QDBusConnection::connectToBus(
        QDBusConnection::SystemBus, guard.name);

    NetworkWorkerResult out;
    out.code = QStringLiteral("network-failed");
    out.message = QStringLiteral("网络连接失败");

    if (!dbusServiceRegistered(bus, QString::fromLatin1(kNmService))) {
        out.code = QStringLiteral("network-unavailable");
        out.message = QStringLiteral("网络服务不可用");
        return out;
    }
    const QString devicePath = nmDevicePathByInterface(bus, device);
    if (devicePath.isEmpty()) {
        out.code = QStringLiteral("network-device-unavailable");
        out.message = QStringLiteral("网络设备不可用");
        return out;
    }

    QString connectionPath;
    if (!savedProfileUuid.isEmpty()) {
        const NmConnectionTarget saved = nmFindConnection(bus, savedProfileUuid, {});
        if (saved.settingsPath.isEmpty()) {
            out.code = saved.error.isEmpty() ? QStringLiteral("network-failed")
                                           : QStringLiteral("network-unavailable");
            out.message = QStringLiteral("网络配置不存在");
            return out;
        }
        connectionPath = saved.settingsPath;
    } else {
        // The enterprise flow replaces its own profile so a retry always
        // starts from a clean settings dict instead of stacking updates.
        if (!replaceProfileId.isEmpty()) {
            const NmConnectionTarget stale = nmFindConnection(bus, {}, replaceProfileId);
            if (!stale.error.isEmpty())
                return out; // the list call itself failed
            if (!stale.settingsPath.isEmpty() && !nmDeleteConnection(bus, stale.settingsPath))
                return out;
        }
        const QDBusMessage added = nmCallBounded(bus,
            QString::fromLatin1(kNmSettingsPath),
            QString::fromLatin1(kNmSettingsInterface),
            QStringLiteral("AddConnection"),
            {QVariant::fromValue(settings)},
            kNetworkConnectWaitMs);
        if (added.type() != QDBusMessage::ReplyMessage || added.arguments().isEmpty())
            return out;
        connectionPath = qvariant_cast<QDBusObjectPath>(
            added.arguments().constFirst()).path();
        if (connectionPath.isEmpty())
            return out;
    }

    const QDBusMessage activated = nmCallBounded(bus,
        QString::fromLatin1(kNmRootPath), QString::fromLatin1(kNmService),
        QStringLiteral("ActivateConnection"),
        {QVariant::fromValue(QDBusObjectPath(connectionPath)),
         QVariant::fromValue(QDBusObjectPath(devicePath)),
         QVariant::fromValue(QDBusObjectPath(QStringLiteral("/")))},
        kNetworkConnectWaitMs);
    if (activated.type() != QDBusMessage::ReplyMessage || activated.arguments().isEmpty())
        return out;

    // --wait parity: ActivateConnection only means NM accepted the request.
    const QString activePath = qvariant_cast<QDBusObjectPath>(activated.arguments().first()).path();
    if (activePath.isEmpty() || activePath == QStringLiteral("/")
        || !nmWaitConnectionActivated(bus, activePath, kNetworkConnectWaitMs))
        return out;

    out.ok = true;
    out.result = QJsonObject{{QStringLiteral("connected"), true}};
    out.watchPaths = {devicePath};
    return out;
}

} // namespace Detail

} // namespace KosPlatform
