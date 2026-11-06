#include "FlatpakRelease.h"
#include "FlatpakTrustPolicy.h"
#include "IndependentAppRegistry.h"

#include <QCryptographicHash>
#include <QDir>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTimer>
#include <QUrl>
#include <limits>

#pragma push_macro("signals")
#undef signals
#include <flatpak.h>
#pragma pop_macro("signals")

namespace {
constexpr qint64 metadataLimit = 256 * 1024;
constexpr qint64 bundleLimit = 2LL * 1024 * 1024 * 1024;
struct Failure { QString code, message; };
[[noreturn]] void fail(const QString& code, const QString& message) { throw Failure{code, message}; }
void checkCancelled(const FlatpakRelease::Cancelled& cancelled)
{
    if (cancelled()) fail("CANCELLED", "The operation was cancelled.");
}
bool matches(const QString& pattern, const QString& value)
{
    return QRegularExpression(pattern).match(value).hasMatch();
}
bool versionParts(const QString& version, QList<qulonglong>& parts)
{
    if (!matches("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$", version)) return false;
    for (const auto& part : version.split('.')) {
        bool ok = false;
        const auto number = part.toULongLong(&ok);
        if (!ok) return false;
        parts.append(number);
    }
    return true;
}
bool validUrl(const QUrl& url, const QString& repo, bool redirected)
{
    if (!url.isValid() || url.scheme() != "https" || !url.userInfo().isEmpty()
        || url.port(443) != 443 || url.hasFragment()) return false;
    const auto path = url.path();
    if (path.contains("..") || path.contains('\\')) return false;
    if (url.host() == "api.github.com")
        return !url.hasQuery() && path == "/repos/NextKde/" + repo + "/releases/latest";
    if (url.host() == "github.com")
        return !url.hasQuery() && path.startsWith("/NextKde/" + repo + "/releases/download/");
    return redirected && (url.host() == "release-assets.githubusercontent.com" || url.host() == "objects.githubusercontent.com");
}

// Runs only inside the QtConcurrent worker. The local event loop lets Qt's
// network timers and cancellation run without blocking the Settings/CLI thread.
class Download {
public:
    QString repo;
    FlatpakRelease::Cancelled cancelled;
    FlatpakRelease::Progress progress;
    QElapsedTimer budget;
    int budgetMs;
    Download(QString repository, FlatpakRelease::Cancelled stop, FlatpakRelease::Progress notify, int total)
        : repo(std::move(repository)), cancelled(std::move(stop)), progress(std::move(notify)), budgetMs(total) { budget.start(); }

    QByteArray fetch(const QUrl& initial, qint64 limit, const QString& path = {}, qint64 expected = -1)
    {
        for (int attempt = 1; attempt <= 3; ++attempt) {
            checkCancelled(cancelled);
            if (budget.elapsed() >= budgetMs) fail("NETWORK_TIMEOUT", "The download time budget was exhausted.");
            progress(path.isEmpty() ? "Checking signed GitHub release" : QString("Downloading Flatpak bundle (attempt %1/3)").arg(attempt), -1);
            QElapsedTimer absolute;
            absolute.start();
            QNetworkAccessManager network;
            QUrl url = initial;
            bool retry = false;
            for (int redirects = 0; redirects <= 5; ++redirects) {
                if (!validUrl(url, repo, redirects != 0)) fail("UNTRUSTED_URL", "Release download URL is outside the fixed GitHub repository and attachment hosts.");
                QSaveFile file(path);
                if (!path.isEmpty() && !file.open(QIODevice::WriteOnly)) fail("PERMISSION_DENIED", "Cannot create the private bundle download.");
                if (!path.isEmpty()) file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
                QByteArray data;
                qint64 received = 0;
                QString localError;
                bool timeout = false;
                QNetworkRequest request(url);
                request.setRawHeader("User-Agent", "NextKde-Flatpak/1");
                request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
                request.setTransferTimeout(30000);
                auto* reply = network.get(request);
                reply->setReadBufferSize(128 * 1024);
                QEventLoop loop;
                QTimer poll;
                poll.setInterval(100);
                const auto consume = [&] {
                    if (!reply->isOpen()) return;
                    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
                    if (status != 200) { reply->readAll(); return; }
                    const auto length = reply->header(QNetworkRequest::ContentLengthHeader).toLongLong();
                    if (length > limit || (expected >= 0 && length > 0 && length != expected)) {
                        localError = "RESPONSE_TOO_LARGE"; reply->abort(); return;
                    }
                    while (reply->bytesAvailable() > 0) {
                        const auto bytes = reply->read(128 * 1024);
                        received += bytes.size();
                        if (received > limit || (expected >= 0 && received > expected)) {
                            localError = "RESPONSE_TOO_LARGE"; reply->abort(); return;
                        }
                        if (path.isEmpty()) data.append(bytes);
                        else if (file.write(bytes) != bytes.size()) {
                            localError = file.error() == QFileDevice::ResourceError ? "DISK_FULL" : "PERMISSION_DENIED";
                            reply->abort(); return;
                        }
                    }
                };
                QObject::connect(reply, &QNetworkReply::readyRead, &loop, consume);
                QObject::connect(reply, &QNetworkReply::downloadProgress, &loop, [&](qint64 done, qint64) {
                    if (!path.isEmpty() && expected > 0) progress("Downloading Flatpak bundle", int(qMin<qint64>(99, done * 100 / expected)));
                });
                QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
                QObject::connect(&poll, &QTimer::timeout, &loop, [&] {
                    if (cancelled()) reply->abort();
                    else if (absolute.elapsed() >= (path.isEmpty() ? 30000 : 600000) || budget.elapsed() >= budgetMs) {
                        timeout = true; reply->abort();
                    }
                });
                poll.start();
                loop.exec();
                poll.stop();
                consume();
                checkCancelled(cancelled);
                if (!localError.isEmpty()) fail(localError, "The download exceeded its size bound or could not be written.");
                const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
                if (status >= 300 && status < 400) {
                    if (redirects == 5) fail("UNTRUSTED_URL", "Too many attachment redirects.");
                    url = url.resolved(reply->attribute(QNetworkRequest::RedirectionTargetAttribute).toUrl());
                    reply->deleteLater();
                    continue;
                }
                const auto error = reply->error();
                if (!timeout && error == QNetworkReply::NoError && status == 200) {
                    if (received == 0 || (expected >= 0 && received != expected)) fail("INTEGRITY_FAILED", "The downloaded attachment length does not match its signed manifest.");
                    if (!path.isEmpty() && !file.commit()) fail("DISK_FULL", "Cannot finish writing the Flatpak bundle.");
                    return data;
                }
                if (status == 404) fail("RELEASE_UNAVAILABLE", "The stable release or required Flatpak attachment has not been published.");
                if (status == 429 || (status == 403 && reply->rawHeader("X-RateLimit-Remaining") == "0")) {
                    const auto after = reply->rawHeader("Retry-After").left(100);
                    fail("RATE_LIMITED", after.isEmpty() ? "GitHub rate limit reached. Retry later."
                        : "GitHub rate limit reached. Retry-After: " + QString::fromLatin1(after));
                }
                retry = timeout || error == QNetworkReply::TimeoutError || error == QNetworkReply::ConnectionRefusedError
                    || error == QNetworkReply::RemoteHostClosedError || error == QNetworkReply::HostNotFoundError
                    || error == QNetworkReply::TemporaryNetworkFailureError || (status >= 500 && status < 600);
                if (!retry || attempt == 3 || budget.elapsed() >= budgetMs)
                    fail(timeout || error == QNetworkReply::TimeoutError ? "NETWORK_TIMEOUT" : "DOWNLOAD_FAILED",
                        QString("GitHub download failed (HTTP %1, network code %2). No package deployment was started.").arg(status).arg(int(error)));
                break;
            }
            if (retry) {
                progress(QString("Retrying GitHub download (%1/3)").arg(attempt + 1), -1);
                QElapsedTimer delay;
                delay.start();
                while (delay.elapsed() < attempt * 2000) {
                    checkCancelled(cancelled);
                    if (budget.elapsed() >= budgetMs) fail("NETWORK_TIMEOUT", "The download time budget was exhausted.");
                    QEventLoop wait;
                    QTimer::singleShot(100, &wait, &QEventLoop::quit);
                    wait.exec();
                }
            }
        }
        fail("DOWNLOAD_FAILED", "Could not download the release attachment.");
    }
};

bool verify(const QString& appId, const QByteArray& manifest, const QByteArray& signature,
    const FlatpakRelease::Cancelled& cancelled)
{
    if (manifest.isEmpty() || manifest.size() > metadataLimit || signature.isEmpty() || signature.size() > 65536) return false;
    const auto keys = FlatpakRelease::publicKeys(appId);
    if (keys.isEmpty()) return false;
    const auto verifier = QStandardPaths::findExecutable("gpgv");
    if (verifier.isEmpty()) fail("DEPENDENCY_UNSATISFIED", "gpgv is required to verify Flatpak release signatures.");
    const auto cache = qEnvironmentVariable("XDG_CACHE_HOME", QDir::homePath() + "/.cache") + "/kos-settings/flatpak";
    if (!QDir::isAbsolutePath(cache) || !QDir().mkpath(cache)) fail("PERMISSION_DENIED", "Cannot create the private signature verification directory.");
    QTemporaryDir temporary(cache + "/verify-XXXXXX");
    if (!temporary.isValid()) fail("PERMISSION_DENIED", "Cannot create the private signature verification directory.");
    const auto write = [&](const QString& name, const QByteArray& bytes) {
        QFile file(temporary.filePath(name));
        if (!file.open(QIODevice::WriteOnly | QIODevice::NewOnly, QFileDevice::ReadOwner | QFileDevice::WriteOwner)
            || file.write(bytes) != bytes.size()) fail("PERMISSION_DENIED", "Cannot write signature verification input.");
    };
    write("publisher.gpg", keys); write("manifest.json", manifest); write("manifest.sig", signature);
    QProcess process;
    process.setProgram(verifier);
    process.setArguments({"--homedir", temporary.path(), "--keyring", temporary.filePath("publisher.gpg"), "--status-fd", "1",
        "--", temporary.filePath("manifest.sig"), temporary.filePath("manifest.json")});
    process.start();
    QElapsedTimer deadline;
    deadline.start();
    QByteArray output;
    while (!process.waitForFinished(100)) {
        output += process.readAllStandardOutput(); process.readAllStandardError();
        if (cancelled() || deadline.elapsed() > 10000 || output.size() > 65536) {
            process.kill(); process.waitForFinished(1000);
            checkCancelled(cancelled);
            return false;
        }
        if (process.state() == QProcess::NotRunning) return false;
    }
    checkCancelled(cancelled);
    output += process.readAllStandardOutput();
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0 || output.size() > 65536) return false;
    bool valid = false;
    for (const auto& line : output.split('\n')) {
        if (line.startsWith("[GNUPG:] VALIDSIG ")) {
            const auto fields = line.simplified().split(' ');
            // VALIDSIG: fingerprint date timestamp expires version reserved pka hash class [primary].
            if (fields.size() < 11) return false;
            const auto primary = QString::fromLatin1(fields.size() >= 12 ? fields[11] : fields[2]);
            valid |= FlatpakRelease::fingerprints(appId).contains(primary)
                && (fields[9] == "8" || fields[9] == "9" || fields[9] == "10");
        } else if (line.startsWith("[GNUPG:] BADSIG ") || line.startsWith("[GNUPG:] ERRSIG ")
            || line.startsWith("[GNUPG:] EXPKEYSIG ") || line.startsWith("[GNUPG:] REVKEYSIG ")
            || line.startsWith("[GNUPG:] EXPSIG ")) return false;
    }
    return valid;
}

QVariantMap parseManifest(const QString& appId, const QString& arch, const QByteArray& bytes)
{
    QJsonParseError error;
    const auto object = QJsonDocument::fromJson(bytes, &error).object();
    QList<qulonglong> parts;
    const auto version = object.value("version").toString();
    if (error.error != QJsonParseError::NoError || object.value("schemaVersion").toInt() != 2
        || object.value("appId").toString() != appId || !versionParts(version, parts)
        || !matches("^[0-9a-f]{40}$", object.value("revision").toString()))
        fail("INVALID_RELEASE", "Invalid signed Flatpak release identity or version; this release lacks an installation plan.");
    const auto bundle = object.value("bundles").toObject().value(arch).toObject();
    if (bundle.isEmpty()) fail("ARCH_UNAVAILABLE", "No Flatpak bundle has been published for this architecture.");
    const auto name = bundle.value("asset").toString();
    const auto size = bundle.value("size").toDouble(-1);
    if (!matches("^[A-Za-z0-9][A-Za-z0-9._-]*\\.flatpak$", name)
        || bundle.value("ref").toString() != QString("app/%1/%2/stable").arg(appId, arch)
        || !matches("^[0-9a-f]{64}$", bundle.value("commit").toString())
        || !matches("^[0-9a-f]{64}$", bundle.value("sha256").toString())
        || size <= 0 || size > bundleLimit || double(qint64(size)) != size)
        fail("INVALID_RELEASE", "The signed Flatpak attachment has invalid ref, commit, size or digest.");
    const auto metadata = QByteArray::fromBase64(bundle.value("metadata").toString().toLatin1());
    const auto metadataDigest = bundle.value("metadataSha256").toString();
    const auto installedSize = bundle.value("installedSize").toDouble(-1);
    const auto runtime = bundle.value("runtime").toObject();
    if (metadata.isEmpty() || metadata.size() > metadataLimit
        || !matches("^[0-9a-f]{64}$", metadataDigest)
        || QString::fromLatin1(QCryptographicHash::hash(metadata, QCryptographicHash::Sha256).toHex()) != metadataDigest
        || installedSize < 0 || installedSize > bundleLimit || double(qint64(installedSize)) != installedSize
        || !matches("^runtime/[A-Za-z0-9.\\-]+/[A-Za-z0-9_\\-]+/[A-Za-z0-9_.\\-]+$", runtime.value("ref").toString()))
        fail("INVALID_RELEASE", "The signed Flatpak release has no valid application metadata or runtime plan.");
    const auto extensions = bundle.value("requiredExtensions");
    if (!extensions.isArray() || extensions.toArray().size() > 128)
        fail("INVALID_RELEASE", "The signed Flatpak release has an invalid extension plan.");
    for (const auto& item : extensions.toArray()) {
        const auto extension = item.toObject();
        if (!matches("^runtime/[A-Za-z0-9.\\-]+/[A-Za-z0-9_\\-]+/[A-Za-z0-9_.\\-]+$", extension.value("ref").toString()))
            fail("INVALID_RELEASE", "The signed Flatpak release has an invalid extension reference.");
    }
    auto result = bundle.toVariantMap();
    result["schemaVersion"] = 2;
    result["version"] = version; result["revision"] = object.value("revision").toString();
    result["arch"] = arch; result["branch"] = "stable";
    return result;
}
}

namespace FlatpakRelease {
QStringList fingerprints(const QString& appId)
{
    QStringList result;
    for (const auto& publisher : FlatpakTrustPolicy::bundlePublishers)
        if (QString::fromLatin1(publisher.appId) == appId
            && matches("^[0-9A-F]{40}([0-9A-F]{24})?$", QString::fromLatin1(publisher.primaryFingerprint)))
            result.append(QString::fromLatin1(publisher.primaryFingerprint));
    return result;
}
QByteArray publicKeys(const QString& appId)
{
    QByteArray result;
    for (const auto& publisher : FlatpakTrustPolicy::bundlePublishers) {
        if (QString::fromLatin1(publisher.appId) != appId
            || !fingerprints(appId).contains(QString::fromLatin1(publisher.primaryFingerprint))) continue;
        const auto decoded = QByteArray::fromBase64Encoding(QByteArray(publisher.publicKeyBase64), QByteArray::AbortOnBase64DecodingErrors);
        if (!decoded || decoded.decoded.isEmpty()) return {};
        result.append(decoded.decoded);
    }
    return result;
}
bool configured(const QString& appId) { return !publicKeys(appId).isEmpty(); }
int compareVersions(const QString& left, const QString& right, bool* valid)
{
    QList<qulonglong> a, b;
    const bool ok = versionParts(left, a) && versionParts(right, b);
    if (valid) *valid = ok;
    if (!ok) return 0;
    for (int i = 0; i < 3; ++i) { if (a[i] < b[i]) return -1; if (a[i] > b[i]) return 1; }
    return 0;
}
QVariantMap discover(const QString& appId, const QString& arch, const Cancelled& cancelled, const Progress& progress)
{
    try {
        const auto* app = IndependentAppRegistry::find(appId);
        if (!app || !configured(appId)) fail("BUNDLE_KEY_MISSING", "A reviewed Flatpak release public key has not been shipped with this core version.");
        Download client(QString::fromLatin1(app->repository), cancelled, progress, 90000);
        const auto response = client.fetch(QUrl("https://api.github.com/repos/NextKde/" + client.repo + "/releases/latest"), metadataLimit);
        QJsonParseError error;
        const auto release = QJsonDocument::fromJson(response, &error).object();
        const auto tag = release.value("tag_name").toString();
        QList<qulonglong> parts;
        if (error.error != QJsonParseError::NoError || release.value("draft").toBool(true)
            || release.value("prerelease").toBool(true) || !tag.startsWith('v') || !versionParts(tag.mid(1), parts))
            fail("INVALID_RELEASE", "Expected a published stable vX.Y.Z GitHub release.");
        const auto attachment = [&](const QString& name) {
            QJsonObject found;
            int count = 0;
            for (const auto& value : release.value("assets").toArray()) {
                const auto asset = value.toObject();
                if (asset.value("name").toString() == name) { found = asset; ++count; }
            }
            const auto expected = "https://github.com/NextKde/" + client.repo + "/releases/download/" + tag + '/' + name;
            if (count != 1 || found.value("browser_download_url").toString() != expected)
                fail("RELEASE_UNAVAILABLE", "The stable release is missing a unique required Flatpak attachment.");
            return QUrl(expected);
        };
        const auto manifestName = QString::fromLatin1(app->manifest);
        const auto manifest = client.fetch(attachment(manifestName), metadataLimit);
        const auto signature = client.fetch(attachment(manifestName + ".sig"), 65536);
        progress("Verifying Flatpak release signature", -1);
        if (!verify(appId, manifest, signature, cancelled)) fail("FLATPAK_UNTRUSTED", "The Flatpak release manifest signature is invalid or its publisher is not approved.");
        auto result = parseManifest(appId, arch, manifest);
        if (result.value("version").toString() != tag.mid(1)) fail("INVALID_RELEASE", "Signed version does not match the GitHub release tag.");
        result["url"] = attachment(result.value("asset").toString()).toString();
        result["manifest"] = manifest.toBase64(); result["signature"] = signature.toBase64();
        return result;
    } catch (const Failure& failure) { return {{"code", failure.code}, {"message", failure.message}}; }
}
QVariantMap validateDownloaded(const QString& appId, const QVariantMap& discovery, const QString& path,
    const Cancelled& cancelled)
{
    try {
        const auto manifest = QByteArray::fromBase64(discovery.value("manifest").toByteArray());
        const auto signature = QByteArray::fromBase64(discovery.value("signature").toByteArray());
        if (!verify(appId, manifest, signature, cancelled)) fail("FLATPAK_UNTRUSTED", "Flatpak release signature validation failed before deployment.");
        const auto signedData = parseManifest(appId, discovery.value("arch").toString(), manifest);
        for (auto it = signedData.begin(); it != signedData.end(); ++it)
            if (discovery.value(it.key()) != it.value()) fail("INVALID_RELEASE", "The selected release changed before deployment.");
        QFile file(path);
        if (!QDir::isAbsolutePath(path) || !file.open(QIODevice::ReadOnly)
            || file.size() != signedData.value("size").toLongLong()) fail("INTEGRITY_FAILED", "Cannot read the complete downloaded bundle.");
        QCryptographicHash hash(QCryptographicHash::Sha256);
        while (!file.atEnd()) { checkCancelled(cancelled); hash.addData(file.read(128 * 1024)); if (file.error() != QFileDevice::NoError) fail("INTEGRITY_FAILED", "Cannot read complete Flatpak bundle."); }
        if (QString::fromLatin1(hash.result().toHex()) != signedData.value("sha256").toString()) fail("INTEGRITY_FAILED", "Flatpak bundle digest does not match its signed release.");
        auto* bundleFile = g_file_new_for_path(path.toUtf8().constData());
        GError* bundleError = nullptr;
        auto* bundle = flatpak_bundle_ref_new(bundleFile, &bundleError);
        if (!bundle) {
            const auto message = bundleError ? QString::fromUtf8(bundleError->message)
                : QStringLiteral("Cannot inspect Flatpak bundle metadata.");
            g_clear_error(&bundleError);
            g_object_unref(bundleFile);
            fail("INTEGRITY_FAILED", message);
        }
        auto* metadataBytes = flatpak_bundle_ref_get_metadata(bundle);
        gsize metadataSize = 0;
        const auto* metadataData = metadataBytes
            ? static_cast<const char*>(g_bytes_get_data(metadataBytes, &metadataSize)) : nullptr;
        const QByteArray actualMetadata(metadataData ? metadataData : "", qsizetype(metadataSize));
        const auto actualDigest = QString::fromLatin1(
            QCryptographicHash::hash(actualMetadata, QCryptographicHash::Sha256).toHex());
        const auto actualSize = flatpak_bundle_ref_get_installed_size(bundle);
        const bool metadataMatches = actualMetadata
                == QByteArray::fromBase64(signedData.value("metadata").toString().toLatin1())
            && actualDigest == signedData.value("metadataSha256").toString()
            && actualSize == signedData.value("installedSize").toULongLong();
        if (metadataBytes) g_bytes_unref(metadataBytes);
        g_object_unref(bundle);
        g_object_unref(bundleFile);
        if (!metadataMatches)
            fail("INTEGRITY_FAILED", "Flatpak bundle metadata or installed size does not match the signed release plan.");
        return {};
    } catch (const Failure& failure) { return {{"code", failure.code}, {"message", failure.message}}; }
}
QVariantMap download(const QString& appId, const QVariantMap& discovery, const QString& directory,
    const Cancelled& cancelled, const Progress& progress)
{
    try {
        const auto* app = IndependentAppRegistry::find(appId);
        if (!app || !QDir::isAbsolutePath(directory)) fail("INVALID_RELEASE", "Invalid application or private download directory.");
        const auto manifest = QByteArray::fromBase64(discovery.value("manifest").toByteArray());
        const auto signature = QByteArray::fromBase64(discovery.value("signature").toByteArray());
        if (!verify(appId, manifest, signature, cancelled)) fail("FLATPAK_UNTRUSTED", "Flatpak release signature validation failed before download.");
        const auto signedData = parseManifest(appId, discovery.value("arch").toString(), manifest);
        for (auto it = signedData.begin(); it != signedData.end(); ++it)
            if (discovery.value(it.key()) != it.value()) fail("INVALID_RELEASE", "The selected release changed after discovery.");
        const auto expectedUrl = "https://github.com/NextKde/" + QString::fromLatin1(app->repository)
            + "/releases/download/v" + signedData.value("version").toString() + '/' + signedData.value("asset").toString();
        if (discovery.value("url").toString() != expectedUrl) fail("UNTRUSTED_URL", "Unexpected Flatpak attachment URL.");
        Download client(QString::fromLatin1(app->repository), cancelled, progress, 30 * 60 * 1000);
        const auto path = directory + "/application.flatpak";
        client.fetch(QUrl(expectedUrl), bundleLimit, path, signedData.value("size").toLongLong());
        progress("Verifying Flatpak bundle digest", -1);
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly)) fail("PERMISSION_DENIED", "Cannot read downloaded bundle.");
        QCryptographicHash hash(QCryptographicHash::Sha256);
        while (!file.atEnd()) { checkCancelled(cancelled); hash.addData(file.read(128 * 1024)); if (file.error() != QFileDevice::NoError) fail("INTEGRITY_FAILED", "Cannot read complete Flatpak bundle."); }
        if (QString::fromLatin1(hash.result().toHex()) != signedData.value("sha256").toString()) fail("INTEGRITY_FAILED", "Flatpak bundle digest does not match its signed release.");
        return {{"path", path}};
    } catch (const Failure& failure) { return {{"code", failure.code}, {"message", failure.message}}; }
}
}
