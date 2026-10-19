#include "PlatformDbus.h"
#include "PlatformNetworkBackend.h"

#include <QByteArray>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QList>
#include <QMetaType>
#include <QSet>
#include <QVariant>

namespace KosPlatform {
using namespace Detail;

namespace {

struct NmWirelessInfo {
    QString ssid;
    int strength = -1;
    QString accessPointPath;
};

// NMConnectivity enum -> the strings nmcli printed, so the contract result
// keeps the same vocabulary.
QString nmConnectivityName(uint connectivity)
{
    switch (connectivity) {
    case 1: return QStringLiteral("none");
    case 2: return QStringLiteral("portal");
    case 3: return QStringLiteral("limited");
    case 4: return QStringLiteral("full");
    default: return QStringLiteral("unknown");
    }
}

// NMDeviceState -> the strings the old nmcli parser produced.
QString nmDeviceStateName(uint state)
{
    if (state == 100)
        return QStringLiteral("connected");
    if (state == 30)
        return QStringLiteral("disconnected");
    if (state >= 40 && state <= 110)
        return QStringLiteral("connecting");
    return QStringLiteral("unknown");
}

// Every path read through here is appended to `watched` so the caller can
// subscribe PropertiesChanged and drop the reply cache as soon as any piece
QString nmReadActiveConnectionId(const QDBusConnection &bus,
                                 const QString &activeConnectionPath,
                                 QSet<QString> *watched)
{
    if (activeConnectionPath.isEmpty() || activeConnectionPath == QStringLiteral("/"))
        return {};
    if (watched)
        watched->insert(activeConnectionPath);
    return nmGetAll(bus, activeConnectionPath,
                    QStringLiteral("org.freedesktop.NetworkManager.Connection.Active"))
        .value(QStringLiteral("Id")).toString();
}

QString nmReadIpv4(const QDBusConnection &bus, const QString &ip4ConfigPath,
                   QSet<QString> *watched)
{
    if (ip4ConfigPath.isEmpty() || ip4ConfigPath == QStringLiteral("/"))
        return {};
    if (watched)
        watched->insert(ip4ConfigPath);
    const QVariantMap props = nmGetAll(bus, ip4ConfigPath,
        QStringLiteral("org.freedesktop.NetworkManager.IP4Config"));
    const QVariant addressData = props.value(QStringLiteral("AddressData"));
    if (addressData.metaType() != QMetaType::fromType<QDBusArgument>())
        return {};
    QDBusArgument argument = qvariant_cast<QDBusArgument>(addressData);
    argument.beginArray();
    QString address;
    while (!argument.atEnd()) {
        // aa{sv}: each a{sv} element demarshals straight into QVariantMap.
        // No endArray() -- the local argument is discarded anyway, and calling
        // it on a received message only prints a "read-only object" warning.
        QVariantMap fields;
        argument >> fields;
        const QString found = fields.value(QStringLiteral("address")).toString();
        if (!found.isEmpty() && address.isEmpty())
            address = found;
    }
    return address;
}

NmWirelessInfo nmReadWireless(const QDBusConnection &bus,
                              const QVariantMap &deviceProps,
                              QSet<QString> *watched)
{
    NmWirelessInfo info;
    info.accessPointPath = dbusPathOf(
        deviceProps.value(QStringLiteral("ActiveAccessPoint")));
    if (info.accessPointPath.isEmpty() || info.accessPointPath == QStringLiteral("/"))
        return info;
    if (watched)
        watched->insert(info.accessPointPath);
    const QVariantMap accessPoint = nmGetAll(bus, info.accessPointPath,
        QStringLiteral("org.freedesktop.NetworkManager.AccessPoint"));
    const QByteArray ssid = accessPoint.value(QStringLiteral("Ssid")).toByteArray();
    if (!ssid.isEmpty())
        info.ssid = QString::fromUtf8(ssid);
    info.strength = qBound(0,
        accessPoint.value(QStringLiteral("Strength")).toInt(), 100);
    return info;
}

} // namespace

namespace Detail {

QVariantMap nmGetAll(const QDBusConnection &bus, const QString &path,
                     const QString &interface)
{
    return dbusGetAll(bus, kNmService, path, interface);
}

// The GetDevices method call both network workers need; bounded like every
// other D-Bus round-trip.
QList<QDBusObjectPath> nmGetDevices(const QDBusConnection &bus)
{
    QDBusInterface networkManager(QString::fromLatin1(kNmService),
                                  QString::fromLatin1(kNmRootPath),
                                  QString::fromLatin1(kNmService), bus);
    networkManager.setTimeout(kDbusCallTimeoutMs);
    const QDBusMessage reply = networkManager.call(QStringLiteral("GetDevices"));
    if (reply.type() == QDBusMessage::ReplyMessage
        && !reply.arguments().isEmpty())
        return qdbus_cast<QList<QDBusObjectPath>>(reply.arguments().constFirst());
    return {};
}

// Runs on m_dbusPool: the whole N+1 NM walk (registration check, manager
// GetAll, GetDevices, per-device GetAll/AC/Ip4/Wireless reads) is synchronous
// D-Bus and used to stall the socket event loop for seconds on slow-NM
// systems. watchNmPath is deliberately NOT called here -- it mutates
// m_nmWatchedPaths and registers signal matches on the main bus, so the
// touched paths go home in watchPaths for the main thread to subscribe.
NetworkWorkerResult networkRefreshWorker()
{
    const ScopedBusConnection guard(workerBusName(QStringLiteral("net")));
    const QDBusConnection bus = QDBusConnection::connectToBus(
        QDBusConnection::SystemBus, guard.name);

    NetworkWorkerResult out;
    QSet<QString> watched{QString::fromLatin1(kNmRootPath)};

    if (!dbusServiceRegistered(bus, QString::fromLatin1(kNmService))) {
        out.code = QStringLiteral("network-unavailable");
        out.message = QStringLiteral("平台网络状态查询失败");
        return out;
    }

    const QVariantMap manager = nmGetAll(bus, QString::fromLatin1(kNmRootPath),
                                         QString::fromLatin1(kNmService));
    if (manager.isEmpty()) {
        // A transient GetAll failure would otherwise serialize as
        // wifiEnabled:false/"unknown" -- answer retryable instead of caching
        // fabricated state for the Shell to render.
        out.code = QStringLiteral("network-unavailable");
        out.message = QStringLiteral("平台网络状态查询失败");
        return out;
    }

    const QList<QDBusObjectPath> devicePaths = nmGetDevices(bus);

    // Same selection the nmcli table drove: the first wifi/ethernet row,
    // overridden by the activated one.
    QVariantMap selected;
    QString selectedPath;
    // Record the first wireless interface separately: the selected device
    // answers "what carries connectivity" (ethernet wins while Wi-Fi is
    // idle), but the shell's Wi-Fi list needs the radio's ifname even when
    // it is not the selected device. Empty when no usable wifi hardware
    // exists.
    QString wifiDeviceName;
    for (const QDBusObjectPath &devicePath : devicePaths) {
        watched.insert(devicePath.path());
        const QVariantMap device = nmGetAll(bus, devicePath.path(),
            QStringLiteral("org.freedesktop.NetworkManager.Device"));
        const uint type = device.value(QStringLiteral("DeviceType")).toUInt();
        if (type != 1 && type != 2)
            continue;
        if (type == 2 && wifiDeviceName.isEmpty())
            wifiDeviceName = device.value(QStringLiteral("Interface")).toString();
        const uint state = device.value(QStringLiteral("State")).toUInt();
        if (selected.isEmpty()
            || (state == 100 && selected.value(QStringLiteral("State")).toUInt() != 100)) {
            selected = device;
            selectedPath = devicePath.path();
        }
    }

    const uint type = selected.value(QStringLiteral("DeviceType")).toUInt();
    const uint state = selected.value(QStringLiteral("State")).toUInt();
    const QString deviceState = nmDeviceStateName(state);
    QString connectionName;
    QString ssid;
    QString ipv4;
    int signalStrength = -1;
    if (!selected.isEmpty() && state == 100) {
        connectionName = nmReadActiveConnectionId(bus,
            dbusPathOf(selected.value(QStringLiteral("ActiveConnection"))),
            &watched);
        if (type == 2) {
            const NmWirelessInfo wifi = nmReadWireless(bus,
                nmGetAll(bus, selectedPath,
                         QStringLiteral("org.freedesktop.NetworkManager.Device.Wireless")),
                &watched);
            ssid = wifi.ssid;
            signalStrength = wifi.strength;
        }
        ipv4 = nmReadIpv4(bus,
            dbusPathOf(selected.value(QStringLiteral("Ip4Config"))), &watched);
        if (ssid.isEmpty() && type == 2)
            ssid = connectionName;
        // The follow-up network.details request the Shell fires after every
        // refresh asks for exactly these fields -- prefill its cache so the
        // second request stays local.
        out.detailsKey = QStringLiteral("network.details:")
            + selected.value(QStringLiteral("Interface")).toString();
        if (!out.detailsKey.endsWith(QLatin1Char(':')))
            out.detailsPrefill = QJsonObject{
                {QStringLiteral("available"), true},
                {QStringLiteral("connectionName"), connectionName},
                {QStringLiteral("ssid"), ssid},
                {QStringLiteral("ipv4"), ipv4},
                {QStringLiteral("signalStrength"), signalStrength}};
    }

    out.result = QJsonObject{
        {QStringLiteral("available"), true},
        {QStringLiteral("networkingEnabled"),
         manager.value(QStringLiteral("NetworkingEnabled")).toBool()},
        {QStringLiteral("connectivity"),
         nmConnectivityName(manager.value(QStringLiteral("Connectivity")).toUInt())},
        {QStringLiteral("wifiEnabled"),
         manager.value(QStringLiteral("WirelessEnabled")).toBool()},
        {QStringLiteral("connectionType"),
         type == 2 ? QStringLiteral("wifi")
                   : type == 1 ? QStringLiteral("ethernet") : QStringLiteral("none")},
        {QStringLiteral("deviceName"), selected.value(QStringLiteral("Interface")).toString()},
        {QStringLiteral("wifiDeviceName"), wifiDeviceName},
        {QStringLiteral("connectionName"), connectionName},
        {QStringLiteral("deviceState"), deviceState},
        {QStringLiteral("ssid"), ssid},
        {QStringLiteral("signalStrength"), signalStrength},
        {QStringLiteral("ipv4"), ipv4}};
    out.ok = true;
    out.watchPaths = watched.values();
    return out;
}

// Same worker-thread walk for network.details:<device>: find the device by
// Interface name, then read its ActiveConnection/Ip4Config/Wireless state.
NetworkWorkerResult networkDetailsWorker(const QString &device)
{
    const ScopedBusConnection guard(workerBusName(QStringLiteral("net")));
    const QDBusConnection bus = QDBusConnection::connectToBus(
        QDBusConnection::SystemBus, guard.name);

    NetworkWorkerResult out;
    QSet<QString> watched{QString::fromLatin1(kNmRootPath)};

    if (!dbusServiceRegistered(bus, QString::fromLatin1(kNmService))) {
        out.code = QStringLiteral("network-unavailable");
        out.message = QStringLiteral("平台命令不可用");
        return out;
    }

    QVariantMap found;
    QString foundPath;
    const QList<QDBusObjectPath> devicePaths = nmGetDevices(bus);
    for (const QDBusObjectPath &devicePath : devicePaths) {
        watched.insert(devicePath.path());
        const QVariantMap props = nmGetAll(bus, devicePath.path(),
            QStringLiteral("org.freedesktop.NetworkManager.Device"));
        if (props.value(QStringLiteral("Interface")).toString() == device) {
            found = props;
            foundPath = devicePath.path();
            break;
        }
    }
    if (found.isEmpty()) {
        out.code = QStringLiteral("network-device-unavailable");
        out.message = QStringLiteral("平台命令执行失败");
        return out;
    }

    const QString connectionName = nmReadActiveConnectionId(bus,
        dbusPathOf(found.value(QStringLiteral("ActiveConnection"))), &watched);
    const QString ipv4 = nmReadIpv4(bus,
        dbusPathOf(found.value(QStringLiteral("Ip4Config"))), &watched);
    QString ssid = connectionName;
    int signalStrength = -1;
    if (found.value(QStringLiteral("DeviceType")).toUInt() == 2) {
        const NmWirelessInfo wifi = nmReadWireless(bus,
            nmGetAll(bus, foundPath,
                     QStringLiteral("org.freedesktop.NetworkManager.Device.Wireless")),
            &watched);
        if (!wifi.ssid.isEmpty())
            ssid = wifi.ssid;
        signalStrength = wifi.strength;
    }

    out.result = QJsonObject{{QStringLiteral("available"), true},
                             {QStringLiteral("connectionName"), connectionName},
                             {QStringLiteral("ssid"), ssid},
                             {QStringLiteral("ipv4"), ipv4},
                             {QStringLiteral("macAddress"), found.value(QStringLiteral("HwAddress")).toString()},
                             {QStringLiteral("signalStrength"), signalStrength}};
    out.ok = true;
    out.watchPaths = watched.values();
    return out;
}

} // namespace Detail

} // namespace KosPlatform
