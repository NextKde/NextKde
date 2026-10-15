#include "PlatformServer.h"
#include "PlatformDbus.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDir>
#include <QJsonArray>
#include <QMetaType>
#include <QRegularExpression>
#include <QVariant>

namespace KosPlatform {
using namespace Detail;

namespace {

constexpr int kBluetoothCacheTtlMs = 20000;

} // namespace

void PlatformServer::runBluetoothList(QLocalSocket *socket, const QJsonObject &request)
{
    const QString key = QStringLiteral("bluetooth.list");
    if (serveCachedReply(socket, request, key))
        return;

    // With no Bluetooth hardware at all there is nothing BlueZ could report;
    // answer without a D-Bus round-trip.
    const QDir bluetoothClass(QStringLiteral("/sys/class/bluetooth"));
    const bool hasHardware = bluetoothClass.exists()
        && !bluetoothClass.entryList(QDir::Dirs | QDir::NoDotAndDotDot).isEmpty();
    const QDBusConnection bus = QDBusConnection::systemBus();
    const bool serviceRegistered = hasHardware
        && dbusServiceRegistered(bus, QString::fromLatin1(kBluezService));
    // Arm the ObjectManager watch even while the service is down so BlueZ
    // appearing later invalidates the "unavailable" snapshot instead of
    // waiting out the TTL.
    if (hasHardware)
        watchBluezManager();
    if (!serviceRegistered) {
        const QJsonObject result{{QStringLiteral("available"), false},
                                 {QStringLiteral("powered"), false},
                                 {QStringLiteral("devices"), QJsonArray{}}};
        respond(socket, request, true, result);
        storeReply(key, kBluetoothCacheTtlMs, true, result);
        return;
    }

    // BlueZ exposes the full adapter/device tree through its ObjectManager;
    // one GetManagedObjects replaces the bluetoothctl show+devices chain.
    QDBusInterface objectManager(QString::fromLatin1(kBluezService),
                                 QStringLiteral("/"),
                                 QStringLiteral("org.freedesktop.DBus.ObjectManager"),
                                 bus);
    objectManager.setTimeout(kDbusCallTimeoutMs);
    const QDBusMessage reply = objectManager.call(QStringLiteral("GetManagedObjects"));
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty()
        || reply.arguments().constFirst().metaType()
            != QMetaType::fromType<QDBusArgument>()) {
        const QString code = QStringLiteral("command-failed");
        const QString message = QStringLiteral("无法读取蓝牙状态");
        respond(socket, request, false, {}, code, message, true);
        storeReply(key, kBluetoothCacheTtlMs, false, {}, code, message, true);
        return;
    }
    QDBusArgument argument = qvariant_cast<QDBusArgument>(reply.arguments().constFirst());
    // a{oa{sa{sv}}}: declare the nested map types so the template extractor
    // demarshals each level -- nested dicts landing in a bare QVariant end up
    // as unusable QDBusArgument/void* payloads.
    QMap<QDBusObjectPath, QMap<QString, QVariantMap>> objects;
    argument >> objects;

    bool adapterFound = false;
    bool powered = false;
    QJsonArray devices;
    for (auto it = objects.constBegin(); it != objects.constEnd(); ++it) {
        watchBluezPath(it.key().path());
        const QVariantMap adapter = it.value().value(QStringLiteral("org.bluez.Adapter1"));
        if (!adapter.isEmpty()) {
            adapterFound = true;
            powered = powered || adapter.value(QStringLiteral("Powered")).toBool();
        }
        const QVariantMap device = it.value().value(QStringLiteral("org.bluez.Device1"));
        if (device.isEmpty())
            continue;
        // The bluetoothctl `devices` list this replaces reported the paired
        // set; keep that scope (plus anything actually connected).
        if (!device.value(QStringLiteral("Paired")).toBool()
            && !device.value(QStringLiteral("Connected")).toBool())
            continue;
        QString name = device.value(QStringLiteral("Name")).toString().trimmed();
        if (name.isEmpty())
            name = device.value(QStringLiteral("Alias")).toString().trimmed();
        if (name.isEmpty())
            name = device.value(QStringLiteral("Address")).toString();
        devices.append(QJsonObject{
            {QStringLiteral("address"), device.value(QStringLiteral("Address")).toString()},
            {QStringLiteral("name"), name},
            {QStringLiteral("paired"), device.value(QStringLiteral("Paired")).toBool()},
            // The text parser could never fill this in; ObjectManager carries
            // the real link state.
            {QStringLiteral("connected"), device.value(QStringLiteral("Connected")).toBool()}});
    }
    const QJsonObject result{{QStringLiteral("available"), adapterFound},
                             {QStringLiteral("powered"), powered},
                             {QStringLiteral("devices"), devices}};
    respond(socket, request, true, result);
    storeReply(key, kBluetoothCacheTtlMs, true, result);
}

bool PlatformServer::handleBluetoothOperation(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();
    if (op == QStringLiteral("bluetooth.power")) {
        invalidateReplies(QStringLiteral("bluetooth."));
        runCommand(socket, request, QStringLiteral("bluetoothctl"),
                   {QStringLiteral("power"), payload.value(QStringLiteral("enabled")).toBool() ? QStringLiteral("on") : QStringLiteral("off")},
                   {}, 15000);
        return true;
    }
    if (op == QStringLiteral("bluetooth.list")) {
        runBluetoothList(socket, request);
        return true;
    }
    if (op == QStringLiteral("bluetooth.connect") || op == QStringLiteral("bluetooth.disconnect")) {
        invalidateReplies(QStringLiteral("bluetooth."));
        const QString address = payload.value(QStringLiteral("address")).toString().trimmed();
        static const QRegularExpression addressPattern(QStringLiteral("^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$"));
        if (!addressPattern.match(address).hasMatch()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-address"),
                    QStringLiteral("蓝牙地址无效"), false);
            return true;
        }
        runCommand(socket, request, QStringLiteral("bluetoothctl"),
                   {op == QStringLiteral("bluetooth.connect") ? QStringLiteral("connect") : QStringLiteral("disconnect"), address},
                   {}, 75000);
        return true;
    }
    return false;
}

} // namespace KosPlatform
