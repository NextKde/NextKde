#include "PlatformServer.h"
#include "PlatformNetworkBackend.h"
#include "PlatformProcess.h"

#include <QByteArray>
#include <QCryptographicHash>
#include <QFile>
#include <QFutureWatcher>
#include <QJsonArray>
#include <QJsonDocument>
#include <QList>
#include <QProcess>
#include <QRegularExpression>
#include <QStringList>
#include <QtConcurrent>
#include <algorithm>

namespace KosPlatform {
using namespace Detail;

namespace {

constexpr int kNetworkCacheTtlMs = 15000;

constexpr int kNetworkConnectTtlMs = 1000;

QStringList splitNmcli(const QString &line)
{
    QStringList fields;
    QString value;
    bool escaped = false;
    for (const QChar c : line) {
        if (escaped) {
            value += c;
            escaped = false;
        } else if (c == QChar('\\')) {
            escaped = true;
        } else if (c == QChar(':')) {
            fields.append(value);
            value.clear();
        } else {
            value += c;
        }
    }
    fields.append(value);
    return fields;
}

bool validNetworkDevice(const QString &device)
{
    // Linux interface names are at most IFNAMSIZ-1 bytes and cannot contain
    // path separators. Restricting the alphabet also keeps the sysfs path
    // below within /sys/class/net instead of relying on shell escaping.
    static const QRegularExpression pattern(QStringLiteral("^[A-Za-z0-9_.-]{1,15}$"));
    return pattern.match(device).hasMatch();
}

QJsonObject parseNetworkScan(const QByteArray &output, int exitCode)
{
    QJsonArray networks;
    if (exitCode == 0) {
        QHash<QString, QJsonObject> bySsid;
        for (const QString &line : QString::fromUtf8(output).split(QChar('\n'), Qt::SkipEmptyParts)) {
            const QStringList fields = splitNmcli(line);
            if (fields.size() < 4)
                continue;
            const QString ssid = fields.value(1).trimmed();
            if (ssid.isEmpty())
                continue;
            const int signal = qBound(0, fields.value(2).toInt(), 100);
            QJsonObject item{{QStringLiteral("ssid"), ssid},
                             {QStringLiteral("signalStrength"), signal},
                             {QStringLiteral("security"), fields.mid(3).join(QStringLiteral(":"))},
                             {QStringLiteral("secured"), !fields.mid(3).join(QStringLiteral(":")).trimmed().isEmpty()},
                             {QStringLiteral("enterprise"), fields.mid(3).join(QStringLiteral(":")).contains(QStringLiteral("802.1x"), Qt::CaseInsensitive)},
                             {QStringLiteral("active"), fields.value(0).trimmed() == QStringLiteral("*")}};
            const QJsonObject existing = bySsid.value(ssid);
            const int existingSignal = existing.value(QStringLiteral("signalStrength")).toInt();
            const bool replace = !bySsid.contains(ssid)
                || item.value(QStringLiteral("signalStrength")).toInt() > existingSignal
                // Multiple APs may advertise one SSID at exactly the same
                // strength. Preserve the associated BSSID in that tie so the
                // Shell keeps its connected checkmark after de-duplication.
                || (item.value(QStringLiteral("active")).toBool()
                    && !existing.value(QStringLiteral("active")).toBool());
            if (replace)
                bySsid.insert(ssid, item);
        }
        QList<QJsonObject> sorted;
        sorted.reserve(bySsid.size());
        for (const auto &item : bySsid)
            sorted.append(item);
        std::sort(sorted.begin(), sorted.end(), [](const QJsonObject &left,
                                                   const QJsonObject &right) {
            const bool leftActive = left.value(QStringLiteral("active")).toBool();
            const bool rightActive = right.value(QStringLiteral("active")).toBool();
            if (leftActive != rightActive)
                return leftActive;
            const int leftSignal = left.value(QStringLiteral("signalStrength")).toInt();
            const int rightSignal = right.value(QStringLiteral("signalStrength")).toInt();
            if (leftSignal != rightSignal)
                return leftSignal > rightSignal;
            return left.value(QStringLiteral("ssid")).toString()
                < right.value(QStringLiteral("ssid")).toString();
        });
        for (const auto &item : sorted)
            networks.append(item);
    }
    return QJsonObject{{QStringLiteral("available"), exitCode == 0},
                       {QStringLiteral("networks"), networks}};
}

QHash<QString, QString> parseSavedWifiProfiles(const QByteArray &output, int exitCode)
{
    QHash<QString, QString> profiles;
    if (exitCode != 0)
        return profiles;
    for (const QString &line : QString::fromUtf8(output).split(QChar('\n'), Qt::SkipEmptyParts)) {
        const QStringList fields = splitNmcli(line);
        if (fields.size() < 3 || fields.value(1) != QStringLiteral("802-11-wireless"))
            continue;
        const QString uuid = fields.value(0).trimmed();
        const QString ssid = fields.mid(2).join(QStringLiteral(":"));
        if (!uuid.isEmpty() && !ssid.isEmpty() && !profiles.contains(ssid))
            profiles.insert(ssid, uuid);
    }
    return profiles;
}

} // namespace

void PlatformServer::runNetworkRefresh(QLocalSocket *socket,
                                       const QJsonObject &request)
{
    const QString key = QStringLiteral("network.refresh");
    if (serveCachedReply(socket, request, key)
        || queueIfInFlight(key, socket, request))
        return;

    // The whole NM walk (registration check, GetAll, GetDevices, per-device
    // reads) is synchronous D-Bus; on m_dbusPool it cannot stall the socket
    // event loop for seconds the way it used to on a slow NetworkManager.
    auto *watcher = new QFutureWatcher<NetworkWorkerResult>(this);
    connect(watcher, &QFutureWatcher<NetworkWorkerResult>::finished, this,
            [this, watcher, key]() {
        watcher->deleteLater();
        const NetworkWorkerResult out = watcher->result();
        for (const QString &path : out.watchPaths)
            watchNmPath(path);
        // This refresh re-confirmed every live path (root + devices + the
        // selected connection's sub-objects); anything older than
        // kDbusStaleWatchMs is a leftover from a dead object.
        pruneStaleDbusWatches();
        if (!out.detailsKey.isEmpty() && !out.detailsKey.endsWith(QLatin1Char(':')))
            storeReply(out.detailsKey, kNetworkCacheTtlMs, true, out.detailsPrefill);
        completeInFlight(key, out.ok, out.result, out.code, out.message,
                         out.retryable, kNetworkCacheTtlMs);
    });
    watcher->setFuture(QtConcurrent::run(&m_dbusPool, networkRefreshWorker));
}

void PlatformServer::runNetworkDetails(QLocalSocket *socket,
                                       const QJsonObject &request,
                                       const QString &device)
{
    const QString key = QStringLiteral("network.details:") + device;
    if (serveCachedReply(socket, request, key)
        || queueIfInFlight(key, socket, request))
        return;

    auto *watcher = new QFutureWatcher<NetworkWorkerResult>(this);
    connect(watcher, &QFutureWatcher<NetworkWorkerResult>::finished, this,
            [this, watcher, key]() {
        watcher->deleteLater();
        const NetworkWorkerResult out = watcher->result();
        for (const QString &path : out.watchPaths)
            watchNmPath(path);
        pruneStaleDbusWatches();
        completeInFlight(key, out.ok, out.result, out.code, out.message,
                         out.retryable, kNetworkCacheTtlMs);
    });
    watcher->setFuture(QtConcurrent::run(&m_dbusPool, networkDetailsWorker,
                                         device));
}

// network.connect / network.connect-enterprise share one runner: the payload
// is already validated by the caller, so this only marshals the settings dict
// and parks the reply behind the worker. The short TTL dedupes the retry the
// panel fires while the user is staring at a spinner without letting a stale
// success mask a real failure.
void PlatformServer::runNetworkConnect(QLocalSocket *socket,
                                       const QJsonObject &request,
                                       const NmConnectRequest &connectRequest)
{
    // A retry with a corrected password/identity is a different request. Hash
    // the original payload so secrets never become plaintext cache keys and
    // the newly generated settings UUID does not defeat identical retries.
    const QByteArray payload = QJsonDocument(request.value(QStringLiteral("payload"))
        .toObject()).toJson(QJsonDocument::Compact);
    const QString key = QStringLiteral("network.connect:") + operation(request)
        + QLatin1Char(':') + QString::fromLatin1(
            QCryptographicHash::hash(payload, QCryptographicHash::Sha256).toHex());
    if (serveCachedReply(socket, request, key)
        || queueIfInFlight(key, socket, request))
        return;

    auto *watcher = new QFutureWatcher<NetworkWorkerResult>(this);
    connect(watcher, &QFutureWatcher<NetworkWorkerResult>::finished, this,
            [this, watcher, key]() {
        watcher->deleteLater();
        const NetworkWorkerResult out = watcher->result();
        for (const QString &path : out.watchPaths)
            watchNmPath(path);
        pruneStaleDbusWatches();
        completeInFlight(key, out.ok, out.result, out.code, out.message,
                         out.retryable, kNetworkConnectTtlMs);
    });
    watcher->setFuture(QtConcurrent::run(&m_dbusPool, networkConnectWorker,
                                         connectRequest.device,
                                         connectRequest.savedProfileUuid,
                                         connectRequest.settings,
                                         connectRequest.replaceProfileId));
}

bool PlatformServer::handleNetworkOperation(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();
    if (op == QStringLiteral("network.refresh")) {
        runNetworkRefresh(socket, request);
        return true;
    }
    if (op == QStringLiteral("network.details")) {
        const QString device = payload.value(QStringLiteral("device")).toString().trimmed();
        if (!validNetworkDevice(device)) {
            respond(socket, request, false, {}, QStringLiteral("invalid-device"),
                    QStringLiteral("网络设备无效"), false);
            return true;
        }
        runNetworkDetails(socket, request, device);
        return true;
    }
    if (op == QStringLiteral("network.scan")) {
        const QString device = payload.value(QStringLiteral("device")).toString().trimmed();
        if (!validNetworkDevice(device)) {
            respond(socket, request, false, {}, QStringLiteral("invalid-device"),
                    QStringLiteral("网络设备无效"), false);
            return true;
        }
        // A rescan can legitimately take several seconds on a busy radio; the
        // panel also fires one at open plus retries. Dedupe concurrent scans
        // for the same interface behind one nmcli invocation instead of
        // double-rescanning the radio.
        const QString scanKey = QStringLiteral("network.scan:") + device;
        if (queueIfInFlight(scanKey, socket, request))
            return true;
        // Resolve saved profiles before the RF scan so matching rows can carry
        // their immutable UUID. `connection show` accepts only summary fields;
        // NetworkManager uses NAME as the Wi-Fi profile identifier by default.
        // This metadata is optional: failure must not hide otherwise valid APs.
        auto *profiles = new QProcess(this);
        profiles->setProgram(QStringLiteral("nmcli"));
        profiles->setArguments({QStringLiteral("-t"), QStringLiteral("-f"),
                                QStringLiteral("UUID,TYPE,NAME"),
                                QStringLiteral("connection"), QStringLiteral("show")});
        armProcessWatchdog(profiles, 10000);
        const QPointer<QProcess> profilesGuard(profiles);
        auto startScan = [this, scanKey, device](const QHash<QString, QString> &savedProfiles) {
            auto *scan = new QProcess(this);
            scan->setProgram(QStringLiteral("nmcli"));
            scan->setArguments({QStringLiteral("-t"), QStringLiteral("-f"),
                                QStringLiteral("IN-USE,SSID,SIGNAL,SECURITY"),
                                QStringLiteral("device"), QStringLiteral("wifi"),
                                QStringLiteral("list"), QStringLiteral("ifname"), device,
                                QStringLiteral("--rescan"), QStringLiteral("yes")});
            // A rescan can legitimately take several seconds on a busy radio.
            armProcessWatchdog(scan, 25000);
            connect(scan, &QProcess::errorOccurred, this,
                    [this, scanKey, scan](QProcess::ProcessError) {
                QObject::disconnect(scan, &QProcess::finished, this, nullptr);
                completeInFlight(scanKey, false, {}, QStringLiteral("network-scan-failed"),
                                 QStringLiteral("Wi‑Fi 扫描失败"), true, 0);
                scan->deleteLater();
            });
            connect(scan, &QProcess::finished, this,
                    [this, scanKey, savedProfiles, scan](int scanExit,
                                                         QProcess::ExitStatus) {
                const QJsonObject result = parseNetworkScan(
                    scan->readAllStandardOutput(), scanExit);
                scan->deleteLater();
                if (scanExit != 0) {
                    completeInFlight(scanKey, false, {}, QStringLiteral("network-scan-failed"),
                                     QStringLiteral("Wi‑Fi 扫描失败"), true, 0);
                    return;
                }
                QJsonArray networks = result.value(QStringLiteral("networks")).toArray();
                for (int index = 0; index < networks.size(); ++index) {
                    QJsonObject network = networks.at(index).toObject();
                    network.insert(QStringLiteral("savedProfileUuid"),
                                   savedProfiles.value(network.value(QStringLiteral("ssid"))
                                                           .toString()));
                    networks[index] = network;
                }
                QJsonObject normalized{{QStringLiteral("available"), true},
                                       {QStringLiteral("networks"), networks}};
                completeInFlight(scanKey, true, normalized, {}, {}, true, 0);
            });
            scan->start();
        };
        connect(profiles, &QProcess::errorOccurred, this,
                [profilesGuard, profiles, startScan](QProcess::ProcessError) {
            // A crash also emits finished(); drop that connection so the
            // chain neither advances nor answers the same request twice.
            // Profile metadata is optional: continue the RF scan with no
            // saved profiles rather than failing the whole request.
            QObject::disconnect(profiles, &QProcess::finished, nullptr, nullptr);
            if (profilesGuard)
                profiles->deleteLater();
            startScan({});
        });
        connect(profiles, &QProcess::finished, this,
                [startScan, profiles](int profileExit,
                                      QProcess::ExitStatus) {
            const QHash<QString, QString> savedProfiles = parseSavedWifiProfiles(
                profiles->readAllStandardOutput(), profileExit);
            profiles->deleteLater();
            startScan(savedProfiles);
        });
        profiles->start();
        return true;
    }
    if (op == QStringLiteral("network.wifi-power")) {
        invalidateReplies(QStringLiteral("network."));
        runCommand(socket, request, QStringLiteral("nmcli"),
                   {QStringLiteral("radio"), QStringLiteral("wifi"), payload.value(QStringLiteral("enabled")).toBool() ? QStringLiteral("on") : QStringLiteral("off")},
                   {}, 15000);
        return true;
    }
    if (op == QStringLiteral("network.connect")) {
        invalidateReplies(QStringLiteral("network."));
        const QString ssid = payload.value(QStringLiteral("ssid")).toString();
        const QString device = payload.value(QStringLiteral("device")).toString();
        const QString password = payload.value(QStringLiteral("password")).toString();
        const QString uuid = payload.value(QStringLiteral("savedProfileUuid")).toString();
        if (ssid.isEmpty() || !validNetworkDevice(device)) {
            respond(socket, request, false, {}, QStringLiteral("invalid-network"),
                    QStringLiteral("网络参数无效"), false);
            return true;
        }
        NmConnectRequest connect;
        connect.device = device;
        connect.savedProfileUuid = uuid;
        // The saved-profile path reuses an existing connection so it needs no
        // password at all; open networks simply omit wireless-security.
        connect.settings = nmWifiSettings(ssid, password);
        runNetworkConnect(socket, request, connect);
        return true;
    }
    if (op == QStringLiteral("network.connect-enterprise")) {
        invalidateReplies(QStringLiteral("network."));
        const QString ssid = payload.value(QStringLiteral("ssid")).toString();
        const QString device = payload.value(QStringLiteral("device")).toString();
        const QString identity = payload.value(QStringLiteral("identity")).toString();
        const QString password = payload.value(QStringLiteral("password")).toString();
        const QString method = payload.value(QStringLiteral("eapMethod")).toString().toLower();
        const QString phase2 = method == QStringLiteral("peap") ? QStringLiteral("mschapv2")
            : method == QStringLiteral("ttls") ? QStringLiteral("pap") : QString();
        const QString anonymous = payload.value(QStringLiteral("anonymousIdentity")).toString();
        if (ssid.isEmpty() || device.isEmpty() || identity.isEmpty() || password.isEmpty()
            || phase2.isEmpty() || !validNetworkDevice(device)) {
            respond(socket, request, false, {}, QStringLiteral("invalid-network"),
                    QStringLiteral("802.1X 参数无效"), false);
            return true;
        }
        // The four nmcli steps (delete/add/modify/up) collapsed into a single
        // D-Bus round: a fresh AddConnection replaces any stale profile, and
        // ActivateConnection on the resolved device replaces `connection up`.
        const QString profile = QStringLiteral("quickshell-8021x-") + ssid;
        NmConnectRequest connect;
        connect.device = device;
        connect.replaceProfileId = profile;
        connect.settings = nmEnterpriseSettings(profile, ssid, identity,
                                                password, method, phase2,
                                                anonymous);
        runNetworkConnect(socket, request, connect);
        return true;
    }
    if (op == QStringLiteral("network.disconnect")) {
        invalidateReplies(QStringLiteral("network."));
        const QString device = payload.value(QStringLiteral("device")).toString().trimmed();
        if (!validNetworkDevice(device)) {
            respond(socket, request, false, {}, QStringLiteral("invalid-device"), QStringLiteral("网络设备无效"), false);
            return true;
        }
        runCommand(socket, request, QStringLiteral("nmcli"), {QStringLiteral("device"), QStringLiteral("disconnect"), device}, {}, 15000);
        return true;
    }
    if (op == QStringLiteral("network.traffic")) {
        const QString device = payload.value(QStringLiteral("device")).toString().trimmed();
        if (!validNetworkDevice(device)) {
            respond(socket, request, false, {}, QStringLiteral("invalid-device"),
                    QStringLiteral("网络设备无效"), false);
            return true;
        }
        const QString base = QStringLiteral("/sys/class/net/") + device
            + QStringLiteral("/statistics/");
        QFile rxFile(base + QStringLiteral("rx_bytes"));
        QFile txFile(base + QStringLiteral("tx_bytes"));
        bool rxOk = false;
        bool txOk = false;
        const qint64 rx = rxFile.open(QIODevice::ReadOnly)
            ? QString::fromUtf8(rxFile.readAll()).trimmed().toLongLong(&rxOk) : 0;
        const qint64 tx = txFile.open(QIODevice::ReadOnly)
            ? QString::fromUtf8(txFile.readAll()).trimmed().toLongLong(&txOk) : 0;
        if (!rxOk || !txOk || rx < 0 || tx < 0) {
            respond(socket, request, false, {}, QStringLiteral("network-traffic-unavailable"),
                    QStringLiteral("无法读取网络流量"), true);
            return true;
        }
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("device"), device},
                            {QStringLiteral("rxBytes"), static_cast<double>(rx)},
                            {QStringLiteral("txBytes"), static_cast<double>(tx)}});
        return true;
    }
    if (op == QStringLiteral("network.forget")) {
        invalidateReplies(QStringLiteral("network."));
        const QString uuid = payload.value(QStringLiteral("uuid")).toString();
        static const QRegularExpression uuidPattern(QStringLiteral("^[0-9A-Fa-f-]{8,}$"));
        if (!uuidPattern.match(uuid).hasMatch()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-profile"), QStringLiteral("网络配置无效"), false);
            return true;
        }
        runCommand(socket, request, QStringLiteral("nmcli"), {QStringLiteral("connection"), QStringLiteral("delete"), QStringLiteral("uuid"), uuid}, {}, 15000);
        return true;
    }
    return false;
}

} // namespace KosPlatform
