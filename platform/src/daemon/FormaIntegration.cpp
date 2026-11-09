#include "FormaIntegration.h"

#include <KConfig>
#include <KConfigGroup>
#include <KService>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QLockFile>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QStringList>
#include <QVector>
#include <initializer_list>
#include <memory>
#include <utility>
#include <vector>

namespace KosPlatform {
namespace {
constexpr qint64 maximumStateBytes = 512 * 1024;
constexpr qint64 maximumConfigBytes = 1024 * 1024;
constexpr qsizetype maximumValueLength = 8192;

struct Application {
    QString role;
    QString name;
    QString desktopId;
};

const QVector<Application> &registry()
{
    static const QVector<Application> applications = {
        {QStringLiteral("finder"), QStringLiteral("Forma Finder"), QStringLiteral("io.github.egely1337.Mayonnaise.Finder.desktop")},
        {QStringLiteral("terminal"), QStringLiteral("Forma Terminal"), QStringLiteral("io.github.egely1337.Mayonnaise.Terminal.desktop")},
        {QStringLiteral("text"), QStringLiteral("Forma Text"), QStringLiteral("io.github.egely1337.Mayonnaise.TextEditor.desktop")},
        {QStringLiteral("photos"), QStringLiteral("Forma Photos"), QStringLiteral("io.github.egely1337.Mayonnaise.Photos.desktop")},
        {QStringLiteral("video"), QStringLiteral("Forma Video"), QStringLiteral("io.github.egely1337.Mayonnaise.VideoPlayer.desktop")},
        {QStringLiteral("music"), QStringLiteral("Forma Music"), QStringLiteral("io.github.egely1337.Mayonnaise.Music.desktop")},
        {QStringLiteral("calculator"), QStringLiteral("Forma Calculator"), QStringLiteral("io.github.egely1337.Mayonnaise.Calculator.desktop")},
        {QStringLiteral("taskmanager"), QStringLiteral("Forma Task Manager"), QStringLiteral("io.github.egely1337.Mayonnaise.TaskManager.desktop")},
        {QStringLiteral("screenshot"), QStringLiteral("Forma Screenshot"), QStringLiteral("io.github.skjsbsnq.Forma.Screenshot.desktop")},
        {QStringLiteral("appstore"), QStringLiteral("Forma App Store"), QStringLiteral("io.github.skjsbsnq.Forma.AppStore.desktop")},
        // The actual Mail desktop file uses Forma, not the older Mayonnaise prefix.
        {QStringLiteral("mail"), QStringLiteral("Forma Mail"), QStringLiteral("io.github.skjsbsnq.Forma.Mail.desktop")},
    };
    return applications;
}

QString desktopId(const QString &role)
{
    for (const auto &application : registry())
        if (application.role == role) return application.desktopId;
    return {};
}

struct Association {
    QString key;
    QString role;
    QString fallback;
};

// Deliberately not the union of installed desktop files' MimeType declarations.
// In particular, HTML, PDF, archives and browser protocols remain untouched.
const QVector<Association> &associations()
{
    static const QVector<Association> values = [] {
        QVector<Association> result;
        const auto add = [&result](const QString &role, std::initializer_list<const char *> keys,
                                   const QString &fallback = {}) {
            for (const auto *key : keys) result.append({QString::fromLatin1(key), role, fallback});
        };
        add(QStringLiteral("finder"), {"inode/directory"});
        add(QStringLiteral("text"), {
            "text/plain", "text/markdown", "text/x-c", "text/x-csrc", "text/x-chdr",
            "text/x-c++", "text/x-c++src", "text/x-c++hdr", "text/x-python", "text/x-shellscript",
            "application/x-shellscript", "text/x-java", "text/javascript", "application/javascript",
            "text/css", "text/x-makefile", "text/x-cmake", "text/x-qml", "text/x-rustsrc",
            "text/x-go", "application/json", "application/ld+json", "application/yaml",
            "application/x-yaml", "text/yaml", "text/x-yaml", "image/svg+xml"});
        add(QStringLiteral("photos"), {
            "image/jpeg", "image/png", "image/gif", "image/bmp", "image/x-tga", "image/x-portable-pixmap"});
        add(QStringLiteral("video"), {
            "video/mp4", "video/x-matroska", "video/webm", "video/quicktime", "video/x-msvideo",
            "video/mpeg", "video/ogg", "video/mp2t", "video/x-m4v"});
        // Both players use FFmpeg for these audio formats; Music takes precedence.
        add(QStringLiteral("music"), {
            "audio/mpeg", "audio/flac", "audio/ogg", "audio/x-wav", "audio/mp4", "audio/aac",
            "audio/x-flac", "audio/x-vorbis+ogg", "audio/opus", "audio/x-m4a", "audio/x-aiff",
            "audio/x-ape", "audio/x-wavpack"}, QStringLiteral("video"));
        add(QStringLiteral("mail"), {"x-scheme-handler/mailto"});
        // Declared by the fixed AppStore desktop entry; no generic package/file takeover.
        add(QStringLiteral("appstore"), {"x-scheme-handler/appstream"});
        return result;
    }();
    return values;
}

struct Entry {
    // File is a fixed basename, never a path taken from state JSON.
    QString file;
    QString group;
    QString key;
    bool existed = false;
    QString original;
    QString owned;
    // Retained while changing Music/Video ownership, until every sync and final save succeeds.
    QString previousOwned;
};

struct State {
    bool enabled = false;
    bool restorePending = false;
    QString pendingAction;
    QString error;
    QVector<Entry> entries;
};

QString identity(const Entry &entry)
{
    return entry.file + QLatin1Char('\n') + entry.group + QLatin1Char('\n') + entry.key;
}

bool allowedOwned(const Entry &entry, const QString &value)
{
    // Recovery-only compatibility for already journaled terminal preferences;
    // new enables never claim these keys while command execution is unsupported.
    if (entry.file == QLatin1String("kdeglobals") && entry.group == QLatin1String("General")) {
        if (entry.key == QLatin1String("TerminalApplication")) return value == QLatin1String("forma-terminal");
        if (entry.key == QLatin1String("TerminalService")) return value == desktopId(QStringLiteral("terminal"));
        return false;
    }
    if ((entry.file != QLatin1String("mimeapps.list") && entry.file != QLatin1String("kde-mimeapps.list"))
        || entry.group != QLatin1String("Default Applications")) return false;
    for (const auto &association : associations()) {
        if (association.key != entry.key) continue;
        return value == desktopId(association.role) + QLatin1Char(';')
            || (!association.fallback.isEmpty() && value == desktopId(association.fallback) + QLatin1Char(';'));
    }
    return false;
}

bool boundedString(const QJsonValue &value)
{
    return value.isString() && value.toString().size() <= maximumValueLength;
}

bool safeFile(const QString &path, qint64 maximumBytes, QString &error)
{
    const QFileInfo info(path);
    if (info.isSymLink() || (info.exists() && (!info.isFile() || info.size() > maximumBytes))) {
        error = QStringLiteral("Not a bounded regular file: ") + path;
        return false;
    }
    if (info.exists()) {
        // KConfig must not silently treat an unreadable existing file as empty.
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly)) {
            error = QStringLiteral("Cannot read file: ") + path;
            return false;
        }
        const auto bytes = file.read(maximumBytes + 1);
        if (bytes.size() > maximumBytes || file.error() != QFileDevice::NoError) {
            error = QStringLiteral("File read failed or exceeds the size limit: ") + path;
            return false;
        }
    }
    return true;
}

bool validRoots(const QString &configRoot, const QString &stateRoot, QString &error)
{
    for (const auto &root : {configRoot, stateRoot}) {
        const QFileInfo info(root);
        if (!QDir::isAbsolutePath(root) || info.isSymLink() || (info.exists() && !info.isDir())) {
            error = QStringLiteral("Invalid integration root: ") + root;
            return false;
        }
    }
    return true;
}

QString statePath(const QString &root)
{
    return QDir(root).filePath(QStringLiteral("forma-integration.json"));
}

bool loadState(const QString &root, State &state, bool &exists, QString &error)
{
    const QString path = statePath(root);
    if (!safeFile(path, maximumStateBytes, error)) return false;
    exists = QFileInfo::exists(path);
    if (!exists) return true;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        error = QStringLiteral("Cannot read integration state: ") + file.errorString();
        return false;
    }
    const auto bytes = file.read(maximumStateBytes + 1);
    if (bytes.size() > maximumStateBytes || file.error() != QFileDevice::NoError) {
        error = QStringLiteral("Integration state read failed or exceeds the size limit");
        return false;
    }
    QJsonParseError parseError;
    const auto document = QJsonDocument::fromJson(bytes, &parseError);
    const auto object = document.object();
    if (parseError.error != QJsonParseError::NoError || !document.isObject()
        || !object.value(QStringLiteral("schema")).isDouble()
        || object.value(QStringLiteral("schema")).toDouble() != 1
        || !object.value(QStringLiteral("enabled")).isBool()
        || !object.value(QStringLiteral("restorePending")).isBool()
        || !boundedString(object.value(QStringLiteral("pendingAction")))
        || !boundedString(object.value(QStringLiteral("error")))
        || !object.value(QStringLiteral("entries")).isArray()) {
        error = QStringLiteral("Invalid or unsupported integration state (expected schema 1)");
        return false;
    }
    State loaded;
    loaded.enabled = object.value(QStringLiteral("enabled")).toBool();
    loaded.restorePending = object.value(QStringLiteral("restorePending")).toBool();
    loaded.pendingAction = object.value(QStringLiteral("pendingAction")).toString();
    loaded.error = object.value(QStringLiteral("error")).toString();
    if ((loaded.restorePending && loaded.pendingAction != QLatin1String("apply")
         && loaded.pendingAction != QLatin1String("restore"))
        || (!loaded.restorePending && !loaded.pendingAction.isEmpty())) {
        error = QStringLiteral("Invalid integration recovery state");
        return false;
    }
    const auto entries = object.value(QStringLiteral("entries")).toArray();
    const qsizetype maximumEntries = associations().size() * 2 + 2;
    if (entries.size() > maximumEntries) {
        error = QStringLiteral("Too many integration backup entries");
        return false;
    }
    QSet<QString> seen;
    for (const auto &value : entries) {
        const auto row = value.toObject();
        Entry entry;
        if (!value.isObject() || !row.value(QStringLiteral("existed")).isBool()
            || !boundedString(row.value(QStringLiteral("file")))
            || !boundedString(row.value(QStringLiteral("group")))
            || !boundedString(row.value(QStringLiteral("key")))
            || !boundedString(row.value(QStringLiteral("original")))
            || !boundedString(row.value(QStringLiteral("owned")))
            || !boundedString(row.value(QStringLiteral("previousOwned")))) {
            error = QStringLiteral("Invalid integration backup entry");
            return false;
        }
        entry.file = row.value(QStringLiteral("file")).toString();
        entry.group = row.value(QStringLiteral("group")).toString();
        entry.key = row.value(QStringLiteral("key")).toString();
        entry.existed = row.value(QStringLiteral("existed")).toBool();
        entry.original = row.value(QStringLiteral("original")).toString();
        entry.owned = row.value(QStringLiteral("owned")).toString();
        entry.previousOwned = row.value(QStringLiteral("previousOwned")).toString();
        if (!allowedOwned(entry, entry.owned)
            || (!entry.previousOwned.isEmpty() && !allowedOwned(entry, entry.previousOwned))
            || (!entry.existed && !entry.original.isEmpty()) || seen.contains(identity(entry))) {
            error = QStringLiteral("Unsupported or duplicate integration backup key/value");
            return false;
        }
        seen.insert(identity(entry));
        loaded.entries.append(entry);
    }
    if (!loaded.enabled && !loaded.restorePending && !loaded.entries.isEmpty()) {
        error = QStringLiteral("Disabled integration state has unexpected backup entries");
        return false;
    }
    state = std::move(loaded);
    return true;
}

bool saveState(const QString &root, const State &state, QString &error)
{
    const QString path = statePath(root);
    if (!safeFile(path, maximumStateBytes, error)) return false;
    QJsonArray entries;
    for (const auto &entry : state.entries) {
        entries.append(QJsonObject{
            {QStringLiteral("file"), entry.file}, {QStringLiteral("group"), entry.group},
            {QStringLiteral("key"), entry.key}, {QStringLiteral("existed"), entry.existed},
            {QStringLiteral("original"), entry.original}, {QStringLiteral("owned"), entry.owned},
            {QStringLiteral("previousOwned"), entry.previousOwned}});
    }
    const QJsonObject object{
        {QStringLiteral("schema"), 1}, {QStringLiteral("enabled"), state.enabled},
        {QStringLiteral("restorePending"), state.restorePending},
        {QStringLiteral("pendingAction"), state.pendingAction}, {QStringLiteral("error"), state.error},
        {QStringLiteral("entries"), entries}};
    const auto bytes = QJsonDocument(object).toJson(QJsonDocument::Compact);
    if (bytes.size() > maximumStateBytes) {
        error = QStringLiteral("Integration backup exceeds the size limit");
        return false;
    }
    QSaveFile file(path);
    file.setDirectWriteFallback(false);
    if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size() || !file.commit()) {
        error = QStringLiteral("Cannot atomically save integration state: ") + file.errorString();
        return false;
    }
    return true;
}

QSet<QString> installedRoles(const FormaIntegration::ServiceResolver &resolver)
{
    QSet<QString> installed;
    for (const auto &application : registry())
        if (resolver(application.desktopId)) installed.insert(application.role);
    return installed;
}

QJsonObject report(const State &state, const QSet<QString> &installed, const QString &error,
                   bool available = true)
{
    QJsonArray applications;
    for (const auto &application : registry()) {
        applications.append(QJsonObject{
            {QStringLiteral("role"), application.role}, {QStringLiteral("name"), application.name},
            {QStringLiteral("desktopId"), application.desktopId},
            {QStringLiteral("installed"), installed.contains(application.role)}});
    }
    QString message = error.isEmpty() ? state.error : error;
    if (message.isEmpty() && state.restorePending)
        message = QStringLiteral("Integration changes are incomplete; retry or disable to restore owned keys");
    return {{QStringLiteral("available"), available},
            {QStringLiteral("ready"), message.isEmpty() && !state.restorePending},
            {QStringLiteral("enabled"), state.enabled}, {QStringLiteral("busy"), false},
            {QStringLiteral("applications"), applications}, {QStringLiteral("error"), message},
            {QStringLiteral("restorePending"), state.restorePending},
            {QStringLiteral("terminalCommandSupported"), false}};
}

QString defaultStateRoot()
{
    QString root = qEnvironmentVariable("XDG_STATE_HOME");
    if (!QDir::isAbsolutePath(root)) root = QDir::homePath() + QStringLiteral("/.local/state");
    return QDir(root).filePath(QStringLiteral("quickshell/kos"));
}

struct ConfigFile {
    QString name;
    std::unique_ptr<KConfig> config;
    bool changed = false;
};

KConfig *configFor(std::vector<ConfigFile> &files, const QString &name)
{
    for (auto &file : files) if (file.name == name) return file.config.get();
    return nullptr;
}

bool isOwned(const Entry &entry, const KConfigGroup &group)
{
    if (!group.hasKey(entry.key)) return false;
    const QString current = group.readEntry(entry.key, QString());
    return current == entry.owned || (!entry.previousOwned.isEmpty() && current == entry.previousOwned);
}
} // namespace

FormaIntegration::FormaIntegration()
    : FormaIntegration(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation), defaultStateRoot())
{
}

FormaIntegration::FormaIntegration(QString configRoot, QString stateRoot, ServiceResolver resolver)
    : m_configRoot(std::move(configRoot)), m_stateRoot(std::move(stateRoot)), m_resolver(std::move(resolver))
{
    if (!m_resolver) {
        m_resolver = [](const QString &id) {
            const auto service = KService::serviceByStorageId(id);
            return service && service->isApplication() && !service->exec().trimmed().isEmpty();
        };
    }
}

QJsonObject FormaIntegration::snapshot() const
{
    State state;
    bool exists = false;
    QString error;
    const bool available = validRoots(m_configRoot, m_stateRoot, error)
        && loadState(m_stateRoot, state, exists, error);
    if (error.isEmpty()) error = m_lastError;
    return report(state, installedRoles(m_resolver), error, available);
}

QString FormaIntegration::preferredDesktopId(const QString &role) const
{
    State state;
    bool exists = false;
    QString error;
    if (!validRoots(m_configRoot, m_stateRoot, error)
        || !loadState(m_stateRoot, state, exists, error) || !state.enabled) return {};
    const QString id = desktopId(role);
    return !id.isEmpty() && m_resolver(id) ? id : QString();
}

QString FormaIntegration::finderDesktopId()
{
    return desktopId(QStringLiteral("finder"));
}

QJsonObject FormaIntegration::setEnabled(bool enabled)
{
    State state;
    bool exists = false;
    QString error;
    m_lastError.clear();
    const auto fail = [this, &state](QString message) {
        m_lastError = message;
        // Re-read the durable state, never report a requested-but-uncommitted toggle.
        State durable;
        bool present = false;
        QString readError;
        const bool available = validRoots(m_configRoot, m_stateRoot, readError)
            && loadState(m_stateRoot, durable, present, readError);
        if (available) state = std::move(durable);
        return report(state, installedRoles(m_resolver), message, available);
    };
    // Refuse malformed state before creating directories or even a lock file.
    if (!validRoots(m_configRoot, m_stateRoot, error)
        || !loadState(m_stateRoot, state, exists, error)) return fail(error);
    if (!enabled && !exists) return report(state, installedRoles(m_resolver), {});
    if (!QDir().mkpath(m_stateRoot)) return fail(QStringLiteral("Cannot create integration state directory"));
    QLockFile lock(QDir(m_stateRoot).filePath(QStringLiteral("forma-integration.lock")));
    if (!lock.tryLock(0)) return fail(QStringLiteral("Integration state is locked; retry later"));
    state = {};
    if (!loadState(m_stateRoot, state, exists, error)) return fail(error);
    if (!enabled && !state.enabled && !state.restorePending && state.entries.isEmpty())
        return report(state, installedRoles(m_resolver), {});
    if (enabled && state.restorePending && state.pendingAction == QLatin1String("restore"))
        return fail(QStringLiteral("Restoration is pending; retry disabling before enabling again"));

    QVector<Entry> desired;
    if (enabled) {
        const auto installed = installedRoles(m_resolver);
        QStringList mimeFiles{QStringLiteral("mimeapps.list")};
        if (QFileInfo::exists(QDir(m_configRoot).filePath(QStringLiteral("kde-mimeapps.list"))))
            mimeFiles.append(QStringLiteral("kde-mimeapps.list"));
        for (const auto &association : associations()) {
            const QString role = installed.contains(association.role) ? association.role
                : installed.contains(association.fallback) ? association.fallback : QString();
            if (role.isEmpty()) continue;
            for (const auto &file : mimeFiles) {
                Entry entry;
                entry.file = file;
                entry.group = QStringLiteral("Default Applications");
                entry.key = association.key;
                entry.owned = desktopId(role) + QLatin1Char(';');
                desired.append(entry);
            }
        }
        // Forma Terminal currently accepts only a cwd, not -e/--command.
        // Keep Terminal=true application execution preferences untouched. The
        // terminal role remains available for Dock/direct terminal launchers.
    }

    // Open only fixed files needed by this operation, with no system/global fallbacks.
    QSet<QString> needed;
    for (const auto &entry : desired) needed.insert(entry.file);
    for (const auto &entry : state.entries) needed.insert(entry.file);
    std::vector<ConfigFile> files;
    for (const auto &name : needed) {
        const QString path = QDir(m_configRoot).filePath(name);
        if (!safeFile(path, maximumConfigBytes, error)) return fail(error);
        ConfigFile file;
        file.name = name;
        file.config = std::make_unique<KConfig>(path, KConfig::SimpleConfig);
        files.push_back(std::move(file));
    }

    if (enabled) {
        for (const auto &target : desired) {
            Entry *backup = nullptr;
            for (auto &entry : state.entries)
                if (identity(entry) == identity(target)) { backup = &entry; break; }
            if (backup) {
                if (backup->owned != target.owned) {
                    backup->previousOwned = backup->owned;
                    backup->owned = target.owned;
                }
                continue; // Never replace the first pre-integration value.
            }
            Entry entry = target;
            KConfigGroup group(configFor(files, entry.file), entry.group);
            entry.existed = group.hasKey(entry.key);
            entry.original = group.readEntry(entry.key, QString());
            if (entry.original.size() > maximumValueLength)
                return fail(QStringLiteral("Original association exceeds the backup value limit"));
            state.entries.append(entry);
        }
    }

    const auto &changes = enabled ? desired : state.entries;
    for (const auto &file : files) {
        // Reserve bounded room for escaped values/groups before any write, so an
        // enable cannot create an oversized config that recovery then refuses.
        qint64 upperBytes = QFileInfo(QDir(m_configRoot).filePath(file.name)).size() + 1024;
        for (const auto &entry : changes) {
            if (entry.file != file.name) continue;
            const KConfigGroup group(file.config.get(), entry.group);
            if ((!enabled && !isOwned(entry, group))
                || (enabled && group.hasKey(entry.key) && group.readEntry(entry.key, QString()) == entry.owned)) continue;
            if (group.isEntryImmutable(entry.key))
                return fail(QStringLiteral("Preference is immutable: ") + file.name + QLatin1Char('/') + entry.key);
            const QString value = enabled ? entry.owned : entry.original;
            upperBytes += 4 * (value.toUtf8().size() + entry.key.toUtf8().size() + entry.group.toUtf8().size()) + 64;
        }
        if (upperBytes > maximumConfigBytes)
            return fail(QStringLiteral("Configuration changes exceed the file size limit: ") + file.name);
    }

    state.restorePending = true;
    state.pendingAction = enabled ? QStringLiteral("apply") : QStringLiteral("restore");
    state.error.clear();
    // Write-ahead backup: no KConfig mutation is allowed before this commit.
    if (!saveState(m_stateRoot, state, error)) return fail(error);
    if (!needed.isEmpty() && !QDir().mkpath(m_configRoot)) {
        state.error = QStringLiteral("Cannot create integration configuration directory");
        QString saveError;
        saveState(m_stateRoot, state, saveError);
        return fail(state.error);
    }
    for (const auto &entry : changes) {
        KConfigGroup group(configFor(files, entry.file), entry.group);
        if (!enabled && !isOwned(entry, group)) continue;
        if (enabled) {
            if (group.hasKey(entry.key) && group.readEntry(entry.key, QString()) == entry.owned) continue;
            group.writeEntry(entry.key, entry.owned);
        } else if (entry.existed) {
            group.writeEntry(entry.key, entry.original);
        } else {
            group.deleteEntry(entry.key);
        }
        for (auto &file : files) if (file.name == entry.file) file.changed = true;
    }
    for (auto &file : files) {
        if (!file.changed || file.config->sync()) continue;
        state.error = QStringLiteral("Cannot sync ") + file.name
            + QStringLiteral("; backup retained, retry or disable to restore");
        QString saveError;
        if (!saveState(m_stateRoot, state, saveError)) state.error += QStringLiteral("; ") + saveError;
        return fail(state.error);
    }

    State completed = state;
    completed.enabled = enabled;
    completed.restorePending = false;
    completed.pendingAction.clear();
    completed.error.clear();
    if (!enabled) completed.entries.clear();
    else for (auto &entry : completed.entries) entry.previousOwned.clear();
    if (!saveState(m_stateRoot, completed, error)) {
        // The pending journal remains usable even though config syncs succeeded.
        return fail(error + QStringLiteral("; configuration changed, recovery backup retained"));
    }
    return snapshot();
}

} // namespace KosPlatform
