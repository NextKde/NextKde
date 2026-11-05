#include "IndependentAppWidgets.h"

#include <KDesktopFile>
#include <KConfigGroup>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDate>
#include <utility>
#include <cmath>
#include <limits>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSet>
#include <QStandardPaths>
#include <QTimeZone>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#pragma push_macro("signals")
#undef signals
#include <flatpak.h>
#pragma pop_macro("signals")

namespace KosPlatform::IndependentAppWidgets {
namespace {
constexpr qint64 maximumBytes = 512 * 1024;

QJsonObject state(const QString &value, const QString &message)
{
    return {{QStringLiteral("state"), value}, {QStringLiteral("message"), message}};
}

// Walk by directory descriptors so a symlink swap cannot redirect the read.
QByteArray readSummary(const QString &path, QString &error)
{
    const auto parts = QDir::cleanPath(path).split('/', Qt::SkipEmptyParts);
    if (!path.startsWith('/') || parts.isEmpty()) {
        error = QStringLiteral("Invalid summary location");
        return {};
    }
    int fd = ::open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    for (qsizetype i = 0; fd >= 0 && i < parts.size(); ++i) {
        const bool last = i == parts.size() - 1;
        const QByteArray name = parts[i].toUtf8();
        const int next = ::openat(fd, name.constData(), O_RDONLY | O_CLOEXEC
                                 | O_NOFOLLOW | O_NONBLOCK | (last ? 0 : O_DIRECTORY));
        ::close(fd);
        fd = next;
    }
    if (fd < 0) {
        error = QStringLiteral("Summary missing, inaccessible, or uses a symbolic link");
        return {};
    }
    struct stat info{};
    if (::fstat(fd, &info) != 0 || !S_ISREG(info.st_mode)
        || info.st_uid != ::getuid() || info.st_size <= 0 || info.st_size > maximumBytes) {
        ::close(fd);
        error = QStringLiteral("Summary must be a bounded regular file owned by this user");
        return {};
    }
    QFile file;
    if (!file.open(fd, QIODevice::ReadOnly, QFileDevice::AutoCloseHandle)) {
        ::close(fd);
        error = QStringLiteral("Unable to read summary");
        return {};
    }
    const QByteArray bytes = file.read(maximumBytes + 1);
    if (bytes.size() > maximumBytes || file.error() != QFileDevice::NoError) {
        error = QStringLiteral("Summary read failed or exceeds the size limit");
        return {};
    }
    return bytes;
}

bool number(const QJsonValue &value, double minimum = -std::numeric_limits<double>::max(),
            double maximum = std::numeric_limits<double>::max())
{
    return value.isDouble() && std::isfinite(value.toDouble())
        && value.toDouble() >= minimum && value.toDouble() <= maximum;
}

bool weatherCode(const QJsonValue &value)
{
    return number(value, 0, 99) && std::floor(value.toDouble()) == value.toDouble();
}

bool weatherTime(const QJsonValue &value)
{
    return value.isString() && value.toString().size() <= 64
        && QDateTime::fromString(value.toString(), Qt::ISODate).isValid();
}

bool weatherLocation(const QJsonValue &value)
{
    if (!value.isObject()) return false;
    const auto location = value.toObject();
    const QString id = location.value(QStringLiteral("id")).toString();
    const QString name = location.value(QStringLiteral("name")).toString();
    if (id.isEmpty() || id.size() > 512 || name.trimmed().isEmpty() || name.size() > 512
        || !number(location.value(QStringLiteral("latitude")), -90, 90)
        || !number(location.value(QStringLiteral("longitude")), -180, 180)) return false;
    for (const auto *field : {"admin1", "country", "countryCode", "timezone"}) {
        const auto text = location.value(QString::fromLatin1(field));
        if (!text.isUndefined() && (!text.isString() || text.toString().size() > 512)) return false;
    }
    const auto summary = location.value(QStringLiteral("summary"));
    if (!summary.isNull() && !summary.isUndefined()) {
        const auto row = summary.toObject();
        if (!summary.isObject() || !weatherTime(row.value(QStringLiteral("time")))
            || !number(row.value(QStringLiteral("temperature")))
            || !weatherCode(row.value(QStringLiteral("weatherCode")))
            || !row.value(QStringLiteral("isDay")).isBool()
            || !number(row.value(QStringLiteral("tempHigh")))
            || !number(row.value(QStringLiteral("tempLow")))
            || row.value(QStringLiteral("tempHigh")).toDouble() < row.value(QStringLiteral("tempLow")).toDouble()) return false;
    }
    return true;
}

bool weatherConditions(const QJsonValue &value, bool hourly)
{
    if (!value.isObject()) return false;
    const auto row = value.toObject();
    if (!weatherTime(row.value(QStringLiteral("time")))
        || !number(row.value(QStringLiteral("temperature")))
        || !number(row.value(QStringLiteral("apparentTemperature")))
        || !number(row.value(QStringLiteral("relativeHumidity")), 0, 100)
        || !number(row.value(QStringLiteral("windSpeed")), 0)
        || !weatherCode(row.value(QStringLiteral("weatherCode")))
        || !row.value(QStringLiteral("isDay")).isBool()) return false;
    if (hourly) return number(row.value(QStringLiteral("precipitationProbability")), 0, 100);
    if (!number(row.value(QStringLiteral("windDirection")), 0, 360)) return false;
    for (const auto *field : {"windGust", "uvIndex", "visibility", "pressure", "moonPhase", "moonIllumination"}) {
        const QString name = QString::fromLatin1(field);
        const auto optional = row.value(name);
        const double maximum = name == QLatin1String("moonPhase") ? 1
            : name == QLatin1String("moonIllumination") ? 100 : std::numeric_limits<double>::max();
        if (!optional.isUndefined() && !optional.isNull() && !number(optional, 0, maximum)) return false;
    }
    return true;
}

bool weatherDay(const QJsonValue &value)
{
    if (!value.isObject()) return false;
    const auto row = value.toObject();
    const QString date = row.value(QStringLiteral("date")).toString();
    if (!QDate::fromString(date, Qt::ISODate).isValid()
        || QDate::fromString(date, Qt::ISODate).toString(Qt::ISODate) != date
        || !weatherCode(row.value(QStringLiteral("weatherCode")))
        || !number(row.value(QStringLiteral("temperatureMaximum")))
        || !number(row.value(QStringLiteral("temperatureMinimum")))
        || row.value(QStringLiteral("temperatureMaximum")).toDouble() < row.value(QStringLiteral("temperatureMinimum")).toDouble()
        || !number(row.value(QStringLiteral("precipitationProbability")), 0, 100)) return false;
    // Sunrise/sunset can be absent at polar locations.
    for (const auto *field : {"sunrise", "sunset"}) {
        const auto time = row.value(QString::fromLatin1(field));
        if (!time.isUndefined() && (!time.isString() || (!time.toString().isEmpty() && !weatherTime(time)))) return false;
    }
    return true;
}

bool weatherTimestamp(const QJsonValue &value)
{
    return value.isUndefined() || (number(value, 0, 9007199254740991.0)
        && std::floor(value.toDouble()) == value.toDouble());
}

bool bounded(const QJsonValue &value, int depth = 0)
{
    if (depth > 8) return false;
    if (value.isString()) return value.toString().size() <= 8192;
    if (value.isArray()) {
        const auto array = value.toArray();
        if (array.size() > 192) return false;
        for (const auto &item : array) if (!bounded(item, depth + 1)) return false;
    } else if (value.isObject()) {
        const auto object = value.toObject();
        if (object.size() > 64) return false;
        for (auto it = object.begin(); it != object.end(); ++it)
            if (it.key().size() > 128 || !bounded(it.value(), depth + 1)) return false;
    }
    return true;
}
}

QueryControl::QueryControl()
    : cancellable(g_cancellable_new()), deadline(std::chrono::steady_clock::now() + std::chrono::seconds(15))
{
}

QueryControl::~QueryControl() { g_object_unref(cancellable); }
void QueryControl::cancel() {
    cancelled.store(true);
    g_cancellable_cancel(cancellable);
}
bool QueryControl::expired() const {
    return cancelled.load() || std::chrono::steady_clock::now() >= deadline;
}

bool launchEntryMatches(const QJsonObject &source)
{
    const QString path = source.value(QStringLiteral("entryPath")).toString();
    const QString expected = source.value(QStringLiteral("canonicalEntry")).toString();
    if (path.isEmpty() || expected.isEmpty() || QFileInfo(path).canonicalFilePath() != expected)
        return false;
    // Open the resolved regular file without following a replacement symlink.
    const int fd = ::open(QFile::encodeName(expected).constData(), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) return false;
    struct stat info{};
    if (::fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) || info.st_size <= 0 || info.st_size > 65536) {
        ::close(fd);
        return false;
    }
    QFile file;
    if (!file.open(fd, QIODevice::ReadOnly, QFileDevice::AutoCloseHandle)) {
        ::close(fd);
        return false;
    }
    const auto bytes = file.read(65537);
    if (file.error() != QFileDevice::NoError || bytes.size() > 65536
        || QString::fromLatin1(QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex())
            != source.value(QStringLiteral("entryHash")).toString()
        || QFileInfo(path).canonicalFilePath() != expected) return false;

    const auto ref = source.value(QStringLiteral("flatpakRef")).toObject();
    if (!ref.isEmpty()) {
        const QString installation = ref.value(QStringLiteral("installation")).toString();
        const QString id = ref.value(QStringLiteral("id")).toString();
        const QString arch = ref.value(QStringLiteral("arch")).toString();
        const QString branch = ref.value(QStringLiteral("branch")).toString();
        const QString deployment = ref.value(QStringLiteral("deployDirectory")).toString();
        for (const auto &part : {id, arch, branch}) {
            if (part.isEmpty() || part == QLatin1String(".") || part == QLatin1String("..")
                || part.contains('/') || part.contains('\\')) return false;
        }
        const QString appRoot = installation + QStringLiteral("/app/") + id;
        const QString branchRoot = appRoot + '/' + arch + '/' + branch;
        const QString resolvedBranch = QFileInfo(branchRoot).canonicalFilePath();
        // Flatpak's current branch and active deployment must still be the
        // inspected ones. Unknown layouts fail closed rather than guessing.
        if (deployment.isEmpty() || resolvedBranch.isEmpty()
            || QFileInfo(appRoot + QStringLiteral("/current")).canonicalFilePath() != resolvedBranch
            || QFileInfo(branchRoot + QStringLiteral("/active")).canonicalFilePath() != deployment
            || QFileInfo(deployment + QStringLiteral("/export/share/applications/") + id + QStringLiteral(".desktop")).canonicalFilePath() != expected)
            return false;
    }
    return true;
}

bool supported(const QString &key)
{
    return key == QLatin1String("calendar") || key == QLatin1String("weather");
}

QJsonObject snapshot(const QString &key, const std::shared_ptr<QueryControl> &control)
{
    const auto timeout = [] { return state(QStringLiteral("unavailable"), QStringLiteral("Application inspection timed out; installation state is unknown")); };
    if (control->expired()) return timeout();
    if (!supported(key)) return state(QStringLiteral("invalid"), QStringLiteral("Unsupported widget app"));
    const QString appId = QStringLiteral("org.nextks.") + key;
    const QString legacyId = QStringLiteral("kos-") + key;
    const QString retiredId = QStringLiteral("org.nextkde.")
        + (key == QLatin1String("calendar") ? QStringLiteral("Calendar") : QStringLiteral("Weather"));
    QStringList roots;
    for (const auto &root : QStandardPaths::standardLocations(QStandardPaths::GenericDataLocation))
        roots.append(QDir(root).filePath(QStringLiteral("applications")));
    roots << QDir::homePath() + QStringLiteral("/.local/share/flatpak/exports/share/applications")
          << QStringLiteral("/var/lib/flatpak/exports/share/applications");
    const QStringList ids{appId, legacyId, retiredId};
    // Inventory all configured installations, not just the branch exported to
    // the desktop. A hidden second ref still shares this app's private data.
    g_autoptr(GError) inventoryError = nullptr;
    g_autoptr(FlatpakInstallation) user = flatpak_installation_new_user(control->cancellable, &inventoryError);
    if (!user)
        return state(QStringLiteral("unavailable"), QStringLiteral("Cannot inspect user Flatpak installation"));
    g_autoptr(GPtrArray) installations = flatpak_get_system_installations(control->cancellable, &inventoryError);
    if (!installations)
        return state(QStringLiteral("unavailable"), QStringLiteral("Cannot enumerate configured Flatpak installations"));
    g_ptr_array_add(installations, g_object_ref(user));
    QList<QJsonObject> installedRefs;
    QSet<QString> installationsSeen;
    for (guint i = 0; i < installations->len; ++i) {
        if (control->expired()) return timeout();
        auto *installation = FLATPAK_INSTALLATION(g_ptr_array_index(installations, i));
        flatpak_installation_set_no_interaction(installation, TRUE);
        g_autofree char *rawPath = g_file_get_path(flatpak_installation_get_path(installation));
        const QString installPath = QString::fromUtf8(rawPath);
        if (installPath.isEmpty())
            return state(QStringLiteral("unavailable"), QStringLiteral("Flatpak installation has no local path"));
        const QString canonical = QFileInfo(installPath).canonicalFilePath();
        const QString identity = canonical.isEmpty() ? QDir::cleanPath(installPath) : canonical;
        if (installationsSeen.contains(identity)) continue;
        installationsSeen.insert(identity);
        roots.append(installPath + QStringLiteral("/exports/share/applications"));
        g_autoptr(GPtrArray) refs = flatpak_installation_list_installed_refs_by_kind(
            installation, FLATPAK_REF_KIND_APP, control->cancellable, &inventoryError);
        if (!refs)
            return state(QStringLiteral("unavailable"), QStringLiteral("Flatpak inventory is unreadable; installation state is unknown"));
        for (guint j = 0; j < refs->len; ++j) {
            if (control->expired()) return timeout();
            auto *installed = FLATPAK_INSTALLED_REF(g_ptr_array_index(refs, j));
            auto *ref = FLATPAK_REF(installed);
            const QString id = QString::fromUtf8(flatpak_ref_get_name(ref));
            if (!ids.contains(id)) continue;
            installedRefs.append({
                {QStringLiteral("id"), id},
                {QStringLiteral("installation"), identity},
                {QStringLiteral("scope"), flatpak_installation_get_is_user(installation) ? QStringLiteral("user") : QStringLiteral("system")},
                {QStringLiteral("arch"), QString::fromUtf8(flatpak_ref_get_arch(ref))},
                {QStringLiteral("branch"), QString::fromUtf8(flatpak_ref_get_branch(ref))},
                {QStringLiteral("commit"), QString::fromUtf8(flatpak_ref_get_commit(ref))},
                {QStringLiteral("origin"), QString::fromUtf8(flatpak_installed_ref_get_origin(installed))},
                {QStringLiteral("deployDirectory"), QFileInfo(QString::fromUtf8(flatpak_installed_ref_get_deploy_dir(installed))).canonicalFilePath()},
                {QStringLiteral("current"), bool(flatpak_installed_ref_get_is_current(installed))},
            });
        }
    }
    if (installedRefs.size() > 1)
        return state(QStringLiteral("ambiguous"), QStringLiteral("Multiple Flatpak identities, branches, architectures or installations found; manage them before connecting widgets"));
    QSet<QString> seen;
    QList<QJsonObject> candidates;
    for (const auto &root : std::as_const(roots)) {
        for (const auto &id : ids) {
            if (control->expired()) return timeout();
            const QString path = QDir(root).filePath(id + QStringLiteral(".desktop"));
            const QFileInfo info(path);
            const QString canonical = info.canonicalFilePath();
            if (canonical.isEmpty() || seen.contains(canonical)) continue;
            seen.insert(canonical);
            if (!info.isFile() || info.size() > 65536)
                return state(QStringLiteral("unavailable"), QStringLiteral("Invalid application entry"));
            KDesktopFile desktop(path);
            const auto group = desktop.desktopGroup();
            if (group.readEntry("Type", QString()) != QLatin1String("Application")
                || group.readEntry("Hidden", false))
                return state(QStringLiteral("unavailable"), QStringLiteral("Application entry is hidden or unavailable"));
            const QString exec = group.readEntry("Exec", QString());
            const QString tryExec = group.readEntry("TryExec", QString());
            if (exec.isEmpty() || exec.size() > 8192 || (!tryExec.isEmpty()
                && QStandardPaths::findExecutable(tryExec).isEmpty()))
                return state(QStringLiteral("unavailable"), QStringLiteral("Application executable is unavailable"));
            const QString flatpak = group.readEntry("X-Flatpak", QString());
            const bool exported = canonical.contains(QStringLiteral("/flatpak/"));
            if ((!flatpak.isEmpty() && flatpak != id) || (exported && flatpak.isEmpty()))
                return state(QStringLiteral("ambiguous"), QStringLiteral("Application export identity cannot be confirmed"));
            QFile entryFile(path);
            if (!entryFile.open(QIODevice::ReadOnly))
                return state(QStringLiteral("unavailable"), QStringLiteral("Application entry cannot be read"));
            const QByteArray entryBytes = entryFile.read(65537);
            if (entryBytes.size() > 65536)
                return state(QStringLiteral("unavailable"), QStringLiteral("Application entry exceeds its size limit"));
            candidates.append({{QStringLiteral("entryHash"), QString::fromLatin1(QCryptographicHash::hash(entryBytes, QCryptographicHash::Sha256).toHex())},
                               {QStringLiteral("desktopId"), id},
                               {QStringLiteral("entryPath"), path},
                               {QStringLiteral("canonicalEntry"), canonical},
                               {QStringLiteral("command"), exec},
                               {QStringLiteral("channel"), flatpak.isEmpty() ? QStringLiteral("native") : QStringLiteral("flatpak")}});
        }
    }
    if (candidates.isEmpty()) {
        if (!installedRefs.isEmpty())
            return state(QStringLiteral("unavailable"), QStringLiteral("Flatpak is installed but has no usable desktop export; repair its export with the original manager"));
        return state(QStringLiteral("not-installed"), QStringLiteral("Install the application to open it"));
    }
    if (candidates.size() != 1) return state(QStringLiteral("ambiguous"), QStringLiteral("Multiple application installations found; manage them in Settings"));
    QJsonObject result = candidates.first();
    if (result.value(QStringLiteral("channel")) == QLatin1String("flatpak")) {
        if (installedRefs.size() != 1)
            return state(QStringLiteral("unavailable"), QStringLiteral("Desktop export has no matching installed Flatpak ref"));
        const auto ref = installedRefs.first();
        const QString deployment = ref.value(QStringLiteral("deployDirectory")).toString();
        const QString expected = QFileInfo(deployment + QStringLiteral("/export/share/applications/")
            + ref.value(QStringLiteral("id")).toString() + QStringLiteral(".desktop")).canonicalFilePath();
        if (!ref.value(QStringLiteral("current")).toBool() || deployment.isEmpty() || expected.isEmpty()
            || ref.value(QStringLiteral("id")) != result.value(QStringLiteral("desktopId"))
            || expected != result.value(QStringLiteral("canonicalEntry")).toString())
            return state(QStringLiteral("ambiguous"), QStringLiteral("Desktop export does not match the unique current Flatpak deployment"));
        result.insert(QStringLiteral("flatpakRef"), ref);
    } else if (!installedRefs.isEmpty()) {
        return state(QStringLiteral("ambiguous"), QStringLiteral("Native and Flatpak installations coexist; choose one before connecting widgets"));
    }
    const QString id = result.value(QStringLiteral("desktopId")).toString();
    const bool sandbox = result.value(QStringLiteral("channel")) == QLatin1String("flatpak");
    const QString dataHome = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
    const QString dataRoot = sandbox ? QDir::homePath() + QStringLiteral("/.var/app/") + id + QStringLiteral("/data") : dataHome;
    const QString configuredState = qEnvironmentVariable("XDG_STATE_HOME");
    const QString stateRoot = sandbox ? dataRoot + QStringLiteral("/state")
        : (configuredState.isEmpty() ? QDir::homePath() + QStringLiteral("/.local/state") : configuredState);
    const QString path = key == QLatin1String("calendar")
        ? dataRoot + QStringLiteral("/kos/pim/widget-snapshot.json")
        : stateRoot + QStringLiteral("/quickshell/kos-weather/standalone-backend/widget-snapshot.json");
    const QByteArray identity = QJsonDocument(result).toJson(QJsonDocument::Compact) + path.toUtf8();
    result.insert(QStringLiteral("sourceToken"), QString::fromLatin1(QCryptographicHash::hash(identity, QCryptographicHash::Sha256).toHex()));
    result.insert(QStringLiteral("installed"), true);
    const auto fail = [&result](const QString &status, const QString &message) {
        result.insert(QStringLiteral("state"), status);
        result.insert(QStringLiteral("message"), message);
        return result;
    };
    if (id == retiredId || (sandbox && id != appId))
        return fail(QStringLiteral("unsupported"), QStringLiteral("This application identity does not provide the widget interface"));
    if (!sandbox && key == QLatin1String("calendar") && !qEnvironmentVariableIsEmpty("KOS_PIM_STORAGE_DIR"))
        return fail(QStringLiteral("unsupported"), QStringLiteral("Custom Calendar storage is not connected to widgets"));
    if (!sandbox && key == QLatin1String("weather") && qEnvironmentVariableIsSet("KOS_DATA_SOCKET"))
        return fail(QStringLiteral("unsupported"), QStringLiteral("Custom Weather backend is not connected to widgets"));
    if (control->expired()) return timeout();
    QString error;
    const QByteArray bytes = readSummary(path, error);
    if (control->expired()) return timeout();
    if (bytes.isEmpty()) return fail(QStringLiteral("missing"), error + QStringLiteral("; open the application to publish data"));
    QJsonParseError parseError;
    const auto document = QJsonDocument::fromJson(bytes, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject() || !bounded(document.object()))
        return fail(QStringLiteral("invalid"), QStringLiteral("Invalid widget summary"));
    const QJsonObject payload = document.object();
    const bool legacy = !sandbox && id == legacyId && key == QLatin1String("calendar")
        && !payload.contains(QStringLiteral("widgetContractVersion"));
    if (!legacy && (payload.value(QStringLiteral("widgetContractVersion")).toInt() != 2
        || payload.value(QStringLiteral("appId")).toString() != appId
        || payload.value(QStringLiteral("channel")) != result.value(QStringLiteral("channel"))
        || payload.value(QStringLiteral("storageMode")).toString() != QLatin1String("default")))
        return fail(QStringLiteral("unsupported"), QStringLiteral("Widget summary identity or version is unsupported"));
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const qint64 generatedAt = payload.value(QStringLiteral("generatedAt")).toInteger();
    if (generatedAt <= 0 || generatedAt > now + 60000)
        return fail(QStringLiteral("invalid"), QStringLiteral("Widget summary time is invalid"));
    bool stale = now - generatedAt > (key == QLatin1String("calendar") ? 12 * 60000 : 2 * 3600000);
    if (key == QLatin1String("calendar")) {
        if (payload.value(QStringLiteral("schemaVersion")).toInt() != 1
            || !payload.value(QStringLiteral("events")).isArray() || !payload.value(QStringLiteral("todos")).isArray()
            || payload.value(QStringLiteral("events")).toArray().size() > 16
            || payload.value(QStringLiteral("todos")).toArray().size() > 16)
            return fail(QStringLiteral("invalid"), QStringLiteral("Invalid Calendar widget data"));
        if (!legacy && payload.value(QStringLiteral("storagePath")).toString()
            != (sandbox ? QStringLiteral("/var/data/kos/pim") : dataRoot + QStringLiteral("/kos/pim"))) {
            // Flatpak may expose XDG_DATA_HOME using its host-shaped path.
            const QString stored = payload.value(QStringLiteral("storagePath")).toString();
            if (!sandbox || stored != dataRoot + QStringLiteral("/kos/pim"))
                return fail(QStringLiteral("unsupported"), QStringLiteral("Calendar uses a different storage profile"));
        }
        for (const auto *list : {"events", "todos"}) {
            for (const auto &item : payload.value(QString::fromLatin1(list)).toArray()) {
                const auto row = item.toObject();
                const QString uid = row.value(QStringLiteral("id")).toString();
                if (!item.isObject() || uid.isEmpty() || uid.size() > 512
                    || !row.value(QStringLiteral("title")).isString()
                    || (QString::fromLatin1(list) == QLatin1String("events")
                        && !QDateTime::fromString(row.value(QStringLiteral("start")).toString(), Qt::ISODate).isValid())
                    || (QString::fromLatin1(list) == QLatin1String("todos")
                        && !row.value(QStringLiteral("completed")).isBool()))
                    return fail(QStringLiteral("invalid"), QStringLiteral("Invalid Calendar item fields"));
            }
        }
        stale |= payload.value(QStringLiteral("today")).toString() != QDate::currentDate().toString(Qt::ISODate);
        if (!legacy) stale |= payload.value(QStringLiteral("timeZone")).toString() != QString::fromUtf8(QTimeZone::systemTimeZoneId());
        result.insert(QStringLiteral("payload"), payload);
    } else {
        const QJsonObject weather = payload.value(QStringLiteral("weather")).toObject();
        const QString status = weather.value(QStringLiteral("status")).toString();
        const auto error = weather.value(QStringLiteral("error"));
        if (weather.value(QStringLiteral("schemaVersion")) != QJsonValue(1)
            || !QStringList{QStringLiteral("idle"), QStringLiteral("loading"), QStringLiteral("ready"), QStringLiteral("error")}.contains(status)
            || (!error.isUndefined() && !error.isString()))
            return fail(QStringLiteral("invalid"), QStringLiteral("Invalid Weather widget data"));
        if (weather.value(QStringLiteral("units")).toString() != QLatin1String("metric")
            && weather.value(QStringLiteral("units")).toString() != QLatin1String("imperial"))
            return fail(QStringLiteral("invalid"), QStringLiteral("Invalid Weather units"));
        for (const auto *field : {"fetchedAt", "staleAt", "nextRefreshAt"}) {
            if (!weatherTimestamp(weather.value(QString::fromLatin1(field))))
                return fail(QStringLiteral("invalid"), QStringLiteral("Invalid Weather timestamp fields"));
        }
        const auto current = weather.value(QStringLiteral("current"));
        if (current.isUndefined() || current.isNull())
            return fail(QStringLiteral("missing"), QStringLiteral("No current Weather reading; open the application to update"));
        if (!weatherConditions(current, false) || !weatherLocation(weather.value(QStringLiteral("location"))))
            return fail(QStringLiteral("invalid"), QStringLiteral("Invalid Weather conditions or location"));
        if (!weather.value(QStringLiteral("locations")).isArray()
            || !weather.value(QStringLiteral("hourly")).isArray()
            || weather.value(QStringLiteral("hourly")).toArray().size() > 48
            || !weather.value(QStringLiteral("daily")).isArray()
            || weather.value(QStringLiteral("daily")).toArray().size() > 7)
            return fail(QStringLiteral("invalid"), QStringLiteral("Invalid Weather forecast arrays"));
        QSet<QString> locations;
        for (const auto &item : weather.value(QStringLiteral("locations")).toArray()) {
            const QString id = item.toObject().value(QStringLiteral("id")).toString();
            if (!weatherLocation(item) || locations.contains(id))
                return fail(QStringLiteral("invalid"), QStringLiteral("Invalid Weather saved location"));
            locations.insert(id);
        }
        for (const auto &item : weather.value(QStringLiteral("hourly")).toArray()) {
            if (!weatherConditions(item, true))
                return fail(QStringLiteral("invalid"), QStringLiteral("Invalid Weather hourly forecast"));
        }
        QString previousDate;
        for (const auto &item : weather.value(QStringLiteral("daily")).toArray()) {
            const QString date = item.toObject().value(QStringLiteral("date")).toString();
            if (!weatherDay(item) || (!previousDate.isEmpty() && date <= previousDate))
                return fail(QStringLiteral("invalid"), QStringLiteral("Invalid Weather daily forecast"));
            previousDate = date;
        }
        const auto air = weather.value(QStringLiteral("airQuality"));
        if (!air.isNull() && !air.isUndefined()) {
            const auto quality = air.toObject();
            const auto aqi = quality.value(QStringLiteral("usAqi"));
            const auto category = quality.value(QStringLiteral("category"));
            if (!air.isObject() || !weatherTime(quality.value(QStringLiteral("time")))
                || (!aqi.isNull() && !number(aqi, 0))
                || (!category.isUndefined() && !category.isString()))
                return fail(QStringLiteral("invalid"), QStringLiteral("Invalid Weather air quality"));
        }
        const qint64 fetched = weather.value(QStringLiteral("fetchedAt")).toInteger();
        const qint64 expires = weather.value(QStringLiteral("staleAt")).toInteger();
        if (fetched > now + 60000 || (expires > 0 && expires < fetched))
            return fail(QStringLiteral("invalid"), QStringLiteral("Weather collection time is invalid"));
        stale |= fetched <= 0 || expires <= now || now - fetched > 2 * 3600000 || status == QLatin1String("error");
        result.insert(QStringLiteral("payload"), weather);
    }
    result.insert(QStringLiteral("generatedAt"), generatedAt);
    return fail(stale ? QStringLiteral("stale") : QStringLiteral("ready"),
                stale ? QStringLiteral("Cached data; open the application to update") : QString());
}
}
