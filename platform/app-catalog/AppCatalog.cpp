#include "AppCatalog.h"
#include "CatalogTrust.h"
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLockFile>
#include <QMutex>
#include <QMutexLocker>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTimer>

static void catalogResources() { Q_INIT_RESOURCE(catalog); }
namespace {
constexpr qint64 limit = 4 * 1024 * 1024;
bool matches(const QString& pattern, const QString& text)
{ return QRegularExpression(pattern).match(text).hasMatch(); }
bool identifier(const QString& id) { return matches("^[a-z][a-z0-9-]{0,63}$", id); }
bool appIdentifier(const QString& id)
{ return matches("^[A-Za-z][A-Za-z0-9_-]*(\\.[A-Za-z][A-Za-z0-9_-]*){2,}$", id) && id.size() <= 200; }
bool localizedText(const QVariant& value, int maximum)
{
    if (value.metaType().id() != QMetaType::QVariantMap) return false;
    const auto entries = value.toMap();
    if (entries.isEmpty() || entries.size() > 32 || !entries.contains("en")) return false;
    for (auto it = entries.cbegin(); it != entries.cend(); ++it) {
        if (!matches("^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$", it.key())
            || it.value().metaType().id() != QMetaType::QString) return false;
        const auto text = it.value().toString();
        if (text.trimmed().isEmpty() || text.toUcs4().size() > maximum) return false;
        for (const auto ch : text)
            if (ch.unicode() < 32 || (ch.unicode() >= 127 && ch.unicode() <= 159)) return false;
    }
    return true;
}
QByteArray read(const QString& path, qint64 maximum = limit)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly) || file.size() > maximum) return {};
    return file.readAll();
}
bool save(const QString& path, const QByteArray& bytes)
{
    if (!QDir().mkpath(QFileInfo(path).absolutePath())) return false;
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) return false;
    file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    return file.write(bytes) == bytes.size() && file.commit();
}
QString configPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
        + "/kos-settings/app-sources.json";
}
QVariantMap official()
{
    return {{"id", "nextkde"}, {"repository", "NextKde/appCatalog"},
        {"fingerprint", CatalogTrust::releaseFingerprint}, {"publicKey", CatalogTrust::releasePublicKey}};
}
QVariantMap configuration()
{
    const auto bytes = read(configPath());
    if (bytes.isEmpty() && !QFileInfo::exists(configPath()))
        return {{"sources", QVariantList{official()}}};
    return QJsonDocument::fromJson(bytes).object().toVariantMap();
}
QString cachePath(const QString& id) { return AppCatalog::stateDirectory() + "/catalogs/" + id + ".json"; }
QVariantMap bootstrap()
{
    static const auto value = [] {
        catalogResources();
        return QJsonDocument::fromJson(read(":/kos/catalog/bootstrap.json")).object().toVariantMap();
    }();
    return value;
}
QString validate(const QVariantMap& catalog, const QString& source)
{
    const auto sequence = catalog.value("sequence").toLongLong();
    if (catalog.value("schemaVersion").toInt() != 1 || catalog.value("sourceId").toString() != source
        || sequence < 1 || sequence > 9007199254740991LL || catalog.value("sequence").toDouble() != double(sequence)
        || catalog.value("apps").metaType().id() != QMetaType::QVariantList
        || catalog.value("apps").toList().size() > 1000) return "Invalid catalog identity, sequence or applications";
    const auto issued = QDateTime::fromString(catalog.value("issuedAt").toString(), Qt::ISODate);
    const auto expiry = QDateTime::fromString(catalog.value("expiresAt").toString(), Qt::ISODate);
    if (!issued.isValid() || !expiry.isValid() || expiry <= issued
        || issued > QDateTime::currentDateTimeUtc().addSecs(300)) return "Invalid catalog dates";
    QSet<QString> ids, keys;
    for (const auto& item : catalog.value("apps").toList()) {
        const auto app = item.toMap();
        const auto id = app.value("appId").toString(), key = app.value("key").toString();
        const auto status = app.value("status", "active").toString();
        const auto publisher = app.value("publisher").toMap();
        if (!appIdentifier(id) || !identifier(key) || ids.contains(id) || keys.contains(key)
            || !AppCatalog::githubRepository(app.value("repository").toString())
            || !matches("^[A-Za-z0-9][A-Za-z0-9._-]{0,180}\\.json$", app.value("manifest").toString())
            || !matches("^[a-z][a-z0-9-]{0,30}$", app.value("format").toString())
            || !localizedText(app.value("name"), 120)
            || !localizedText(app.value("description"), 600)
            || !QStringList{"active", "withdrawn", "revoked"}.contains(status)) return "Invalid application entry";
        for (const auto& field : {"command", "installCommand", "script", "installRoot", "executable"})
            if (app.contains(field)) return "Catalogs cannot supply commands";
        if (app.contains("publisher") && (app.value("publisher").metaType().id() != QMetaType::QVariantMap
            || publisher.isEmpty())) return "Invalid optional publisher key";
        if (!publisher.isEmpty() && (!matches("^[0-9A-F]{40}([0-9A-F]{24})?$", publisher.value("fingerprint").toString())
            || QByteArray::fromBase64(publisher.value("publicKey").toByteArray()).isEmpty()
            || publisher.value("publicKey").toByteArray().size() > 65536)) return "Invalid optional publisher key";
        ids.insert(id); keys.insert(key);
    }
    return {};
}
QVariantMap cached(const QVariantMap& source)
{
    const auto id = source.value("id").toString();
    if (!identifier(id)) return {};
    const auto envelope = QJsonDocument::fromJson(read(cachePath(id), limit * 2)).object().toVariantMap();
    const auto bytes = QByteArray::fromBase64(envelope.value("catalog").toByteArray());
    const auto signature = QByteArray::fromBase64(envelope.value("signature").toByteArray());
    // Cache only successful verification for identical bytes, trust and process.
    // Expiration is evaluated by the caller on every read.
    static QMutex mutex;
    static QMap<QByteArray, QVariantMap> verified;
    const auto digest = QCryptographicHash::hash(bytes + signature
        + QJsonDocument::fromVariant(source).toJson(QJsonDocument::Compact), QCryptographicHash::Sha256);
    QMutexLocker lock(&mutex);
    if (verified.contains(digest)) return verified.value(digest);
    const auto object = QJsonDocument::fromJson(bytes).object().toVariantMap();
    if (!validate(object, id).isEmpty() || !AppCatalog::verify(bytes, signature,
        QByteArray::fromBase64(source.value("publicKey").toByteArray()), source.value("fingerprint").toString())) return {};
    if (verified.size() > 32) verified.clear();
    verified.insert(digest, object);
    return object;
}
}
namespace AppCatalog {
QString validateUpdate(const QVariantMap& candidate, const QVariantMap& previous, const QString& sourceId)
{
    const auto error = validate(candidate, sourceId);
    if (!error.isEmpty()) return error;
    if (candidate.value("sequence").toLongLong() < previous.value("sequence").toLongLong()
        || (candidate.value("sequence") == previous.value("sequence") && candidate != previous))
        return "Catalog rollback or reused sequence";
    if (QDateTime::fromString(candidate.value("expiresAt").toString(), Qt::ISODate) <= QDateTime::currentDateTimeUtc())
        return "Catalog expired";
    return {};
}
QString stateDirectory()
{
    const auto configured = qEnvironmentVariable("XDG_STATE_HOME");
    const auto root = QDir::isAbsolutePath(configured) ? configured : QDir::homePath() + "/.local/state";
    return root + "/kos-settings/app-catalog";
}
QVariantMap readState(const QString& name)
{
    if (!matches("^[A-Za-z0-9_.-]+$", name)) return {};
    return QJsonDocument::fromJson(read(stateDirectory() + '/' + name + ".json", limit * 4)).object().toVariantMap();
}
bool writeState(const QString& name, const QVariantMap& value)
{
    return matches("^[A-Za-z0-9_.-]+$", name) && save(stateDirectory() + '/' + name + ".json",
        QJsonDocument::fromVariant(value).toJson(QJsonDocument::Compact));
}
QVariantMap receipt(const QString& appId)
{ return appIdentifier(appId) ? readState("installed-" + appId) : QVariantMap{}; }
bool recordInstallation(const QString& appId, const QVariantMap& installation)
{
    if (!appIdentifier(appId) || !QDir().mkpath(stateDirectory())) return false;
    QLockFile lock(stateDirectory() + "/receipt-" + appId + ".lock");
    if (!lock.tryLock(1000)) return false;
    // A concurrent inventory observation must never overwrite a verified deployment receipt.
    if (installation.value("observed").toBool() && !receipt(appId).isEmpty()) return true;
    return writeState("installed-" + appId, installation);
}
bool forgetInstallation(const QString& appId)
{
    if (!appIdentifier(appId) || !QDir().mkpath(stateDirectory())) return false;
    QLockFile lock(stateDirectory() + "/receipt-" + appId + ".lock");
    if (!lock.tryLock(1000)) return false;
    const auto path = stateDirectory() + "/installed-" + appId + ".json";
    return !QFile::exists(path) || QFile::remove(path);
}
QString entryDigest(const QVariantMap& app)
{
    auto identity = app;
    for (const auto& key : {"active", "error", "conflict"}) identity.remove(key);
    return QString::fromLatin1(QCryptographicHash::hash(QJsonDocument::fromVariant(identity).toJson(QJsonDocument::Compact),
        QCryptographicHash::Sha256).toHex());
}
bool githubRepository(const QString& repository)
{
    return repository.size() <= 200 && matches("^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$", repository)
        && !repository.contains("..");
}
bool githubUrl(const QUrl& url, const QString& repository, bool redirected)
{
    if (!githubRepository(repository) || !url.isValid() || url.scheme() != "https" || !url.userInfo().isEmpty()
        || url.port(443) != 443 || url.hasFragment() || url.path().contains("..") || url.path().contains('\\')) return false;
    if (url.host() == "api.github.com") return !url.hasQuery() && url.path() == "/repos/" + repository + "/releases/latest";
    if (url.host() == "github.com") return !url.hasQuery() && url.path().startsWith('/' + repository + "/releases/download/");
    return redirected && (url.host() == "release-assets.githubusercontent.com" || url.host() == "objects.githubusercontent.com");
}
QByteArray fetch(const QUrl& initial, const QString& repository, qint64 maximum, QString* error, const Cancelled& cancelled)
{
    QNetworkAccessManager manager;
    auto url = initial;
    for (int redirect = 0; redirect <= 5; ++redirect) {
        if (cancelled()) { *error = "Cancelled"; return {}; }
        if (!githubUrl(url, repository, redirect > 0)) { *error = "Untrusted GitHub URL"; return {}; }
        QNetworkRequest request(url);
        request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
        request.setRawHeader("User-Agent", "NextKde-AppCatalog/1");
        request.setTransferTimeout(30000);
        auto* reply = manager.get(request);
        QEventLoop loop;
        QTimer timeout, poll;
        timeout.setSingleShot(true); timeout.start(30000); poll.start(100);
        QByteArray bytes;
        QObject::connect(&timeout, &QTimer::timeout, reply, &QNetworkReply::abort);
        QObject::connect(&poll, &QTimer::timeout, reply, [&] { if (cancelled()) reply->abort(); });
        QObject::connect(reply, &QNetworkReply::readyRead, reply, [&] {
            bytes += reply->readAll(); if (bytes.size() > maximum) reply->abort();
        });
        QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
        loop.exec(); bytes += reply->readAll();
        const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto target = reply->attribute(QNetworkRequest::RedirectionTargetAttribute).toUrl();
        const auto failure = reply->error();
        delete reply;
        if (bytes.size() > maximum) { *error = "Response too large"; return {}; }
        if (status >= 300 && status < 400 && !target.isEmpty()) { url = url.resolved(target); continue; }
        if (failure != QNetworkReply::NoError || status != 200) {
            *error = status == 403 || status == 429 ? "GitHub rate limit or access denied" : "GitHub release request failed";
            return {};
        }
        return bytes;
    }
    *error = "Too many redirects"; return {};
}
bool verify(const QByteArray& bytes, const QByteArray& signature, const QByteArray& keys, const QString& fingerprint)
{
    if (bytes.isEmpty() || bytes.size() > limit || signature.isEmpty() || signature.size() > 65536
        || keys.isEmpty() || keys.size() > 65536 || !matches("^[0-9A-F]{40}([0-9A-F]{24})?$", fingerprint)) return false;
    QTemporaryDir directory;
    if (!directory.isValid() || !save(directory.filePath("key.gpg"), keys)
        || !save(directory.filePath("payload"), bytes) || !save(directory.filePath("signature"), signature)) return false;
    QProcess process;
    process.setProgram(QStandardPaths::findExecutable("gpgv"));
    process.setArguments({"--homedir", directory.path(), "--keyring", directory.filePath("key.gpg"),
        "--status-fd", "1", "--", directory.filePath("signature"), directory.filePath("payload")});
    process.start();
    if (!process.waitForFinished(10000)) { process.kill(); process.waitForFinished(1000); return false; }
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) return false;
    bool valid = false;
    const auto output = process.readAllStandardOutput();
    if (output.size() > 65536) return false;
    for (const auto& line : output.split('\n')) {
        if (line.startsWith("[GNUPG:] VALIDSIG ")) {
            const auto fields = line.simplified().split(' ');
            if (fields.size() < 11) return false;
            valid |= QString::fromLatin1(fields.size() >= 12 ? fields[11] : fields[2]) == fingerprint
                && (fields[9] == "8" || fields[9] == "9" || fields[9] == "10");
        } else if (line.contains("BADSIG") || line.contains("ERRSIG") || line.contains("EXPKEYSIG")
            || line.contains("REVKEYSIG") || line.contains("EXPSIG")) return false;
    }
    return valid;
}
QVariantList sources()
{
    QVariantList result;
    for (const auto& item : configuration().value("sources").toList()) {
        auto source = item.toMap();
        if (!identifier(source.value("id").toString())) continue;
        const auto catalog = cached(source);
        source["sequence"] = catalog.value("sequence", 0);
        source["expiresAt"] = catalog.value("expiresAt");
        source["error"] = readState("source-" + source.value("id").toString()).value("error");
        source["lastChecked"] = readState("source-" + source.value("id").toString()).value("lastChecked");
        source.remove("publicKey"); result.append(source);
    }
    return result;
}
QVariantList apps()
{
    QMap<QString, QVariantMap> entries;
    for (const auto& item : configuration().value("sources").toList()) {
        const auto source = item.toMap();
        auto catalog = cached(source);
        bool seed = false;
        if (catalog.isEmpty() && source == official() && !QFileInfo::exists(cachePath("nextkde"))) {
            catalog = bootstrap(); seed = true;
        }
        const bool fresh = seed || QDateTime::fromString(catalog.value("expiresAt").toString(), Qt::ISODate) > QDateTime::currentDateTimeUtc();
        for (const auto& value : catalog.value("apps").toList()) {
            auto app = value.toMap();
            const auto id = app.value("appId").toString();
            app["sourceId"] = source.value("id");
            app["active"] = fresh && app.value("status", "active").toString() == "active";
            if (!fresh) app["error"] = "Catalog expired";
            if (entries.contains(id)) {
                app["active"] = false; app["conflict"] = true;
                app["error"] = "Conflicting application ID in multiple sources";
            }
            entries[id] = app;
        }
    }
    // Receipts keep installed apps removable after withdrawal or source removal.
    // They never grant permission to install or update from a deleted source.
    const QDir directory(stateDirectory());
    for (const auto& name : directory.entryList({"installed-*.json"}, QDir::Files)) {
        const auto record = readState(name.chopped(5));
        const auto old = record.value("entry").toMap();
        const auto id = old.value("appId").toString();
        if (!appIdentifier(id)) continue;
        if (!entries.contains(id) || entries[id].value("sourceId") != old.value("sourceId")) {
            auto inactive = old; inactive["active"] = false; inactive["status"] = "withdrawn";
            if (entries.value(id).value("conflict").toBool()) {
                inactive["conflict"] = true; inactive["error"] = "Conflicting application ID in multiple sources";
            }
            entries[id] = inactive;
        }
    }
    // Preserve legacy signed installations when an initial catalog removes them.
    for (const auto& item : bootstrap().value("apps").toList()) {
        auto app = item.toMap(); const auto id = app.value("appId").toString();
        if (!entries.contains(id)) { app["sourceId"] = "nextkde"; app["active"] = false; app["status"] = "withdrawn"; entries[id] = app; }
    }
    QVariantList result;
    for (const auto& entry : entries) result.append(entry);
    return result;
}
QVariantMap find(const QString& id)
{
    QVariantMap match;
    for (const auto& value : apps()) {
        const auto app = value.toMap();
        if (app.value("appId").toString() == id) return app;
        if (app.value("key").toString() == id) { if (!match.isEmpty()) return {}; match = app; }
    }
    return match;
}
QString addSource(const QString& id, const QString& repository, const QString& fingerprint, const QString& publicKeyFile)
{
    if (!identifier(id) || !githubRepository(repository) || !matches("^[0-9A-F]{40}([0-9A-F]{24})?$", fingerprint))
        return "Invalid source ID, GitHub owner/repository or full fingerprint";
    const auto keys = read(publicKeyFile, 65536);
    if (keys.isEmpty()) return "Cannot read exported binary public key";
    QDir().mkpath(stateDirectory());
    QLockFile lock(stateDirectory() + "/sources.lock");
    if (!lock.tryLock(0)) return "Source configuration is busy";
    auto config = configuration(); auto list = config.value("sources").toList();
    if (list.size() >= 32) return "At most 32 application sources are supported";
    for (const auto& value : list) if (value.toMap().value("id").toString() == id) return "Source ID already exists";
    // Old signed snapshots remain a rollback floor when the same source is re-added.
    const QVariantMap proposed{{"id", id}, {"repository", repository}, {"fingerprint", fingerprint}, {"publicKey", keys.toBase64()}};
    if (QFileInfo::exists(cachePath(id)) && cached(proposed).isEmpty())
        return "Source history does not verify with this key; use a new source ID";
    list.append(proposed);
    config["sources"] = list;
    return save(configPath(), QJsonDocument::fromVariant(config).toJson()) ? QString() : "Cannot save sources";
}
QString removeSource(const QString& id)
{
    QDir().mkpath(stateDirectory()); QLockFile lock(stateDirectory() + "/sources.lock");
    if (!lock.tryLock(0)) return "Source configuration is busy";
    auto config = configuration(); QVariantList list;
    for (const auto& value : config.value("sources").toList())
        if (value.toMap().value("id").toString() != id) list.append(value);
    config["sources"] = list;
    return save(configPath(), QJsonDocument::fromVariant(config).toJson()) ? QString() : "Cannot save sources";
}
QString refresh(const Cancelled& cancelled)
{
    QDir().mkpath(stateDirectory()); QLockFile lock(stateDirectory() + "/sources.lock");
    if (!lock.tryLock(0)) return "Source refresh is already running";
    QStringList errors;
    for (const auto& item : configuration().value("sources").toList()) {
        if (cancelled()) break;
        const auto source = item.toMap(); const auto id = source.value("id").toString();
        const auto repository = source.value("repository").toString();
        if (!identifier(id) || !githubRepository(repository)) { errors.append("Invalid source configuration"); continue; }
        QString error;
        const auto releaseBytes = fetch(QUrl("https://api.github.com/repos/" + repository + "/releases/latest"), repository, limit, &error, cancelled);
        const auto release = QJsonDocument::fromJson(releaseBytes).object();
        const auto tag = release.value("tag_name").toString();
        if (error.isEmpty() && (release.value("draft").toBool(true) || release.value("prerelease").toBool(true)
            || !matches("^[A-Za-z0-9][A-Za-z0-9._-]{0,100}$", tag))) error = "Expected a published stable GitHub Release";
        const auto attachment = [&](const QString& name, qint64 maximum) -> QByteArray {
            if (!error.isEmpty()) return {};
            const auto expected = "https://github.com/" + repository + "/releases/download/" + tag + '/' + name;
            int count = 0;
            for (const auto& value : release.value("assets").toArray()) {
                const auto asset = value.toObject();
                if (asset.value("name").toString() == name && asset.value("browser_download_url").toString() == expected) ++count;
            }
            if (count != 1) { error = "Missing unique catalog release attachment"; return {}; }
            return fetch(QUrl(expected), repository, maximum, &error, cancelled);
        };
        const auto bytes = attachment("catalog.json", limit);
        const auto signature = attachment("catalog.json.sig", 65536);
        auto catalog = QJsonDocument::fromJson(bytes).object().toVariantMap();
        if (error.isEmpty() && !verify(bytes, signature, QByteArray::fromBase64(source.value("publicKey").toByteArray()), source.value("fingerprint").toString())) error = "Catalog signature is invalid";
        const auto previous = cached(source);
        if (error.isEmpty() && QFileInfo::exists(cachePath(id)) && previous.isEmpty()) error = "Previous catalog cannot be verified; refusing to reset rollback history";
        if (error.isEmpty()) error = validateUpdate(catalog, previous, id);
        if (error.isEmpty() && !save(cachePath(id), QJsonDocument::fromVariant(QVariantMap{{"catalog", bytes.toBase64()}, {"signature", signature.toBase64()}}).toJson())) error = "Cannot save catalog";
        writeState("source-" + id, {{"error", error}, {"lastChecked", QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}});
        if (!error.isEmpty()) errors.append(id + ": " + error);
    }
    return errors.join('\n');
}
}
