#include "AppCatalog.h"
#include "CatalogTrust.h"
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QEventLoop>
#include <QElapsedTimer>
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
#include <QUuid>
#include <QtEndian>

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
QString modePath()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
        + "/kos-settings/app-catalog-mode.json";
}
QVariantMap modeSettings()
{ return QJsonDocument::fromJson(read(modePath())).object().toVariantMap(); }
QString configPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
        + (AppCatalog::testMode() ? "/kos-settings/app-sources-test.json" : "/kos-settings/app-sources.json");
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
        return {{"sources", AppCatalog::testMode() ? QVariantList{} : QVariantList{official()}}};
    return QJsonDocument::fromJson(bytes).object().toVariantMap();
}
QString cachePath(const QString& id, bool widgetCatalog = false)
{
    const QString folder = widgetCatalog
        ? (AppCatalog::testMode() ? "/test/widget-catalogs/" : "/widget-catalogs/")
        : (AppCatalog::testMode() ? "/test/catalogs/" : "/catalogs/");
    return AppCatalog::stateDirectory() + folder + id + ".json";
}
QVariantMap bootstrap()
{
    static const auto value = [] {
        catalogResources();
        return QJsonDocument::fromJson(read(":/kos/catalog/bootstrap.json")).object().toVariantMap();
    }();
    return value;
}
QString validateCatalog(const QVariantMap& catalog, const QString& source, bool widgetCatalog)
{
    const QString listKey = widgetCatalog ? QStringLiteral("widgets") : QStringLiteral("apps");
    const auto sequence = catalog.value("sequence").toLongLong();
    if (!QList<int>{1, 2}.contains(catalog.value("schemaVersion").toInt()) || catalog.value("sourceId").toString() != source
        || sequence < 1 || sequence > 9007199254740991LL || catalog.value("sequence").toDouble() != double(sequence)
        || catalog.value(listKey).metaType().id() != QMetaType::QVariantList
        || catalog.value(listKey).toList().size() > 1000) return "Invalid catalog identity, sequence or applications";
    const auto issued = QDateTime::fromString(catalog.value("issuedAt").toString(), Qt::ISODate);
    const auto expiry = QDateTime::fromString(catalog.value("expiresAt").toString(), Qt::ISODate);
    if (!issued.isValid() || !expiry.isValid() || expiry <= issued
        || issued > QDateTime::currentDateTimeUtc().addSecs(300)) return "Invalid catalog dates";
    QSet<QString> ids, keys;
    for (const auto& item : catalog.value(listKey).toList()) {
        const auto app = item.toMap();
        const auto id = app.value("appId").toString(), key = app.value("key").toString();
        const auto format = app.value("format").toString();
        const auto status = app.value("status", "active").toString();
        const auto publisher = app.value("publisher").toMap();
        if (!appIdentifier(id) || !identifier(key) || ids.contains(id) || keys.contains(key)
            || !AppCatalog::githubRepository(app.value("repository").toString())
            || !matches("^[A-Za-z0-9][A-Za-z0-9._-]{0,180}\\.json$", app.value("manifest").toString())
            || !matches("^[a-z][a-z0-9-]{0,30}$", format)
            || (widgetCatalog && format != QLatin1String("qml-widget"))
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
        if (catalog.value("schemaVersion").toInt() == 2 && !app.contains("release")) return "Missing catalog release selection";
        const auto release = app.value("release").toMap();
        if (app.contains("release") && !app.value("release").isNull() && release.isEmpty()) return "Invalid catalog release selection";
        if (!release.isEmpty()) {
            const auto bytes = QByteArray::fromBase64(release.value("manifest").toByteArray());
            const auto data = QJsonDocument::fromJson(bytes).object();
            const auto version = release.value("version").toString();
            const bool expectedPayload = widgetCatalog
                ? data.value("package").isObject()
                : (format == QLatin1String("declarative-widget") ? data.value("plugin").isObject() : data.value("bundles").isObject());
            if (!matches("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$", version)
                || release.value("tag").toString() != "v" + version || version.size() > 100
                || bytes.isEmpty() || bytes.size() > 1024 * 1024
                || data.value("schemaVersion").toInt() != 2 || data.value("appId").toString() != id
                || data.value("version").toString() != version
                || !expectedPayload
                || (!publisher.isEmpty() && QByteArray::fromBase64(release.value("signature").toByteArray()).isEmpty()))
                return "Invalid catalog release selection";
            if (widgetCatalog) {
                const auto package = data.value("package").toObject();
                const auto size = package.value("size").toDouble();
                if (data.size() != 4 || package.size() != 3 || !package.value("asset").isString()
                    || !matches("^[A-Za-z0-9][A-Za-z0-9._-]{0,140}\\.(tar\\.gz|tgz|zip|koswidget)$", package.value("asset").toString())
                    || !package.value("sha256").isString() || !matches("^[0-9a-f]{64}$", package.value("sha256").toString())
                    || !package.value("size").isDouble() || size < 1 || size > 32.0 * 1024 * 1024 || size != qint64(size))
                    return "Invalid widget plugin release descriptor";
            } else if (format == QLatin1String("declarative-widget")) {
                const auto plugin = data.value("plugin").toObject();
                const auto size = plugin.value("size").toDouble();
                if (data.size() != 4 || plugin.size() != 3 || !plugin.value("asset").isString()
                    || !matches("^[A-Za-z0-9][A-Za-z0-9._-]{0,110}\\.json$", plugin.value("asset").toString())
                    || !plugin.value("sha256").isString() || !matches("^[0-9a-f]{64}$", plugin.value("sha256").toString())
                    || !plugin.value("size").isDouble() || size < 1 || size > 128 * 1024 || size != qint64(size))
                    return "Invalid declarative plugin release descriptor";
            }
        }
        if (app.contains("icon")) {
            const auto icon = app.value("icon").toMap(); const QUrl url(icon.value("url").toString());
            if (url.scheme() != "https" || url.host() != "raw.githubusercontent.com" || !url.userInfo().isEmpty()
                || url.port(443) != 443 || url.hasQuery() || url.hasFragment()
                || !matches("^/[A-Za-z0-9-]+/[A-Za-z0-9_.-]+/[0-9a-f]{40}/icons/" + QRegularExpression::escape(id) + "\\.png$", url.path())
                || !matches("^[0-9a-f]{64}$", icon.value("sha256").toString())
                || icon.value("size").toLongLong() < 33 || icon.value("size").toLongLong() > 512 * 1024)
                return "Invalid catalog icon";
        }
        ids.insert(id); keys.insert(key);
    }
    return {};
}
QVariantMap cachedCatalog(const QVariantMap& source, bool widgetCatalog = false)
{
    const auto id = source.value("id").toString();
    if (!identifier(id)) return {};
    const auto envelope = QJsonDocument::fromJson(read(cachePath(id, widgetCatalog), limit * 2)).object().toVariantMap();
    const auto bytes = QByteArray::fromBase64(envelope.value("catalog").toByteArray());
    const auto signature = QByteArray::fromBase64(envelope.value("signature").toByteArray());
    // Cache only successful verification for identical bytes, trust and process.
    // Expiration is evaluated by the caller on every read.
    static QMutex mutex;
    static QMap<QByteArray, QVariantMap> verified;
    const auto digest = QCryptographicHash::hash(QByteArray(widgetCatalog ? "w:" : "a:") + bytes + signature
        + QJsonDocument::fromVariant(source).toJson(QJsonDocument::Compact), QCryptographicHash::Sha256);
    QMutexLocker lock(&mutex);
    if (verified.contains(digest)) return verified.value(digest);
    const auto object = QJsonDocument::fromJson(bytes).object().toVariantMap();
    if (!validateCatalog(object, id, widgetCatalog).isEmpty() || !AppCatalog::verify(bytes, signature,
        QByteArray::fromBase64(source.value("publicKey").toByteArray()), source.value("fingerprint").toString())) return {};
    if (verified.size() > 64) verified.clear();
    verified.insert(digest, object);
    return object;
}
}
namespace AppCatalog {
bool testMode() { return modeSettings().value("testMode", false).toBool(); }
QString contextToken()
{
    const auto mode = modeSettings();
    return (mode.value("testMode").toBool() ? "test:" : "normal:") + mode.value("generation").toString();
}
bool releaseTag(const QString& tag)
{ return matches("^[A-Za-z0-9][A-Za-z0-9._-]{0,100}$", tag) && !tag.contains(".."); }
QString setTestMode(bool enabled)
{
    QDir().mkpath(stateDirectory());
    QLockFile context(stateDirectory() + "/context.lock"), mutation(stateDirectory() + "/flatpak-mutation.lock"), sources(stateDirectory() + "/sources.lock");
    if (!context.tryLock(0) || !mutation.tryLock(0) || !sources.tryLock(0)) return "BUSY";
    if (testMode() == enabled) return {};
    auto status = readState("update-status"); status["running"] = false; writeState("update-status", status);
    if (!save(modePath(), QJsonDocument::fromVariant(QVariantMap{{"testMode", enabled},
        {"generation", QUuid::createUuid().toString(QUuid::WithoutBraces)}}).toJson())) return "Cannot save test mode";
    status = readState("update-status"); status["running"] = false; writeState("update-status", status);
    writeState("check-request", {{"timestamp", 0}});
    return {};
}
QString selectSourceRelease(const QString& id, const QString& repository, const QString& tag)
{
    QDir().mkpath(stateDirectory()); QLockFile context(stateDirectory() + "/context.lock"), lock(stateDirectory() + "/sources.lock");
    if (!context.tryLock(0) || !lock.tryLock(0)) return "BUSY";
    if (!testMode()) return "Release selection requires test mode";
    if (!tag.isEmpty() && !releaseTag(tag)) return "Invalid Release tag";
    auto config = configuration(); auto list = config.value("sources").toList(); bool found = false;
    for (auto& value : list) {
        auto source = value.toMap();
        if (source.value("id") == id && source.value("repository") == repository) {
            source["releaseTag"] = tag; value = source; found = true;
        }
    }
    if (!found) return "The source changed. Refresh and try again.";
    config["sources"] = list;
    // The same source's signed sequence history is retained when changing tags.
    return save(configPath(), QJsonDocument::fromVariant(config).toJson()) ? QString() : "Cannot save sources";
}
QString selectReleaseInternal(const QString& targetId, const QString& repository, const QString& tag, bool widgetCatalog)
{
    QDir().mkpath(stateDirectory()); QLockFile context(stateDirectory() + "/context.lock"), lock(stateDirectory() + "/sources.lock");
    if (!context.tryLock(0) || !lock.tryLock(0)) return "BUSY";
    if (!testMode()) return "Release selection requires test mode";
    if (!tag.isEmpty() && !releaseTag(tag)) return "Invalid Release tag";
    const auto entry = widgetCatalog ? findWidget(targetId) : find(targetId);
    if (!entry.value("active").toBool() || entry.value("repository") != repository) return "The source changed. Refresh and try again.";
    const QString key = widgetCatalog ? QStringLiteral("widgetReleases") : QStringLiteral("appReleases");
    auto config = configuration(); auto selections = config.value(key).toMap();
    selections[targetId] = QVariantMap{{"repository", repository}, {"tag", tag},
        {"generation", QUuid::createUuid().toString(QUuid::WithoutBraces)}};
    config[key] = selections;
    return save(configPath(), QJsonDocument::fromVariant(config).toJson()) ? QString() : "Cannot save sources";
}
QString selectAppRelease(const QString& appId, const QString& repository, const QString& tag)
{ return selectReleaseInternal(appId, repository, tag, false); }
QString selectWidgetRelease(const QString& widgetId, const QString& repository, const QString& tag)
{ return selectReleaseInternal(widgetId, repository, tag, true); }
QVariantMap releaseChoices(const QString& repository)
{
    if (!testMode() || !githubRepository(repository)) return {{"error", "Release selection requires test mode"}};
    QString error;
    const auto bytes = fetch(QUrl("https://api.github.com/repos/" + repository + "/releases"), repository, limit, &error);
    QJsonParseError parse;
    const auto document = QJsonDocument::fromJson(bytes, &parse);
    if (error.isEmpty() && (parse.error != QJsonParseError::NoError || !document.isArray())) error = "Invalid Release list";
    QVariantList list;
    for (const auto& item : document.array()) {
        const auto release = item.toObject(); const auto tag = release.value("tag_name").toString();
        if (release.value("draft").toBool(true) || !releaseTag(tag)) continue;
        list.append(QVariantMap{{"tag", tag}, {"prerelease", release.value("prerelease").toBool()}});
        if (list.size() == 30) break;
    }
    return {{"releases", list}, {"error", error}};
}
static QString validateCatalogUpdate(const QVariantMap& candidate, const QVariantMap& previous, const QString& sourceId, bool widgetCatalog)
{
    const auto error = validateCatalog(candidate, sourceId, widgetCatalog);
    if (!error.isEmpty()) return error;
    if (candidate.value("sequence").toLongLong() < previous.value("sequence").toLongLong()
        || (candidate.value("sequence") == previous.value("sequence") && candidate != previous))
        return "Catalog rollback or reused sequence";
    if (QDateTime::fromString(candidate.value("expiresAt").toString(), Qt::ISODate) <= QDateTime::currentDateTimeUtc())
        return "Catalog expired";
    return {};
}
QString validateUpdate(const QVariantMap& candidate, const QVariantMap& previous, const QString& sourceId)
{ return validateCatalogUpdate(candidate, previous, sourceId, false); }
QString validateWidgetUpdate(const QVariantMap& candidate, const QVariantMap& previous, const QString& sourceId)
{ return validateCatalogUpdate(candidate, previous, sourceId, true); }
QString stateDirectory()
{
    const auto configured = qEnvironmentVariable("XDG_STATE_HOME");
    const auto root = QDir::isAbsolutePath(configured) ? configured : QDir::homePath() + "/.local/state";
    return root + "/kos-settings/app-catalog";
}
static bool isReceiptState(const QString& name)
{ return name.startsWith("installed-") || name.startsWith("widget-installed-"); }
QVariantMap readState(const QString& name)
{
    if (!matches("^[A-Za-z0-9_.-]+$", name)) return {};
    return QJsonDocument::fromJson(read(stateDirectory() + (testMode() && !isReceiptState(name) ? "/test/" : "/") + name + ".json", limit * 4)).object().toVariantMap();
}
bool writeState(const QString& name, const QVariantMap& value)
{
    return matches("^[A-Za-z0-9_.-]+$", name) && save(stateDirectory() + (testMode() && !isReceiptState(name) ? "/test/" : "/") + name + ".json",
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
QVariantMap widgetReceipt(const QString& widgetId)
{ return appIdentifier(widgetId) ? readState("widget-installed-" + widgetId) : QVariantMap{}; }
bool recordWidgetInstallation(const QString& widgetId, const QVariantMap& installation)
{
    if (!appIdentifier(widgetId) || !QDir().mkpath(stateDirectory())) return false;
    QLockFile lock(stateDirectory() + "/widget-receipt-" + widgetId + ".lock");
    if (!lock.tryLock(1000)) return false;
    return writeState("widget-installed-" + widgetId, installation);
}
bool forgetWidgetInstallation(const QString& widgetId)
{
    if (!appIdentifier(widgetId) || !QDir().mkpath(stateDirectory())) return false;
    QLockFile lock(stateDirectory() + "/widget-receipt-" + widgetId + ".lock");
    if (!lock.tryLock(1000)) return false;
    const auto path = stateDirectory() + "/widget-installed-" + widgetId + ".json";
    return !QFile::exists(path) || QFile::remove(path);
}
QString entryDigest(const QVariantMap& app)
{
    auto identity = app;
    identity["catalogContext"] = contextToken();
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
    if (url.host() == "api.github.com") {
        const auto prefix = "/repos/" + repository + "/releases";
        return !url.hasQuery() && (url.path() == prefix + "/latest"
            || (testMode() && (url.path() == prefix || (url.path().startsWith(prefix + "/tags/")
                && releaseTag(url.path().mid(prefix.size() + 6))))));
    }
    if (url.host() == "github.com") return !url.hasQuery() && url.path().startsWith('/' + repository + "/releases/download/");
    return redirected && (url.host() == "release-assets.githubusercontent.com" || url.host() == "objects.githubusercontent.com");
}
static QByteArray fetchBounded(const QUrl& initial, const QString& repository, qint64 maximum, QString* error, const Cancelled& cancelled, bool iconOnly)
{
    QNetworkAccessManager manager;
    auto url = initial;
    for (int redirect = 0; redirect <= 5; ++redirect) {
        if (cancelled()) { *error = "Cancelled"; return {}; }
        if (iconOnly ? (redirect != 0 || url != initial) : !githubUrl(url, repository, redirect > 0)) { *error = "Untrusted GitHub URL"; return {}; }
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
QByteArray fetch(const QUrl& url, const QString& repository, qint64 maximum, QString* error, const Cancelled& cancelled)
{ return fetchBounded(url, repository, maximum, error, cancelled, false); }
static bool validIconBytes(const QByteArray& bytes, const QVariantMap& icon)
{
    if (bytes.size() != icon.value("size").toLongLong() || bytes.size() < 33 || bytes.size() > 512 * 1024
        || bytes.left(8) != QByteArray::fromHex("89504e470d0a1a0a") || bytes.mid(12, 4) != "IHDR") return false;
    const auto width = qFromBigEndian<quint32>(bytes.constData() + 16), height = qFromBigEndian<quint32>(bytes.constData() + 20);
    return width > 0 && width <= 1024 && height > 0 && height <= 1024
        && QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex() == icon.value("sha256").toByteArray();
}
static QString cachedIconFile(const QVariantMap& icon)
{
    const auto digest = icon.value("sha256").toString();
    if (!matches("^[0-9a-f]{64}$", digest)) return {};
    const auto path = stateDirectory() + "/icons/" + digest + ".png";
    return validIconBytes(read(path, 512 * 1024), icon) ? QUrl::fromLocalFile(path).toString() : QString();
}
static QString iconSourceIdentity(const QVariantMap& source)
{
    return QString::fromLatin1(QCryptographicHash::hash(
        QJsonDocument::fromVariant(source).toJson(QJsonDocument::Compact), QCryptographicHash::Sha256).toHex());
}
static void rememberIcons(const QVariantMap& source, const QVariantMap& catalog, bool widgetCatalog = false)
{
    const auto id = source.value("id").toString();
    const auto key = (widgetCatalog ? QStringLiteral("last-widget-icons-") : QStringLiteral("last-icons-")) + id;
    const auto identity = iconSourceIdentity(source);
    const auto previous = readState(key);
    const auto previousIcons = previous.value("source").toString() == identity
        ? previous.value("icons").toMap() : QVariantMap{};
    QVariantMap icons;
    const auto listKey = widgetCatalog ? QStringLiteral("widgets") : QStringLiteral("apps");
    for (const auto& value : catalog.value(listKey).toList()) {
        const auto entry = value.toMap(); const auto entryId = entry.value("appId").toString();
        const auto current = entry.value("icon").toMap();
        if (current.isEmpty()) continue;
        if (!cachedIconFile(current).isEmpty()) icons[entryId] = current;
        else {
            const auto old = previousIcons.value(entryId).toMap();
            if (!cachedIconFile(old).isEmpty()) icons[entryId] = old;
        }
    }
    const QVariantMap next{{"source", identity}, {"icons", icons}};
    if (next != previous) writeState(key, next);
}
QString iconFile(const QVariantMap& app)
{
    const auto icon = app.value("icon").toMap();
    if (icon.isEmpty()) return {};
    const auto current = cachedIconFile(icon);
    if (!current.isEmpty()) return current;
    const auto id = app.value("appId").toString(), sourceId = app.value("sourceId").toString();
    if (!appIdentifier(id) || !identifier(sourceId)) return {};
    const bool widgetCatalog = app.value("format").toString() == QLatin1String("qml-widget");
    const auto history = readState((widgetCatalog ? QStringLiteral("last-widget-icons-") : QStringLiteral("last-icons-")) + sourceId);
    for (const auto& value : configuration().value("sources").toList()) {
        const auto source = value.toMap();
        if (source.value("id").toString() == sourceId && history.value("source").toString() == iconSourceIdentity(source))
            // Display-only local history: never used for downloads, version
            // selection, package verification or installation authorization.
            return cachedIconFile(history.value("icons").toMap().value(id).toMap());
    }
    return {};
}
static void cacheIcons(const QVariantMap& catalog, const QVariantMap& source, const Cancelled& cancelled, bool widgetCatalog = false)
{
    const auto listKey = widgetCatalog ? QStringLiteral("widgets") : QStringLiteral("apps");
    const auto entries = catalog.value(listKey).toList();
    if (entries.isEmpty()) return;
    rememberIcons(source, catalog, widgetCatalog);
    const auto repository = source.value("repository").toString();
    const auto cursorKey = (widgetCatalog ? QStringLiteral("widget-icon-cursor-") : QStringLiteral("icon-cursor-")) + catalog.value("sourceId").toString();
    const int start = qMax(0, readState(cursorKey).value("next").toInt()) % entries.size();
    int next = start;
    QElapsedTimer budget; budget.start();
    const auto stop = [&] { return cancelled() || budget.elapsed() >= 15000; };
    for (int offset = 0; offset < entries.size(); ++offset) {
        if (stop()) break;
        const int index = (start + offset) % entries.size();
        next = (index + 1) % entries.size();
        const auto app = entries[index].toMap(); const auto icon = app.value("icon").toMap();
        // A retained old image must not suppress downloading its replacement.
        if (icon.isEmpty() || !cachedIconFile(icon).isEmpty()) continue;
        const QUrl url(icon.value("url").toString());
        // Only immutable artwork in this catalog's own repository is authorized.
        if (!url.path().startsWith('/' + repository + '/')) continue;
        QString error;
        QElapsedTimer attempt; attempt.start();
        const auto bytes = fetchBounded(url, repository, 512 * 1024, &error,
            [&] { return stop() || attempt.elapsed() >= 5000; }, true);
        if (error.isEmpty() && validIconBytes(bytes, icon)) save(stateDirectory() + "/icons/" + icon.value("sha256").toString() + ".png", bytes);
    }
    // Continue after a slow/broken image on the next pass instead of starving later apps.
    writeState(cursorKey, {{"next", next}});
    rememberIcons(source, catalog, widgetCatalog);
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
        const auto catalog = cachedCatalog(source, false);
        source["sequence"] = catalog.value("sequence", 0);
        source["expiresAt"] = catalog.value("expiresAt");
        source["error"] = readState("source-" + source.value("id").toString()).value("error");
        source["lastChecked"] = readState("source-" + source.value("id").toString()).value("lastChecked");
        source.remove("publicKey"); result.append(source);
    }
    return result;
}
static QVariantList resolveCatalogEntries(bool widgetCatalog)
{
    const QString listKey = widgetCatalog ? QStringLiteral("widgets") : QStringLiteral("apps");
    const QString selectionKey = widgetCatalog ? QStringLiteral("widgetReleases") : QStringLiteral("appReleases");
    const QString receiptGlob = widgetCatalog ? QStringLiteral("widget-installed-*.json") : QStringLiteral("installed-*.json");
    const auto config = configuration();
    QMap<QString, QVariantMap> entries;
    for (const auto& item : config.value("sources").toList()) {
        const auto source = item.toMap();
        const auto id = source.value("id").toString();
        auto catalog = cachedCatalog(source, widgetCatalog);
        bool seed = false;
        if (!widgetCatalog && !testMode() && catalog.isEmpty() && source == official() && !QFileInfo::exists(cachePath("nextkde", false))) {
            catalog = bootstrap(); seed = true;
        }
        const auto envelope = QJsonDocument::fromJson(read(cachePath(id, widgetCatalog), limit * 2)).object();
        const bool selected = !testMode() || envelope.value("releaseTag").toString() == source.value("releaseTag").toString();
        const bool fresh = selected && (seed || QDateTime::fromString(catalog.value("expiresAt").toString(), Qt::ISODate) > QDateTime::currentDateTimeUtc());
        for (const auto& value : catalog.value(listKey).toList()) {
            auto entry = value.toMap();
            const auto entryId = entry.value("appId").toString();
            entry["sourceId"] = source.value("id");
            entry["testMode"] = testMode();
            if (testMode()) entry["catalogReleaseTag"] = source.value("releaseTag").toString();
            entry.remove("releaseTag"); entry.remove("releaseSelection");
            const auto selection = config.value(selectionKey).toMap().value(entryId).toMap();
            if (testMode() && selection.value("repository") == entry.value("repository")) {
                entry["releaseTag"] = selection.value("tag");
                entry["releaseSelection"] = selection.value("generation");
            }
            entry["active"] = fresh && entry.value("status", "active").toString() == "active";
            if (!fresh) entry["error"] = selected ? "Catalog expired" : "Refresh the selected catalog Release";
            if (entries.contains(entryId)) {
                entry["active"] = false; entry["conflict"] = true;
                entry["error"] = "Conflicting application ID in multiple sources";
            }
            entries[entryId] = entry;
        }
    }
    // Receipts keep installed apps/widgets removable after withdrawal or source removal.
    // They never grant permission to install or update from a deleted source.
    const QDir directory(stateDirectory());
    for (const auto& name : directory.entryList({receiptGlob}, QDir::Files)) {
        const auto record = readState(name.chopped(5));
        const auto old = record.value("entry").toMap();
        const auto id = old.value("appId").toString();
        if (!appIdentifier(id)) continue;
        if (!entries.contains(id) || (!testMode() && old.value("testMode").toBool())
            || (entries[id].value("testMode").toBool() == old.value("testMode").toBool()
                && entries[id].value("sourceId") != old.value("sourceId"))) {
            auto inactive = old; inactive["active"] = false; inactive["status"] = "withdrawn";
            if (entries.value(id).value("conflict").toBool()) {
                inactive["conflict"] = true; inactive["error"] = "Conflicting application ID in multiple sources";
            }
            entries[id] = inactive;
        }
    }
    if (!widgetCatalog) {
        // Preserve legacy signed installations when an initial catalog removes them.
        for (const auto& item : (testMode() ? QVariantList{} : bootstrap().value("apps").toList())) {
            auto app = item.toMap(); const auto id = app.value("appId").toString();
            if (!entries.contains(id)) { app["sourceId"] = "nextkde"; app["active"] = false; app["status"] = "withdrawn"; entries[id] = app; }
        }
    }
    QVariantList result;
    for (const auto& entry : entries) result.append(entry);
    return result;
}
static QVariantMap findCatalogEntry(const QVariantList& list, const QString& id)
{
    QVariantMap match;
    for (const auto& value : list) {
        const auto entry = value.toMap();
        if (entry.value("appId").toString() == id) return entry;
        if (entry.value("key").toString() == id) { if (!match.isEmpty()) return {}; match = entry; }
    }
    return match;
}
QVariantList apps() { return resolveCatalogEntries(false); }
QVariantList widgets() { return resolveCatalogEntries(true); }
QVariantMap find(const QString& id) { return findCatalogEntry(apps(), id); }
QVariantMap findWidget(const QString& id) { return findCatalogEntry(widgets(), id); }
QString addSource(const QString& id, const QString& repository, const QString& fingerprint, const QString& publicKeyFile)
{
    if (!identifier(id) || !githubRepository(repository) || !matches("^[0-9A-F]{40}([0-9A-F]{24})?$", fingerprint))
        return "Invalid source ID, GitHub owner/repository or full fingerprint";
    const auto keys = read(publicKeyFile, 65536);
    if (keys.isEmpty()) return "Cannot read exported binary public key";
    QDir().mkpath(stateDirectory());
    QLockFile context(stateDirectory() + "/context.lock"), lock(stateDirectory() + "/sources.lock");
    if (!context.tryLock(0) || !lock.tryLock(0)) return "Source configuration is busy";
    auto config = configuration(); auto list = config.value("sources").toList();
    if (list.size() >= 32) return "At most 32 application sources are supported";
    for (const auto& value : list) if (value.toMap().value("id").toString() == id) return "Source ID already exists";
    // Old signed snapshots remain a rollback floor when the same source is re-added.
    const QVariantMap proposed{{"id", id}, {"repository", repository}, {"fingerprint", fingerprint}, {"publicKey", keys.toBase64()}};
    if ((QFileInfo::exists(cachePath(id, false)) && cachedCatalog(proposed, false).isEmpty())
        || (QFileInfo::exists(cachePath(id, true)) && cachedCatalog(proposed, true).isEmpty()))
        return "Source history does not verify with this key; use a new source ID";
    list.append(proposed);
    config["sources"] = list;
    return save(configPath(), QJsonDocument::fromVariant(config).toJson()) ? QString() : "Cannot save sources";
}
QString removeSource(const QString& id)
{
    QDir().mkpath(stateDirectory()); QLockFile context(stateDirectory() + "/context.lock"), lock(stateDirectory() + "/sources.lock");
    if (!context.tryLock(0) || !lock.tryLock(0)) return "Source configuration is busy";
    auto config = configuration(); QVariantList list;
    for (const auto& value : config.value("sources").toList())
        if (value.toMap().value("id").toString() != id) list.append(value);
    config["sources"] = list;
    return save(configPath(), QJsonDocument::fromVariant(config).toJson()) ? QString() : "Cannot save sources";
}
bool needsRefresh(const QVariantMap& catalog, const QVariantMap& state, const QDateTime& now)
{
    auto success = QDateTime::fromString(state.value("lastSuccess").toString(), Qt::ISODate);
    if (!success.isValid() && state.value("error").toString().isEmpty())
        success = QDateTime::fromString(state.value("lastChecked").toString(), Qt::ISODate);
    const auto expiry = QDateTime::fromString(catalog.value("expiresAt").toString(), Qt::ISODate);
    return catalog.isEmpty() || !expiry.isValid() || expiry <= now
        || (catalog.value("schemaVersion").toInt() < 2 && state.value("clientCatalogSchema").toInt() < 2)
        || !success.isValid() || success > now || success.secsTo(now) >= 1800;
}
QString refresh(const Cancelled& cancelled, bool ifNeeded)
{
    // Developer test sources and selected Releases only change on explicit refresh.
    if (ifNeeded && testMode()) return {};
    QDir().mkpath(stateDirectory()); QLockFile context(stateDirectory() + "/context.lock"), lock(stateDirectory() + "/sources.lock");
    if (!context.tryLock(1000) || !lock.tryLock(0)) return "Source refresh is already running";
    if (ifNeeded && testMode()) return {};
    QStringList errors;
    for (const auto& item : configuration().value("sources").toList()) {
        if (cancelled()) break;
        const auto source = item.toMap(); const auto id = source.value("id").toString();
        const auto repository = source.value("repository").toString();
        if (!identifier(id) || !githubRepository(repository)) { errors.append("Invalid source configuration"); continue; }
        const auto previous = cachedCatalog(source, false);
        const auto previousWidgets = cachedCatalog(source, true);
        auto state = readState("source-" + id);
        if (ifNeeded) {
            const auto now = QDateTime::currentDateTimeUtc();
            const auto attempted = QDateTime::fromString(state.value("pageAttempt").toString(), Qt::ISODate);
            if (attempted.isValid() && attempted <= now && attempted.secsTo(now) < 60) continue;
            state["pageAttempt"] = now.toString(Qt::ISODate);
            writeState("source-" + id, state);
            if (!needsRefresh(previous, state, now)) {
                cacheIcons(previous, source, cancelled, false);
                if (!previousWidgets.isEmpty()) cacheIcons(previousWidgets, source, cancelled, true);
                continue;
            }
        }
        QString error;
        const auto releaseBytes = fetch(QUrl("https://api.github.com/repos/" + repository + (testMode() && !source.value("releaseTag").toString().isEmpty()
            ? "/releases/tags/" + source.value("releaseTag").toString() : "/releases/latest")), repository, limit, &error, cancelled);
        const auto release = QJsonDocument::fromJson(releaseBytes).object();
        const auto tag = release.value("tag_name").toString();
        if (error.isEmpty() && (release.value("draft").toBool(true) || (release.value("prerelease").toBool(true) && (!testMode() || source.value("releaseTag").toString().isEmpty()))
            || (!source.value("releaseTag").toString().isEmpty() && testMode() && tag != source.value("releaseTag").toString())
            || !matches("^[A-Za-z0-9][A-Za-z0-9._-]{0,100}$", tag))) error = "Expected a published stable GitHub Release";
        const auto hasAssetNamed = [&](const QString& name) {
            for (const auto& value : release.value("assets").toArray())
                if (value.toObject().value("name").toString() == name) return true;
            return false;
        };
        const auto attachment = [&](const QString& name, qint64 maximum, QString* targetError) -> QByteArray {
            if (!targetError->isEmpty()) return {};
            const auto expected = "https://github.com/" + repository + "/releases/download/" + tag + '/' + name;
            int count = 0;
            for (const auto& value : release.value("assets").toArray()) {
                const auto asset = value.toObject();
                if (asset.value("name").toString() == name && asset.value("browser_download_url").toString() == expected) ++count;
            }
            if (count != 1) { *targetError = "Missing unique catalog release attachment"; return {}; }
            return fetch(QUrl(expected), repository, maximum, targetError, cancelled);
        };
        const auto bytes = attachment("catalog.json", limit, &error);
        const auto signature = attachment("catalog.json.sig", 65536, &error);
        auto catalog = QJsonDocument::fromJson(bytes).object().toVariantMap();
        if (error.isEmpty() && !verify(bytes, signature, QByteArray::fromBase64(source.value("publicKey").toByteArray()), source.value("fingerprint").toString())) error = "Catalog signature is invalid";
        if (error.isEmpty() && QFileInfo::exists(cachePath(id, false)) && previous.isEmpty()) error = "Previous catalog cannot be verified; refusing to reset rollback history";
        if (error.isEmpty()) error = validateUpdate(catalog, previous, id);
        // Persist each ready old image before readers see the new icon digests.
        // The signed catalog itself still advances independently of artwork.
        if (error.isEmpty()) rememberIcons(source, previous, false);
        if (error.isEmpty() && !save(cachePath(id, false), QJsonDocument::fromVariant(QVariantMap{{"catalog", bytes.toBase64()}, {"signature", signature.toBase64()}, {"releaseTag", source.value("releaseTag").toString()}}).toJson())) error = "Cannot save catalog";
        if (error.isEmpty()) cacheIcons(catalog, source, cancelled, false);
        else if (QDateTime::fromString(previous.value("expiresAt").toString(), Qt::ISODate) > QDateTime::currentDateTimeUtc())
            cacheIcons(previous, source, cancelled, false);

        QString widgetError;
        if (error.isEmpty() && (hasAssetNamed("widgets.json") || hasAssetNamed("widgets.json.sig"))) {
            const auto widgetBytes = attachment("widgets.json", limit, &widgetError);
            const auto widgetSignature = attachment("widgets.json.sig", 65536, &widgetError);
            const auto widgetCatalog = QJsonDocument::fromJson(widgetBytes).object().toVariantMap();
            if (widgetError.isEmpty() && !verify(widgetBytes, widgetSignature, QByteArray::fromBase64(source.value("publicKey").toByteArray()), source.value("fingerprint").toString())) widgetError = "Catalog signature is invalid";
            if (widgetError.isEmpty() && QFileInfo::exists(cachePath(id, true)) && previousWidgets.isEmpty()) widgetError = "Previous catalog cannot be verified; refusing to reset rollback history";
            if (widgetError.isEmpty()) widgetError = validateWidgetUpdate(widgetCatalog, previousWidgets, id);
            if (widgetError.isEmpty()) rememberIcons(source, previousWidgets, true);
            if (widgetError.isEmpty() && !save(cachePath(id, true), QJsonDocument::fromVariant(QVariantMap{{"catalog", widgetBytes.toBase64()}, {"signature", widgetSignature.toBase64()}, {"releaseTag", source.value("releaseTag").toString()}}).toJson())) widgetError = "Cannot save catalog";
            if (widgetError.isEmpty()) cacheIcons(widgetCatalog, source, cancelled, true);
            else if (QDateTime::fromString(previousWidgets.value("expiresAt").toString(), Qt::ISODate) > QDateTime::currentDateTimeUtc())
                cacheIcons(previousWidgets, source, cancelled, true);
        }

        state["error"] = error;
        state["widgetError"] = widgetError;
        state["lastChecked"] = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
        if (error.isEmpty()) {
            state["lastSuccess"] = state["lastChecked"];
            state["clientCatalogSchema"] = 2;
        }
        writeState("source-" + id, state);
        if (!error.isEmpty()) errors.append(id + ": " + error);
        if (!widgetError.isEmpty()) errors.append(id + " (widgets): " + widgetError);
    }
    return errors.join('\n');
}
}
