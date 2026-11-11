#include "DeclarativePlugins.h"
#include "AppCatalog.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDebug>
#include <cerrno>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLockFile>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QUuid>
#include <QTimer>
#include <QVersionNumber>
#include <QtConcurrentRun>
#include <algorithm>
#include <cmath>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/sysinfo.h>
#include <unistd.h>

namespace KosPlatform {
namespace {
constexpr qsizetype MaxPackageBytes = 128 * 1024;
constexpr qsizetype MaxStateBytes = 12 * 1024 * 1024;
constexpr int MaxPlugins = 64;
constexpr int MaxInstances = 128;
const QString Format = QStringLiteral("declarative-widget");
const QString SystemPermission = QStringLiteral("system.summary");

struct Outcome {
    bool ok = false;
    QJsonObject result;
    QString code, message;
};
Outcome fail(const QString &code, const QString &message) { return {false, {}, code, message}; }
QString digest(const QByteArray &bytes)
{ return QString::fromLatin1(QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex()); }
bool matches(const QString &text, const char *pattern)
{ return QRegularExpression(QString::fromLatin1(pattern)).match(text).hasMatch(); }
bool identifier(const QJsonValue &v)
{ return v.isString() && matches(v.toString(), "^[a-zA-Z][a-zA-Z0-9_-]{0,47}$"); }
bool pluginId(const QJsonValue &v)
{ return v.isString() && v.toString().size() <= 160 && matches(v.toString(), "^[a-zA-Z][a-zA-Z0-9_-]*(\\.[a-zA-Z][a-zA-Z0-9_-]*)+$"); }
bool text(const QJsonValue &v, int maximum, bool empty = true)
{
    if (!v.isString() || v.toString().size() > maximum || (!empty && v.toString().trimmed().isEmpty())) return false;
    for (const auto ch : v.toString())
        if ((ch.unicode() < 32 && ch != '\n' && ch != '\t') || ch.unicode() == 127) return false;
    return true;
}
bool integer(const QJsonValue &v, double low = -1000000000, double high = 1000000000)
{ return v.isDouble() && std::isfinite(v.toDouble()) && v.toDouble() == std::floor(v.toDouble()) && v.toDouble() >= low && v.toDouble() <= high; }
bool fields(const QJsonObject &o, const QStringList &required, const QStringList &optional = {})
{
    for (const auto &key : required) if (!o.contains(key)) return false;
    for (auto it = o.begin(); it != o.end(); ++it) if (!required.contains(it.key()) && !optional.contains(it.key())) return false;
    return true;
}
bool bounded(const QJsonValue &v, int depth, int &nodes, int maxNodes, int maxString)
{
    if (depth > 24 || ++nodes > maxNodes) return false;
    if (v.isString()) return v.toString().size() <= maxString;
    if (v.isDouble()) return std::isfinite(v.toDouble());
    if (v.isArray()) {
        if (v.toArray().size() > maxNodes) return false;
        for (const auto &item : v.toArray()) if (!bounded(item, depth + 1, nodes, maxNodes, maxString)) return false;
    } else if (v.isObject()) {
        const auto o = v.toObject();
        for (auto it = o.begin(); it != o.end(); ++it)
            if (it.key().size() > 160 || !bounded(it.value(), depth + 1, nodes, maxNodes, maxString)) return false;
    }
    return true;
}
QJsonObject parse(const QByteArray &bytes, qsizetype limit, QString &error, bool state = false)
{
    if (bytes.isEmpty() || bytes.size() > limit) { error = "JSON file is empty or exceeds its size limit"; return {}; }
    // Reject excessive nesting before invoking Qt's JSON parser.
    int depth = 0; bool quoted = false, escaped = false;
    for (const char ch : bytes) {
        if (quoted) { if (escaped) escaped = false; else if (ch == '\\') escaped = true; else if (ch == '"') quoted = false; }
        else if (ch == '"') quoted = true;
        else if (ch == '{' || ch == '[') { if (++depth > 24) { error = "JSON nesting exceeds limit"; return {}; } }
        else if (ch == '}' || ch == ']') --depth;
    }
    QJsonParseError e;
    const auto doc = QJsonDocument::fromJson(bytes, &e);
    int nodes = 0;
    if (e.error != QJsonParseError::NoError || !doc.isObject()
        || !bounded(doc.object(), 0, nodes, state ? 250000 : 8192, 4096)) {
        error = "Invalid or oversized JSON structure"; return {};
    }
    return doc.object();
}

// Every path component is opened without following links, including ancestors.
// No special files, /proc pseudo-files, arbitrary-size reads or URL inputs.
QByteArray readLocal(const QString &path, qsizetype limit, QString &error)
{
    if (path.size() > 4096 || !path.startsWith('/') || path.contains(QChar::Null)
        || QDir::cleanPath(path) != path || path.startsWith("/proc/") || path.startsWith("/sys/") || path.startsWith("/dev/")) {
        error = "Select an absolute regular JSON file path without links or traversal"; return {};
    }
    const auto parts = path.split('/', Qt::SkipEmptyParts);
    if (parts.isEmpty()) { error = "A file is required"; return {}; }
    int fd = ::open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    for (qsizetype i = 0; i < parts.size() && fd >= 0; ++i) {
        const auto name = QFile::encodeName(parts[i]);
        const int next = ::openat(fd, name.constData(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
                                 | (i + 1 < parts.size() ? O_DIRECTORY : 0));
        ::close(fd); fd = next;
    }
    struct stat st{};
    if (fd < 0 || ::fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_uid != ::getuid()
        || st.st_size <= 0 || st.st_size > limit) {
        if (fd >= 0) ::close(fd);
        error = "File must be a bounded, current-user regular file with no symlinks"; return {};
    }
    QFile file;
    if (!file.open(fd, QIODevice::ReadOnly, QFileDevice::AutoCloseHandle)) { ::close(fd); error = "Cannot open file"; return {}; }
    const auto bytes = file.read(limit + 1);
    if (bytes.size() > limit || bytes.size() != st.st_size) { error = "File changed or exceeds size limit"; return {}; }
    return bytes;
}

bool validPermissionArray(const QJsonValue &v, const QJsonArray &requested = QJsonArray{SystemPermission})
{
    if (!v.isArray() || v.toArray().size() > 1) return false;
    QSet<QString> seen;
    for (const auto &p : v.toArray()) {
        if (!p.isString() || !requested.contains(p) || seen.contains(p.toString())) return false;
        seen.insert(p.toString());
    }
    return true;
}
QString origin(const QString &kind, const QString &source, const QString &identity)
{ return digest((kind + "\n" + source + "\n" + identity).toUtf8()); }
QJsonObject schemaFor(const QJsonArray &schema, const QString &key)
{ for (const auto &entry : schema) if (entry.toObject().value("key").toString() == key) return entry.toObject(); return {}; }
bool validSetting(const QJsonObject &s, const QJsonValue &value)
{
    const auto type = s.value("type").toString();
    if (type == "number") return integer(value, s.value("min").toDouble(), s.value("max").toDouble());
    if (type == "boolean") return value.isBool();
    if (type == "string") return text(value, s.value("maxLength").toInt());
    return false;
}
bool validateSettingsSchema(const QJsonValue &v)
{
    if (!v.isArray() || v.toArray().size() > 16) return false;
    QSet<QString> keys;
    for (const auto &value : v.toArray()) {
        if (!value.isObject()) return false;
        const auto s = value.toObject(); const auto key = s.value("key").toString(), type = s.value("type").toString();
        QStringList required{"key", "label", "type", "default"};
        if (type == "number") required << "min" << "max";
        else if (type == "string") required << "maxLength";
        else if (type != "boolean") return false;
        if (!fields(s, required) || !identifier(s.value("key")) || keys.contains(key) || !text(s.value("label"), 120, false)) return false;
        if (type == "number" && (!integer(s.value("min")) || !integer(s.value("max")) || s.value("min").toDouble() > s.value("max").toDouble())) return false;
        if (type == "string" && !integer(s.value("maxLength"), 1, 512)) return false;
        if (!validSetting(s, s.value("default"))) return false;
        keys.insert(key);
    }
    return true;
}
bool validAction(const QJsonObject &a, const QJsonArray &schema)
{
    const auto s = schemaFor(schema, a.value("key").toString());
    if (s.isEmpty()) return false;
    const auto type = a.value("type").toString();
    if (type == "toggle") return fields(a, {"type", "key"}) && s.value("type") == "boolean";
    if (type == "increment") return fields(a, {"type", "key", "delta"}) && s.value("type") == "number" && integer(a.value("delta")) && a.value("delta").toDouble() != 0;
    if (type == "set") return fields(a, {"type", "key", "value"}) && validSetting(s, a.value("value"));
    return false;
}
const QStringList SystemFields{"memoryTotalMiB", "memoryUsedMiB", "memoryUsedPercent", "uptimeSeconds"};
bool validateView(const QJsonValue &v, const QJsonArray &schema, const QJsonArray &permissions, QSet<QString> &ids, int depth)
{
    if (!v.isObject() || depth > 8 || ids.size() >= 64) return false;
    const auto n = v.toObject(); const auto id = n.value("id").toString(), type = n.value("type").toString();
    if (!identifier(n.value("id")) || ids.contains(id)) return false;
    ids.insert(id);
    if (type == "row" || type == "column") {
        if (!fields(n, {"id", "type", "children"}) || !n.value("children").isArray() || n.value("children").toArray().size() > 16) return false;
        for (const auto &child : n.value("children").toArray()) if (!validateView(child, schema, permissions, ids, depth + 1)) return false;
        return true;
    }
    if (type == "text") return fields(n, {"id", "type", "text"}) && text(n.value("text"), 1024);
    if (type == "button") return fields(n, {"id", "type", "text", "action"}) && text(n.value("text"), 120, false)
        && n.value("action").isObject() && validAction(n.value("action").toObject(), schema);
    if (type != "value" || !fields(n, {"id", "type", "binding"}, {"label", "suffix"}) || !text(n.value("binding"), 80, false)
        || (n.contains("label") && !text(n.value("label"), 120)) || (n.contains("suffix") && !text(n.value("suffix"), 32))) return false;
    const auto binding = n.value("binding").toString();
    return (binding.startsWith("settings.") && !schemaFor(schema, binding.mid(9)).isEmpty())
        || (binding.startsWith("system.") && SystemFields.contains(binding.mid(7)) && permissions.contains(SystemPermission));
}
QString validateManifest(const QJsonObject &m)
{
    if (!fields(m, {"id", "name", "description", "author", "version", "apiVersion", "permissions", "widgets"}, {"license"})
        || !pluginId(m.value("id")) || !text(m.value("name"), 120, false) || !text(m.value("description"), 1024)
        || !text(m.value("author"), 160, false) || !text(m.value("version"), 40, false)
        || !matches(m.value("version").toString(), "^(0|[1-9][0-9]{0,5})\\.(0|[1-9][0-9]{0,5})\\.(0|[1-9][0-9]{0,5})$")
        || !integer(m.value("apiVersion"), 1, 1) || !validPermissionArray(m.value("permissions"))
        || (m.contains("license") && !text(m.value("license"), 120, false)) || !m.value("widgets").isArray()
        || m.value("widgets").toArray().isEmpty() || m.value("widgets").toArray().size() > 8)
        return "Invalid plugin identity, metadata, API version or permissions";
    QSet<QString> widgetIds;
    for (const auto &v : m.value("widgets").toArray()) {
        if (!v.isObject()) return "Invalid widget";
        const auto w = v.toObject();
        if (!fields(w, {"id", "name", "description", "sizes", "multiInstance", "settings", "view"})
            || !identifier(w.value("id")) || widgetIds.contains(w.value("id").toString()) || !text(w.value("name"), 120, false)
            || !text(w.value("description"), 1024) || !w.value("multiInstance").isBool()
            || !w.value("sizes").isArray() || w.value("sizes").toArray().isEmpty() || w.value("sizes").toArray().size() > 3
            || !validateSettingsSchema(w.value("settings"))) return "Invalid widget metadata or settings schema";
        QSet<QString> sizes;
        for (const auto &size : w.value("sizes").toArray()) {
            if (!size.isString() || !QStringList{"small", "medium", "large"}.contains(size.toString()) || sizes.contains(size.toString())) return "Invalid widget sizes";
            sizes.insert(size.toString());
        }
        QSet<QString> nodes;
        if (QJsonDocument(w.value("view").toObject()).toJson(QJsonDocument::Compact).size() > 16384
            || !validateView(w.value("view"), w.value("settings").toArray(), m.value("permissions").toArray(), nodes, 1)) return "Invalid or oversized view or action";
        widgetIds.insert(w.value("id").toString());
    }
    return {};
}
QJsonObject widget(const QJsonObject &manifest, const QString &id)
{ for (const auto &v : manifest.value("widgets").toArray()) if (v.toObject().value("id").toString() == id) return v.toObject(); return {}; }
bool mergeSettings(const QJsonArray &schema, const QJsonObject &current, const QJsonObject &patch, QJsonObject &result)
{
    result = {};
    for (const auto &value : schema) {
        const auto s = value.toObject(); const auto key = s.value("key").toString();
        const auto v = patch.contains(key) ? patch.value(key) : current.value(key).isUndefined() ? s.value("default") : current.value(key);
        if (!validSetting(s, v)) return false;
        result.insert(key, v);
    }
    for (auto it = current.begin(); it != current.end(); ++it) if (schemaFor(schema, it.key()).isEmpty()) return false;
    for (auto it = patch.begin(); it != patch.end(); ++it) if (schemaFor(schema, it.key()).isEmpty()) return false;
    return true;
}
QJsonObject findAction(const QJsonObject &view, const QString &id)
{
    if (view.value("id") == id && view.value("type") == "button") return view.value("action").toObject();
    for (const auto &v : view.value("children").toArray()) { const auto result = findAction(v.toObject(), id); if (!result.isEmpty()) return result; }
    return {};
}
QJsonObject systemSummary()
{
    struct sysinfo info{};
    if (::sysinfo(&info) != 0) return {};
    const double total = double(info.totalram) * double(info.mem_unit), free = double(info.freeram) * double(info.mem_unit);
    const double used = std::max(0.0, total - free - double(info.bufferram) * double(info.mem_unit));
    return {{"memoryTotalMiB", std::floor(total / 1048576)}, {"memoryUsedMiB", std::floor(used / 1048576)},
            {"memoryUsedPercent", total > 0 ? std::round(100 * used / total) : 0}, {"uptimeSeconds", double(info.uptime)}};
}
QJsonObject resolveView(QJsonObject n, const QJsonObject &settings, const QJsonObject &system, bool granted)
{
    const auto type = n.value("type").toString();
    if (type == "column" || type == "row") {
        QJsonArray children;
        for (const auto &v : n.value("children").toArray()) children.append(resolveView(v.toObject(), settings, system, granted));
        n["children"] = children;
    } else if (type == "value") {
        const auto binding = n.take("binding").toString();
        const auto value = binding.startsWith("settings.") ? settings.value(binding.mid(9)) : granted ? system.value(binding.mid(7)) : QJsonValue();
        const bool available = !value.isUndefined() && !value.isNull();
        n["available"] = available;
        n["value"] = !available ? QStringLiteral("—") : value.isString() ? value.toString() : value.isBool() ? (value.toBool() ? QStringLiteral("true") : QStringLiteral("false")) : QString::number(value.toDouble(), 'f', 0);
    } else if (type == "button") { n.remove("action"); n["actionId"] = n.value("id"); }
    return n;
}
QString localized(const QVariant &v)
{
    if (v.metaType().id() == QMetaType::QString) return v.toString();
    const auto map = v.toMap(); return map.value("en", map.isEmpty() ? QVariant{} : map.constBegin().value()).toString();
}
QString sourceIdentity(const QVariantMap &entry, const QVariantList &sources)
{
    for (const auto &v : sources) {
        const auto s = v.toMap();
        if (s.value("id") == entry.value("sourceId"))
            return digest(QJsonDocument::fromVariant(QVariantMap{{"id", s.value("id")}, {"repository", s.value("repository")}, {"fingerprint", s.value("fingerprint")}}).toJson(QJsonDocument::Compact));
    }
    return {};
}
} // namespace

struct DeclarativePlugins::Store {
    QJsonObject state;
    QHash<QString, QJsonObject> plans;
    QVariantList entries, sources;
    qint64 catalogReadAt = 0;
    QString root, error, catalogError, catalogContext;

    Store() : root(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/kos/plugins") {}
    bool load();
    void expirePlans(const QHash<QString, std::shared_ptr<std::atomic_bool>> &connections) {
        const auto now = QDateTime::currentDateTimeUtc();
        for (auto it = plans.begin(); it != plans.end();) {
            const auto token = connections.value(it.value().value("owner").toString());
            if (!token || token->load() || QDateTime::fromString(it.value().value("public").toObject().value("expiresAt").toString(), Qt::ISODate) <= now)
                it = plans.erase(it);
            else ++it;
        }
    }
    bool save(const QJsonObject &next);
    void catalog(bool force = false);
    bool retainRevocations();
    QJsonObject examples() const;
    QString availability(const QJsonObject &record) const;
    QJsonObject snapshot();
    Outcome execute(const QString &operation, const QJsonObject &payload, const QString &owner, const std::shared_ptr<std::atomic_bool> &cancelled);
    Outcome prepare(const QJsonObject &payload, const QString &owner, const std::shared_ptr<std::atomic_bool> &cancelled);
    Outcome mutate(const QString &operation, const QJsonObject &payload, const QString &owner);
};

bool DeclarativePlugins::Store::load()
{
    error.clear();
    if (!QDir::isAbsolutePath(root) || root.contains(QChar::Null) || root.size() > 4096 || QDir::cleanPath(root) != root) { error = "Invalid plugin storage location"; return false; }
    // Pin each ancestor during creation; refuse symlinked XDG storage directories.
    int fd = ::open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    for (const auto &part : root.split('/', Qt::SkipEmptyParts)) {
        const auto name = QFile::encodeName(part);
        if (fd < 0) break;
        int next = ::openat(fd, name.constData(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (next < 0 && errno == ENOENT && ::mkdirat(fd, name.constData(), 0700) == 0)
            next = ::openat(fd, name.constData(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        ::close(fd); fd = next;
    }
    struct stat st{};
    if (fd < 0 || ::fstat(fd, &st) != 0 || st.st_uid != ::getuid() || ::fchmod(fd, 0700) != 0) {
        if (fd >= 0) ::close(fd); error = "Plugin storage must be a private current-user directory without symlinks"; return false;
    }
    ::close(fd);
    const auto path = root + "/state.json";
    if (!QFileInfo::exists(path) && !QFileInfo(path).isSymLink()) {
        state = {{"schemaVersion", 1}, {"revision", 0}, {"plugins", QJsonObject{}}, {"instances", QJsonObject{}}, {"retained", QJsonObject{}}};
        return true;
    }
    const auto data = readLocal(path, MaxStateBytes, error);
    auto candidate = error.isEmpty() ? parse(data, MaxStateBytes, error, true) : QJsonObject{};
    if (!error.isEmpty()) return false;
    if (!fields(candidate, {"schemaVersion", "revision", "plugins", "instances", "retained"})
        || !integer(candidate.value("schemaVersion"), 1, 1) || !integer(candidate.value("revision"), 0, 9007199254740000.0)
        || !candidate.value("plugins").isObject() || !candidate.value("instances").isObject() || !candidate.value("retained").isObject()
        || candidate.value("plugins").toObject().size() > MaxPlugins
        || candidate.value("instances").toObject().size() + candidate.value("retained").toObject().size() > MaxInstances) {
        error = "Invalid plugin state; restore or move the state file before continuing"; return false;
    }
    const auto plugins = candidate.value("plugins").toObject();
    for (auto it = plugins.begin(); it != plugins.end(); ++it) {
        const auto r = it.value().toObject(), m = r.value("manifest").toObject();
        if (m.value("id") != it.key() || !validateManifest(m).isEmpty() || !r.value("enabled").isBool()
            || !validPermissionArray(r.value("grantedPermissions"), m.value("permissions").toArray())
            || !QStringList{"example", "local", "catalog"}.contains(r.value("sourceKind").toString())) {
            error = "Invalid installed plugin record"; return false;
        }
    }
    for (const auto &group : {QStringLiteral("instances"), QStringLiteral("retained")}) {
        const auto instances = candidate.value(group).toObject();
        for (auto it = instances.begin(); it != instances.end(); ++it) {
            const auto i = it.value().toObject();
            if (!matches(it.key(), "^plugin:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
                || !fields(i, {"id", "pluginId", "widgetId", "size", "settings"}, {"retainedOrigin"}) || i.value("id") != it.key()
                || !pluginId(i.value("pluginId")) || !identifier(i.value("widgetId")) || !i.value("settings").isObject()
                || !QStringList{"small", "medium", "large"}.contains(i.value("size").toString())) { error = "Invalid plugin instance record"; return false; }
            if (group == "instances") {
                const auto w = widget(plugins.value(i.value("pluginId").toString()).toObject().value("manifest").toObject(), i.value("widgetId").toString());
                QJsonObject settings;
                if (w.isEmpty() || !w.value("sizes").toArray().contains(i.value("size"))
                    || !mergeSettings(w.value("settings").toArray(), i.value("settings").toObject(), {}, settings)) { error = "Incompatible persisted instance"; return false; }
            }
        }
    }
    state = candidate;
    return true;
}
bool DeclarativePlugins::Store::save(const QJsonObject &next)
{
    const auto bytes = QJsonDocument(next).toJson(QJsonDocument::Compact);
    qsizetype packageBytes = 0;
    for (const auto &v : next.value("plugins").toObject())
        packageBytes += QJsonDocument(v.toObject().value("manifest").toObject()).toJson(QJsonDocument::Compact).size();
    if (bytes.size() > MaxStateBytes || packageBytes > 1024 * 1024) { error = "Plugin storage quota exceeded (1 MiB total installed manifests)"; return false; }
    QSaveFile file(root + "/state.json");
    file.setDirectWriteFallback(false);
    if (!file.open(QIODevice::WriteOnly) || !file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner)
        || file.write(bytes) != bytes.size() || !file.commit()) { error = "Cannot atomically persist plugin state"; return false; }
    state = next; return true;
}
void DeclarativePlugins::Store::catalog(bool force)
{
    const auto now = QDateTime::currentMSecsSinceEpoch();
    const auto context = AppCatalog::contextToken();
    if (!force && context == catalogContext && catalogReadAt > 0 && now - catalogReadAt < 30000) return;
    entries = AppCatalog::apps(); sources = AppCatalog::sources(); catalogReadAt = now; catalogContext = context;
    catalogError.clear();
    for (const auto &v : sources) {
        const auto s = v.toMap(); const auto e = s.value("error").toString();
        if (!e.isEmpty()) { catalogError = e; break; }
    }
}
bool DeclarativePlugins::Store::retainRevocations()
{
    if (AppCatalog::testMode()) return true;
    auto records = state.value("plugins").toObject(); bool changed = false;
    for (const auto &v : entries) {
        const auto e = v.toMap(); const auto id = e.value("appId").toString(); auto r = records.value(id).toObject();
        if (e.value("status") != "revoked" || r.isEmpty() || r.value("sourceKind") != "catalog"
            || r.value("sourceId").toString() != e.value("sourceId").toString()
            || sourceIdentity(e, sources) != r.value("sourceIdentity").toString() || r.value("revoked").toBool()) continue;
        r["revoked"] = true; r["enabled"] = false; r["grantedPermissions"] = QJsonArray{};
        records[id] = r; changed = true;
    }
    if (!changed) return true;
    auto next = state; next["plugins"] = records; next["revision"] = state.value("revision").toDouble() + 1;
    return save(next);
}
QJsonObject DeclarativePlugins::Store::examples() const
{
    QJsonObject result;
    for (const auto &name : {QStringLiteral("counter"), QStringLiteral("system")}) {
        QFile f(":/kos/plugins/examples/" + name + ".json");
        if (!f.open(QIODevice::ReadOnly)) continue;
        QString e; const auto m = parse(f.read(MaxPackageBytes + 1), MaxPackageBytes, e);
        if (e.isEmpty() && validateManifest(m).isEmpty()) result.insert(m.value("id").toString(), m);
    }
    return result;
}
QString DeclarativePlugins::Store::availability(const QJsonObject &record) const
{
    if (record.value("revoked").toBool()) return "Plugin was revoked by its catalog; a newly approved installation is required";
    if (record.value("sourceKind") != "catalog") return {};
    if (AppCatalog::testMode()) return "Signed marketplace plugins are paused while application catalog test mode is active";
    for (const auto &v : entries) {
        const auto entry = v.toMap();
        if (entry.value("appId").toString() != record.value("manifest").toObject().value("id").toString()) continue;
        if (entry.value("status") == "revoked") return "Plugin was revoked by its catalog";
        if (entry.value("conflict").toBool()) return "Plugin identity conflicts across sources";
        if (entry.value("sourceId").toString() != record.value("sourceId").toString()) return "Plugin source identity changed";
        const auto identity = sourceIdentity(entry, sources);
        if (!identity.isEmpty() && identity != record.value("sourceIdentity").toString()) return "Plugin signing source changed";
    }
    return {};
}
QJsonObject DeclarativePlugins::Store::snapshot()
{
    QJsonArray plugins, instances, catalogRows;
    const auto records = state.value("plugins").toObject();
    for (auto it = records.begin(); it != records.end(); ++it) {
        const auto r = it.value().toObject(); auto p = r.value("manifest").toObject();
        const auto blocked = availability(r);
        for (const auto &key : {"enabled", "grantedPermissions", "sourceId", "sourceKind"}) p[key] = r.value(key);
        p["status"] = !blocked.isEmpty() ? "unavailable" : r.value("enabled").toBool() ? "enabled" : "disabled";
        p["message"] = blocked;
        plugins.append(p);
    }
    QJsonObject system;
    const auto storedInstances = state.value("instances").toObject();
    for (auto it = storedInstances.begin(); it != storedInstances.end(); ++it) {
        auto i = it.value().toObject(); const auto r = records.value(i.value("pluginId").toString()).toObject();
        const auto m = r.value("manifest").toObject(), w = widget(m, i.value("widgetId").toString());
        const bool granted = r.value("grantedPermissions").toArray().contains(SystemPermission);
        const bool required = m.value("permissions").toArray().contains(SystemPermission) && !granted;
        const auto blocked = availability(r);
        const bool enabled = r.value("enabled").toBool();
        i["name"] = w.value("name"); i["sizes"] = w.value("sizes"); i["settingsSchema"] = w.value("settings");
        i["state"] = !blocked.isEmpty() ? "unavailable" : !enabled ? "disabled" : required ? "permission-required" : "ready";
        i["message"] = !blocked.isEmpty() ? blocked : !enabled ? "Plugin is disabled" : required ? "System summary permission is not granted" : "";
        if (enabled && blocked.isEmpty()) {
            if (granted && system.isEmpty()) system = systemSummary();
            i["view"] = resolveView(w.value("view").toObject(), i.value("settings").toObject(), system, granted);
        } else i["view"] = QJsonObject{};
        instances.append(i);
    }
    const auto samples = examples();
    for (auto it = samples.begin(); it != samples.end(); ++it) {
        auto row = it.value().toObject();
        row["sourceId"] = "examples"; row["sourceKind"] = "example";
        row["installed"] = records.contains(it.key()); row["available"] = true; row["status"] = "example"; row["error"] = "";
        catalogRows.append(row);
    }
    bool catalogTruncated = false;
    for (const auto &v : entries) {
        const auto e = v.toMap(); if (e.value("format") != Format) continue;
        if (catalogRows.size() >= 256) { catalogTruncated = true; continue; }
        catalogRows.append(QJsonObject{{"id", e.value("appId").toString()}, {"sourceId", e.value("sourceId").toString()}, {"sourceKind", "catalog"},
            {"name", localized(e.value("name"))}, {"description", localized(e.value("description"))}, {"author", e.value("repository").toString()},
            {"version", e.value("release").toMap().value("version").toString()}, {"installed", records.contains(e.value("appId").toString())},
            {"available", e.value("active").toBool() && !e.value("conflict").toBool() && !AppCatalog::testMode()},
            {"status", e.value("status", "active").toString()}, {"error", e.value("error").toString()}});
    }
    QJsonObject result{{"revision", state.value("revision")}, {"plugins", plugins}, {"instances", instances}, {"catalog", catalogRows},
            {"sources", QJsonArray::fromVariantList(sources)}, {"error", !error.isEmpty() ? error : catalogTruncated ? QStringLiteral("Catalog display limit reached (256 entries)") : catalogError}};
    // Keep comfortably below the platform/client 8 MiB reply cap, including plans.
    // Resource exhaustion hides views rather than serializing an oversized frame.
    if (QJsonDocument(result).toJson(QJsonDocument::Compact).size() > 6 * 1024 * 1024) {
        QJsonArray boundedInstances;
        for (const auto &v : instances) {
            auto instance = v.toObject(); instance["view"] = QJsonObject{};
            instance["state"] = "unavailable"; instance["message"] = "Aggregate plugin view budget exceeded";
            boundedInstances.append(instance);
        }
        result["instances"] = boundedInstances;
        result["error"] = "Aggregate plugin view budget exceeded; reduce installed widgets";
    }
    if (QJsonDocument(result).toJson(QJsonDocument::Compact).size() > 6 * 1024 * 1024)
        // Never send a successful empty inventory: clients would interpret it as
        // removal of every instance and could discard their persisted placements.
        return {{"snapshotError", "Plugin snapshot exceeds output budget. Existing instances were retained; an already committed change may have succeeded. Reduce installed data and refresh."}};
    return result;
}

Outcome DeclarativePlugins::Store::prepare(const QJsonObject &payload, const QString &owner, const std::shared_ptr<std::atomic_bool> &cancelled)
{
    QByteArray bytes; QString kind, source, sourceHash, entryHash;
    QJsonObject manifest;
    if (payload.contains("path")) {
        if (!fields(payload, {"path"}) || !text(payload.value("path"), 4096, false)) return fail("invalid-payload", "Choose a local JSON file or a catalog identity");
        QString e; bytes = readLocal(payload.value("path").toString(), MaxPackageBytes, e);
        if (!e.isEmpty()) return fail("invalid-package", e);
        kind = "local"; source = "local";
    } else {
        if (!fields(payload, {"sourceId", "pluginId"}) || !text(payload.value("sourceId"), 80, false) || !pluginId(payload.value("pluginId")))
            return fail("invalid-payload", "A source and plugin identity are required");
        source = payload.value("sourceId").toString();
        const auto id = payload.value("pluginId").toString();
        if (source == "examples") {
            manifest = examples().value(id).toObject();
            if (manifest.isEmpty()) return fail("not-found", "Unknown bundled example");
            kind = "example"; bytes = QJsonDocument(manifest).toJson(QJsonDocument::Compact);
        } else {
            if (AppCatalog::testMode()) return fail("catalog-test-mode", "Plugin installation requires the normal approved catalog");
            catalog(true);
            QVariantMap entry;
            for (const auto &v : entries) if (v.toMap().value("appId").toString() == id && v.toMap().value("sourceId").toString() == source) entry = v.toMap();
            if (entry.isEmpty() || entry.value("format") != Format || !entry.value("active").toBool() || entry.value("conflict").toBool())
                return fail("untrusted-catalog", "Plugin is not active in the selected verified catalog; refresh sources first");
            sourceHash = sourceIdentity(entry, sources);
            if (sourceHash.isEmpty()) return fail("untrusted-catalog", "Catalog signing source is unavailable");
            const auto release = entry.value("release").toMap();
            const auto descriptorBytes = QByteArray::fromBase64(release.value("manifest").toByteArray());
            QString e; const auto descriptor = parse(descriptorBytes, MaxPackageBytes, e);
            const auto artifact = descriptor.value("plugin").toObject();
            if (!e.isEmpty() || descriptor.value("appId").toString() != id || descriptor.value("version").toString() != release.value("version").toString()
                || release.value("tag").toString() != "v" + release.value("version").toString()
                || !fields(descriptor, {"schemaVersion", "appId", "version", "plugin"}) || !integer(descriptor.value("schemaVersion"), 2, 2)
                || !fields(artifact, {"asset", "sha256", "size"}) || !text(artifact.value("asset"), 120, false)
                || !matches(artifact.value("asset").toString(), "^[A-Za-z0-9][A-Za-z0-9._-]{0,110}\\.json$")
                || !matches(artifact.value("sha256").toString(), "^[0-9a-f]{64}$") || !integer(artifact.value("size"), 1, MaxPackageBytes))
                return fail("invalid-release", "Invalid approved plugin release descriptor");
            const auto publisher = entry.value("publisher").toMap();
            if (!publisher.isEmpty() && !AppCatalog::verify(descriptorBytes, QByteArray::fromBase64(release.value("signature").toByteArray()),
                    QByteArray::fromBase64(publisher.value("publicKey").toByteArray()), publisher.value("fingerprint").toString()))
                return fail("signature-failed", "Plugin publisher signature is invalid");
            const auto repository = entry.value("repository").toString();
            const QUrl url("https://github.com/" + repository + "/releases/download/" + release.value("tag").toString() + "/" + artifact.value("asset").toString());
            bytes = AppCatalog::fetch(url, repository, MaxPackageBytes, &e, [cancelled] { return cancelled->load(); });
            if (!e.isEmpty()) return fail("download-failed", e);
            if (bytes.size() != artifact.value("size").toInt() || digest(bytes) != artifact.value("sha256").toString()) return fail("digest-mismatch", "Downloaded plugin does not match its approved size and SHA-256");
            manifest = parse(bytes, MaxPackageBytes, e);
            if (!e.isEmpty() || manifest.value("id").toString() != id || manifest.value("version").toString() != release.value("version").toString())
                return fail("identity-mismatch", "Plugin identity/version differs from the approved catalog release");
            entryHash = AppCatalog::entryDigest(entry); kind = "catalog";
        }
    }
    QString e;
    if (manifest.isEmpty()) manifest = parse(bytes, MaxPackageBytes, e);
    if (!e.isEmpty()) return fail("invalid-package", e);
    e = validateManifest(manifest);
    if (!e.isEmpty()) return fail("invalid-package", e);
    const auto id = manifest.value("id").toString();
    const auto existing = state.value("plugins").toObject().value(id).toObject();
    if (!existing.isEmpty()) {
        if (existing.value("sourceKind") != kind || existing.value("sourceId") != source
            || (kind == "catalog" && existing.value("sourceIdentity") != sourceHash)) return fail("source-conflict", "Installed plugin identity belongs to another source; uninstall it explicitly first");
        if (QVersionNumber::compare(QVersionNumber::fromString(manifest.value("version").toString()), QVersionNumber::fromString(existing.value("manifest").toObject().value("version").toString())) < 0)
            return fail("version-rollback", "A plugin update cannot downgrade the installed version");
    } else if (state.value("plugins").toObject().size() >= MaxPlugins) return fail("quota-exceeded", "At most 64 plugins may be installed");
    QJsonArray added;
    const auto previous = existing.value("grantedPermissions").toArray();
    for (const auto &p : manifest.value("permissions").toArray()) if (!previous.contains(p)) added.append(p);
    const auto planId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    const auto expires = QDateTime::currentDateTimeUtc().addSecs(300);
    QJsonArray warnings;
    if (kind == "local") warnings.append("Unsigned local development file. Confirm that you selected and trust this data package; data permissions remain separately controlled.");
    warnings.append("Data-only runtime: no third-party executable code, network or arbitrary files.");
    int retainedCount = 0;
    for (const auto &v : state.value("retained").toObject()) if (v.toObject().value("pluginId") == id) ++retainedCount;
    if (retainedCount > 0) warnings.append(QStringLiteral("Reinstalling restores %1 retained widget instance(s) and their settings if compatible.").arg(retainedCount));
    QJsonObject publicPlan{{"id", planId}, {"pluginId", id}, {"name", manifest.value("name")}, {"version", manifest.value("version")},
        {"previousVersion", existing.value("manifest").toObject().value("version").toString()}, {"sourceId", source}, {"sourceKind", kind},
        {"permissions", manifest.value("permissions")}, {"previousPermissions", previous}, {"addedPermissions", added}, {"requiresTrust", kind == "local"},
        {"digest", digest(bytes)}, {"expiresAt", expires.toString(Qt::ISODate)}, {"widgets", manifest.value("widgets")}, {"warnings", warnings}};
    // Only the latest plan for a given frontend is live; globally bounded memory.
    for (auto it = plans.begin(); it != plans.end();) {
        if (it.value().value("owner") == owner || QDateTime::fromString(it.value().value("public").toObject().value("expiresAt").toString(), Qt::ISODate) <= QDateTime::currentDateTimeUtc()) it = plans.erase(it); else ++it;
    }
    if (plans.size() >= 16) return fail("busy", "Too many outstanding installation plans");
    plans.insert(planId, {{"owner", owner}, {"revision", state.value("revision")}, {"manifest", manifest}, {"public", publicPlan},
                         {"sourceIdentity", sourceHash}, {"entryDigest", entryHash}});
    auto result = snapshot(); result["plan"] = publicPlan;
    return {true, result, {}, {}};
}

Outcome DeclarativePlugins::Store::mutate(const QString &operation, const QJsonObject &payload, const QString &owner)
{
    auto next = state;
    auto plugins = next.value("plugins").toObject(), instances = next.value("instances").toObject(), retained = next.value("retained").toObject();
    QString addedInstance;
    if (operation == "plugin.confirm-install") {
        if (!fields(payload, {"planId", "permissions"}, {"trustLocal"}) || !text(payload.value("planId"), 64, false)
            || (payload.contains("trustLocal") && !payload.value("trustLocal").isBool())) return fail("invalid-payload", "Invalid installation confirmation");
        const auto planId = payload.value("planId").toString(); const auto plan = plans.value(planId), pub = plan.value("public").toObject();
        if (plan.isEmpty() || plan.value("owner") != owner || plan.value("revision") != state.value("revision")
            || QDateTime::fromString(pub.value("expiresAt").toString(), Qt::ISODate) <= QDateTime::currentDateTimeUtc())
            return fail("stale-plan", "Installation plan expired, changed or belongs to another connection; prepare again");
        const auto manifest = plan.value("manifest").toObject(); const auto id = manifest.value("id").toString();
        if (!validPermissionArray(payload.value("permissions"), manifest.value("permissions").toArray())) return fail("invalid-permissions", "Only permissions requested by this plugin can be granted");
        if (pub.value("requiresTrust").toBool() && !payload.value("trustLocal").toBool()) return fail("trust-required", "Explicit confirmation of the selected unsigned local file is required");
        if (pub.value("sourceKind") == "catalog") {
            catalog(true); QVariantMap entry;
            for (const auto &v : entries) if (v.toMap().value("appId").toString() == id && v.toMap().value("sourceId").toString() == pub.value("sourceId").toString()) entry = v.toMap();
            if (AppCatalog::testMode() || entry.isEmpty() || !entry.value("active").toBool() || entry.value("conflict").toBool()
                || AppCatalog::entryDigest(entry) != plan.value("entryDigest").toString() || sourceIdentity(entry, sources) != plan.value("sourceIdentity").toString())
                return fail("source-changed", "Approved catalog or signing source changed; prepare a new plan");
        }
        // Validate every existing/retained configuration before switching packages.
        QHash<QString, int> counts;
        for (const auto &group : {instances, retained}) {
            for (auto it = group.begin(); it != group.end(); ++it) {
                auto i = it.value().toObject(); if (i.value("pluginId") != id) continue;
                if (i.contains("retainedOrigin") && i.value("retainedOrigin").toString()
                    != origin(pub.value("sourceKind").toString(), pub.value("sourceId").toString(), plan.value("sourceIdentity").toString()))
                    return fail("retained-source-conflict", "Retained instance settings belong to another source; delete retained data explicitly before changing origin");
                i.remove("retainedOrigin");
                const auto w = widget(manifest, i.value("widgetId").toString()); QJsonObject settings;
                if (w.isEmpty() || !w.value("sizes").toArray().contains(i.value("size"))
                    || !mergeSettings(w.value("settings").toArray(), i.value("settings").toObject(), {}, settings)
                    || (++counts[i.value("widgetId").toString()] > 1 && !w.value("multiInstance").toBool()))
                    return fail("incompatible-settings", "Update cannot preserve existing instances; old package and settings were kept");
                i["settings"] = settings; instances[it.key()] = i; retained.remove(it.key());
            }
        }
        const auto old = plugins.value(id).toObject();
        plugins[id] = QJsonObject{{"manifest", manifest}, {"enabled", old.isEmpty() ? true : old.value("enabled").toBool()},
            {"grantedPermissions", payload.value("permissions")}, {"sourceKind", pub.value("sourceKind")}, {"sourceId", pub.value("sourceId")},
            {"sourceIdentity", plan.value("sourceIdentity")}, {"digest", pub.value("digest")}, {"installedAt", QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}};
        plans.remove(planId);
    } else if (operation == "plugin.set-enabled" || operation == "plugin.set-permissions" || operation == "plugin.uninstall") {
        const auto field = operation == "plugin.set-enabled" ? QStringLiteral("enabled") : operation == "plugin.set-permissions" ? QStringLiteral("permissions") : QStringLiteral("removeData");
        if (!fields(payload, {"pluginId", field}) || !pluginId(payload.value("pluginId"))) return fail("invalid-payload", "Invalid plugin mutation");
        const auto id = payload.value("pluginId").toString(); auto p = plugins.value(id).toObject();
        if (p.isEmpty() && !(operation == "plugin.uninstall" && payload.value("removeData").isBool() && payload.value("removeData").toBool()))
            return fail("not-found", "Plugin is not installed");
        if (operation == "plugin.set-permissions") {
            if (!validPermissionArray(payload.value(field), p.value("manifest").toObject().value("permissions").toArray())) return fail("invalid-permissions", "Unknown or unrequested permission");
            p["grantedPermissions"] = payload.value(field); plugins[id] = p;
        } else {
            if (!payload.value(field).isBool()) return fail("invalid-payload", "A boolean is required");
            if (operation == "plugin.set-enabled") {
                if (payload.value(field).toBool() && !availability(p).isEmpty()) return fail("plugin-unavailable", availability(p));
                p["enabled"] = payload.value(field); plugins[id] = p;
            } else {
                for (auto it = instances.begin(); it != instances.end();) {
                    if (it.value().toObject().value("pluginId") == id) {
                        if (!payload.value("removeData").toBool()) {
                            auto saved = it.value().toObject();
                            saved["retainedOrigin"] = origin(p.value("sourceKind").toString(), p.value("sourceId").toString(), p.value("sourceIdentity").toString());
                            retained[it.key()] = saved;
                        }
                        it = instances.erase(it);
                    } else ++it;
                }
                if (payload.value("removeData").toBool()) for (auto it = retained.begin(); it != retained.end();) {
                    if (it.value().toObject().value("pluginId") == id) it = retained.erase(it); else ++it;
                }
                plugins.remove(id);
            }
        }
    } else if (operation == "plugin.instance-add") {
        if (!fields(payload, {"pluginId", "widgetId"}, {"settings", "size"}) || !pluginId(payload.value("pluginId")) || !identifier(payload.value("widgetId"))
            || (payload.contains("settings") && !payload.value("settings").isObject())) return fail("invalid-payload", "Invalid instance creation");
        const auto id = payload.value("pluginId").toString(); const auto p = plugins.value(id).toObject();
        const auto w = widget(p.value("manifest").toObject(), payload.value("widgetId").toString());
        if (p.isEmpty() || w.isEmpty()) return fail("not-found", "Plugin or widget type was not found");
        if (!p.value("enabled").toBool() || !availability(p).isEmpty()) return fail("plugin-unavailable", "Enable an available plugin before adding its widget");
        if (instances.size() + retained.size() >= MaxInstances) return fail("quota-exceeded", "At most 128 active or retained instances are allowed");
        if (!w.value("multiInstance").toBool()) for (const auto &v : instances) {
            const auto i = v.toObject(); if (i.value("pluginId") == id && i.value("widgetId") == payload.value("widgetId")) return fail("single-instance", "This widget supports one instance");
        }
        const auto sizes = w.value("sizes").toArray();
        const auto size = payload.contains("size") ? payload.value("size") : sizes.contains("medium") ? QJsonValue("medium") : sizes.first();
        QJsonObject settings;
        if (!sizes.contains(size) || !mergeSettings(w.value("settings").toArray(), {}, payload.value("settings").toObject(), settings)) return fail("invalid-settings", "Unsupported size or settings");
        addedInstance = "plugin:" + QUuid::createUuid().toString(QUuid::WithoutBraces);
        instances[addedInstance] = QJsonObject{{"id", addedInstance}, {"pluginId", id}, {"widgetId", payload.value("widgetId")}, {"size", size}, {"settings", settings}};
    } else if (operation == "plugin.instance-remove" || operation == "plugin.instance-configure" || operation == "plugin.instance-action") {
        if (!text(payload.value("instanceId"), 64, false)) return fail("invalid-payload", "An instance identity is required");
        const auto id = payload.value("instanceId").toString(); auto i = instances.value(id).toObject();
        if (i.isEmpty()) return fail("not-found", "Instance was not found");
        if (operation == "plugin.instance-remove") {
            if (!fields(payload, {"instanceId"})) return fail("invalid-payload", "Unknown removal field");
            instances.remove(id);
        } else {
            const auto p = plugins.value(i.value("pluginId").toString()).toObject(), w = widget(p.value("manifest").toObject(), i.value("widgetId").toString());
            const auto schema = w.value("settings").toArray(); auto settings = i.value("settings").toObject();
            if (operation == "plugin.instance-configure") {
                if (!fields(payload, {"instanceId"}, {"settings", "size"}) || (payload.contains("settings") && !payload.value("settings").isObject())) return fail("invalid-payload", "Invalid configuration patch");
                QJsonObject merged;
                if (!mergeSettings(schema, settings, payload.value("settings").toObject(), merged) || (payload.contains("size") && !w.value("sizes").toArray().contains(payload.value("size")))) return fail("invalid-settings", "Settings or size are outside the widget schema");
                settings = merged; if (payload.contains("size")) i["size"] = payload.value("size");
            } else {
                if (!fields(payload, {"instanceId", "actionId"}) || !identifier(payload.value("actionId"))) return fail("invalid-payload", "Invalid action identity");
                if (!p.value("enabled").toBool() || !availability(p).isEmpty()) return fail("plugin-unavailable", "Disabled or unavailable plugins cannot execute actions");
                const auto a = findAction(w.value("view").toObject(), payload.value("actionId").toString());
                if (a.isEmpty()) return fail("unknown-action", "Action is not defined by this instance's widget");
                const auto key = a.value("key").toString(), type = a.value("type").toString();
                const auto s = schemaFor(schema, key);
                if (type == "toggle") settings[key] = !settings.value(key).toBool();
                else if (type == "set") settings[key] = a.value("value");
                else if (type == "increment") settings[key] = std::clamp(settings.value(key).toDouble() + a.value("delta").toDouble(), s.value("min").toDouble(), s.value("max").toDouble());
                if (!validSetting(s, settings.value(key))) return fail("invalid-action", "Action result does not satisfy its settings schema");
            }
            i["settings"] = settings; instances[id] = i;
        }
    } else return fail("unknown-operation", "Unknown declarative plugin operation");
    next["plugins"] = plugins; next["instances"] = instances; next["retained"] = retained;
    next["revision"] = next.value("revision").toDouble() + 1;
    if (!save(next)) return fail("storage-error", error);
    plans.clear();
    auto result = snapshot(); if (!addedInstance.isEmpty()) result["instanceId"] = addedInstance;
    return {true, result, {}, {}};
}

Outcome DeclarativePlugins::Store::execute(const QString &operation, const QJsonObject &payload, const QString &owner, const std::shared_ptr<std::atomic_bool> &cancelled)
{
    int nodes = 0;
    if (!bounded(payload, 0, nodes, 512, 4096)) return fail("invalid-payload", "Plugin request exceeds structural limits");
    if (!load()) return fail("storage-error", error);
    QLockFile lock(root + "/state.lock");
    if (!lock.tryLock(0)) return fail("busy", "Plugin state is being changed by another process");
    // Load under the cross-process mutation lock to avoid stale writes.
    if (!load()) return fail("storage-error", error);
    if (cancelled->load()) return fail("cancelled", "Requesting frontend disconnected");
    catalog();
    if (!retainRevocations()) return fail("storage-error", error);
    if (operation == "plugin.snapshot") {
        if (!payload.isEmpty()) return fail("invalid-payload", "Snapshot takes no arguments");
        return {true, snapshot(), {}, {}};
    }
    if (operation == "plugin.refresh-catalog") {
        if (!payload.isEmpty()) return fail("invalid-payload", "Catalog refresh takes no arguments");
        const auto e = AppCatalog::refresh([cancelled] { return cancelled->load(); });
        catalog(true);
        if (!retainRevocations()) return fail("storage-error", error);
        if (!e.isEmpty()) catalogError = e;
        return {true, snapshot(), {}, {}};
    }
    if (operation == "plugin.prepare-install") return prepare(payload, owner, cancelled);
    return mutate(operation, payload, owner);
}

DeclarativePlugins::DeclarativePlugins(QObject *parent) : QObject(parent), m_store(std::make_shared<Store>())
{
    m_clock.start();
    auto *timer = new QTimer(this); timer->setInterval(1000);
    connect(timer, &QTimer::timeout, this, [this] {
        // Store is accessed by at most one worker; main-thread cleanup only when idle.
        if (m_busy) return;
        m_store->expirePlans(m_connections);
        for (auto it = m_connections.begin(); it != m_connections.end();) {
            if (it.value()->load()) it = m_connections.erase(it); else ++it;
        }
    });
    timer->start();
}
DeclarativePlugins::~DeclarativePlugins()
{ for (const auto &token : m_connections) token->store(true); }
void DeclarativePlugins::request(QLocalSocket *peer, const QString &operation, const QJsonObject &payload, Reply reply)
{
    if (m_busy) { reply(false, {}, "busy", "A plugin request is already running; retry shortly"); return; }
    const auto now = m_clock.elapsed();
    if (m_lastRequest.contains(peer) && now - m_lastRequest.value(peer) < 30) { reply(false, {}, "rate-limited", "Plugin requests are limited to 30 per second per frontend"); return; }
    m_lastRequest[peer] = now;
    auto owner = peer->property("kosPluginOwner").toString();
    if (owner.isEmpty()) {
        owner = QUuid::createUuid().toString(QUuid::WithoutBraces);
        peer->setProperty("kosPluginOwner", owner);
        const auto token = std::make_shared<std::atomic_bool>(false);
        m_connections.insert(owner, token);
        connect(peer, &QLocalSocket::disconnected, this, [this, owner, token] {
            token->store(true);
            if (!m_busy) m_store->expirePlans(m_connections);
        });
        connect(peer, &QObject::destroyed, this, [this, peer, token] { token->store(true); m_lastRequest.remove(peer); });
    }
    m_store->expirePlans(m_connections);
    m_busy = true;
    auto cancelled = std::make_shared<std::atomic_bool>(false);
    auto *watcher = new QFutureWatcher<Outcome>(this);
    const auto disconnected = connect(peer, &QLocalSocket::disconnected, watcher, [cancelled] { cancelled->store(true); });
    const auto destroyed = connect(this, &QObject::destroyed, [cancelled] { cancelled->store(true); });
    connect(watcher, &QFutureWatcher<Outcome>::finished, this, [this, watcher, cancelled, disconnected, destroyed, reply = std::move(reply)] {
        disconnect(disconnected); disconnect(destroyed);
        m_busy = false;
        m_store->expirePlans(m_connections);
        const auto outcome = watcher->result(); watcher->deleteLater();
        if (!outcome.ok) qWarning().noquote() << "Declarative plugin request rejected:" << outcome.code;
        if (!cancelled->load()) {
            if (outcome.ok && outcome.result.contains("snapshotError"))
                reply(false, {}, "snapshot-too-large", outcome.result.value("snapshotError").toString());
            else reply(outcome.ok, outcome.result, outcome.code, outcome.message);
        }
    });
    const auto store = m_store;
    watcher->setFuture(QtConcurrent::run([store, operation, payload, owner, cancelled] { return store->execute(operation, payload, owner, cancelled); }));
}
} // namespace KosPlatform
