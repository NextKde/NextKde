#include "PlatformServer.h"
#include "Shortcuts.h"
#include "../kwin/KWinBridge.h"

#include <QClipboard>
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusArgument>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusReply>
#include <QDBusVariant>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QImage>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QMimeData>
#include <QMetaType>
#include <QMimeDatabase>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>
#include <QThread>
#include <QTimer>
#include <QUuid>
#include <QtConcurrent>

#include <KIO/ApplicationLauncherJob>
#include <KService>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <functional>
#include <memory>

namespace KosPlatform {
namespace {

constexpr int kProtocolVersion = 1;
constexpr auto kClipboardCutMime = "application/x-kde-cutselection";
constexpr auto kGnomeFilesMime = "x-special/gnome-copied-files";
// Cap on unparsed bytes buffered per client socket. The largest legitimate
// request is a single JSON line (path lists, shortcut tables, cliphist
// records -- clipboard image data travels through cliphist files, never
// inline), all orders of magnitude below this; anything past the cap is a
// client streaming without a newline, which is cut off instead of growing
// the buffer without bound.
constexpr qsizetype kMaxClientBufferBytes = 1024 * 1024;

bool finiteNumber(const QJsonValue &value, double minimum, double maximum)
{
    if (!value.isDouble())
        return false;
    const double number = value.toDouble();
    return std::isfinite(number) && number >= minimum && number <= maximum;
}

bool validRect(const QJsonValue &value)
{
    if (!value.isObject())
        return false;
    const QJsonObject rect = value.toObject();
    return finiteNumber(rect.value(QStringLiteral("x")), -1000000.0, 1000000.0)
        && finiteNumber(rect.value(QStringLiteral("y")), -1000000.0, 1000000.0)
        && finiteNumber(rect.value(QStringLiteral("width")), 1.0, 1000000.0)
        && finiteNumber(rect.value(QStringLiteral("height")), 1.0, 1000000.0);
}

bool validLayoutPayload(const QJsonObject &payload)
{
    const QString outputName = payload.value(QStringLiteral("outputName")).toString();
    const QString dockPosition = payload.value(QStringLiteral("dockPosition")).toString();
    return !outputName.isEmpty() && outputName.size() <= 255
        && validRect(payload.value(QStringLiteral("outputRect")))
        && validRect(payload.value(QStringLiteral("dockRect")))
        && finiteNumber(payload.value(QStringLiteral("barReservedHeight")), 0.0, 4096.0)
        && finiteNumber(payload.value(QStringLiteral("workspaceGap")), 0.0, 512.0)
        && (dockPosition == QStringLiteral("bottom")
            || dockPosition == QStringLiteral("left")
            || dockPosition == QStringLiteral("right"));
}

QString runtimeSocketPath()
{
    // KOS_PLATFORM_SOCKET lets a development daemon listen beside the
    // installed one (see kosctl dev); the installed layout never sets it.
    const QString overridePath = qEnvironmentVariable("KOS_PLATFORM_SOCKET");
    if (!overridePath.isEmpty())
        return overridePath;
    const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (!runtime.isEmpty())
        return runtime + QStringLiteral("/kos-platform.sock");
    return QDir::tempPath() + QStringLiteral("/kos-platform-")
        + QString::number(QCoreApplication::applicationPid()) + QStringLiteral(".sock");
}

QJsonObject errorObject(const QString &code, const QString &message, bool retryable)
{
    return QJsonObject{{QStringLiteral("code"), code},
                       {QStringLiteral("message"), message},
                       {QStringLiteral("retryable"), retryable}};
}

// Outcome of a file.copy run on the copy pool. Empty when the copy
// committed; a description of the failed stage otherwise.
struct CopyResult {
    QString error;
};

// Runs on a m_copyPool thread: QFile/QSaveFile are plain file objects and
// safe off the event loop. The 1MiB chunk loop matches the old inline
// implementation, including the QSaveFile commit() fsync.
CopyResult copyFileChunked(const QString &source, const QString &destination)
{
    QFile input(source);
    QSaveFile output(destination);
    if (!input.open(QIODevice::ReadOnly))
        return {QStringLiteral("open-source")};
    if (!output.open(QIODevice::WriteOnly))
        return {QStringLiteral("open-destination")};
    while (!input.atEnd()) {
        const QByteArray chunk = input.read(1024 * 1024);
        if (chunk.isEmpty() && !input.atEnd())
            return {QStringLiteral("read")};
        if (output.write(chunk) != chunk.size())
            return {QStringLiteral("write")};
    }
    if (!output.commit())
        return {QStringLiteral("commit")};
    return {};
}

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

QJsonObject menuItemFromArgument(const QDBusArgument &argument)
{
    qint32 id = 0;
    QVariantMap properties;
    argument.beginStructure();
    argument >> id >> properties;
    const QVariant type = unwrapDbusValue(properties.value(QStringLiteral("type")));
    const QVariant label = unwrapDbusValue(properties.value(QStringLiteral("label")));
    const QVariant visible = unwrapDbusValue(properties.value(QStringLiteral("visible")));
    const QVariant enabled = unwrapDbusValue(properties.value(QStringLiteral("enabled")));
    const QVariant iconName = unwrapDbusValue(properties.value(QStringLiteral("icon-name")));
    const QVariant childrenDisplay = unwrapDbusValue(properties.value(QStringLiteral("children-display")));
    const QVariant toggleType = unwrapDbusValue(properties.value(QStringLiteral("toggle-type")));
    const QVariant toggleState = unwrapDbusValue(properties.value(QStringLiteral("toggle-state")));
    QJsonArray children;
    argument.beginArray();
    while (!argument.atEnd()) {
        // DBusMenuLayoutItem encodes children as `av`: each child structure is
        // wrapped in a D-Bus variant. Reading it as a structure directly
        // corrupts QDBusArgument's iterator and aborts the daemon.
        QVariant child;
        argument >> child;
        const QDBusArgument childArgument = qvariant_cast<QDBusArgument>(unwrapDbusValue(child));
        children.append(menuItemFromArgument(childArgument));
    }
    argument.endArray();
    argument.endStructure();
    const bool hasChildren = !children.isEmpty()
        || childrenDisplay.toString() == QStringLiteral("submenu");
    const bool checkable = toggleType.isValid() && !toggleType.toString().isEmpty();
    const bool checked = toggleState.isValid() && toggleState.toInt() == 1;
    return QJsonObject{{QStringLiteral("id"), id},
                       {QStringLiteral("label"), label.toString().remove(QLatin1Char('_'))},
                       {QStringLiteral("icon"), QString()},
                       {QStringLiteral("separator"), type.toString() == QStringLiteral("separator")},
                       {QStringLiteral("visible"), !visible.isValid() || visible.toBool()},
                       {QStringLiteral("enabled"), !enabled.isValid() || enabled.toBool()},
                       {QStringLiteral("hasChildren"), hasChildren},
                       {QStringLiteral("checkable"), checkable},
                       {QStringLiteral("checked"), checked},
                       {QStringLiteral("children"), children}};
}

bool validAppMenuAddress(const QString &service, const QString &path)
{
    return !service.isEmpty() && service.size() <= 255
        && !path.isEmpty() && path.startsWith(QLatin1Char('/')) && path.size() <= 1024;
}

QString cleanPath(const QString &path)
{
    if (path.isEmpty() || path.contains(QChar('\0')))
        return {};
    const QFileInfo raw(path);
    if (!raw.isAbsolute())
        return {};

    // Canonicalise existing entries so `..` and symlink aliases cannot make
    // two requests refer to different paths. For a new rename/create target,
    // canonicalise its existing parent and append only the final component;
    // this preserves legitimate non-existent targets while keeping the
    // operation inside a real directory boundary.
    const QString cleaned = QDir::cleanPath(raw.absoluteFilePath());
    const QFileInfo info(cleaned);
    if (info.exists())
        return info.canonicalFilePath();

    const QString fileName = info.fileName();
    const QFileInfo parentInfo(info.path());
    if (fileName.isEmpty() || fileName == QStringLiteral(".")
        || fileName == QStringLiteral("..")
        || !parentInfo.exists() || !parentInfo.isDir()
        || parentInfo.isSymLink())
        return {};
    const QString canonicalParent = parentInfo.canonicalFilePath();
    if (canonicalParent.isEmpty())
        return {};
    return QDir(canonicalParent).filePath(fileName);
}

QString cleanCreatePath(const QString &path)
{
    if (path.isEmpty() || path.contains(QChar('\0')))
        return {};
    const QFileInfo raw(path);
    if (!raw.isAbsolute())
        return {};
    const QString cleaned = QDir::cleanPath(raw.absoluteFilePath());
    QString cursor = cleaned;
    QStringList suffix;
    while (!QFileInfo(cursor).exists()) {
        const QFileInfo missing(cursor);
        if (missing.fileName().isEmpty() || missing.fileName() == QStringLiteral(".")
            || missing.fileName() == QStringLiteral(".."))
            return {};
        suffix.prepend(missing.fileName());
        const QString parent = missing.path();
        if (parent == cursor)
            return {};
        cursor = parent;
    }
    const QFileInfo base(cursor);
    if (!base.isDir() || base.isSymLink())
        return {};
    QString result = base.canonicalFilePath();
    if (result.isEmpty())
        return {};
    for (const QString &part : suffix)
        result = QDir(result).filePath(part);
    return result;
}

// ---------------------------------------------------------------------------
// Shell state files (state.read / state.write).
//
// The Shell persists small JSON blobs under Quickshell.stateDir, i.e.
// $XDG_STATE_HOME/quickshell/<shell id>. Both ops are rooted at the shared
// quickshell state root so every component reads the same files while nothing
// outside $XDG_STATE_HOME/quickshell can be addressed.
// ---------------------------------------------------------------------------

// A single state payload is a small JSON document; 1 MiB is orders of
// magnitude above the largest legitimate config while still bounding the
// memory a request can make the daemon read or write.
constexpr qint64 kMaxStateFileBytes = 1024 * 1024;
constexpr qsizetype kMaxStateDirLength = 512;
constexpr qsizetype kMaxStateFileNameLength = 255;

QString stateRootPath()
{
    // Mirrors Quickshell.stateDir's root: $XDG_STATE_HOME/quickshell.
    return QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation)
        + QStringLiteral("/quickshell");
}

// Returns the resolved absolute path for <root>/<dir>/<file>, or {} when the
// pair escapes the root. `dir` may be empty (the root itself), a relative
// sub-path, or an absolute path that must sit under the root; `file` is a
// bare file name. Everything existing is canonicalized first, so `..`
// segments and symlinks that resolve outside the root are rejected by the
// final prefix check rather than by string comparison on the raw input.
QString resolveStatePath(const QString &dir, const QString &file)
{
    if (file.isEmpty() || file.size() > kMaxStateFileNameLength
        || file == QStringLiteral(".") || file == QStringLiteral("..")
        || file.contains(QLatin1Char('/')) || file.contains(QLatin1Char('\\'))
        || file.contains(QChar('\0')))
        return {};
    if (dir.size() > kMaxStateDirLength || dir.contains(QChar('\0')))
        return {};

    const QString root = QDir::cleanPath(stateRootPath());
    QString joined;
    if (QFileInfo(dir).isAbsolute())
        joined = QDir::cleanPath(dir);
    else
        joined = QDir::cleanPath(dir.isEmpty() ? root
                                               : root + QLatin1Char('/') + dir);
    if (joined != root && !joined.startsWith(root + QLatin1Char('/')))
        return {};

    // cleanCreatePath canonicalizes the deepest existing ancestor and appends
    // the still-missing components literally, so it resolves both an existing
    // directory and one about to be mkpath'ed.
    const QString resolvedRoot = cleanCreatePath(root);
    if (resolvedRoot.isEmpty())
        return {};
    const QString resolvedDir = cleanCreatePath(joined);
    if (resolvedDir.isEmpty()
        || (resolvedDir != resolvedRoot
            && !resolvedDir.startsWith(resolvedRoot + QLatin1Char('/'))))
        return {};
    // An existing dir must be a real directory; a file here would make the
    // append below meaningless (and mkpath would fail later anyway).
    const QFileInfo dirInfo(resolvedDir);
    if (dirInfo.exists() && !dirInfo.isDir())
        return {};

    const QString target = resolvedDir + QLatin1Char('/') + file;
    const QFileInfo targetInfo(target);
    if (!targetInfo.exists())
        return target;
    // The file exists: resolve it once more so a symlink planted inside the
    // state tree cannot point a read outside the root. (QSaveFile replaces a
    // symlink atomically instead of following it, but reads do follow.)
    const QString canonicalTarget = targetInfo.canonicalFilePath();
    if (canonicalTarget.isEmpty()
        || !canonicalTarget.startsWith(resolvedRoot + QLatin1Char('/')))
        return {};
    return canonicalTarget;
}

QString resolveDesktopFile(const QString &id)
{
    if (id.isEmpty() || id.contains(QChar('\0')))
        return {};
    // Desktop icons hand over the absolute path of the .desktop file that sits
    // in ~/Desktop, which is never inside an applications directory, so an
    // absolute path is resolved directly instead of being rejected.
    if (QFileInfo(id).isAbsolute()) {
        const QFileInfo info(id);
        if (!info.isFile()
            || !info.fileName().endsWith(QStringLiteral(".desktop"), Qt::CaseInsensitive))
            return {};
        const QString canonical = info.canonicalFilePath();
        return canonical.isEmpty() ? info.absoluteFilePath() : canonical;
    }
    if (id.contains(QChar('/')) || id.contains(QChar('\\')))
        return {};
    const QString name = id.endsWith(QStringLiteral(".desktop"), Qt::CaseInsensitive)
        ? id : id + QStringLiteral(".desktop");
    const QStringList roots = QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation);
    for (const QString &root : roots) {
        const QString candidate = QDir(root).filePath(name);
        if (QFileInfo(candidate).isFile())
            return QFileInfo(candidate).absoluteFilePath();
    }
    return {};
}

QStringList cleanPaths(const QJsonValue &value)
{
    QStringList paths;
    QSet<QString> seen;
    for (const QJsonValue &item : value.toArray()) {
        const QString path = cleanPath(item.toString());
        if (!path.isEmpty() && !seen.contains(path)) {
            seen.insert(path);
            paths.append(path);
        }
    }
    return paths;
}

QString freedesktopTrashRoot()
{
    QString dataHome = qEnvironmentVariable("XDG_DATA_HOME");
    if (dataHome.isEmpty())
        dataHome = QDir(QStandardPaths::writableLocation(QStandardPaths::HomeLocation))
            .filePath(QStringLiteral(".local/share"));
    const QFileInfo info(dataHome);
    if (!info.isAbsolute())
        return {};
    return QDir(info.absoluteFilePath()).filePath(QStringLiteral("Trash"));
}

bool removeTrashEntry(const QString &path)
{
    const QFileInfo info(path);
    if (info.isSymLink() || !info.isDir())
        return QFile::remove(path);
    return QDir(path).removeRecursively();
}

bool emptyTrashDirectory(const QString &directory)
{
    const QFileInfo rootInfo(directory);
    if (!rootInfo.exists())
        return true;
    if (!rootInfo.isDir() || rootInfo.isSymLink())
        return false;
    QDirIterator iterator(directory, QDir::NoDotAndDotDot | QDir::AllEntries
                          | QDir::Hidden | QDir::System);
    while (iterator.hasNext()) {
        iterator.next();
        if (!removeTrashEntry(iterator.filePath()))
            return false;
    }
    return true;
}

QJsonArray jsonPaths(const QStringList &paths)
{
    QJsonArray values;
    for (const QString &path : paths)
        values.append(path);
    return values;
}

QJsonObject parseOutput(const QByteArray &output, int exitCode)
{
    return QJsonObject{{QStringLiteral("exitCode"), exitCode},
                       {QStringLiteral("stdout"), QString::fromUtf8(output)}};
}

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

constexpr int kDefaultCommandTimeoutMs = 8000;
// Failure replies are cached only briefly so a missing helper or a stopped
// service cannot spin a fork-per-poll loop, while recovery is still noticed
// within seconds.
constexpr int kFailureCacheTtlMs = 5000;
constexpr int kNetworkCacheTtlMs = 15000;
constexpr int kBluetoothCacheTtlMs = 20000;
constexpr int kAudioCacheTtlMs = 30000;
constexpr int kBrightnessCacheTtlMs = 10000;
constexpr int kNightLightCacheTtlMs = 10000;
// clipboard.history.list answers from this cache for a moment at most; the
// wl-paste watcher's dataChanged callback invalidates on the next copy, so a
// real entry never waits out the TTL.
constexpr int kClipboardHistoryCacheTtlMs = 1500;
// tray.identify answers may ride the reply cache briefly: the Shell debounces
// its own refresh, and a tray icon's identity never changes mid-session.
constexpr int kTrayIdentifyCacheTtlMs = 3000;
// Bounded D-Bus round-trips: a wedged NetworkManager/BlueZ used to be able
// to stall the whole daemon through the default 25 s call timeout.
constexpr int kDbusCallTimeoutMs = 2000;

constexpr auto kNmService = "org.freedesktop.NetworkManager";
constexpr auto kNmRootPath = "/org/freedesktop/NetworkManager";
constexpr auto kBluezService = "org.bluez";

// A wedged helper (bluetoothctl waiting on a dead BlueZ, cliphist on a hung
// store, nmcli on a suspended NetworkManager) used to pile up one process
// per poll forever. Every short-lived query process gets a kill watchdog;
// interactive tools opt out explicitly at the call site.
void armProcessWatchdog(QProcess *process, int timeoutMs)
{
    if (timeoutMs <= 0)
        return;
    const QPointer<QProcess> guard(process);
    QTimer::singleShot(timeoutMs, process, [guard]() {
        if (guard && guard->state() != QProcess::NotRunning)
            guard->kill();
    });
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

QVariantMap nmGetAll(const QDBusConnection &bus, const QString &path,
                     const QString &interface)
{
    return dbusGetAll(bus, kNmService, path, interface);
}

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

struct NmWirelessInfo {
    QString ssid;
    int strength = -1;
    QString accessPointPath;
};

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

// connectToBus registers `name` in a process-wide connection registry that
// only disconnectFromBus removes; a worker that returned early would leak the
// entry forever. This guard also handles the destructor-warning path
// (QDBusConnection objects must not outlive the name they hold).
struct ScopedBusConnection {
    explicit ScopedBusConnection(const QString &name) : name(name) {}
    ~ScopedBusConnection() { QDBusConnection::disconnectFromBus(name); }
    QString name;
};

// Every read a network worker performs ends up in this result. The worker
// thread owns no Qt objects beyond its private bus connection; everything
// that must happen on the server (watch subscriptions, reply cache, socket
// writes) is carried back here for the main thread to apply.
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
    for (const QDBusObjectPath &devicePath : devicePaths) {
        watched.insert(devicePath.path());
        const QVariantMap device = nmGetAll(bus, devicePath.path(),
            QStringLiteral("org.freedesktop.NetworkManager.Device"));
        const uint type = device.value(QStringLiteral("DeviceType")).toUInt();
        if (type != 1 && type != 2)
            continue;
        const uint state = device.value(QStringLiteral("State")).toUInt();
        if (selected.isEmpty() || state == 100) {
            selected = device;
            selectedPath = devicePath.path();
        }
        if (state == 100)
            break;
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
                             {QStringLiteral("signalStrength"), signalStrength}};
    out.ok = true;
    out.watchPaths = watched.values();
    return out;
}
// ---------------------------------------------------------------------------
// NetworkManager connect path (network.connect / network.connect-enterprise).
//
// These used to shell out to nmcli with the passphrase on argv, where any
// local user could read it through /proc/*/cmdline. Both operations now
// assemble the connection settings in memory and hand them to NM over D-Bus
// (Settings.AddConnection + ActivateConnection), so the secret never leaves
// the daemon address space.
//
// All of it runs on m_dbusPool as one synchronous walk per request, bounded
// by kDbusCallTimeoutMs per call -- the same pattern the R8 refresh/details
// workers established, so a wedged NM cannot stall the socket event loop.
// ---------------------------------------------------------------------------

constexpr int kNetworkConnectWaitMs = 30000;
constexpr int kNetworkConnectTtlMs = 1000;
constexpr auto kNmSettingsPath = "/org/freedesktop/NetworkManager/Settings";
constexpr auto kNmSettingsInterface = "org.freedesktop.NetworkManager.Settings";
constexpr auto kNmConnectionInterface =
    "org.freedesktop.NetworkManager.Settings.Connection";
constexpr auto kNmDeviceInterface = "org.freedesktop.NetworkManager.Device";
constexpr auto kNmActiveConnectionInterface =
    "org.freedesktop.NetworkManager.Connection.Active";

// NMDeviceState: 30 = disconnected, 100 = activated, 120 = failed, 40-110 =
// the transition states in between.
constexpr uint kNmDeviceActivated = 100;
constexpr uint kNmDeviceDisconnected = 30;
constexpr uint kNmDeviceFailed = 120;

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

// a{sa{sv}}: the wire format AddConnection expects. Nested dict members are
// wrapped in QDBusVariant so QtDBus marshals each as a variant, matching the
// same convention nmcli's own libnm calls use.
QVariantMap nmConnectionSettings(const QString &id, const QString &type,
                                 const QVariantMap &section)
{
    QVariantMap connection{{QStringLiteral("id"), id},
                           {QStringLiteral("type"), type},
                           {QStringLiteral("uuid"),
                            QUuid::createUuid().toString(QUuid::WithoutBraces)}};
    QVariantMap settings{{QStringLiteral("connection"), connection}};
    for (auto it = section.constBegin(); it != section.constEnd(); ++it) {
        QVariantMap inner;
        const QVariantMap entries = it.value().toMap();
        for (auto entry = entries.constBegin(); entry != entries.constEnd(); ++entry)
            inner.insert(entry.key(), QVariant::fromValue(QDBusVariant(entry.value())));
        settings.insert(it.key(), QVariant::fromValue(QDBusVariant(inner)));
    }
    return settings;
}

// Poll Device.State until it settles: activated is the success terminal, a
// drop back to disconnected/failed means the activation attempt ended. The
// bounded GetAll rounds keep the loop from running unbounded on a wedged NM.
bool nmWaitDeviceActivated(const QDBusConnection &bus, const QString &devicePath,
                           int timeoutMs)
{
    const qint64 deadline = QDateTime::currentMSecsSinceEpoch() + timeoutMs;
    uint lastState = 0;
    while (QDateTime::currentMSecsSinceEpoch() < deadline) {
        const QVariantMap props = nmGetAll(bus, devicePath,
                                           QString::fromLatin1(kNmDeviceInterface));
        const uint state = props.value(QStringLiteral("State")).toUInt();
        if (state == kNmDeviceActivated)
            return true;
        if (lastState != 0
            && (state <= kNmDeviceDisconnected || state >= kNmDeviceFailed))
            return false;
        lastState = state;
        QThread::msleep(250);
    }
    return false;
}

struct NmConnectionTarget {
    QString settingsPath;
    QString uuid;
    QString error;
};

// Find a saved profile by UUID (savedProfileUuid flow) or by the profile id
// the enterprise op owns. Returns a target with error set when the lookup
// itself failed (as opposed to "not found", which is a valid answer).
NmConnectionTarget nmFindConnection(const QDBusConnection &bus,
                                    const QString &uuid, const QString &id)
{
    const QDBusMessage reply = nmCallBounded(bus, QString::fromLatin1(kNmSettingsPath),
        QString::fromLatin1(kNmSettingsInterface), QStringLiteral("ListConnections"),
        {}, kDbusCallTimeoutMs);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
        return {QString(), QString(), QStringLiteral("list")};
    const QList<QDBusObjectPath> paths =
        qdbus_cast<QList<QDBusObjectPath>>(reply.arguments().constFirst());
    for (const QDBusObjectPath &path : paths) {
        const QVariantMap props = nmGetAll(bus, path.path(),
                                           QString::fromLatin1(kNmConnectionInterface));
        const QString foundUuid = props.value(QStringLiteral("Uuid")).toString();
        const QString foundId = props.value(QStringLiteral("Id")).toString();
        if (!uuid.isEmpty() && foundUuid == uuid)
            return {path.path(), foundUuid, {}};
        if (uuid.isEmpty() && !id.isEmpty() && foundId == id)
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

// The settings dict for a WPA-PSK / open join. `key-mgmt` is omitted for open
// networks -- NM treats a missing wireless-security section as open.
QVariantMap nmWifiSettings(const QString &ssid, const QString &password)
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
// it stays a QVariantList; the anonymous identity is optional.
QVariantMap nmEnterpriseSettings(const QString &profile, const QString &ssid,
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
                                         const QVariantMap &settings,
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
            if (!stale.settingsPath.isEmpty())
                nmDeleteConnection(bus, stale.settingsPath);
        }
        const QDBusMessage added = nmCallBounded(bus,
            QString::fromLatin1(kNmSettingsPath),
            QString::fromLatin1(kNmSettingsInterface),
            QStringLiteral("AddConnection"),
            {QVariant::fromValue(QDBusVariant(settings))},
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
    if (activated.type() != QDBusMessage::ReplyMessage)
        return out;

    // --wait parity: ActivateConnection only means NM accepted the request.
    // Poll the device state so the answer matches the old nmcli semantics.
    if (!nmWaitDeviceActivated(bus, devicePath, kNetworkConnectWaitMs))
        return out;

    out.ok = true;
    out.result = QJsonObject{{QStringLiteral("connected"), true}};
    out.watchPaths = {devicePath};
    return out;
}

// ---------------------------------------------------------------------------
// tray.identify
//
// SNI items from Electron apps often carry generated ids ("1",
// "chrome_status_icon_*") and no title, so the Shell cannot label the tray
// icon. The walk runs on m_dbusPool over a private session-bus connection:
// RegisteredStatusNotifierItems from the watcher, then per-item Id/Title
// plus the owning connection's UnixProcessID; /proc/<pid>/comm and cmdline
// are read locally. Everything on the bus is bounded by kDbusCallTimeoutMs.
// Names resolve through a fixed alias table (mirrored by
// SysTrayIdentityService.qml's synchronous fast path), then the item title,
// then the capitalised process name.
// ---------------------------------------------------------------------------

struct TrayIdentityResult {
    bool ok = false;
    QString code;
    QString message;
    QJsonObject names;
};

QString trayIdentityAlias(const QString &commLower)
{
    static const QHash<QString, QString> aliases{
        {QStringLiteral("qq"), QStringLiteral("QQ")},
        {QStringLiteral("linuxqq"), QStringLiteral("QQ")},
        {QStringLiteral("antigravity"), QStringLiteral("Antigravity")},
        {QStringLiteral("rustdesk"), QStringLiteral("RustDesk")},
        {QStringLiteral("karing"), QStringLiteral("Karing")},
        {QStringLiteral("sunshine"), QStringLiteral("Sunshine")},
        {QStringLiteral("wechat"), QStringLiteral("微信")},
        {QStringLiteral("fcitx"), QStringLiteral("输入法")},
        {QStringLiteral("fcitx5"), QStringLiteral("输入法")},
        {QStringLiteral("google-chrome"), QStringLiteral("Google Chrome")},
        {QStringLiteral("chrome"), QStringLiteral("Google Chrome")},
        {QStringLiteral("chromium"), QStringLiteral("Chromium")},
        {QStringLiteral("code"), QStringLiteral("VS Code")},
    };
    return aliases.value(commLower);
}

TrayIdentityResult trayIdentifyWorker()
{
    const ScopedBusConnection guard(workerBusName(QStringLiteral("tray")));
    const QDBusConnection bus = QDBusConnection::connectToBus(
        QDBusConnection::SessionBus, guard.name);

    TrayIdentityResult out;
    const QVariant itemsVariant = dbusGetProperty(bus,
        QStringLiteral("org.kde.StatusNotifierWatcher"),
        QStringLiteral("/StatusNotifierWatcher"),
        QStringLiteral("org.kde.StatusNotifierWatcher"),
        QStringLiteral("RegisteredStatusNotifierItems"));
    if (itemsVariant.metaType() != QMetaType::fromType<QStringList>()) {
        out.code = QStringLiteral("tray-unavailable");
        out.message = QStringLiteral("托盘状态不可用");
        return out;
    }

    const QStringList items = itemsVariant.toStringList();
    for (const QString &item : items) {
        const qsizetype slash = item.indexOf(QLatin1Char('/'));
        if (slash <= 0)
            continue;
        const QString service = item.left(slash);
        const QString path = QStringLiteral("/") + item.mid(slash + 1);
        const QString id = dbusGetProperty(bus, service, path,
            QStringLiteral("org.kde.StatusNotifierItem"),
            QStringLiteral("Id")).toString();
        if (id.isEmpty())
            continue;
        const QString title = dbusGetProperty(bus, service, path,
            QStringLiteral("org.kde.StatusNotifierItem"),
            QStringLiteral("Title")).toString();
        const uint pid = dbusUnixProcessId(bus, service);

        // /proc reads are local files; a process that exits between the bus
        // lookup and the read just yields no name.
        QString comm;
        QString cmd;
        if (pid > 0) {
            QFile commFile(QStringLiteral("/proc/%1/comm").arg(pid));
            if (commFile.open(QIODevice::ReadOnly))
                comm = QString::fromUtf8(commFile.readAll()).trimmed().toLower();
            QFile cmdFile(QStringLiteral("/proc/%1/cmdline").arg(pid));
            if (cmdFile.open(QIODevice::ReadOnly)) {
                QByteArray raw = cmdFile.readAll();
                raw.replace('\0', " ");
                cmd = QString::fromUtf8(raw).trimmed().toLower();
            }
        }

        QString name;
        const QString alias = trayIdentityAlias(comm);
        if (comm.contains(QStringLiteral("qq")) || cmd.contains(QStringLiteral("/qq/"))
            || cmd.contains(QStringLiteral("linuxqq"))) {
            name = QStringLiteral("QQ");
        } else if (!alias.isEmpty()) {
            name = alias;
        } else if (!title.isEmpty()) {
            name = title;
        } else if (!comm.isEmpty()) {
            name = comm;
            name[0] = name[0].toUpper();
        }
        if (!name.isEmpty())
            out.names.insert(id, name);
    }
    out.ok = true;
    return out;
}

QJsonObject parseAudio(const QByteArray &output, int exitCode)
{
    const QString text = QString::fromUtf8(output);
    const QRegularExpression match(QStringLiteral("Volume:\\s*([0-9.]+)"));
    const auto m = match.match(text);
    if (exitCode != 0 || !m.hasMatch())
        return QJsonObject{{QStringLiteral("available"), false}};
    const double value = qBound(0.0, m.captured(1).toDouble(), 1.5);
    return QJsonObject{{QStringLiteral("available"), true},
                       {QStringLiteral("percent"), qRound(value * 100.0)},
                       {QStringLiteral("muted"), text.contains(QStringLiteral("[MUTED]"))}};
}

QJsonObject parseAudioApplications(const QByteArray &output, int exitCode)
{
    if (exitCode != 0)
        return QJsonObject{{QStringLiteral("available"), false}};

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(output, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isArray())
        return QJsonObject{{QStringLiteral("available"), false}};

    QJsonArray applications;
    for (const QJsonValue &value : document.array()) {
        const QJsonObject stream = value.toObject();
        const QJsonObject properties = stream.value(QStringLiteral("properties")).toObject();
        QString name = properties.value(QStringLiteral("application.name")).toString().trimmed();
        if (name.isEmpty())
            name = properties.value(QStringLiteral("media.name")).toString().trimmed();
        if (name.isEmpty())
            name = QStringLiteral("音频应用");

        const QJsonObject volume = stream.value(QStringLiteral("volume")).toObject();
        double volumePercent = 0.0;
        for (auto it = volume.constBegin(); it != volume.constEnd(); ++it) {
            const QJsonObject channel = it.value().toObject();
            const QString percent = channel.value(QStringLiteral("value_percent")).toString();
            if (!percent.isEmpty()) {
                volumePercent = percent.left(percent.indexOf(QLatin1Char('%'))).toDouble();
                break;
            }
        }

        applications.append(QJsonObject{
            {QStringLiteral("id"), stream.value(QStringLiteral("index")).toInt()},
            {QStringLiteral("name"), name},
            {QStringLiteral("percent"), qBound(0, qRound(volumePercent), 150)},
            {QStringLiteral("muted"), stream.value(QStringLiteral("mute")).toBool()},
            {QStringLiteral("icon"), properties.value(QStringLiteral("application.icon-name")).toString()}
        });
    }
    return QJsonObject{{QStringLiteral("available"), true},
                       {QStringLiteral("applications"), applications}};
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

std::unique_ptr<QDBusInterface> openScreenBrightness(QString &serviceName)
{
    for (const QString &candidate : {QStringLiteral("org.kde.ScreenBrightness"),
                                     QStringLiteral("org.kde.Solid.PowerManagement")}) {
        auto interface = std::make_unique<QDBusInterface>(
            candidate, QStringLiteral("/org/kde/ScreenBrightness"),
            QStringLiteral("org.kde.ScreenBrightness"), QDBusConnection::sessionBus());
        interface->setTimeout(kDbusCallTimeoutMs);
        if (interface->isValid()) {
            serviceName = candidate;
            return interface;
        }
    }
    return nullptr;
}

QString screenBrightnessPath(const QString &displayId)
{
    return QStringLiteral("/org/kde/ScreenBrightness/") + displayId;
}

QJsonObject readKdeBrightness(QString *serviceNameOut = nullptr,
                              QStringList *displayIdsOut = nullptr)
{
    QString serviceName;
    auto screenBrightness = openScreenBrightness(serviceName);
    if (!screenBrightness)
        return {{QStringLiteral("available"), false}};

    const QStringList displayIds = screenBrightness->property("DisplaysDBusNames").toStringList();
    if (serviceNameOut)
        *serviceNameOut = serviceName;
    if (displayIdsOut)
        *displayIdsOut = displayIds;
    QJsonArray displays;
    QJsonObject primary;
    for (const QString &displayId : displayIds) {
        if (displayId.isEmpty() || displayId.contains(QLatin1Char('/')))
            continue;
        QDBusInterface display(serviceName, screenBrightnessPath(displayId),
                               QStringLiteral("org.kde.ScreenBrightness.Display"),
                               QDBusConnection::sessionBus());
        display.setTimeout(kDbusCallTimeoutMs);
        if (!display.isValid())
            continue;
        const int maximum = display.property("MaxBrightness").toInt();
        if (maximum <= 0)
            continue;
        const int current = qBound(0, display.property("Brightness").toInt(), maximum);
        const bool internal = display.property("IsInternal").toBool();
        const QString label = display.property("Label").toString().trimmed();
        const QJsonObject item{
            {QStringLiteral("id"), displayId},
            {QStringLiteral("label"), label.isEmpty() ? displayId : label},
            {QStringLiteral("isInternal"), internal},
            {QStringLiteral("percent"), qRound(current * 100.0 / maximum)},
            {QStringLiteral("brightness"), current},
            {QStringLiteral("maximum"), maximum}
        };
        displays.append(item);
        if (primary.isEmpty() || (internal && !primary.value(QStringLiteral("isInternal")).toBool()))
            primary = item;
    }
    if (primary.isEmpty())
        return {{QStringLiteral("available"), false}};
    return {
        {QStringLiteral("available"), true},
        {QStringLiteral("percent"), primary.value(QStringLiteral("percent"))},
        {QStringLiteral("device"), primary.value(QStringLiteral("label"))},
        {QStringLiteral("displayId"), primary.value(QStringLiteral("id"))},
        {QStringLiteral("displays"), displays}
    };
}

bool setKdeDisplayBrightness(const QString &displayId, int percent)
{
    QString serviceName;
    auto screenBrightness = openScreenBrightness(serviceName);
    if (!screenBrightness)
        return false;
    const QStringList displayIds = screenBrightness->property("DisplaysDBusNames").toStringList();
    if (!displayIds.contains(displayId))
        return false;
    QDBusInterface display(serviceName, screenBrightnessPath(displayId),
                           QStringLiteral("org.kde.ScreenBrightness.Display"),
                           QDBusConnection::sessionBus());
    display.setTimeout(kDbusCallTimeoutMs);
    if (!display.isValid())
        return false;
    const int maximum = display.property("MaxBrightness").toInt();
    if (maximum <= 0)
        return false;
    const int target = qRound(qBound(0, percent, 100) * maximum / 100.0);
    const QDBusMessage reply = display.call(QStringLiteral("SetBrightness"), target,
                                            static_cast<uint>(0));
    return reply.type() == QDBusMessage::ReplyMessage;
}

QJsonObject readSysfsBrightness()
{
    const QDir backlights(QStringLiteral("/sys/class/backlight"));
    const QFileInfoList entries = backlights.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot,
                                                           QDir::Name);
    for (const QFileInfo &entry : entries) {
        QFile currentFile(entry.filePath() + QStringLiteral("/brightness"));
        QFile maximumFile(entry.filePath() + QStringLiteral("/max_brightness"));
        if (!currentFile.open(QIODevice::ReadOnly) || !maximumFile.open(QIODevice::ReadOnly))
            continue;
        bool currentOk = false;
        bool maximumOk = false;
        const int current = QString::fromUtf8(currentFile.readAll()).trimmed().toInt(&currentOk);
        const int maximum = QString::fromUtf8(maximumFile.readAll()).trimmed().toInt(&maximumOk);
        if (!currentOk || !maximumOk || maximum <= 0)
            continue;
        return QJsonObject{{QStringLiteral("available"), true},
                           {QStringLiteral("percent"), qRound(qBound(0.0,
                               current * 100.0 / maximum, 100.0))},
                           {QStringLiteral("device"), entry.fileName()},
                           {QStringLiteral("maximum"), maximum}};
    }
    return QJsonObject{{QStringLiteral("available"), false}};
}

QJsonObject parseBrightness(const QByteArray &output, int exitCode)
{
    if (exitCode != 0)
        return QJsonObject{{QStringLiteral("available"), false}};
    const QString text = QString::fromUtf8(output).trimmed();
    // brightnessctl -m: device,class,current,max,percentage
    const QStringList fields = text.split(QChar(','));
    if (fields.size() >= 5) {
        const auto match = QRegularExpression(QStringLiteral("(\\d+)%")).match(fields.at(4));
        if (match.hasMatch())
            return QJsonObject{{QStringLiteral("available"), true},
                               {QStringLiteral("percent"), match.captured(1).toInt()},
                               {QStringLiteral("device"), fields.at(0)}};
    }
    return QJsonObject{{QStringLiteral("available"), false}};
}

QString uniquePath(const QString &destination, const QString &baseName)
{
    QString candidate = QDir(destination).filePath(baseName);
    if (!QFileInfo::exists(candidate))
        return candidate;
    const QFileInfo sourceInfo(baseName);
    const QString suffix = sourceInfo.suffix();
    const QString stem = suffix.isEmpty() ? baseName
                                          : baseName.left(baseName.size() - suffix.size() - 1);
    for (int index = 1; index < 10000; ++index) {
        const QString copyName = suffix.isEmpty()
            ? QStringLiteral("%1 (copy %2)").arg(stem).arg(index)
            : QStringLiteral("%1 (copy %2).%3").arg(stem).arg(index).arg(suffix);
        candidate = QDir(destination).filePath(copyName);
        if (!QFileInfo::exists(candidate))
            return candidate;
    }
    return {};
}

bool copyRecursively(const QString &source, const QString &target)
{
    const QFileInfo info(source);
    if (info.isDir()) {
        if (!QDir().mkpath(target))
            return false;
        QDirIterator iterator(source, QDir::NoDotAndDotDot | QDir::AllEntries);
        while (iterator.hasNext()) {
            iterator.next();
            const QString childTarget = QDir(target).filePath(iterator.fileName());
            if (!copyRecursively(iterator.filePath(), childTarget))
                return false;
        }
        return true;
    }
    return QFile::copy(source, target);
}

bool moveOrCopy(const QString &source, const QString &destination, bool move)
{
    const QFileInfo sourceInfo(source);
    if (!sourceInfo.exists())
        return false;
    if (sourceInfo.isDir() && destination.startsWith(sourceInfo.absoluteFilePath() + QDir::separator()))
        return false;
    if (move && QFile::rename(source, destination))
        return true;
    if (!copyRecursively(source, destination))
        return false;
    if (!move)
        return true;
    return sourceInfo.isDir() ? QDir(source).removeRecursively() : QFile::remove(source);
}

QString mimeOperation(const QMimeData *mime)
{
    if (mime->hasFormat(QString::fromLatin1(kClipboardCutMime))
        && mime->data(QString::fromLatin1(kClipboardCutMime)).trimmed() == "1")
        return QStringLiteral("cut");
    if (mime->hasFormat(QString::fromLatin1(kGnomeFilesMime))) {
        const QByteArray first = mime->data(QString::fromLatin1(kGnomeFilesMime))
                                     .split('\n').value(0).trimmed();
        if (first == "cut")
            return QStringLiteral("cut");
    }
    return QStringLiteral("copy");
}

QStringList localClipboardPaths(const QMimeData *mime)
{
    QStringList result;
    QSet<QString> seen;
    const auto append = [&result, &seen](const QUrl &url) {
        if (!url.isLocalFile())
            return;
        const QString path = cleanPath(url.toLocalFile());
        if (!path.isEmpty() && !seen.contains(path)) {
            seen.insert(path);
            result.append(path);
        }
    };
    for (const QUrl &url : mime->urls())
        append(url);
    if (result.isEmpty() && mime->hasFormat(QStringLiteral("text/uri-list"))) {
        for (QByteArray line : mime->data(QStringLiteral("text/uri-list")).split('\n')) {
            line = line.trimmed();
            if (!line.isEmpty() && !line.startsWith('#'))
                append(QUrl::fromEncoded(line));
        }
    }
    if (result.isEmpty() && mime->hasFormat(QString::fromLatin1(kGnomeFilesMime))) {
        const QList<QByteArray> lines = mime->data(QString::fromLatin1(kGnomeFilesMime))
                                            .split('\n');
        for (qsizetype i = 1; i < lines.size(); ++i)
            append(QUrl::fromEncoded(lines.at(i).trimmed()));
    }
    return result;
}

// ---------------------------------------------------------------------------
// Clipboard pin store and preview cache.
//
// cliphist owns the history, but it cannot keep an entry that must outlive
// history rotation, and it cannot hand the Shell a rendered preview. Both are
// kept under the state directory the Shell already owns, so nothing lands
// outside $XDG_STATE_HOME.
//
// Everything here is content-addressed: a file name is a hash of the bytes (or
// of the cliphist record) it belongs to. That is what makes deletion exact -- a
// delete never has to guess which file to drop -- and it makes pinning the same
// content twice an overwrite instead of a second copy.
// ---------------------------------------------------------------------------

QString clipboardStateDir()
{
    // Mirrors AppearanceConfig::configPath(): Quickshell.stateDir resolves to
    // $XDG_STATE_HOME/quickshell/<shell id>, and this shell's id is "kos".
    const QString stateDir = QStandardPaths::writableLocation(
        QStandardPaths::GenericStateLocation);
    return stateDir + QStringLiteral("/quickshell/kos/clipboard");
}

QString clipboardPinnedDir()
{
    return clipboardStateDir() + QStringLiteral("/pinned");
}

QString clipboardThumbsDir()
{
    return clipboardStateDir() + QStringLiteral("/thumbs");
}

QString clipboardTopic(const QString &record)
{
    return QString::fromLatin1(QCryptographicHash::hash(record.toUtf8(),
                                                        QCryptographicHash::Sha1)
                                   .toHex());
}

QString clipboardPinId(const QByteArray &content)
{
    return QString::fromLatin1(QCryptographicHash::hash(content,
                                                        QCryptographicHash::Sha1)
                                   .toHex()
                                   .left(16));
}

// Pin ids travel through the Shell, so they are validated before ever being
// joined onto a path.
bool isClipboardPinId(const QString &pinId)
{
    static const QRegularExpression pattern(QStringLiteral("^[0-9a-f]{16}$"));
    return pattern.match(pinId).hasMatch();
}

bool clipboardWriteFile(const QString &path, const QByteArray &bytes)
{
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.write(bytes);
    return file.commit();
}

// Renders a decoded payload into the shared preview size. Returns an empty
// string when the bytes are not an image at all, which is how text pins avoid
// getting a thumbnail file they would never use.
QString clipboardWriteThumb(const QByteArray &content, const QString &path)
{
    QImage image;
    if (!image.loadFromData(content))
        return {};
    // 192 px covers both places the panel draws an entry (list row and grid
    // tile) at device pixel ratio 2, without keeping full screenshots around.
    if (image.width() > 192 || image.height() > 192) {
        image = image.scaled(192, 192, Qt::KeepAspectRatio,
                             Qt::SmoothTransformation);
    }
    if (!image.save(path, "PNG"))
        return {};
    return path;
}

void clipboardRemoveThumb(const QString &record)
{
    if (record.isEmpty())
        return;
    QFile::remove(clipboardThumbsDir() + QLatin1Char('/') + clipboardTopic(record)
                  + QStringLiteral(".png"));
}

// Drops every cached preview whose record is no longer in cliphist's output.
// The list operation is the only place that knows the authoritative current
// history, and it runs on every panel refresh, so eviction by cliphist itself
// cannot leave previews behind.
void clipboardPruneThumbs(const QByteArray &listOutput)
{
    QDir dir(clipboardThumbsDir());
    if (!dir.exists())
        return;
    QSet<QString> keep;
    const QStringList lines = QString::fromUtf8(listOutput).split(QChar('\n'));
    for (const QString &line : lines) {
        if (!line.isEmpty())
            keep.insert(clipboardTopic(line));
    }
    const QStringList cached = dir.entryList({QStringLiteral("*.png")}, QDir::Files);
    for (const QString &name : cached) {
        if (!keep.contains(name.chopped(4)))
            dir.remove(name);
    }
}

} // namespace

PlatformServer::PlatformServer(QObject *parent)
    : QObject(parent), m_socketPath(runtimeSocketPath())
{
    // KDED starts the AppMenu registrar only while a menu view exists. Plasma's
    // applet normally owns this queueable marker service; own it here so the
    // Bar can receive menus without running a separate Plasma panel applet.
    QDBusConnection::sessionBus().interface()->registerService(
        QStringLiteral("org.kde.kappmenuview"),
        QDBusConnectionInterface::QueueService,
        QDBusConnectionInterface::DontAllowReplacement);
    connect(&m_server, &QLocalServer::newConnection,
            this, &PlatformServer::acceptConnections);
    const QString wlPaste = QStandardPaths::findExecutable(QStringLiteral("wl-paste"));
    const QString cliphist = QStandardPaths::findExecutable(QStringLiteral("cliphist"));
    if (wlPaste.isEmpty() || cliphist.isEmpty()) {
        QStringList missing;
        if (wlPaste.isEmpty())
            missing.append(QStringLiteral("wl-paste (wl-clipboard)"));
        if (cliphist.isEmpty())
            missing.append(QStringLiteral("cliphist"));
        qInfo().noquote() << "Clipboard history disabled; optional tools missing:"
                          << missing.join(QStringLiteral(", "));
    } else {
        startClipboardHistoryWatcher(m_textHistoryWatcher,
            {wlPaste, QStringLiteral("--type"), QStringLiteral("text"),
             QStringLiteral("--watch"), cliphist, QStringLiteral("store")});
        startClipboardHistoryWatcher(m_imageHistoryWatcher,
            {wlPaste, QStringLiteral("--type"), QStringLiteral("image"),
             QStringLiteral("--watch"), cliphist, QStringLiteral("store")});
    }
    // The wl-paste watcher already forks `cliphist store` on every new entry;
    // hooking QClipboard::dataChanged catches the same moment without parsing
    // wl-paste output, so the list cache can stay cheap and still drop stale
    // answers as soon as the clipboard moves.
    if (QClipboard *clipboard = QGuiApplication::clipboard()) {
        connect(clipboard, &QClipboard::dataChanged, this, [this] {
            invalidateReplies(QStringLiteral("clipboard.history.list"));
        });
    }
    const QString pactl = QStandardPaths::findExecutable(QStringLiteral("pactl"));
    if (!pactl.isEmpty())
        startAudioEventWatcher(pactl);
    // Two concurrent copies at most: more would thrash the same disk anyway,
    // and the pool queue keeps additional requests waiting off the event loop.
    m_copyPool.setMaxThreadCount(2);
    // network.refresh/network.details run their synchronous NM D-Bus walks
    // here; a dedicated pool keeps them from queueing behind file.copy work
    // (and vice versa).
    m_dbusPool.setMaxThreadCount(2);
}

PlatformServer::~PlatformServer()
{
    // QLocalServer owns accepted sockets and is destroyed after the tracking
    // containers below. Disconnect first so socket destruction cannot call
    // clientDisconnected() after those containers have already been freed.
    for (QLocalSocket *socket : m_buffers.keys())
        QObject::disconnect(socket, nullptr, this, nullptr);
}

bool PlatformServer::listen()
{
    QLocalServer::removeServer(m_socketPath);
    if (!m_server.listen(m_socketPath)) {
        qWarning() << "Unable to listen on" << m_socketPath << m_server.errorString();
        return false;
    }
    // QLocalServer follows the platform's default umask, which is commonly
    // 0666.  The platform socket carries clipboard paths and power controls,
    // so it must never be readable by another local user.
    QFile::setPermissions(m_socketPath, QFileDevice::ReadOwner
        | QFileDevice::WriteOwner);
    return true;
}

void PlatformServer::acceptConnections()
{
    while (m_server.hasPendingConnections()) {
        auto *socket = m_server.nextPendingConnection();
        m_buffers.insert(socket, {});
        connect(socket, &QLocalSocket::readyRead, this, &PlatformServer::readClient);
        connect(socket, &QLocalSocket::disconnected, this, &PlatformServer::clientDisconnected);
    }
}

void PlatformServer::readClient()
{
    auto *socket = qobject_cast<QLocalSocket *>(sender());
    if (!socket)
        return;
    QByteArray &buffer = m_buffers[socket];
    buffer.append(socket->readAll());
    // A newline-free client would otherwise grow this buffer forever; the
    // cap bounds per-connection memory and rejects the peer explicitly.
    if (buffer.size() > kMaxClientBufferBytes) {
        QJsonObject response{{QStringLiteral("version"), kProtocolVersion},
                              {QStringLiteral("ok"), false},
                              {QStringLiteral("error"), errorObject(
                                   QStringLiteral("request-too-large"),
                                   QStringLiteral("请求超出大小限制"), false)}};
        socket->write(QJsonDocument(response).toJson(QJsonDocument::Compact) + '\n');
        socket->flush();
        // Emits disconnected() -> clientDisconnected(), which removes the
        // buffer and schedules the socket for deletion.
        socket->disconnectFromServer();
        return;
    }
    // Consume complete lines through a cursor and compact once at the end;
    // removing per line would memmove the tail for every line in a batch.
    qsizetype offset = 0;
    while (true) {
        const qsizetype newline = buffer.indexOf('\n', offset);
        if (newline < 0)
            break;
        const QByteArray line = buffer.mid(offset, newline - offset).trimmed();
        offset = newline + 1;
        if (line.isEmpty())
            continue;
        QJsonParseError error;
        const QJsonDocument document = QJsonDocument::fromJson(line, &error);
        if (error.error != QJsonParseError::NoError || !document.isObject()) {
            QJsonObject response{{QStringLiteral("version"), kProtocolVersion},
                                  {QStringLiteral("ok"), false},
                                  {QStringLiteral("error"), errorObject(
                                       QStringLiteral("invalid-json"),
                                       QStringLiteral("请求不是有效 JSON"), false)}};
            socket->write(QJsonDocument(response).toJson(QJsonDocument::Compact) + '\n');
            socket->flush();
            continue;
        }
        handleRequest(socket, document.object());
    }
    // Bytes after the last newline are a partial line; keep them for the
    // next readyRead and drop only what was consumed.
    if (offset > 0)
        buffer.remove(0, offset);
}

void PlatformServer::clientDisconnected()
{
    auto *socket = qobject_cast<QLocalSocket *>(sender());
    if (!socket)
        return;
    m_windowSubscribers.remove(socket);
    m_buffers.remove(socket);
    socket->deleteLater();
}

QString PlatformServer::requestId(const QJsonObject &request) const
{
    return request.value(QStringLiteral("requestId")).toString();
}

QString PlatformServer::operation(const QJsonObject &request) const
{
    return request.value(QStringLiteral("operation")).toString();
}

void PlatformServer::respond(QLocalSocket *socket, const QJsonObject &request,
                              bool ok, const QJsonObject &result,
                              const QString &code, const QString &message,
                              bool retryable)
{
    if (!socket || socket->state() != QLocalSocket::ConnectedState)
        return;
    QJsonObject response{{QStringLiteral("version"), kProtocolVersion},
                         {QStringLiteral("requestId"), requestId(request)},
                         {QStringLiteral("ok"), ok}};
    if (ok)
        response.insert(QStringLiteral("result"), result);
    else
        response.insert(QStringLiteral("error"), errorObject(code, message, retryable));
    socket->write(QJsonDocument(response).toJson(QJsonDocument::Compact) + '\n');
    socket->flush();
}

void PlatformServer::sendEvent(QLocalSocket *socket, const QJsonObject &event)
{
    if (!socket || socket->state() != QLocalSocket::ConnectedState)
        return;
    QString eventName = event.value(QStringLiteral("type")).toString();
    if (eventName == QStringLiteral("snapshot"))
        eventName = QStringLiteral("window.snapshot");
    else if (eventName == QStringLiteral("action"))
        eventName = QStringLiteral("window.action");
    QJsonObject message{{QStringLiteral("version"), kProtocolVersion},
                        {QStringLiteral("event"), eventName},
                        {QStringLiteral("payload"), event}};
    socket->write(QJsonDocument(message).toJson(QJsonDocument::Compact) + '\n');
    socket->flush();
}

void PlatformServer::broadcastKWinEvent(const QJsonObject &event)
{
    const QString type = event.value(QStringLiteral("type")).toString();
    if (type == QStringLiteral("snapshot"))
        m_latestWindowSnapshot = event;
    else if (type == QStringLiteral("desktops"))
        m_latestDesktopSnapshot = event;
    for (auto *socket : std::as_const(m_windowSubscribers))
        sendEvent(socket, event);
}

void PlatformServer::runCommand(QLocalSocket *socket, const QJsonObject &request,
                                const QString &program, const QStringList &arguments,
                                std::function<QJsonObject(const QByteArray &, int)> parser,
                                int timeoutMs, const QString &cacheKey, int cacheTtlMs)
{
    // With a cacheKey the response is shared: a poll that lands while the
    // same operation is still running queues onto it instead of spawning a
    // second copy of the same command.
    if (!cacheKey.isEmpty()
        && (serveCachedReply(socket, request, cacheKey)
            || queueIfInFlight(cacheKey, socket, request)))
        return;
    if (timeoutMs < 0)
        timeoutMs = kDefaultCommandTimeoutMs;
    const QPointer<QLocalSocket> guardedSocket(socket);
    auto *process = new QProcess(this);
    process->setProgram(program);
    process->setArguments(arguments);
    const auto replied = std::make_shared<bool>(false);
    const auto timedOut = std::make_shared<bool>(false);
    // timeoutMs == 0 opts out (interactive tools whose lifetime is the user's
    // session, not the request). Everything else gets a kill watchdog so a
    // wedged helper fails instead of stacking up one process per poll.
    if (timeoutMs > 0) {
        QPointer<QProcess> processGuard(process);
        QTimer::singleShot(timeoutMs, process, [processGuard, timedOut]() {
            if (processGuard && processGuard->state() != QProcess::NotRunning) {
                *timedOut = true;
                processGuard->kill();
            }
        });
    }
    connect(process, &QProcess::finished, this,
            [this, guardedSocket, request, process, parser, replied, timedOut,
             cacheKey, cacheTtlMs](int exitCode, QProcess::ExitStatus exitStatus) {
        if (*replied)
            return;
        *replied = true;
        const QByteArray output = process->readAllStandardOutput();
        const QByteArray error = process->readAllStandardError();
        const bool ok = exitStatus == QProcess::NormalExit && exitCode == 0;
        const QString code = *timedOut ? QStringLiteral("command-timeout")
                                       : QStringLiteral("command-failed");
        const QString message = *timedOut ? QStringLiteral("平台命令执行超时")
                                          : QStringLiteral("平台命令执行失败");
        QJsonObject result;
        if (ok)
            result = parser ? parser(output, exitCode) : parseOutput(output, exitCode);
        if (cacheKey.isEmpty()) {
            if (ok)
                respond(guardedSocket.data(), request, true, result);
            else {
                Q_UNUSED(error);
                respond(guardedSocket.data(), request, false, {}, code, message, true);
            }
        } else {
            completeInFlight(cacheKey, ok, result, code, message, true, cacheTtlMs);
        }
        process->deleteLater();
    });
    connect(process, &QProcess::errorOccurred, this,
            [this, guardedSocket, request, process, replied, timedOut,
             cacheKey, cacheTtlMs](QProcess::ProcessError) {
        if (*replied)
            return;
        *replied = true;
        // A watchdog kill arrives here as Crashed, ahead of finished() --
        // surface the timeout instead of a generic failure.
        const QString code = *timedOut ? QStringLiteral("command-timeout")
                                       : QStringLiteral("command-unavailable");
        const QString message = *timedOut ? QStringLiteral("平台命令执行超时")
                                          : QStringLiteral("平台命令不可用");
        if (cacheKey.isEmpty())
            respond(guardedSocket.data(), request, false, {}, code, message, true);
        else
            completeInFlight(cacheKey, false, {}, code, message, true, cacheTtlMs);
        process->deleteLater();
    });
    process->start();
}

bool PlatformServer::serveCachedReply(QLocalSocket *socket, const QJsonObject &request,
                                      const QString &key)
{
    const auto it = m_replyCache.find(key);
    if (it == m_replyCache.end())
        return false;
    if (QDateTime::currentMSecsSinceEpoch() >= it->expiresAt) {
        m_replyCache.erase(it);
        return false;
    }
    if (it->ok)
        respond(socket, request, true, it->result);
    else
        respond(socket, request, false, {}, it->code, it->message, it->retryable);
    return true;
}

void PlatformServer::storeReply(const QString &key, int ttlMs, bool ok,
                                const QJsonObject &result, const QString &code,
                                const QString &message, bool retryable)
{
    if (ttlMs <= 0)
        return;
    CachedReply entry;
    entry.ok = ok;
    entry.result = result;
    entry.code = code;
    entry.message = message;
    entry.retryable = retryable;
    entry.expiresAt = QDateTime::currentMSecsSinceEpoch()
        + (ok ? ttlMs : qMin(ttlMs, static_cast<int>(kFailureCacheTtlMs)));
    m_replyCache.insert(key, entry);
}

void PlatformServer::invalidateReplies(const QString &keyPrefix)
{
    for (auto it = m_replyCache.begin(); it != m_replyCache.end();) {
        if (it.key().startsWith(keyPrefix))
            it = m_replyCache.erase(it);
        else
            ++it;
    }
}

bool PlatformServer::queueIfInFlight(const QString &key, QLocalSocket *socket,
                                     const QJsonObject &request)
{
    QList<PendingReply> &pending = m_inFlightReplies[key];
    const bool alreadyRunning = !pending.isEmpty();
    pending.append({QPointer<QLocalSocket>(socket), request});
    return alreadyRunning;
}

void PlatformServer::completeInFlight(const QString &key, bool ok,
                                      const QJsonObject &result,
                                      const QString &code, const QString &message,
                                      bool retryable, int ttlMs)
{
    storeReply(key, ttlMs, ok, result, code, message, retryable);
    const QList<PendingReply> pending = m_inFlightReplies.take(key);
    for (const PendingReply &entry : pending) {
        if (ok)
            respond(entry.socket.data(), entry.request, true, result);
        else
            respond(entry.socket.data(), entry.request, false, {},
                    code, message, retryable);
    }
}

void PlatformServer::watchNmPath(const QString &path)
{
    if (path.isEmpty() || path == QStringLiteral("/") || m_nmWatchedPaths.contains(path))
        return;
    m_nmWatchedPaths.insert(path);
    QDBusConnection::systemBus().connect(QString::fromLatin1(kNmService), path,
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("PropertiesChanged"),
        this, SLOT(nmPropertiesChanged(QString,QVariantMap,QStringList)));
}

void PlatformServer::watchBluezManager()
{
    if (m_bluezManagerWatched)
        return;
    m_bluezManagerWatched = true;
    QDBusConnection bus = QDBusConnection::systemBus();
    bus.connect(QString::fromLatin1(kBluezService), QStringLiteral("/"),
        QStringLiteral("org.freedesktop.DBus.ObjectManager"),
        QStringLiteral("InterfacesAdded"),
        this, SLOT(bluezInterfacesAdded(QDBusObjectPath,QVariantMap)));
    bus.connect(QString::fromLatin1(kBluezService), QStringLiteral("/"),
        QStringLiteral("org.freedesktop.DBus.ObjectManager"),
        QStringLiteral("InterfacesRemoved"),
        this, SLOT(bluezInterfacesRemoved(QDBusObjectPath,QStringList)));
}

void PlatformServer::watchBluezPath(const QString &path)
{
    if (path.isEmpty() || path == QStringLiteral("/")
        || m_bluezWatchedPaths.contains(path))
        return;
    m_bluezWatchedPaths.insert(path);
    QDBusConnection::systemBus().connect(QString::fromLatin1(kBluezService), path,
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("PropertiesChanged"),
        this, SLOT(bluezPropertiesChanged(QString,QVariantMap,QStringList)));
}

void PlatformServer::watchBrightnessPath(const QString &service, const QString &path)
{
    const QString key = service + QLatin1Char(' ') + path;
    if (service.isEmpty() || path.isEmpty() || m_brightnessWatched.contains(key))
        return;
    m_brightnessWatched.insert(key);
    QDBusConnection::sessionBus().connect(service, path,
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("PropertiesChanged"),
        this, SLOT(brightnessPropertiesChanged(QString,QVariantMap,QStringList)));
}

void PlatformServer::watchNightLight()
{
    if (m_nightLightWatched)
        return;
    m_nightLightWatched = true;
    QDBusConnection::sessionBus().connect(QStringLiteral("org.kde.KWin"),
        QStringLiteral("/org/kde/KWin/NightLight"),
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("PropertiesChanged"),
        this, SLOT(nightLightPropertiesChanged(QString,QVariantMap,QStringList)));
}

void PlatformServer::nmPropertiesChanged(const QString &, const QVariantMap &,
                                         const QStringList &)
{
    invalidateReplies(QStringLiteral("network."));
}

void PlatformServer::bluezPropertiesChanged(const QString &, const QVariantMap &,
                                            const QStringList &)
{
    invalidateReplies(QStringLiteral("bluetooth."));
}

void PlatformServer::bluezInterfacesAdded(const QDBusObjectPath &path,
                                          const QVariantMap &)
{
    // A new adapter or device object is also a new path worth watching.
    watchBluezPath(path.path());
    invalidateReplies(QStringLiteral("bluetooth."));
}

void PlatformServer::bluezInterfacesRemoved(const QDBusObjectPath &path,
                                            const QStringList &)
{
    // The object is gone; let the next list call re-subscribe if it returns.
    m_bluezWatchedPaths.remove(path.path());
    invalidateReplies(QStringLiteral("bluetooth."));
}

void PlatformServer::brightnessPropertiesChanged(const QString &, const QVariantMap &,
                                                 const QStringList &)
{
    invalidateReplies(QStringLiteral("display.brightness."));
}

void PlatformServer::nightLightPropertiesChanged(const QString &, const QVariantMap &,
                                                 const QStringList &)
{
    invalidateReplies(QStringLiteral("nightlight."));
}

// One resident `pactl subscribe` replaces the per-poll wpctl/pactl spawns:
// every event line marks the audio reply cache stale, so the next poll
// re-reads only when something actually changed.
void PlatformServer::startAudioEventWatcher(const QString &pactl)
{
    if (m_audioEventWatcher)
        return;
    auto *process = new QProcess(this);
    m_audioEventWatcher = process;
    process->setProgram(pactl);
    process->setArguments({QStringLiteral("subscribe")});
    process->setProperty("startedAt", QDateTime::currentMSecsSinceEpoch());
    connect(process, &QProcess::readyReadStandardOutput, this, [this, process]() {
        if (!process->readAllStandardOutput().isEmpty())
            invalidateReplies(QStringLiteral("audio."));
    });
    const auto restart = [this, process]() {
        // A subscribe that exits immediately after every start is a
        // permanently broken helper, not a dropped connection -- back off to
        // a slow retry instead of fork-spinning.
        const qint64 ran = QDateTime::currentMSecsSinceEpoch()
            - process->property("startedAt").toLongLong();
        QTimer::singleShot(ran < 10000 ? 60000 : 2000, this, [this, process]() {
            if (process != m_audioEventWatcher
                || process->state() != QProcess::NotRunning)
                return;
            process->setProperty("startedAt", QDateTime::currentMSecsSinceEpoch());
            process->start();
        });
    };
    connect(process, &QProcess::finished, this, restart);
    // FailedToStart does not always emit finished(); route it through the
    // same backoff restart so the watcher cannot silently die.
    connect(process, &QProcess::errorOccurred, this, restart);
    process->start();
}

void PlatformServer::applySystemTheme(QLocalSocket *socket,
                                      const QJsonObject &request, bool dark)
{
    const QString colorScheme = dark ? QStringLiteral("BreezeDark")
                                     : QStringLiteral("BreezeLight");
    const QString lookAndFeel = dark ? QStringLiteral("org.kde.breezedark.desktop")
                                     : QStringLiteral("org.kde.breeze.desktop");
    const QString applyColorScheme = QStandardPaths::findExecutable(
        QStringLiteral("plasma-apply-colorscheme"));
    const QString applyLookAndFeel = QStandardPaths::findExecutable(
        QStringLiteral("plasma-apply-lookandfeel"));

    QString program;
    QStringList arguments;
    QString method;
    if (!applyColorScheme.isEmpty()) {
        // A light/dark toggle only needs to change the palette. Applying a
        // complete Look-and-Feel package also replaces icons, cursors and
        // workspace defaults while Quickshell is rendering them, which can
        // tear down the Shell's platform connection mid-request.
        program = applyColorScheme;
        arguments = {colorScheme};
        method = QStringLiteral("colorScheme");
    } else if (!applyLookAndFeel.isEmpty()) {
        program = applyLookAndFeel;
        arguments = {QStringLiteral("--apply"), lookAndFeel};
        method = QStringLiteral("lookAndFeel");
    } else {
        respond(socket, request, false, {}, QStringLiteral("theme-apply-failed"),
                QStringLiteral("未找到可用的 KDE 明暗主题"), true);
        return;
    }

    runCommand(socket, request, program, arguments,
               [dark, colorScheme, lookAndFeel, method](const QByteArray &, int) {
        return QJsonObject{{QStringLiteral("dark"), dark},
                           {QStringLiteral("colorScheme"), colorScheme},
                           {QStringLiteral("lookAndFeel"), lookAndFeel},
                           {QStringLiteral("method"), method}};
    }, 30000);
}

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
    const QString key = QStringLiteral("network.connect:") + connectRequest.device
        + QLatin1Char(':') + connectRequest.savedProfileUuid
        + QLatin1Char(':') + connectRequest.replaceProfileId
        + QLatin1Char(':')
        + connectRequest.settings.value(QStringLiteral("connection"))
              .toMap().value(QStringLiteral("id")).toString();
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
        completeInFlight(key, out.ok, out.result, out.code, out.message,
                         out.retryable, kNetworkConnectTtlMs);
    });
    watcher->setFuture(QtConcurrent::run(&m_dbusPool, networkConnectWorker,
                                         connectRequest.device,
                                         connectRequest.savedProfileUuid,
                                         connectRequest.settings,
                                         connectRequest.replaceProfileId));
}

void PlatformServer::runTrayIdentify(QLocalSocket *socket, const QJsonObject &request)
{
    const QString key = QStringLiteral("tray.identify");
    if (serveCachedReply(socket, request, key)
        || queueIfInFlight(key, socket, request))
        return;

    // The walk is a bounded D-Bus sweep (one Get per item plus a PID lookup)
    // on m_dbusPool, so a slow or wedged watcher cannot stall the socket loop.
    auto *watcher = new QFutureWatcher<TrayIdentityResult>(this);
    connect(watcher, &QFutureWatcher<TrayIdentityResult>::finished, this,
            [this, watcher, key]() {
        watcher->deleteLater();
        const TrayIdentityResult out = watcher->result();
        completeInFlight(key, out.ok,
                         out.ok ? QJsonObject{{QStringLiteral("names"), out.names}}
                                : QJsonObject{},
                         out.code, out.message, true, kTrayIdentifyCacheTtlMs);
    });
    watcher->setFuture(QtConcurrent::run(&m_dbusPool, trayIdentifyWorker));
}

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

void PlatformServer::startClipboardHistoryWatcher(QProcess *&watcher,
                                                   const QStringList &arguments)
{
    if (watcher)
        return;
    if (arguments.isEmpty())
        return;
    auto *process = new QProcess(this);
    watcher = process;
    const QString program = arguments.first();
    const QStringList args = arguments.mid(1);
    process->setProgram(program);
    process->setArguments(args);
    connect(process, &QProcess::errorOccurred, this,
            [program](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            qWarning() << "Clipboard history watcher unavailable:" << program;
    });
    connect(process, &QProcess::finished, this,
            [this, process, program, args](int, QProcess::ExitStatus) {
        // wl-paste --watch exits when the Wayland connection disappears. Keep
        // the one resident watcher recoverable without spawning a Shell-side
        // supervisor or multiplying helper executables.
        QTimer::singleShot(2000, this, [this, process, program, args] {
            if (process->state() != QProcess::NotRunning)
                return;
            if (process == m_imageHistoryWatcher && !m_watchImages)
                return;
            process->setProgram(program);
            process->setArguments(args);
            process->start();
        });
    });
    process->start();
}

void PlatformServer::runClipboardDecode(QLocalSocket *socket,
                                         const QJsonObject &request,
                                         const QString &record)
{
    if (record.isEmpty()) {
        respond(socket, request, false, {}, QStringLiteral("invalid-clipboard-entry"),
                QStringLiteral("剪贴板记录无效"), false);
        return;
    }
    const QPointer<QLocalSocket> guardedSocket(socket);
    auto *decode = new QProcess(this);
    decode->setProgram(QStringLiteral("cliphist"));
    decode->setArguments({QStringLiteral("decode")});
    armProcessWatchdog(decode, 15000);
    const auto replied = std::make_shared<bool>(false);
    connect(decode, &QProcess::errorOccurred, this,
            [this, guardedSocket, request, decode, replied](QProcess::ProcessError) {
        if (*replied)
            return;
        *replied = true;
        respond(guardedSocket.data(), request, false, {}, QStringLiteral("clipboard-unavailable"),
                QStringLiteral("剪贴板历史不可用"), true);
        decode->deleteLater();
    });
    connect(decode, &QProcess::finished, this,
            [this, guardedSocket, request, decode, replied](int exitCode, QProcess::ExitStatus) {
        if (*replied)
            return;
        if (exitCode != 0) {
            *replied = true;
            respond(guardedSocket.data(), request, false, {}, QStringLiteral("clipboard-decode-failed"),
                    QStringLiteral("无法恢复剪贴板记录"), true);
            decode->deleteLater();
            return;
        }
        const QByteArray decoded = decode->readAllStandardOutput();
        decode->deleteLater();
        auto *copy = new QProcess(this);
        copy->setProgram(QStringLiteral("wl-copy"));
        armProcessWatchdog(copy, 15000);
        connect(copy, &QProcess::started, this,
                [copy, decoded] {
            copy->write(decoded);
            copy->closeWriteChannel();
        });
        connect(copy, &QProcess::errorOccurred, this,
                [this, guardedSocket, request, copy, replied](QProcess::ProcessError) {
            if (*replied)
                return;
            *replied = true;
            respond(guardedSocket.data(), request, false, {}, QStringLiteral("clipboard-unavailable"),
                    QStringLiteral("无法写入剪贴板"), true);
            copy->deleteLater();
        });
        connect(copy, &QProcess::finished, this,
                [this, guardedSocket, request, copy, replied](int exitCode, QProcess::ExitStatus) {
            if (*replied)
                return;
            *replied = true;
            if (exitCode == 0)
                respond(guardedSocket.data(), request, true,
                        QJsonObject{{QStringLiteral("copied"), true}});
            else
                respond(guardedSocket.data(), request, false, {}, QStringLiteral("clipboard-copy-failed"),
                        QStringLiteral("无法写入剪贴板"), true);
            copy->deleteLater();
        });
        copy->start();
    });
    connect(decode, &QProcess::started, this,
            [decode, record] {
        decode->write(record.toUtf8());
        decode->write("\n");
        decode->closeWriteChannel();
    });
    decode->start();
}

void PlatformServer::runClipboardDelete(QLocalSocket *socket,
                                         const QJsonObject &request,
                                         const QString &record)
{
    if (record.isEmpty()) {
        respond(socket, request, false, {}, QStringLiteral("invalid-clipboard-entry"),
                QStringLiteral("剪贴板记录无效"), false);
        return;
    }
    const QPointer<QLocalSocket> guardedSocket(socket);
    auto *process = new QProcess(this);
    process->setProgram(QStringLiteral("cliphist"));
    process->setArguments({QStringLiteral("delete")});
    armProcessWatchdog(process, 10000);
    const auto replied = std::make_shared<bool>(false);
    connect(process, &QProcess::errorOccurred, this,
            [this, guardedSocket, request, process, replied](QProcess::ProcessError) {
        if (*replied)
            return;
        *replied = true;
        respond(guardedSocket.data(), request, false, {}, QStringLiteral("clipboard-unavailable"),
                QStringLiteral("剪贴板历史不可用"), true);
        process->deleteLater();
    });
    connect(process, &QProcess::finished, this,
            [this, guardedSocket, request, process, record, replied](int exitCode,
                                                              QProcess::ExitStatus) {
        if (*replied)
            return;
        *replied = true;
        if (exitCode == 0) {
            // The cached preview belongs to the entry that just went away.
            // Dropping it here is what keeps the state directory from growing
            // a file per deleted entry.
            clipboardRemoveThumb(record);
            invalidateReplies(QStringLiteral("clipboard.history.list"));
            respond(guardedSocket.data(), request, true,
                    QJsonObject{{QStringLiteral("deleted"), true}});
        } else {
            respond(guardedSocket.data(), request, false, {}, QStringLiteral("clipboard-delete-failed"),
                    QStringLiteral("无法删除剪贴板记录"), true);
        }
        process->deleteLater();
    });
    connect(process, &QProcess::started, this,
            [process, record] {
        process->write(record.toUtf8());
        process->write("\n");
        process->closeWriteChannel();
    });
    process->start();
}

void PlatformServer::runCliphistDecode(const QString &record,
                                       std::function<void(bool, const QByteArray &)> done)
{
    auto *process = new QProcess(this);
    process->setProgram(QStringLiteral("cliphist"));
    process->setArguments({QStringLiteral("decode")});
    armProcessWatchdog(process, 15000);
    const auto replied = std::make_shared<bool>(false);
    connect(process, &QProcess::errorOccurred, this,
            [process, replied, done](QProcess::ProcessError) {
        if (*replied)
            return;
        *replied = true;
        process->deleteLater();
        done(false, {});
    });
    connect(process, &QProcess::finished, this,
            [process, replied, done](int exitCode, QProcess::ExitStatus) {
        if (*replied)
            return;
        *replied = true;
        const QByteArray output = process->readAllStandardOutput();
        process->deleteLater();
        done(exitCode == 0, output);
    });
    connect(process, &QProcess::started, this,
            [process, record] {
        process->write(record.toUtf8());
        process->write("\n");
        process->closeWriteChannel();
    });
    process->start();
}

void PlatformServer::runWlCopy(const QByteArray &payload,
                               std::function<void(bool)> done)
{
    auto *process = new QProcess(this);
    process->setProgram(QStringLiteral("wl-copy"));
    armProcessWatchdog(process, 15000);
    const auto replied = std::make_shared<bool>(false);
    connect(process, &QProcess::errorOccurred, this,
            [process, replied, done](QProcess::ProcessError) {
        if (*replied)
            return;
        *replied = true;
        process->deleteLater();
        done(false);
    });
    connect(process, &QProcess::finished, this,
            [process, replied, done](int exitCode, QProcess::ExitStatus) {
        if (*replied)
            return;
        *replied = true;
        process->deleteLater();
        done(exitCode == 0);
    });
    connect(process, &QProcess::started, this,
            [process, payload] {
        process->write(payload);
        process->closeWriteChannel();
    });
    process->start();
}

void PlatformServer::runClipboardThumb(QLocalSocket *socket,
                                       const QJsonObject &request,
                                       const QString &record)
{
    if (record.isEmpty()) {
        respond(socket, request, false, {}, QStringLiteral("invalid-clipboard-entry"),
                QStringLiteral("剪贴板记录无效"), false);
        return;
    }
    const QPointer<QLocalSocket> guardedSocket(socket);
    const QString path = clipboardThumbsDir() + QLatin1Char('/')
        + clipboardTopic(record) + QStringLiteral(".png");
    if (QFileInfo::exists(path)) {
        respond(guardedSocket.data(), request, true,
                QJsonObject{{QStringLiteral("path"), path}});
        return;
    }
    runCliphistDecode(record, [this, guardedSocket, request, path](bool ok,
                                                                 const QByteArray &content) {
        if (!ok) {
            respond(guardedSocket.data(), request, false, {},
                    QStringLiteral("clipboard-decode-failed"),
                    QStringLiteral("无法恢复剪贴板记录"), true);
            return;
        }
        if (!QDir().mkpath(clipboardThumbsDir())
            || clipboardWriteThumb(content, path).isEmpty()) {
            respond(guardedSocket.data(), request, false, {},
                    QStringLiteral("clipboard-image-unavailable"),
                    QStringLiteral("剪贴板记录不是图片"), false);
            return;
        }
        respond(guardedSocket.data(), request, true,
                QJsonObject{{QStringLiteral("path"), path}});
    });
}

void PlatformServer::runClipboardPinnedList(QLocalSocket *socket,
                                            const QJsonObject &request)
{
    const QString pinnedDir = clipboardPinnedDir();
    QJsonArray items;
    const QStringList metas = QDir(pinnedDir).entryList({QStringLiteral("*.json")},
                                                        QDir::Files, QDir::Name);
    for (const QString &metaName : metas) {
        const QString pinId = metaName.chopped(5); // ".json"
        if (!isClipboardPinId(pinId))
            continue;
        QFile metaFile(pinnedDir + QLatin1Char('/') + metaName);
        if (!metaFile.open(QIODevice::ReadOnly))
            continue;
        const QJsonObject meta = QJsonDocument::fromJson(metaFile.readAll()).object();
        const bool isImage = meta.value(QStringLiteral("isImage")).toBool();
        const QString thumbnailPath = pinnedDir + QLatin1Char('/') + pinId
            + QStringLiteral(".png");
        items.append(QJsonObject{
            {QStringLiteral("pinId"), pinId},
            {QStringLiteral("isImage"), isImage},
            {QStringLiteral("preview"), meta.value(QStringLiteral("preview")).toString()},
            {QStringLiteral("thumbnailPath"),
             isImage && QFileInfo::exists(thumbnailPath) ? thumbnailPath : QString()},
        });
    }
    respond(socket, request, true, QJsonObject{{QStringLiteral("items"), items}});
}

void PlatformServer::runClipboardPinnedAdd(QLocalSocket *socket,
                                           const QJsonObject &request,
                                           const QString &record,
                                           const QString &preview)
{
    if (record.isEmpty()) {
        respond(socket, request, false, {}, QStringLiteral("invalid-clipboard-entry"),
                QStringLiteral("剪贴板记录无效"), false);
        return;
    }
    const QPointer<QLocalSocket> guardedSocket(socket);
    runCliphistDecode(record, [this, guardedSocket, request, preview](bool ok,
                                                                     const QByteArray &content) {
        if (!ok) {
            respond(guardedSocket.data(), request, false, {},
                    QStringLiteral("clipboard-decode-failed"),
                    QStringLiteral("无法恢复剪贴板记录"), true);
            return;
        }
        const QString pinnedDir = clipboardPinnedDir();
        // Content-addressed: pinning the same thing twice overwrites its own
        // three files instead of producing a second copy.
        const QString pinId = clipboardPinId(content);
        const QString dataPath = pinnedDir + QLatin1Char('/') + pinId
            + QStringLiteral(".data");
        const QString metaPath = pinnedDir + QLatin1Char('/') + pinId
            + QStringLiteral(".json");
        const QString thumbPath = pinnedDir + QLatin1Char('/') + pinId
            + QStringLiteral(".png");

        if (!QDir().mkpath(pinnedDir) || !clipboardWriteFile(dataPath, content)) {
            respond(guardedSocket.data(), request, false, {},
                    QStringLiteral("clipboard-pin-failed"),
                    QStringLiteral("无法写入固定条目"), true);
            return;
        }

        // The payload decides what this is, not the Shell's guess: a decodable
        // image gets a rendered preview, anything else stays text-only.
        QImage probe;
        const bool isImage = probe.loadFromData(content);
        if (isImage)
            clipboardWriteThumb(content, thumbPath);

        const QJsonObject meta{{QStringLiteral("preview"), preview},
                               {QStringLiteral("isImage"), isImage}};
        if (!clipboardWriteFile(metaPath,
                                QJsonDocument(meta).toJson(QJsonDocument::Compact))) {
            // Never leave a half-written pin behind.
            QFile::remove(dataPath);
            QFile::remove(thumbPath);
            respond(guardedSocket.data(), request, false, {},
                    QStringLiteral("clipboard-pin-failed"),
                    QStringLiteral("无法写入固定条目"), true);
            return;
        }

        respond(guardedSocket.data(), request, true,
                QJsonObject{{QStringLiteral("pinId"), pinId},
                            {QStringLiteral("isImage"), isImage},
                            {QStringLiteral("preview"), preview},
                            {QStringLiteral("thumbnailPath"),
                             isImage ? thumbPath : QString()}});
    });
}

void PlatformServer::runClipboardPinnedRemove(QLocalSocket *socket,
                                              const QJsonObject &request,
                                              const QString &pinId)
{
    if (!isClipboardPinId(pinId)) {
        respond(socket, request, false, {}, QStringLiteral("invalid-clipboard-pin"),
                QStringLiteral("固定条目标识无效"), false);
        return;
    }
    const QString pinnedDir = clipboardPinnedDir();
    bool removed = false;
    const QStringList suffixes{QStringLiteral(".data"), QStringLiteral(".json"),
                               QStringLiteral(".png")};
    for (const QString &suffix : suffixes) {
        removed = QFile::remove(pinnedDir + QLatin1Char('/') + pinId + suffix)
            || removed;
    }
    respond(socket, request, true, QJsonObject{{QStringLiteral("removed"), removed}});
}

void PlatformServer::runClipboardPinnedCopy(QLocalSocket *socket,
                                            const QJsonObject &request,
                                            const QString &pinId)
{
    if (!isClipboardPinId(pinId)) {
        respond(socket, request, false, {}, QStringLiteral("invalid-clipboard-pin"),
                QStringLiteral("固定条目标识无效"), false);
        return;
    }
    QFile file(clipboardPinnedDir() + QLatin1Char('/') + pinId
               + QStringLiteral(".data"));
    if (!file.open(QIODevice::ReadOnly)) {
        respond(socket, request, false, {}, QStringLiteral("clipboard-pin-missing"),
                QStringLiteral("固定条目不存在"), false);
        return;
    }
    const QByteArray content = file.readAll();
    file.close();

    const QPointer<QLocalSocket> guardedSocket(socket);
    runWlCopy(content, [this, guardedSocket, request](bool ok) {
        if (ok) {
            respond(guardedSocket.data(), request, true,
                    QJsonObject{{QStringLiteral("copied"), true}});
        } else {
            respond(guardedSocket.data(), request, false, {},
                    QStringLiteral("clipboard-copy-failed"),
                    QStringLiteral("无法写入剪贴板"), true);
        }
    });
}

bool PlatformServer::handleClipboard(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    QClipboard *clipboard = QGuiApplication::clipboard();
    if (!clipboard) {
        respond(socket, request, false, {}, QStringLiteral("clipboard-unavailable"),
                QStringLiteral("剪贴板不可用"), true);
        return true;
    }
    if (op == QStringLiteral("clipboard.set")) {
        const QString mode = request.value(QStringLiteral("payload")).toObject()
                                 .value(QStringLiteral("mode")).toString();
        const QStringList paths = cleanPaths(request.value(QStringLiteral("payload"))
                                                  .toObject().value(QStringLiteral("paths")));
        if ((mode != QStringLiteral("copy") && mode != QStringLiteral("cut"))
            || paths.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-clipboard-request"),
                    QStringLiteral("剪贴板请求无效"), false);
            return true;
        }
        auto *mime = new QMimeData;
        QList<QUrl> urls;
        for (const QString &path : paths)
            urls.append(QUrl::fromLocalFile(path));
        mime->setUrls(urls);
        mime->setData(QString::fromLatin1(kClipboardCutMime), mode == QStringLiteral("cut") ? "1" : "0");
        QByteArray gnome = mode.toUtf8();
        for (const QUrl &url : urls) {
            gnome.append('\n');
            gnome.append(url.toEncoded());
        }
        mime->setData(QString::fromLatin1(kGnomeFilesMime), gnome);
        clipboard->setMimeData(mime, QClipboard::Clipboard);
        if (!clipboard->ownsClipboard()) {
            respond(socket, request, false, {}, QStringLiteral("clipboard-not-owned"),
                    QStringLiteral("无法取得剪贴板所有权"), true);
            return true;
        }
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("mode"), mode},
                            {QStringLiteral("paths"), jsonPaths(paths)}});
        return true;
    }
    if (op == QStringLiteral("clipboard.read")) {
        const QMimeData *mime = clipboard->mimeData(QClipboard::Clipboard);
        if (!mime) {
            respond(socket, request, false, {}, QStringLiteral("clipboard-unavailable"),
                    QStringLiteral("剪贴板不可用"), true);
            return true;
        }
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("mode"), mimeOperation(mime)},
                            {QStringLiteral("paths"), jsonPaths(localClipboardPaths(mime))}});
        return true;
    }
    if (op == QStringLiteral("clipboard.save-image")) {
        const QString destination = cleanCreatePath(request.value(QStringLiteral("payload"))
                                                  .toObject()
                                                  .value(QStringLiteral("destination"))
                                                  .toString());
        const QMimeData *mime = clipboard->mimeData(QClipboard::Clipboard);
        if (destination.isEmpty() || !mime) {
            respond(socket, request, false, {}, QStringLiteral("invalid-clipboard-request"),
                    QStringLiteral("剪贴板请求无效"), false);
            return true;
        }
        QImage image;
        if (mime->hasImage())
            image = qvariant_cast<QImage>(mime->imageData());
        if (image.isNull() && mime->hasFormat(QStringLiteral("image/png")))
            image.loadFromData(mime->data(QStringLiteral("image/png")), "PNG");
        if (image.isNull()) {
            respond(socket, request, false, {}, QStringLiteral("clipboard-image-unavailable"),
                    QStringLiteral("剪贴板中没有 PNG 图片"), false);
            return true;
        }
        QSaveFile output(destination);
        if (!output.open(QIODevice::WriteOnly) || !image.save(&output, "PNG")
            || !output.commit()) {
            respond(socket, request, false, {}, QStringLiteral("clipboard-image-save-failed"),
                    QStringLiteral("无法保存剪贴板图片"), true);
            return true;
        }
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("path"), destination},
                            {QStringLiteral("width"), image.width()},
                            {QStringLiteral("height"), image.height()}});
        return true;
    }
    if (op == QStringLiteral("clipboard.history.watch-images")) {
        m_watchImages = request.value(QStringLiteral("payload")).toObject()
                            .value(QStringLiteral("enabled")).toBool();
        if (!m_watchImages && m_imageHistoryWatcher)
            m_imageHistoryWatcher->kill();
        else if (m_watchImages && m_imageHistoryWatcher
                 && m_imageHistoryWatcher->state() == QProcess::NotRunning)
            m_imageHistoryWatcher->start();
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("enabled"), m_watchImages}});
        return true;
    }
    if (op == QStringLiteral("clipboard.history.list")) {
        runCommand(socket, request, QStringLiteral("cliphist"),
                   {QStringLiteral("list")},
                   [this](const QByteArray &output, int exitCode) {
            // Prune only when the authoritative list actually changed, and no
            // more than once per throttle window: the panel polls this on
            // every refresh, so a naive prune would re-walk the thumbs dir
            // each time for nothing.
            const qint64 now = QDateTime::currentMSecsSinceEpoch();
            const QByteArray hash = QCryptographicHash::hash(
                output, QCryptographicHash::Sha1).toHex();
            if (hash != m_lastClipboardListHash
                || now - m_lastClipboardPruneMs >= 5000) {
                m_lastClipboardListHash = hash;
                m_lastClipboardPruneMs = now;
                clipboardPruneThumbs(output);
            }
            return parseOutput(output, exitCode);
        },
        kDefaultCommandTimeoutMs,
        QStringLiteral("clipboard.history.list"),
        kClipboardHistoryCacheTtlMs);
        return true;
    }
    if (op == QStringLiteral("clipboard.history.copy")) {
        runClipboardDecode(socket, request,
                           request.value(QStringLiteral("payload")).toObject()
                               .value(QStringLiteral("record")).toString());
        return true;
    }
    if (op == QStringLiteral("clipboard.history.delete")) {
        runClipboardDelete(socket, request,
                           request.value(QStringLiteral("payload")).toObject()
                               .value(QStringLiteral("record")).toString());
        return true;
    }
    if (op == QStringLiteral("clipboard.history.clear")) {
        const QPointer<QLocalSocket> guardedSocket(socket);
        auto *process = new QProcess(this);
        process->setProgram(QStringLiteral("cliphist"));
        process->setArguments({QStringLiteral("wipe")});
        armProcessWatchdog(process, 15000);
        const auto replied = std::make_shared<bool>(false);
        connect(process, &QProcess::errorOccurred, this,
                [this, guardedSocket, request, process, replied](QProcess::ProcessError) {
            if (*replied)
                return;
            *replied = true;
            respond(guardedSocket.data(), request, false, {}, QStringLiteral("clipboard-unavailable"),
                    QStringLiteral("剪贴板历史不可用"), true);
            process->deleteLater();
        });
        connect(process, &QProcess::finished, this,
                [this, guardedSocket, request, process, replied](int exitCode, QProcess::ExitStatus) {
            if (*replied)
                return;
            *replied = true;
            if (exitCode == 0) {
                if (auto *clipboard = QGuiApplication::clipboard())
                    clipboard->clear(QClipboard::Clipboard);
                // Pinned entries survive a wipe by design; only the history
                // preview cache is owned by the history that just disappeared.
                QDir(clipboardThumbsDir()).removeRecursively();
                invalidateReplies(QStringLiteral("clipboard.history.list"));
                respond(guardedSocket.data(), request, true,
                        QJsonObject{{QStringLiteral("cleared"), true}});
            } else {
                respond(guardedSocket.data(), request, false, {}, QStringLiteral("clipboard-clear-failed"),
                        QStringLiteral("无法清空剪贴板历史"), true);
            }
            process->deleteLater();
        });
        process->start();
        return true;
    }
    const QJsonObject clipboardPayload =
        request.value(QStringLiteral("payload")).toObject();
    if (op == QStringLiteral("clipboard.thumb")) {
        runClipboardThumb(socket, request,
                          clipboardPayload.value(QStringLiteral("record")).toString());
        return true;
    }
    if (op == QStringLiteral("clipboard.pinned.list")) {
        runClipboardPinnedList(socket, request);
        return true;
    }
    if (op == QStringLiteral("clipboard.pinned.add")) {
        runClipboardPinnedAdd(socket, request,
                              clipboardPayload.value(QStringLiteral("record")).toString(),
                              clipboardPayload.value(QStringLiteral("preview")).toString());
        return true;
    }
    if (op == QStringLiteral("clipboard.pinned.remove")) {
        runClipboardPinnedRemove(socket, request,
                                 clipboardPayload.value(QStringLiteral("pinId")).toString());
        return true;
    }
    if (op == QStringLiteral("clipboard.pinned.copy")) {
        runClipboardPinnedCopy(socket, request,
                               clipboardPayload.value(QStringLiteral("pinId")).toString());
        return true;
    }
    return false;
}

bool PlatformServer::handleApplication(QLocalSocket *socket,
                                       const QJsonObject &request)
{
    if (operation(request) != QStringLiteral("application.launch"))
        return false;

    const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();
    const QString desktopId = payload.value(QStringLiteral("desktopId")).toString().trimmed();
    if (desktopId.isEmpty() || desktopId.contains(QChar('/'))
        || desktopId.contains(QChar('\\')) || desktopId.size() > 255) {
        respond(socket, request, false, {}, QStringLiteral("invalid-desktop-id"),
                QStringLiteral("应用标识无效"), false);
        return true;
    }

    const KService::Ptr service = KService::serviceByStorageId(desktopId);
    if (!service || !service->isApplication()) {
        respond(socket, request, false, {}, QStringLiteral("application-not-found"),
                QStringLiteral("应用启动器不存在"), false);
        return true;
    }

    QList<QUrl> urls;
    const QJsonValue urlsValue = payload.value(QStringLiteral("urls"));
    if (!urlsValue.isUndefined() && !urlsValue.isArray()) {
        respond(socket, request, false, {}, QStringLiteral("invalid-urls"),
                QStringLiteral("应用 URL 参数无效"), false);
        return true;
    }
    const QJsonArray urlArray = urlsValue.toArray();
    if (urlArray.size() > 64) {
        respond(socket, request, false, {}, QStringLiteral("too-many-urls"),
                QStringLiteral("应用 URL 参数过多"), false);
        return true;
    }
    for (const QJsonValue &value : urlArray) {
        if (!value.isString()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-urls"),
                    QStringLiteral("应用 URL 参数无效"), false);
            return true;
        }
        const QUrl url = QUrl::fromUserInput(value.toString());
        if (!url.isValid()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-urls"),
                    QStringLiteral("应用 URL 参数无效"), false);
            return true;
        }
        urls.append(url);
    }

    auto *job = new KIO::ApplicationLauncherJob(service, this);
    job->setUrls(urls);
    const QPointer<QLocalSocket> guardedSocket(socket);
    connect(job, &KJob::result, this,
            [this, guardedSocket, request, job]() {
        if (job->error() != 0) {
            respond(guardedSocket.data(), request, false, {},
                    QStringLiteral("application-launch-failed"),
                    job->errorText().isEmpty() ? QStringLiteral("应用启动失败")
                                               : job->errorText(),
                    true);
            return;
        }
        QJsonArray pids;
        for (const qint64 pid : job->pids())
            pids.append(pid);
        respond(guardedSocket.data(), request, true,
                QJsonObject{{QStringLiteral("started"), true},
                            {QStringLiteral("pids"), pids}});
    });
    job->start();
    return true;
}

bool PlatformServer::handleFileOperation(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();
    if (op == QStringLiteral("file.open")) {
        const QString path = cleanPath(payload.value(QStringLiteral("path")).toString());
        if (path.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"), QStringLiteral("文件路径无效"), false);
            return true;
        }
        // xdg-open hands the request to a GUI helper whose lifetime is not
        // this request's business; no watchdog.
        runCommand(socket, request, QStringLiteral("xdg-open"), {path}, {}, 0);
        return true;
    }
    if (op == QStringLiteral("file.copy")) {
        const QString source = cleanPath(payload.value(QStringLiteral("source")).toString());
        const QString destination = cleanCreatePath(payload.value(QStringLiteral("destination")).toString());
        if (source.isEmpty() || destination.isEmpty() || !QFileInfo(source).isFile()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"),
                    QStringLiteral("文件路径无效"), false);
            return true;
        }
        if (!QDir().mkpath(QFileInfo(destination).path())) {
            respond(socket, request, false, {}, QStringLiteral("copy-failed"),
                    QStringLiteral("无法创建目标目录"), true);
            return true;
        }
        // QSaveFile truncates destination on open, so copying a file onto
        // itself would erase the source before the first read. Canonical
        // paths resolve symlinks; when one side has no canonical form (the
        // destination usually does not exist yet) fall back to absolutes.
        const QFileInfo sourceInfo(source);
        const QFileInfo destinationInfo(destination);
        const QString sourceCanonical = sourceInfo.canonicalFilePath();
        const QString destinationCanonical = destinationInfo.canonicalFilePath();
        const bool sameFile = !sourceCanonical.isEmpty() && !destinationCanonical.isEmpty()
            ? sourceCanonical == destinationCanonical
            : sourceInfo.absoluteFilePath() == destinationInfo.absoluteFilePath();
        if (sameFile) {
            respond(socket, request, false, {}, QStringLiteral("copy-failed"),
                    QStringLiteral("无法复制文件"), true);
            return true;
        }
        // The copy itself runs on m_copyPool: a multi-GB transfer would
        // otherwise block every socket client, KWin broadcast and D-Bus
        // signal on this event loop for its whole duration.
        auto *watcher = new QFutureWatcher<CopyResult>(this);
        const QPointer<QLocalSocket> guardedSocket(socket);
        connect(watcher, &QFutureWatcher<CopyResult>::finished, this,
                [this, watcher, guardedSocket, request, destination]() {
            watcher->deleteLater();
            if (watcher->result().error.isEmpty()) {
                respond(guardedSocket.data(), request, true,
                        QJsonObject{{QStringLiteral("path"), destination}});
            } else {
                respond(guardedSocket.data(), request, false, {},
                        QStringLiteral("copy-failed"),
                        QStringLiteral("无法复制文件"), true);
            }
        });
        watcher->setFuture(QtConcurrent::run(&m_copyPool, copyFileChunked,
                                             source, destination));
        return true;
    }
    if (op == QStringLiteral("file.launch")) {
        // "打开" on a desktop launcher sends desktopFile (an absolute path),
        // "打开方式" only knows the installed storage id.
        const QString requested = payload.value(QStringLiteral("desktopFile")).toString();
        const QString desktop = resolveDesktopFile(requested.isEmpty()
            ? payload.value(QStringLiteral("desktopId")).toString() : requested);
        const QString target = cleanPath(payload.value(QStringLiteral("path")).toString());
        if (desktop.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-desktop-file"),
                    QStringLiteral("启动器不存在"), false);
            return true;
        }
        if (target.isEmpty() && payload.contains(QStringLiteral("path"))) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"), QStringLiteral("文件路径无效"), false);
            return true;
        }
        QStringList args{QStringLiteral("launch"), desktop};
        if (!target.isEmpty())
            args.append(target);
        runCommand(socket, request, QStringLiteral("gio"), args, {}, 30000);
        return true;
    }
    if (op == QStringLiteral("file.trash")) {
        const QStringList paths = cleanPaths(payload.value(QStringLiteral("paths")));
        if (paths.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"), QStringLiteral("文件路径无效"), false);
            return true;
        }
        runCommand(socket, request, QStringLiteral("gio"), QStringList{QStringLiteral("trash")} + paths, {}, 30000);
        return true;
    }
    if (op == QStringLiteral("file.trash-state")) {
        const QString root = freedesktopTrashRoot();
        if (root.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("trash-unavailable"),
                    QStringLiteral("回收站路径不可用"), false);
            return true;
        }
        const QFileInfo files(root + QStringLiteral("/files"));
        bool hasItems = false;
        if (files.exists() && files.isDir() && !files.isSymLink()) {
            QDirIterator iterator(files.absoluteFilePath(),
                                   QDir::NoDotAndDotDot | QDir::AllEntries
                                       | QDir::Hidden | QDir::System);
            hasItems = iterator.hasNext();
        }
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("hasItems"), hasItems}});
        return true;
    }
    if (op == QStringLiteral("file.empty-trash")) {
        const QString root = freedesktopTrashRoot();
        if (root.isEmpty() || !emptyTrashDirectory(root + QStringLiteral("/files"))
            || !emptyTrashDirectory(root + QStringLiteral("/info"))) {
            respond(socket, request, false, {}, QStringLiteral("trash-empty-failed"),
                    QStringLiteral("无法清空回收站"), true);
            return true;
        }
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("emptied"), true}});
        return true;
    }
    if (op == QStringLiteral("file.open-trash")) {
        const QString dolphin = QStandardPaths::findExecutable(QStringLiteral("dolphin"));
        if (dolphin.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("trash-unavailable"),
                    QStringLiteral("Dolphin 不可用"), false);
            return true;
        }
        // Dolphin is a long-lived GUI process; killing it on a watchdog
        // would close the file manager window the user just opened.
        runCommand(socket, request, dolphin, {QStringLiteral("trash:")}, {}, 0);
        return true;
    }
    if (op == QStringLiteral("file.rename")) {
        const QString source = cleanPath(payload.value(QStringLiteral("source")).toString());
        const QString target = cleanPath(payload.value(QStringLiteral("target")).toString());
        if (source.isEmpty() || target.isEmpty() || QFileInfo::exists(target)) {
            respond(socket, request, false, {}, QStringLiteral("target-exists"), QStringLiteral("目标文件已存在或路径无效"), false);
            return true;
        }
        if (QFile::rename(source, target))
            respond(socket, request, true, QJsonObject{{QStringLiteral("path"), target}});
        else
            respond(socket, request, false, {}, QStringLiteral("rename-failed"), QStringLiteral("重命名失败"), true);
        return true;
    }
    if (op == QStringLiteral("file.create-folder") || op == QStringLiteral("file.create-file")) {
        const QString directory = cleanPath(payload.value(QStringLiteral("directory")).toString());
        if (directory.isEmpty() || !QFileInfo(directory).isDir()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"), QStringLiteral("文件路径无效"), false);
            return true;
        }
        const QString baseName = op.endsWith(QStringLiteral("folder"))
            ? QStringLiteral("untitled folder") : QStringLiteral("untitled file.txt");
        QString path = uniquePath(directory, baseName);
        const bool ok = path.isEmpty() ? false
            : (op.endsWith(QStringLiteral("folder")) ? QDir().mkpath(path)
               : [&path] { QFile file(path); return file.open(QIODevice::WriteOnly); }());
        if (ok)
            respond(socket, request, true, QJsonObject{{QStringLiteral("path"), path}});
        else
            respond(socket, request, false, {}, QStringLiteral("create-failed"), QStringLiteral("创建失败"), true);
        return true;
    }
    if (op == QStringLiteral("file.transfer")) {
        const QString destination = cleanPath(payload.value(QStringLiteral("destination")).toString());
        const QString mode = payload.value(QStringLiteral("mode")).toString();
        const bool move = mode == QStringLiteral("move");
        const QStringList paths = cleanPaths(payload.value(QStringLiteral("paths")));
        if (destination.isEmpty() || paths.isEmpty()
            || (mode != QStringLiteral("copy") && !move)) {
            respond(socket, request, false, {}, QStringLiteral("invalid-transfer"),
                    QStringLiteral("文件传输请求无效"), false);
            return true;
        }
        if (!QFileInfo(destination).isDir() && !QDir().mkpath(destination)) {
            respond(socket, request, false, {}, QStringLiteral("invalid-destination"),
                    QStringLiteral("目标文件夹无效"), false);
            return true;
        }
        QStringList transferred;
        for (const QString &source : paths) {
            const QString target = uniquePath(destination, QFileInfo(source).fileName());
            if (target.isEmpty() || target == source || !moveOrCopy(source, target, move)) {
                respond(socket, request, false, {}, QStringLiteral("transfer-failed"),
                        QStringLiteral("文件传输未完成"), true);
                return true;
            }
            transferred.append(target);
        }
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("paths"), jsonPaths(transferred)},
                            {QStringLiteral("mode"), mode}});
        return true;
    }
    if (op == QStringLiteral("file.open-with")) {
        const QString path = cleanPath(payload.value(QStringLiteral("path")).toString());
        if (path.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"), QStringLiteral("文件路径无效"), false);
            return true;
        }
        const QString requestedMime = payload.value(QStringLiteral("mime")).toString().trimmed();
        const QPointer<QLocalSocket> guardedSocket(socket);
        auto finish = [this, guardedSocket, request, path](const QString &mime) {
            if (mime.isEmpty()) {
                respond(guardedSocket.data(), request, false, {}, QStringLiteral("mime-unavailable"),
                        QStringLiteral("无法确定文件类型"), false);
                return;
            }
            auto *process = new QProcess(this);
            process->setProgram(QStringLiteral("gio"));
            process->setArguments({QStringLiteral("mime"), mime});
            armProcessWatchdog(process, 10000);
            connect(process, &QProcess::errorOccurred, this,
                    [this, guardedSocket, request, process](QProcess::ProcessError) {
                QObject::disconnect(process, &QProcess::finished, this, nullptr);
                respond(guardedSocket.data(), request, false, {}, QStringLiteral("open-with-failed"),
                        QStringLiteral("无法读取打开方式"), true);
                process->deleteLater();
            });
            connect(process, &QProcess::finished, this,
                    [this, guardedSocket, request, process, mime, path](int exitCode, QProcess::ExitStatus) {
                const QString output = QString::fromUtf8(process->readAllStandardOutput());
                if (exitCode != 0) {
                    respond(guardedSocket.data(), request, false, {}, QStringLiteral("open-with-failed"),
                            QStringLiteral("无法读取打开方式"), true);
                    process->deleteLater();
                    return;
                }
                QString defaultId;
                QStringList handlers;
                const QStringList lines = output.split(QRegularExpression(QStringLiteral("\\r?\\n")));
                for (const QString &line : lines) {
                    const QString trimmed = line.trimmed();
                    const QRegularExpressionMatch defaultMatch =
                        QRegularExpression(QStringLiteral("^Default application.*:\\s*(\\S+)$"))
                            .match(trimmed);
                    if (defaultMatch.hasMatch())
                        defaultId = defaultMatch.captured(1);
                    const QRegularExpressionMatch idMatch =
                        QRegularExpression(QStringLiteral("^(\\S+\\.desktop)$")).match(trimmed);
                    if (idMatch.hasMatch() && !handlers.contains(idMatch.captured(1)))
                        handlers.append(idMatch.captured(1));
                }
                if (!defaultId.isEmpty() && !handlers.contains(defaultId))
                    handlers.prepend(defaultId);
                respond(guardedSocket.data(), request, true,
                        QJsonObject{{QStringLiteral("path"), path},
                                    {QStringLiteral("mime"), mime},
                                    {QStringLiteral("defaultId"), defaultId},
                                    {QStringLiteral("handlers"), QJsonArray::fromStringList(handlers)}});
                process->deleteLater();
            });
            process->start();
        };
        if (!requestedMime.isEmpty()) {
            finish(requestedMime);
            return true;
        }
        auto *info = new QProcess(this);
        info->setProgram(QStringLiteral("gio"));
        info->setArguments({QStringLiteral("info"), QStringLiteral("-a"),
                            QStringLiteral("standard::content-type"), path});
        armProcessWatchdog(info, 10000);
        connect(info, &QProcess::errorOccurred, this,
                [this, info, finish](QProcess::ProcessError) {
            QObject::disconnect(info, &QProcess::finished, this, nullptr);
            finish(QString());
            info->deleteLater();
        });
        connect(info, &QProcess::finished, this,
                [info, finish](int exitCode, QProcess::ExitStatus) {
            const QString output = QString::fromUtf8(info->readAllStandardOutput());
            QString mime;
            if (exitCode == 0) {
                const QRegularExpressionMatch match =
                    QRegularExpression(QStringLiteral("standard::content-type:\\s*(\\S+)"))
                        .match(output);
                if (match.hasMatch())
                    mime = match.captured(1);
            }
            finish(mime);
            info->deleteLater();
        });
        info->start();
        return true;
    }
    if (op == QStringLiteral("file.set-default")) {
        const QString mime = payload.value(QStringLiteral("mime")).toString().trimmed();
        const QString desktopId = payload.value(QStringLiteral("desktopId")).toString().trimmed();
        if (mime.isEmpty() || desktopId.isEmpty() || desktopId.contains(QChar('/'))
            || !desktopId.endsWith(QStringLiteral(".desktop"))) {
            respond(socket, request, false, {}, QStringLiteral("invalid-handler"),
                    QStringLiteral("默认应用无效"), false);
            return true;
        }
        runCommand(socket, request, QStringLiteral("gio"),
                   {QStringLiteral("mime"), mime, desktopId}, {}, 15000);
        return true;
    }
    if (op == QStringLiteral("file.open-kde")) {
        const QString path = cleanPath(payload.value(QStringLiteral("path")).toString());
        if (path.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-path"),
                    QStringLiteral("文件路径无效"), false);
            return true;
        }
        QDBusInterface portal(QStringLiteral("org.freedesktop.impl.portal.desktop.kde"),
                              QStringLiteral("/org/freedesktop/portal/desktop"),
                              QStringLiteral("org.freedesktop.portal.AppChooser"),
                              QDBusConnection::sessionBus());
        portal.setTimeout(kDbusCallTimeoutMs);
        if (!portal.isValid()) {
            respond(socket, request, false, {}, QStringLiteral("open-with-unavailable"),
                    QStringLiteral("KDE 打开方式面板不可用"), false);
            return true;
        }
        const QString mime = QMimeDatabase().mimeTypeForFile(
            path, QMimeDatabase::MatchExtension).name();
        QVariantMap options;
        options.insert(QStringLiteral("content_type"), mime);
        options.insert(QStringLiteral("uri"), QUrl::fromLocalFile(path).toString());
        options.insert(QStringLiteral("filename"), QFileInfo(path).fileName());
        options.insert(QStringLiteral("modal"), true);
        QString token = requestId(request);
        token.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9_]")),
                      QStringLiteral("_"));
        if (token.isEmpty())
            token = QStringLiteral("request");
        const QDBusPendingCall pending = portal.asyncCall(
            QStringLiteral("ChooseApplication"),
            QVariant::fromValue(QDBusObjectPath(
                QStringLiteral("/org/freedesktop/portal/desktop/request/kos_open_with_")
                    + token)),
            QString(), QString(), QStringList(), options);
        auto *watcher = new QDBusPendingCallWatcher(pending, this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this,
                [this, guardedSocket = QPointer<QLocalSocket>(socket),
                 request, path, watcher] {
            const QDBusMessage reply = watcher->reply();
            watcher->deleteLater();
            if (reply.type() == QDBusMessage::ErrorMessage
                || reply.arguments().size() < 2
                || reply.arguments().at(0).toUInt() != 0) {
                respond(guardedSocket.data(), request, false, {}, QStringLiteral("open-with-failed"),
                        QStringLiteral("KDE 打开方式面板调用失败"), true);
                return;
            }
            const QString applicationId = reply.arguments().at(1).toMap()
                                              .value(QStringLiteral("choice")).toString();
            if (applicationId.isEmpty()) {
                respond(guardedSocket.data(), request, true,
                        QJsonObject{{QStringLiteral("cancelled"), true}});
                return;
            }
            const QString desktop = resolveDesktopFile(applicationId);
            if (desktop.isEmpty()
                || !QProcess::startDetached(QStringLiteral("gio"),
                                            {QStringLiteral("launch"), desktop, path})) {
                respond(guardedSocket.data(), request, false, {}, QStringLiteral("open-with-failed"),
                        QStringLiteral("无法启动选中的应用"), true);
                return;
            }
            respond(guardedSocket.data(), request, true,
                    QJsonObject{{QStringLiteral("desktopId"), applicationId}});
        });
        return true;
    }
    return false;
}

bool PlatformServer::handleKWin(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    if (op == QStringLiteral("kwin.subscribe")) {
        m_windowSubscribers.insert(socket);
        respond(socket, request, true, QJsonObject{{QStringLiteral("subscribed"), true}});
        // A subscriber commonly appears after a Shell reload. KWin emits
        // snapshots only on state changes, so replay the cached authoritative
        // state now instead of leaving the Dock empty until the next change.
        if (!m_latestWindowSnapshot.isEmpty())
            sendEvent(socket, m_latestWindowSnapshot);
        if (!m_latestDesktopSnapshot.isEmpty())
            sendEvent(socket, m_latestDesktopSnapshot);
        return true;
    }
    if (op == QStringLiteral("kwin.layout.update")) {
        const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();
        if (!validLayoutPayload(payload)) {
            respond(socket, request, false, {}, QStringLiteral("invalid-payload"),
                    QStringLiteral("窗口布局参数无效"), false);
            return true;
        }
        QJsonObject command = payload;
        command.insert(QStringLiteral("action"), QStringLiteral("update-layout"));
        if (!enqueueKWinCommand(command)) {
            respond(socket, request, false, {}, QStringLiteral("kwin-unavailable"),
                    QStringLiteral("KWin 平台桥不可用"), true);
            return true;
        }
        respond(socket, request, true);
        return true;
    }
    if (op == QStringLiteral("kwin.command")) {
        if (!enqueueKWinCommand(request.value(QStringLiteral("payload")).toObject())) {
            respond(socket, request, false, {}, QStringLiteral("kwin-unavailable"),
                    QStringLiteral("KWin 平台桥不可用"), true);
            return true;
        }
        respond(socket, request, true);
        return true;
    }
    if (op == QStringLiteral("kwin.animation.update-targets")
        || op == QStringLiteral("kwin.animation.prepare-launch")) {
        const QString payload = request.value(QStringLiteral("payload")).toObject()
                                     .value(QStringLiteral("payload")).toString();
        if (payload.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-payload"),
                    QStringLiteral("动画参数无效"), false);
            return true;
        }
        QDBusInterface effect(QStringLiteral("org.kde.KWin"),
                              QStringLiteral("/KOSDockWindowAnimation"),
                              QStringLiteral("org.kos.KWin.DockWindowAnimation"));
        effect.setTimeout(kDbusCallTimeoutMs);
        if (!effect.isValid()) {
            respond(socket, request, false, {}, QStringLiteral("kwin-effect-unavailable"),
                    QStringLiteral("Dock 窗口动画特效不可用"), true);
            return true;
        }
        const QString method = op.endsWith(QStringLiteral("update-targets"))
            ? QStringLiteral("updateTargets") : QStringLiteral("prepareLaunch");
        const QDBusMessage reply = effect.call(method, payload);
        if (reply.type() == QDBusMessage::ErrorMessage) {
            respond(socket, request, false, {}, QStringLiteral("kwin-effect-failed"),
                    QStringLiteral("Dock 窗口动画特效调用失败"), true);
            return true;
        }
        respond(socket, request, true, QJsonObject{{QStringLiteral("accepted"), true}});
        return true;
    }
    return false;
}

bool PlatformServer::handleAppMenu(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    if (!op.startsWith(QStringLiteral("appmenu.")))
        return false;

    if (op == QStringLiteral("appmenu.active")) {
        QDBusInterface bridge(QStringLiteral("org.kde.KWin"),
                              QStringLiteral("/KOSContextMenuInput"),
                              QStringLiteral("org.kos.KWin.ContextMenuInput"));
        bridge.setTimeout(kDbusCallTimeoutMs);
        if (!bridge.isValid()) {
            respond(socket, request, false, {}, QStringLiteral("appmenu-bridge-unavailable"),
                    QStringLiteral("全局菜单桥接尚未加载"), true);
            return true;
        }
        // Async: a wedged KWin bridge must not stall every other socket
        // client; the pending call is still bounded by the interface timeout.
        const QDBusPendingCall pending = bridge.asyncCall(
            QStringLiteral("activeApplicationMenu"));
        auto *watcher = new QDBusPendingCallWatcher(pending, this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this,
                [this, guardedSocket = QPointer<QLocalSocket>(socket),
                 request, watcher] {
            const QDBusMessage reply = watcher->reply();
            watcher->deleteLater();
            if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().isEmpty()) {
                respond(guardedSocket.data(), request, false, {}, QStringLiteral("appmenu-bridge-failed"),
                        QStringLiteral("无法读取活动窗口菜单"), true);
                return;
            }
            const QVariantMap address = variantMapFromDbusValue(reply.arguments().first());
            respond(guardedSocket.data(), request, true,
                    QJsonObject{{QStringLiteral("available"),
                                 address.value(QStringLiteral("available")).toBool()},
                                {QStringLiteral("service"),
                                 address.value(QStringLiteral("service")).toString()},
                                {QStringLiteral("path"),
                                 address.value(QStringLiteral("path")).toString()}});
        });
        return true;
    }

    const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();
    const QString service = payload.value(QStringLiteral("service")).toString();
    const QString path = payload.value(QStringLiteral("path")).toString();
    if (!validAppMenuAddress(service, path)) {
        respond(socket, request, false, {}, QStringLiteral("invalid-appmenu-address"),
                QStringLiteral("应用菜单地址无效"), false);
        return true;
    }

    QDBusInterface menu(service, path, QStringLiteral("com.canonical.dbusmenu"));
    // Third-party apps own this dbusmenu service and can hang; bound every
    // call on it.
    menu.setTimeout(kDbusCallTimeoutMs);
    if (!menu.isValid()) {
        respond(socket, request, false, {}, QStringLiteral("appmenu-unavailable"),
                QStringLiteral("应用未提供全局菜单"), true);
        return true;
    }
    const int id = payload.value(QStringLiteral("id")).toInt();
    if (op == QStringLiteral("appmenu.layout")) {
        // The root needs one additional level so top-level labels such as
        // File and Edit are identified as submenus rather than actions.
        const int depth = qBound(1, payload.value(QStringLiteral("depth")).toInt(1), 5);
        // A hung third-party app must not stall the daemon's event loop, so
        // the layout read stays async; the interface timeout still bounds
        // the pending call.
        const QDBusPendingCall pending = menu.asyncCall(
            QStringLiteral("GetLayout"), id, depth,
            QStringList{QStringLiteral("label"), QStringLiteral("visible"),
                        QStringLiteral("enabled"), QStringLiteral("type"),
                        QStringLiteral("children-display"), QStringLiteral("toggle-type"),
                        QStringLiteral("toggle-state"), QStringLiteral("icon-name")});
        auto *watcher = new QDBusPendingCallWatcher(pending, this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this,
                [this, guardedSocket = QPointer<QLocalSocket>(socket),
                 request, watcher] {
            const QDBusMessage reply = watcher->reply();
            watcher->deleteLater();
            if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().size() < 2) {
                respond(guardedSocket.data(), request, false, {}, QStringLiteral("appmenu-layout-failed"),
                        QStringLiteral("无法读取应用菜单"), true);
                return;
            }
            const QDBusArgument root = qvariant_cast<QDBusArgument>(reply.arguments().at(1));
            const QJsonObject parent = menuItemFromArgument(root);
            const QJsonArray items = parent.value(QStringLiteral("children")).toArray();
            respond(guardedSocket.data(), request, true,
                    QJsonObject{{QStringLiteral("parent"), parent},
                                {QStringLiteral("items"), items}});
        });
        return true;
    }
    if (op == QStringLiteral("appmenu.open") || op == QStringLiteral("appmenu.close")
        || op == QStringLiteral("appmenu.trigger")) {
        const QString event = op == QStringLiteral("appmenu.open") ? QStringLiteral("opened")
            : op == QStringLiteral("appmenu.close") ? QStringLiteral("closed")
            : QStringLiteral("clicked");
        const quint32 timestamp = static_cast<quint32>(QDateTime::currentMSecsSinceEpoch());

        if (op == QStringLiteral("appmenu.open")) {
            // Give Qt / KDE applications an opportunity to populate lazy dynamic submenus.
            menu.call(QStringLiteral("AboutToShow"), id);
        }

        // com.canonical.dbusmenu Event signature is (isvu): the data argument
        // MUST be typed as a D-Bus variant. Sending a bare QVariantMap produces
        // (isa{sv}u), which Qt's QDBusMenuAdaptor rejects as an unknown method.
        const QDBusVariant dbusData(QVariantMap{{QStringLiteral("timestamp"), timestamp}});
        const QDBusMessage reply = menu.call(QStringLiteral("Event"), id, event,
            QVariant::fromValue(dbusData), timestamp);
        if (reply.type() == QDBusMessage::ErrorMessage) {
            respond(socket, request, false, {}, QStringLiteral("appmenu-event-failed"),
                    QStringLiteral("应用菜单操作失败"), true);
            return true;
        }
        respond(socket, request, true);
        return true;
    }
    respond(socket, request, false, {}, QStringLiteral("unknown-appmenu-operation"),
            QStringLiteral("未知的应用菜单操作"), false);
    return true;
}

bool PlatformServer::handleInput(QLocalSocket *socket, const QJsonObject &request)
{
    if (operation(request) != QStringLiteral("input.paste"))
        return false;

    // Only a compositor-side effect may synthesise a key without uinput
    // privileges, so the chord is delegated to the KWin effect that already
    // owns this session-bus endpoint. Keeping it here means the Shell never has
    // to ship a separate injection helper.
    QDBusInterface effect(QStringLiteral("org.kde.KWin"),
                          QStringLiteral("/KOSContextMenuInput"),
                          QStringLiteral("org.kos.KWin.ContextMenuInput"));
    effect.setTimeout(kDbusCallTimeoutMs);
    if (!effect.isValid()) {
        respond(socket, request, false, {}, QStringLiteral("input-bridge-unavailable"),
                QStringLiteral("按键注入桥接尚未加载"), true);
        return true;
    }

    const QDBusMessage reply = effect.call(QStringLiteral("paste"));
    if (reply.type() == QDBusMessage::ErrorMessage) {
        respond(socket, request, false, {}, QStringLiteral("input-injection-failed"),
                QStringLiteral("无法注入粘贴按键"), true);
        return true;
    }

    respond(socket, request, true, QJsonObject{{QStringLiteral("injected"), true}});
    return true;
}

bool PlatformServer::handleSystemOperation(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();
    if (op == QStringLiteral("settings.open")) {
        QString module = payload.value(QStringLiteral("module")).toString();
        if (module == QStringLiteral("kcm_nightcolor")) {
            module = QStringLiteral("kcm_nightlight");
        }
        static const QSet<QString> allowedModules{
            QStringLiteral("kcm_bluetooth"),
            QStringLiteral("kcm_keys"),
            QStringLiteral("kcm_networkmanagement"),
            QStringLiteral("kcm_kscreen"),
            QStringLiteral("kcm_pulseaudio"),
            QStringLiteral("kcm_nightlight"),
            QStringLiteral("kcm_notifications"),
            QStringLiteral("kcm_soundtheme")};
        if (!allowedModules.contains(module)) {
            respond(socket, request, false, {}, QStringLiteral("invalid-settings-module"),
                    QStringLiteral("设置模块不受支持"), false);
            return true;
        }
        const QString kcmshell = QStandardPaths::findExecutable(QStringLiteral("kcmshell6"));
        const QString systemsettings = QStandardPaths::findExecutable(QStringLiteral("systemsettings"));
        const QString executable = !kcmshell.isEmpty() ? kcmshell : systemsettings;
        if (executable.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("settings-unavailable"),
                    QStringLiteral("KDE 系统设置不可用"), false);
            return true;
        }
        const bool started = QProcess::startDetached(executable, {module});
        respond(socket, request, started, {{QStringLiteral("started"), started}});
        return true;
    }
    if (op == QStringLiteral("settings.launch")) {
        // Fixed argv on purpose: the op exists so the Shell never has to spawn
        // a shell just to resolve kos-settings on PATH, and no caller-supplied
        // argument can turn it into arbitrary command execution.
        //
        // The only tunable is the environment: Settings talks back to its
        // Shell over Quickshell IPC, so a development Shell passes its
        // Quickshell.shellDir through `shellDir` and the child reconnects to
        // that same session instead of the installed `kos` configuration.
        // The value must canonicalise to an existing directory; it is data in
        // KOS_SHELL_DIR, never part of the argv.
        QString shellDir;
        const QJsonValue shellDirValue = payload.value(QStringLiteral("shellDir"));
        if (!shellDirValue.isUndefined()) {
            const QString raw = shellDirValue.toString();
            if (raw.isEmpty() || raw.size() > 1024 || raw.contains(QChar('\0'))) {
                respond(socket, request, false, {}, QStringLiteral("invalid-shell-dir"),
                        QStringLiteral("Shell 目录无效"), false);
                return true;
            }
            const QFileInfo info(raw);
            if (!info.isAbsolute()) {
                respond(socket, request, false, {}, QStringLiteral("invalid-shell-dir"),
                        QStringLiteral("Shell 目录无效"), false);
                return true;
            }
            const QString canonical = info.canonicalFilePath();
            if (canonical.isEmpty() || !QFileInfo(canonical).isDir()) {
                respond(socket, request, false, {}, QStringLiteral("invalid-shell-dir"),
                        QStringLiteral("Shell 目录无效"), false);
                return true;
            }
            shellDir = canonical;
        }
        const QString executable = QStandardPaths::findExecutable(
            QStringLiteral("kos-settings"));
        if (executable.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("settings-unavailable"),
                    QStringLiteral("KOS 设置应用不可用"), true);
            return true;
        }
        QProcess process;
        process.setProgram(executable);
        if (!shellDir.isEmpty()) {
            QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
            environment.insert(QStringLiteral("KOS_SHELL_DIR"), shellDir);
            process.setProcessEnvironment(environment);
        }
        const bool started = process.startDetached();
        respond(socket, request, started, {{QStringLiteral("started"), started}});
        return true;
    }
    if (op == QStringLiteral("notify")) {
        // Bounded freedesktop notification. The daemon prefers the session
        // D-Bus interface (owned by the Shell's own NotificationServer or
        // Plasma) and falls back to a fixed-argv notify-send spawn; either way
        // the payload is validated data, never a command line.
        const QString summary = payload.value(QStringLiteral("summary")).toString();
        const QString body = payload.value(QStringLiteral("body")).toString();
        const QString icon = payload.value(QStringLiteral("icon")).toString();
        // appName is cosmetic (notification grouping / banner header); an
        // empty or oversized value silently falls back to the daemon's name
        // instead of rejecting the whole notification.
        const QString appName = [] (const QString &raw) {
            return (!raw.isEmpty() && raw.size() <= 128
                    && !raw.contains(QChar('\0')))
                ? raw : QStringLiteral("KOS Shell");
        }(payload.value(QStringLiteral("appName")).toString());
        const QString urgencyName = payload.value(QStringLiteral("urgency"))
            .toString(QStringLiteral("normal"));
        uchar urgency = 1;
        if (urgencyName == QStringLiteral("low"))
            urgency = 0;
        else if (urgencyName == QStringLiteral("critical"))
            urgency = 2;
        else if (urgencyName != QStringLiteral("normal")) {
            respond(socket, request, false, {}, QStringLiteral("invalid-notification"),
                    QStringLiteral("通知 urgency 无效"), false);
            return true;
        }
        if (summary.isEmpty() || summary.size() > 256 || body.size() > 1024
            || icon.size() > 255
            || summary.contains(QChar('\0')) || body.contains(QChar('\0'))
            || icon.contains(QChar('\0'))) {
            respond(socket, request, false, {}, QStringLiteral("invalid-notification"),
                    QStringLiteral("通知内容无效或超过长度上限"), false);
            return true;
        }
        if (dbusServiceRegistered(QDBusConnection::sessionBus(),
                                  QStringLiteral("org.freedesktop.Notifications"))) {
            QDBusMessage call = QDBusMessage::createMethodCall(
                QStringLiteral("org.freedesktop.Notifications"),
                QStringLiteral("/org/freedesktop/Notifications"),
                QStringLiteral("org.freedesktop.Notifications"),
                QStringLiteral("Notify"));
            const QVariantMap hints{
                {QStringLiteral("urgency"), QVariant::fromValue<uchar>(urgency)}};
            call.setArguments({appName, 0U, icon, summary, body,
                               QStringList{}, hints, 5000});
            // Fire-and-forget: the notification UI owns delivery, and a slow
            // or absent implementation must not hold the socket reply.
            QDBusConnection::sessionBus().asyncCall(call, kDbusCallTimeoutMs);
            respond(socket, request, true, QJsonObject{{QStringLiteral("delivered"), true}});
            return true;
        }
        const QString notifySend = QStandardPaths::findExecutable(
            QStringLiteral("notify-send"));
        if (notifySend.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("notify-unavailable"),
                    QStringLiteral("没有可用的通知服务"), true);
            return true;
        }
        QStringList args{QStringLiteral("-a"), appName};
        if (!icon.isEmpty())
            args << QStringLiteral("-i") << icon;
        args << QStringLiteral("-u") << urgencyName
             << QStringLiteral("-t") << QStringLiteral("5000")
             // A summary starting with '-' would otherwise be parsed as a
             // GOption flag; "--" terminates option parsing.
             << QStringLiteral("--") << summary << body;
        const bool started = QProcess::startDetached(notifySend, args);
        respond(socket, request, started,
                QJsonObject{{QStringLiteral("delivered"), started}});
        return true;
    }
    if (op == QStringLiteral("nightlight.get")) {
        const QString key = QStringLiteral("nightlight.get");
        if (serveCachedReply(socket, request, key))
            return true;
        watchNightLight();
        QDBusInterface nightLight(QStringLiteral("org.kde.KWin"),
                                  QStringLiteral("/org/kde/KWin/NightLight"),
                                  QStringLiteral("org.kde.KWin.NightLight"),
                                  QDBusConnection::sessionBus());
        nightLight.setTimeout(kDbusCallTimeoutMs);
        if (!nightLight.isValid()) {
            const QString code = QStringLiteral("nightlight-unavailable");
            const QString message = QStringLiteral("夜灯服务不可用");
            respond(socket, request, false, {}, code, message, true);
            storeReply(key, kNightLightCacheTtlMs, false, {}, code, message, true);
            return true;
        }
        const bool available = nightLight.property("available").toBool();
        const bool runtimeEnabled = nightLight.property("enabled").toBool();
        const QString configPath = QStandardPaths::writableLocation(
            QStandardPaths::ConfigLocation) + QStringLiteral("/kwinrc");
        QSettings settings(configPath, QSettings::IniFormat);
        const bool enabled = settings.value(
            QStringLiteral("NightColor/Active"), runtimeEnabled).toBool();
        if (!enabled && runtimeEnabled && !m_nightLightInhibitionCookie.has_value()) {
            const QDBusMessage reply = nightLight.call(QStringLiteral("inhibit"));
            if (reply.type() != QDBusMessage::ErrorMessage && !reply.arguments().isEmpty())
                m_nightLightInhibitionCookie = reply.arguments().constFirst().toUInt();
        }
        const bool running = nightLight.property("running").toBool();
        const bool inhibited = m_nightLightInhibitionCookie.has_value()
            || nightLight.property("inhibited").toBool();
        const uint mode = nightLight.property("mode").toUInt();
        const uint targetTemp = nightLight.property("targetTemperature").toUInt();
        const uint currentTemp = nightLight.property("currentTemperature").toUInt();

        const bool isWarm = enabled && running && !inhibited;

        QJsonObject result{
            {QStringLiteral("available"), available},
            {QStringLiteral("enabled"), enabled},
            {QStringLiteral("running"), isWarm},
            {QStringLiteral("inhibited"), inhibited},
            {QStringLiteral("mode"), static_cast<int>(mode)},
            {QStringLiteral("targetTemperature"), static_cast<int>(targetTemp)},
            {QStringLiteral("currentTemperature"), static_cast<int>(currentTemp)}
        };
        respond(socket, request, true, result);
        storeReply(key, kNightLightCacheTtlMs, true, result);
        return true;
    }
    if (op == QStringLiteral("nightlight.toggle")) {
        invalidateReplies(QStringLiteral("nightlight."));
        QDBusInterface nightLight(QStringLiteral("org.kde.KWin"),
                                  QStringLiteral("/org/kde/KWin/NightLight"),
                                  QStringLiteral("org.kde.KWin.NightLight"),
                                  QDBusConnection::sessionBus());
        nightLight.setTimeout(kDbusCallTimeoutMs);
        if (!nightLight.isValid()
            || !nightLight.property("available").toBool()) {
            respond(socket, request, false, {}, QStringLiteral("nightlight-unavailable"),
                    QStringLiteral("夜灯服务不可用"), true);
            return true;
        }

        const QString configPath = QStandardPaths::writableLocation(
            QStandardPaths::ConfigLocation) + QStringLiteral("/kwinrc");
        QSettings settings(configPath, QSettings::IniFormat);
        const bool currentEnabled = settings.value(
            QStringLiteral("NightColor/Active"),
            nightLight.property("enabled").toBool()).toBool();
        const bool requestedEnabled = payload.contains(QStringLiteral("enabled"))
            ? payload.value(QStringLiteral("enabled")).toBool()
            : !currentEnabled;

        // Active is KWin's persistent master switch. Change only this key so
        // the user's mode, schedule, location, and temperature remain intact.
        settings.setValue(QStringLiteral("NightColor/Active"), requestedEnabled);
        settings.sync();
        if (settings.status() != QSettings::NoError) {
            respond(socket, request, false, {}, QStringLiteral("nightlight-config-failed"),
                    QStringLiteral("无法保存夜灯开关状态"), true);
            return true;
        }

        // The config write already committed, so any failure past this point
        // is partial application, not a failed toggle: the requested state is
        // persisted and KWin will converge on it at the next reconfigure.
        // Report ok with applied:false (and a warning string) so the Shell
        // aligns its UI to the persisted state instead of rolling back to a
        // value that no longer matches kwinrc.
        bool applied = true;
        QString warning;
        if (requestedEnabled && m_nightLightInhibitionCookie.has_value()) {
            const QDBusMessage reply = nightLight.call(
                QStringLiteral("uninhibit"), *m_nightLightInhibitionCookie);
            if (reply.type() == QDBusMessage::ErrorMessage) {
                applied = false;
                warning = QStringLiteral("夜灯已启用，但未能立即恢复");
            } else {
                m_nightLightInhibitionCookie.reset();
            }
        } else if (!requestedEnabled && !m_nightLightInhibitionCookie.has_value()) {
            const QDBusMessage reply = nightLight.call(QStringLiteral("inhibit"));
            if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().isEmpty()) {
                applied = false;
                warning = QStringLiteral("夜灯已关闭，但未能立即暂停当前效果");
            } else {
                m_nightLightInhibitionCookie = reply.arguments().constFirst().toUInt();
            }
        }

        QDBusInterface kwin(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"),
                            QStringLiteral("org.kde.KWin"), QDBusConnection::sessionBus());
        kwin.setTimeout(kDbusCallTimeoutMs);
        const QDBusMessage reconfigureReply = kwin.call(QStringLiteral("reconfigure"));
        if (reconfigureReply.type() == QDBusMessage::ErrorMessage) {
            applied = false;
            warning = QStringLiteral("夜灯状态已保存，但 KWin 未能立即应用");
        }

        const bool available = nightLight.property("available").toBool();
        const bool running = nightLight.property("running").toBool();
        const bool inhibited = m_nightLightInhibitionCookie.has_value()
            || nightLight.property("inhibited").toBool();

        QJsonObject result{
            {QStringLiteral("available"), available},
            {QStringLiteral("enabled"), requestedEnabled},
            {QStringLiteral("running"), requestedEnabled && running && !inhibited},
            {QStringLiteral("inhibited"), inhibited},
            {QStringLiteral("applied"), applied}
        };
        if (!warning.isEmpty())
            result.insert(QStringLiteral("warning"), warning);
        respond(socket, request, true, result);
        return true;
    }
    if (op == QStringLiteral("shortcuts.apply")) {
        // The Shell owns shortcut semantics: it composes each Exec line to
        // match how that Shell instance was launched. The daemon registers
        // the set with KGlobalAccel and runs the Exec lines on activation.
        const QJsonArray shortcuts = payload.value(QStringLiteral("shortcuts")).toArray();
        if (shortcuts.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-shortcut-payload"),
                    QStringLiteral("快捷键请求无效"), false);
            return true;
        }
        QJsonArray normalized;
        for (const QJsonValue &value : shortcuts) {
            QJsonObject item = value.toObject();
            item.insert(QStringLiteral("combo"),
                        normalizedShortcutCombo(item.value(QStringLiteral("combo")).toString()));
            normalized.append(item);
        }
        QString error;
        if (!applyShortcutSet(normalized, &error)) {
            respond(socket, request, false, {},
                    QStringLiteral("shortcuts-apply-failed"),
                    error.isEmpty() ? QStringLiteral("无法应用快捷键") : error, false);
            return true;
        }
        QJsonArray applied;
        for (const QJsonValue &value : normalized)
            applied.append(value.toObject().value(QStringLiteral("id")).toString());
        respond(socket, request, true, QJsonObject{{QStringLiteral("applied"), applied}});
        return true;
    }
    if (op == QStringLiteral("shortcuts.uninstall")) {
        removeShortcuts();
        respond(socket, request, true, QJsonObject{{QStringLiteral("uninstalled"), true}});
        return true;
    }
    if (op == QStringLiteral("audio.get")) {
        runCommand(socket, request, QStringLiteral("wpctl"),
                   {QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@")},
                   parseAudio, kDefaultCommandTimeoutMs,
                   QStringLiteral("audio.get"), kAudioCacheTtlMs);
        return true;
    }
    if (op == QStringLiteral("audio.set-volume")) {
        const int value = qBound(0, payload.value(QStringLiteral("percent")).toInt(), 150);
        runCommand(socket, request, QStringLiteral("wpctl"),
                   {QStringLiteral("set-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@"),
                    QString::number(value / 100.0, 'f', 3)},
                   [this](const QByteArray &output, int exitCode) {
            invalidateReplies(QStringLiteral("audio."));
            return parseOutput(output, exitCode);
        }, 10000);
        return true;
    }
    if (op == QStringLiteral("audio.set-mute")) {
        runCommand(socket, request, QStringLiteral("wpctl"),
                   {QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SINK@"),
                    payload.value(QStringLiteral("muted")).toBool() ? QStringLiteral("1") : QStringLiteral("0")},
                   [this](const QByteArray &output, int exitCode) {
            invalidateReplies(QStringLiteral("audio."));
            return parseOutput(output, exitCode);
        }, 10000);
        return true;
    }
    if (op == QStringLiteral("audio.applications")) {
        const QString pactl = QStandardPaths::findExecutable(QStringLiteral("pactl"));
        if (pactl.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("audio-unavailable"),
                    QStringLiteral("音频服务不可用"), true);
            return true;
        }
        runCommand(socket, request, pactl,
                   {QStringLiteral("--format=json"), QStringLiteral("list"),
                    QStringLiteral("sink-inputs")}, parseAudioApplications,
                   10000, QStringLiteral("audio.applications"), kAudioCacheTtlMs);
        return true;
    }
    if (op == QStringLiteral("audio.application.set-volume")) {
        const int id = payload.value(QStringLiteral("id")).toInt(-1);
        const int value = qBound(0, payload.value(QStringLiteral("percent")).toInt(), 150);
        if (id < 0) {
            respond(socket, request, false, {}, QStringLiteral("invalid-audio-stream"),
                    QStringLiteral("音频应用无效"), false);
            return true;
        }
        const QString pactl = QStandardPaths::findExecutable(QStringLiteral("pactl"));
        if (pactl.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("audio-unavailable"),
                    QStringLiteral("音频服务不可用"), true);
            return true;
        }
        runCommand(socket, request, pactl,
                   {QStringLiteral("set-sink-input-volume"), QString::number(id),
                    QString::number(value) + QLatin1Char('%')},
                   [this](const QByteArray &output, int exitCode) {
            invalidateReplies(QStringLiteral("audio.applications"));
            return parseOutput(output, exitCode);
        }, 10000);
        return true;
    }
    if (op == QStringLiteral("audio.application.set-mute")) {
        const int id = payload.value(QStringLiteral("id")).toInt(-1);
        if (id < 0) {
            respond(socket, request, false, {}, QStringLiteral("invalid-audio-stream"),
                    QStringLiteral("音频应用无效"), false);
            return true;
        }
        const QString pactl = QStandardPaths::findExecutable(QStringLiteral("pactl"));
        if (pactl.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("audio-unavailable"),
                    QStringLiteral("音频服务不可用"), true);
            return true;
        }
        runCommand(socket, request, pactl,
                   {QStringLiteral("set-sink-input-mute"), QString::number(id),
                    payload.value(QStringLiteral("muted")).toBool() ? QStringLiteral("1") : QStringLiteral("0")},
                   [this](const QByteArray &output, int exitCode) {
            invalidateReplies(QStringLiteral("audio.applications"));
            return parseOutput(output, exitCode);
        }, 10000);
        return true;
    }
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
        // Resolve saved profiles before the RF scan so matching rows can carry
        // their immutable UUID. `connection show` accepts only summary fields;
        // NetworkManager uses NAME as the Wi-Fi profile identifier by default.
        // This metadata is optional: failure must not hide otherwise valid APs.
        const QPointer<QLocalSocket> guardedSocket(socket);
        auto *profiles = new QProcess(this);
        profiles->setProgram(QStringLiteral("nmcli"));
        profiles->setArguments({QStringLiteral("-t"), QStringLiteral("-f"),
                                QStringLiteral("UUID,TYPE,NAME"),
                                QStringLiteral("connection"), QStringLiteral("show")});
        armProcessWatchdog(profiles, 10000);
        connect(profiles, &QProcess::errorOccurred, this,
                [this, guardedSocket, request, profiles](QProcess::ProcessError) {
            // A crash also emits finished(); drop that connection so the
            // chain neither advances nor answers the same request twice.
            QObject::disconnect(profiles, &QProcess::finished, this, nullptr);
            respond(guardedSocket.data(), request, false, {}, QStringLiteral("network-scan-failed"),
                    QStringLiteral("Wi‑Fi 扫描失败"), true);
            profiles->deleteLater();
        });
        connect(profiles, &QProcess::finished, this,
                [this, guardedSocket, request, device, profiles](int profileExit,
                                                          QProcess::ExitStatus) {
            const QHash<QString, QString> savedProfiles = parseSavedWifiProfiles(
                profiles->readAllStandardOutput(), profileExit);
            profiles->deleteLater();
            auto *scan = new QProcess(this);
            scan->setProgram(QStringLiteral("nmcli"));
            scan->setArguments({QStringLiteral("-t"), QStringLiteral("-f"),
                                QStringLiteral("IN-USE,SSID,SIGNAL,SECURITY"),
                                QStringLiteral("device"), QStringLiteral("wifi"),
                                QStringLiteral("list"), QStringLiteral("ifname"), device,
                                QStringLiteral("--rescan"), QStringLiteral("auto")});
            // A rescan can legitimately take several seconds on a busy radio.
            armProcessWatchdog(scan, 25000);
            connect(scan, &QProcess::errorOccurred, this,
                    [this, guardedSocket, request, scan](QProcess::ProcessError) {
                QObject::disconnect(scan, &QProcess::finished, this, nullptr);
                respond(guardedSocket.data(), request, false, {}, QStringLiteral("network-scan-failed"),
                        QStringLiteral("Wi‑Fi 扫描失败"), true);
                scan->deleteLater();
            });
            connect(scan, &QProcess::finished, this,
                    [this, guardedSocket, request, savedProfiles, scan](int scanExit,
                                                                  QProcess::ExitStatus) {
                const QJsonObject result = parseNetworkScan(
                    scan->readAllStandardOutput(), scanExit);
                scan->deleteLater();
                if (scanExit != 0) {
                    respond(guardedSocket.data(), request, false, {}, QStringLiteral("network-scan-failed"),
                            QStringLiteral("Wi‑Fi 扫描失败"), true);
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
                respond(guardedSocket.data(), request, true, normalized);
            });
            scan->start();
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
    if (op == QStringLiteral("session.lock")) {
        runCommand(socket, request, QStringLiteral("loginctl"), {QStringLiteral("lock-session")}, {}, 15000);
        return true;
    }
    if (op == QStringLiteral("session.suspend") || op == QStringLiteral("session.hibernate")
        || op == QStringLiteral("session.reboot") || op == QStringLiteral("session.poweroff")) {
        const QString action = op.mid(QStringLiteral("session.").size());
        runCommand(socket, request, QStringLiteral("systemctl"), {action}, {}, 15000);
        return true;
    }
    if (op == QStringLiteral("session.logout")) {
        // plasma-kwin_wayland/kos-shell/kos-platform are PartOf=graphical-
        // session.target, not members of the login session's scope, so
        // `loginctl terminate-session` never reaches them: it kills the PAM
        // helper trio and leaves the compositor running, still holding the
        // DRM device, so the next login's fresh compositor fails to become
        // DRM master and the new session hangs on a blank screen. Stopping
        // the target is what actually tears the session down; --no-block
        // matters because this daemon is itself PartOf=graphical-session
        // .target and would be stopped by this same command, so the call
        // must return before its own process is reaped by that stop.
        runCommand(socket, request, QStringLiteral("systemctl"),
                   {QStringLiteral("--user"), QStringLiteral("--no-block"),
                    QStringLiteral("stop"), QStringLiteral("graphical-session.target")},
                   {}, 15000);
        return true;
    }
    if (op == QStringLiteral("session.switch-user")) {
        runCommand(socket, request, QStringLiteral("dm-tool"), {QStringLiteral("switch-to-greeter")}, {}, 15000);
        return true;
    }
    if (op == QStringLiteral("display.brightness.get")) {
        const QString key = QStringLiteral("display.brightness.get");
        if (serveCachedReply(socket, request, key))
            return true;
        QString brightnessService;
        QStringList displayIds;
        const QJsonObject kdeBrightness = readKdeBrightness(&brightnessService, &displayIds);
        if (kdeBrightness.value(QStringLiteral("available")).toBool()) {
            watchBrightnessPath(brightnessService,
                                QStringLiteral("/org/kde/ScreenBrightness"));
            for (const QString &displayId : displayIds)
                watchBrightnessPath(brightnessService, screenBrightnessPath(displayId));
            respond(socket, request, true, kdeBrightness);
            storeReply(key, kBrightnessCacheTtlMs, true, kdeBrightness);
            return true;
        }
        const QString brightnessctl = QStandardPaths::findExecutable(QStringLiteral("brightnessctl"));
        if (!brightnessctl.isEmpty()) {
            runCommand(socket, request, brightnessctl, {QStringLiteral("-m")},
                       parseBrightness, kDefaultCommandTimeoutMs,
                       key, kBrightnessCacheTtlMs);
        } else {
            const QJsonObject sysfs = readSysfsBrightness();
            respond(socket, request, true, sysfs);
            storeReply(key, kBrightnessCacheTtlMs, true, sysfs);
        }
        return true;
    }
    if (op == QStringLiteral("display.brightness.set")) {
        invalidateReplies(QStringLiteral("display.brightness."));
        const int value = qBound(0, payload.value(QStringLiteral("percent")).toInt(), 100);
        const QString displayId = payload.value(QStringLiteral("displayId")).toString();
        if (!displayId.isEmpty()) {
            if (!setKdeDisplayBrightness(displayId, value)) {
                respond(socket, request, false, {}, QStringLiteral("brightness-display-set-failed"),
                        QStringLiteral("无法设置指定显示器亮度"), true);
                return true;
            }
            respond(socket, request, true, {
                {QStringLiteral("displayId"), displayId},
                {QStringLiteral("percent"), value}
            });
            return true;
        }
        const QString brightnessctl = QStandardPaths::findExecutable(QStringLiteral("brightnessctl"));
        if (!brightnessctl.isEmpty()) {
            runCommand(socket, request, brightnessctl,
                       {QStringLiteral("set"), QStringLiteral("%1%").arg(value)});
            return true;
        }
        const QJsonObject backlight = readSysfsBrightness();
        if (!backlight.value(QStringLiteral("available")).toBool()) {
            respond(socket, request, false, {}, QStringLiteral("brightness-unavailable"),
                    QStringLiteral("亮度控制不可用"), false);
            return true;
        }
        const quint32 rawValue = qRound(value * backlight.value(QStringLiteral("maximum")).toInt() / 100.0);
        QDBusInterface session(QStringLiteral("org.freedesktop.login1"),
                               QStringLiteral("/org/freedesktop/login1/session/auto"),
                               QStringLiteral("org.freedesktop.login1.Session"),
                               QDBusConnection::systemBus());
        session.setTimeout(kDbusCallTimeoutMs);
        const QDBusMessage reply = session.call(QStringLiteral("SetBrightness"),
                                                QStringLiteral("backlight"),
                                                backlight.value(QStringLiteral("device")).toString(), rawValue);
        if (reply.type() == QDBusMessage::ErrorMessage)
            respond(socket, request, false, {}, QStringLiteral("brightness-set-failed"),
                    QStringLiteral("无法设置显示亮度"), true);
        else
            respond(socket, request, true, QJsonObject{{QStringLiteral("percent"), value}});
        return true;
    }
    if (op == QStringLiteral("theme.reconfigure")) {
        QDBusInterface kwin(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"),
                            QStringLiteral("org.kde.KWin"));
        // Fire-and-forget: the reply is unused, so never block the loop.
        if (kwin.isValid())
            kwin.asyncCall(QStringLiteral("reconfigure"));
        respond(socket, request, true, QJsonObject{{QStringLiteral("reconfigured"), true}});
        return true;
    }
    if (op == QStringLiteral("theme.apply-system")) {
        const bool dark = payload.value(QStringLiteral("dark")).toBool();
        applySystemTheme(socket, request, dark);
        return true;
    }
    if (op == QStringLiteral("theme.sync-glass")) {
        const int contentBlur = qBound(1,
            payload.value(QStringLiteral("contentBlurLevel")).toInt(), 15);
        const int refraction = qBound(0,
            payload.value(QStringLiteral("refractionLevel")).toInt(), 20);
        const double refractionEdgeSize = qBound(0.0,
            payload.value(QStringLiteral("refractionEdgeSize")).toDouble(1.8), 50.0);
        const double refractionNormalPow = qBound(0.1,
            payload.value(QStringLiteral("refractionNormalPow")).toDouble(4.0), 10.0);
        const double refractionRGBFringing = qBound(0.0,
            payload.value(QStringLiteral("refractionRGBFringing")).toDouble(5.4), 20.0);
        const double refractionOffsetStrength = qBound(0.0,
            payload.value(QStringLiteral("refractionOffsetStrength")).toDouble(8.0), 20.0);
        const double materialSoftness = qBound(0.0,
            payload.value(QStringLiteral("materialSoftness")).toDouble(), 1.0);
        const double materialReflection = qBound(0.0,
            payload.value(QStringLiteral("materialReflectionStrength")).toDouble(), 1.0);
        const double cornerExponent = qBound(2.0,
            payload.value(QStringLiteral("cornerExponent")).toDouble(3.0), 8.0);
        const QString kwriteconfig = QStandardPaths::findExecutable(
            QStringLiteral("kwriteconfig6"));
        if (kwriteconfig.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("theme-unavailable"),
                    QStringLiteral("KDE 主题配置工具不可用"), false);
            return true;
        }
        const QList<QStringList> writes{
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("BlurStrength"), QString::number(contentBlur)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("RefractionStrength"), QString::number(refraction)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("RefractionEdgeSize"), QString::number(refractionEdgeSize, 'f', 3)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("RefractionNormalPow"), QString::number(refractionNormalPow, 'f', 3)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("RefractionRGBFringing"), QString::number(refractionRGBFringing, 'f', 3)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("RefractionOffsetStrength"), QString::number(refractionOffsetStrength, 'f', 3)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("MaterialSoftness"), QString::number(materialSoftness, 'f', 3)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("MaterialReflectionStrength"), QString::number(materialReflection, 'f', 3)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blurplus"), QStringLiteral("--key"),
             QStringLiteral("CornerExponent"), QString::number(cornerExponent, 'f', 2)},
            {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
             QStringLiteral("Effect-blur"), QStringLiteral("--key"),
             QStringLiteral("BlurStrength"), QString::number(contentBlur)}};
        // QProcess::execute is waitForFinished(-1): a wedged kwriteconfig
        // would freeze the whole event loop. Run the writes as a watchdog-
        // armed async chain instead.
        const QPointer<QLocalSocket> guardedSocket(socket);
        auto pending = std::make_shared<QList<QStringList>>(writes.begin(), writes.end());
        auto step = std::make_shared<std::function<void()>>();
        // Weak capture: a strong step reference inside its own closure would
        // pin the whole chain alive forever.
        *step = [this, guardedSocket, request, kwriteconfig, pending,
                 weakStep = std::weak_ptr<std::function<void()>>(step)]() {
            const auto step = weakStep.lock();
            if (!step)
                return;
            if (pending->isEmpty()) {
                QDBusInterface effects(QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
                                       QStringLiteral("org.kde.kwin.Effects"));
                if (effects.isValid()) {
                    // Fire-and-forget reload notifications; replies unused.
                    effects.asyncCall(QStringLiteral("reconfigureEffect"), QStringLiteral("glass"));
                    effects.asyncCall(QStringLiteral("reconfigureEffect"), QStringLiteral("blur"));
                }
                respond(guardedSocket.data(), request, true,
                        QJsonObject{{QStringLiteral("configured"), true},
                                    {QStringLiteral("kwinAvailable"), effects.isValid()}});
                return;
            }
            const QStringList arguments = pending->takeFirst();
            auto *process = new QProcess(this);
            process->setProgram(kwriteconfig);
            process->setArguments(arguments);
            armProcessWatchdog(process, 10000);
            connect(process, &QProcess::errorOccurred, this,
                    [this, guardedSocket, request, process](QProcess::ProcessError) {
                QObject::disconnect(process, &QProcess::finished, this, nullptr);
                respond(guardedSocket.data(), request, false, {},
                        QStringLiteral("theme-write-failed"),
                        QStringLiteral("无法保存玻璃特效配置"), true);
                process->deleteLater();
            });
            connect(process, &QProcess::finished, this,
                    [this, guardedSocket, request, process, step](int exitCode,
                                                                 QProcess::ExitStatus) {
                process->deleteLater();
                if (exitCode != 0) {
                    respond(guardedSocket.data(), request, false, {},
                            QStringLiteral("theme-write-failed"),
                            QStringLiteral("无法保存玻璃特效配置"), true);
                    return;
                }
                (*step)();
            });
            process->start();
        };
        (*step)();
        return true;
    }
    if (op == QStringLiteral("theme.sync-dock-animation")) {
        const QString style = payload.value(QStringLiteral("style")).toString();
        if (style != QStringLiteral("scale") && style != QStringLiteral("genie")) {
            respond(socket, request, false, {}, QStringLiteral("invalid-style"),
                    QStringLiteral("窗口动画样式无效"), false);
            return true;
        }
        const QString kwriteconfig = QStandardPaths::findExecutable(
            QStringLiteral("kwriteconfig6"));
        if (kwriteconfig.isEmpty()) {
            respond(socket, request, false, {}, QStringLiteral("theme-write-failed"),
                    QStringLiteral("无法保存窗口动画配置"), true);
            return true;
        }
        runCommand(socket, request, kwriteconfig,
                   {QStringLiteral("--file"), QStringLiteral("kwinrc"), QStringLiteral("--group"),
                    QStringLiteral("Effect-kos_dock_window_animation"), QStringLiteral("--key"),
                    QStringLiteral("AnimationStyle"), style},
                   [](const QByteArray &, int) {
            QDBusInterface effects(QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
                                   QStringLiteral("org.kde.kwin.Effects"));
            if (effects.isValid())
                // Fire-and-forget reload notification; the reply is unused.
                effects.asyncCall(QStringLiteral("reconfigureEffect"),
                                  QStringLiteral("kos_dock_window_animation"));
            return QJsonObject{{QStringLiteral("configured"), true},
                               {QStringLiteral("kwinAvailable"), effects.isValid()}};
        }, 10000);
        return true;
    }
    if (op == QStringLiteral("theme.toggle")) {
        const QString configPath = QStandardPaths::writableLocation(
            QStandardPaths::GenericConfigLocation) + QStringLiteral("/kdeglobals");
        QSettings settings(configPath, QSettings::IniFormat);
        QString scheme = settings.value(
            QStringLiteral("ColorScheme")).toString();
        if (scheme.isEmpty()) {
            scheme = settings.value(
                QStringLiteral("General/ColorScheme")).toString();
        }
        bool currentlyDark = scheme.contains(
            QStringLiteral("dark"), Qt::CaseInsensitive);
        if (!currentlyDark && scheme.isEmpty()) {
            const QStringList background = settings.value(
                QStringLiteral("Colors:Window/BackgroundNormal")).toStringList();
            if (background.size() >= 3) {
                const int red = background[0].toInt();
                const int green = background[1].toInt();
                const int blue = background[2].toInt();
                currentlyDark = (red * 299 + green * 587 + blue * 114) / 1000 < 128;
            }
        }
        applySystemTheme(socket, request, !currentlyDark);
        return true;
    }
    if (op == QStringLiteral("screenshot.capture")) {
        const QStringList candidates{QStringLiteral("mark-shot"), QStringLiteral("markshot"),
                                     QStringLiteral("flameshot"), QStringLiteral("ksnip"),
                                     QStringLiteral("spectacle"), QStringLiteral("grimblast")};
        for (const QString &candidate : candidates) {
            const QString executable = QStandardPaths::findExecutable(candidate);
            if (executable.isEmpty())
                continue;
            QStringList args;
            if (candidate == QStringLiteral("mark-shot") || candidate == QStringLiteral("markshot")) args = {QStringLiteral("--capture")};
            else if (candidate == QStringLiteral("flameshot")) args = {QStringLiteral("gui")};
            else if (candidate == QStringLiteral("ksnip")) args = {QStringLiteral("-r")};
            else if (candidate == QStringLiteral("spectacle")) args = {QStringLiteral("-r")};
            else args = {QStringLiteral("copy"), QStringLiteral("area")};
            // Interactive capture tools (flameshot gui, region pickers) stay
            // alive until the user finishes; no watchdog.
            runCommand(socket, request, executable, args, {}, 0);
            return true;
        }
        respond(socket, request, false, {}, QStringLiteral("screenshot-unavailable"),
                QStringLiteral("没有可用的截图工具"), false);
        return true;
    }
    return false;
}

bool PlatformServer::handleStateOperation(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    if (!op.startsWith(QStringLiteral("state.")))
        return false;
    const QJsonObject payload = request.value(QStringLiteral("payload")).toObject();
    const QString path = resolveStatePath(
        payload.value(QStringLiteral("dir")).toString(),
        payload.value(QStringLiteral("file")).toString());
    if (path.isEmpty()) {
        respond(socket, request, false, {}, QStringLiteral("invalid-state-path"),
                QStringLiteral("状态文件路径无效或越出状态目录"), false);
        return true;
    }
    if (op == QStringLiteral("state.read")) {
        const QFileInfo info(path);
        if (!info.exists()) {
            // A missing file is not an error: consumers treat it as "no
            // persisted state yet", same as a first-run config directory.
            respond(socket, request, true,
                    QJsonObject{{QStringLiteral("data"), QString()},
                                {QStringLiteral("exists"), false}});
            return true;
        }
        if (!info.isFile() || info.size() > kMaxStateFileBytes) {
            respond(socket, request, false, {}, QStringLiteral("invalid-state-file"),
                    QStringLiteral("状态文件不可读或超过大小上限"), false);
            return true;
        }
        QFile input(path);
        if (!input.open(QIODevice::ReadOnly)) {
            respond(socket, request, false, {}, QStringLiteral("state-read-failed"),
                    QStringLiteral("无法读取状态文件"), true);
            return true;
        }
        // Read at most cap+1 so a file grown between stat() and open() can't
        // exceed the documented bound.
        const QByteArray content = input.read(kMaxStateFileBytes + 1);
        if (content.size() > kMaxStateFileBytes) {
            respond(socket, request, false, {}, QStringLiteral("invalid-state-file"),
                    QStringLiteral("状态文件超过大小上限"), false);
            return true;
        }
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("data"), QString::fromUtf8(content)},
                            {QStringLiteral("exists"), true}});
        return true;
    }
    if (op == QStringLiteral("state.write")) {
        const QJsonValue data = payload.value(QStringLiteral("data"));
        if (!data.isString()) {
            respond(socket, request, false, {}, QStringLiteral("invalid-state-data"),
                    QStringLiteral("state.write 需要字符串 data 字段"), false);
            return true;
        }
        const QByteArray bytes = data.toString().toUtf8();
        if (bytes.size() > kMaxStateFileBytes) {
            respond(socket, request, false, {}, QStringLiteral("state-data-too-large"),
                    QStringLiteral("状态内容超过大小上限"), false);
            return true;
        }
        const QString parent = QFileInfo(path).path();
        if (!QDir().mkpath(parent)) {
            respond(socket, request, false, {}, QStringLiteral("state-write-failed"),
                    QStringLiteral("无法创建状态目录"), true);
            return true;
        }
        // QSaveFile writes to a sibling temp file and renames on commit, so a
        // crash mid-write never leaves a half-written state file behind.
        QSaveFile output(path);
        if (!output.open(QIODevice::WriteOnly)
            || output.write(bytes) != bytes.size()
            || !output.commit()) {
            respond(socket, request, false, {}, QStringLiteral("state-write-failed"),
                    QStringLiteral("无法写入状态文件"), true);
            return true;
        }
        respond(socket, request, true,
                QJsonObject{{QStringLiteral("written"), bytes.size()}});
        return true;
    }
    return false;
}

bool PlatformServer::handleTrayOperation(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    if (op == QStringLiteral("tray.identify")) {
        runTrayIdentify(socket, request);
        return true;
    }
    return false;
}

void PlatformServer::handleRequest(QLocalSocket *socket, const QJsonObject &request)
{
    if (request.value(QStringLiteral("version")).toInt(kProtocolVersion) != kProtocolVersion) {
        respond(socket, request, false, {}, QStringLiteral("unsupported-version"),
                QStringLiteral("不支持的协议版本"), false);
        return;
    }
    const QString op = operation(request);
    if (op.isEmpty()) {
        respond(socket, request, false, {}, QStringLiteral("missing-operation"),
                QStringLiteral("缺少 operation"), false);
        return;
    }
    if (op == QStringLiteral("platform.ping")) {
        respond(socket, request, true, QJsonObject{{QStringLiteral("ready"), true}});
        return;
    }
    if (handleClipboard(socket, request) || handleApplication(socket, request)
        || handleFileOperation(socket, request)
        || handleKWin(socket, request) || handleAppMenu(socket, request)
        || handleInput(socket, request)
        || handleSystemOperation(socket, request)
        || handleTrayOperation(socket, request)
        || handleStateOperation(socket, request))
        return;
    respond(socket, request, false, {}, QStringLiteral("unknown-operation"),
            QStringLiteral("未知的平台操作"), false);
}

} // namespace KosPlatform
