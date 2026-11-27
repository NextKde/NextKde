#include "WidgetPackages.h"
#include "AppCatalog.h"
#include "WidgetPackageIndex.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLockFile>
#include <QProcess>
#include <QRegularExpression>
#include <QScopeGuard>
#include <QStandardPaths>
#include <QUrl>
#include <QUuid>
#include <QtConcurrentRun>

namespace {

constexpr qint64 kMaxArchiveBytes = 32 * 1024 * 1024;
constexpr qint64 kMaxExtractedBytes = 64 * 1024 * 1024;
constexpr int kMaxArchiveEntries = 500;

bool matchesPattern(const QString& pattern, const QString& text)
{
    return QRegularExpression(pattern).match(text).hasMatch();
}

QString dataHomeRoot()
{
    const auto configured = qEnvironmentVariable("XDG_DATA_HOME");
    return QDir::isAbsolutePath(configured) ? configured : QDir::homePath() + QStringLiteral("/.local/share");
}

struct SemverParts {
    bool valid = false;
    qulonglong major = 0;
    qulonglong minor = 0;
    qulonglong patch = 0;
    QStringList prerelease;
};

SemverParts parseSemver(const QString& version)
{
    static const QRegularExpression re(QStringLiteral("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z.-]+))?$"));
    const auto match = re.match(version);
    if (!match.hasMatch())
        return {};
    bool okMajor = false, okMinor = false, okPatch = false;
    SemverParts out;
    out.major = match.captured(1).toULongLong(&okMajor);
    out.minor = match.captured(2).toULongLong(&okMinor);
    out.patch = match.captured(3).toULongLong(&okPatch);
    if (!okMajor || !okMinor || !okPatch)
        return {};
    const auto pre = match.captured(4);
    if (!pre.isEmpty())
        out.prerelease = pre.split(QLatin1Char('.'), Qt::KeepEmptyParts);
    out.valid = true;
    return out;
}

bool isAllDigits(const QString& text)
{
    if (text.isEmpty())
        return false;
    for (const auto ch : text)
        if (!ch.isDigit())
            return false;
    return true;
}

bool safeArchiveAssetName(const QString& asset)
{
    return matchesPattern(QStringLiteral("^[A-Za-z0-9][A-Za-z0-9._-]{0,140}\\.(tar\\.gz|tgz|zip|koswidget)$"), asset);
}

bool isTarGzAsset(const QString& asset)
{
    return asset.endsWith(QLatin1String(".tar.gz")) || asset.endsWith(QLatin1String(".tgz"));
}

bool runTool(const QString& program, const QStringList& args, QByteArray* stdoutOut, QString* errorOut)
{
    if (program.isEmpty()) {
        if (errorOut)
            *errorOut = QStringLiteral("Required archive extraction tool is not installed.");
        return false;
    }
    QProcess process;
    process.setProgram(program);
    process.setArguments(args);
    process.start();
    if (!process.waitForStarted(5000)) {
        if (errorOut)
            *errorOut = QStringLiteral("Failed to launch archive helper.");
        return false;
    }
    if (!process.waitForFinished(30000)) {
        process.kill();
        process.waitForFinished(1000);
        if (errorOut)
            *errorOut = QStringLiteral("Archive helper timed out.");
        return false;
    }
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        if (errorOut) {
            const auto stderrText = QString::fromUtf8(process.readAllStandardError()).trimmed();
            *errorOut = stderrText.isEmpty() ? QStringLiteral("Archive inspection or extraction failed.") : stderrText;
        }
        return false;
    }
    if (stdoutOut)
        *stdoutOut = process.readAllStandardOutput();
    return true;
}

bool validateArchiveMembers(const QByteArray& listing)
{
    if (listing.size() > 256 * 1024)
        return false;
    int count = 0;
    for (const auto& raw : listing.split('\n')) {
        const auto entry = QString::fromUtf8(raw).trimmed();
        if (entry.isEmpty())
            continue;
        if (++count > kMaxArchiveEntries)
            return false;
        if (entry.startsWith(QLatin1Char('/'))
            || entry.startsWith(QLatin1Char('\\'))
            || entry.contains(QLatin1Char('\\'))
            || entry == QLatin1String("..")
            || entry.startsWith(QLatin1String("../"))
            || entry.endsWith(QLatin1String("/.."))
            || entry.contains(QLatin1String("/../"))) {
            return false;
        }
    }
    return count > 0;
}

bool writeFileBytes(const QString& path, const QByteArray& bytes)
{
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size();
}

} // namespace

WidgetPackages::WidgetPackages(QObject* parent)
    : QObject(parent)
{
    syncCatalog();
    connect(&m_watcher, &QFutureWatcher<DeployResult>::finished, this, [this] {
        const auto appId = m_activeId;
        const auto activeName = m_activeName;
        const auto result = m_watcher.result();
        m_activeId.clear();
        m_activeName.clear();
        m_stage.clear();
        m_cancelled.store(false);
        if (!appId.isEmpty()) {
            if (result.code.isEmpty())
                m_results.remove(appId);
            else
                m_results[appId] = QVariantMap{{QStringLiteral("code"), result.code}, {QStringLiteral("message"), result.message}};
        }
        refresh();
        if (!activeName.isEmpty())
            emit taskFinished(activeName, result.code);
    });
}

WidgetPackages::~WidgetPackages()
{
    if (m_watcher.isRunning()) {
        m_cancelled.store(true);
        m_watcher.waitForFinished();
    }
}

QString WidgetPackages::widgetInstallRoot()
{
    return dataHomeRoot() + QStringLiteral("/kos/widgets");
}

int WidgetPackages::compareSemver(const QString& lhs, const QString& rhs)
{
    const auto a = parseSemver(lhs);
    const auto b = parseSemver(rhs);
    if (!a.valid || !b.valid)
        return QString::compare(lhs, rhs);
    if (a.major != b.major) return a.major < b.major ? -1 : 1;
    if (a.minor != b.minor) return a.minor < b.minor ? -1 : 1;
    if (a.patch != b.patch) return a.patch < b.patch ? -1 : 1;
    if (a.prerelease.isEmpty() && b.prerelease.isEmpty()) return 0;
    if (a.prerelease.isEmpty()) return 1;
    if (b.prerelease.isEmpty()) return -1;
    const int limit = qMin(a.prerelease.size(), b.prerelease.size());
    for (int i = 0; i < limit; ++i) {
        const auto& left = a.prerelease[i];
        const auto& right = b.prerelease[i];
        if (left == right)
            continue;
        const bool leftNum = isAllDigits(left);
        const bool rightNum = isAllDigits(right);
        if (leftNum && rightNum) {
            const auto li = left.toULongLong(), ri = right.toULongLong();
            if (li != ri)
                return li < ri ? -1 : 1;
        } else if (leftNum != rightNum) {
            return leftNum ? -1 : 1;
        } else {
            return QString::compare(left, right) < 0 ? -1 : 1;
        }
    }
    if (a.prerelease.size() == b.prerelease.size())
        return 0;
    return a.prerelease.size() < b.prerelease.size() ? -1 : 1;
}

WidgetPackages::DeployResult WidgetPackages::deployVerifiedArchive(
    const QString& appId,
    const QString& expectedVersion,
    const QString& assetName,
    const QString& expectedSha256,
    qint64 expectedSize,
    const QByteArray& archiveBytes,
    const QString& installRoot,
    bool requireUpgrade,
    const QString& currentVersion,
    bool allowDowngrade)
{
    if (!matchesPattern(QStringLiteral("^[A-Za-z][A-Za-z0-9_-]*(\\.[A-Za-z][A-Za-z0-9_-]*){2,}$"), appId)
        || appId.size() > 200 || !parseSemver(expectedVersion).valid || !safeArchiveAssetName(assetName)) {
        return {QStringLiteral("INVALID_RELEASE"), QStringLiteral("Invalid widget release descriptor."), {}};
    }
    if (requireUpgrade && !allowDowngrade && !currentVersion.isEmpty() && compareSemver(expectedVersion, currentVersion) <= 0) {
        return {QStringLiteral("VERSION_CONFLICT"), QStringLiteral("The release version does not upgrade the installed plugin."), {}};
    }
    if (expectedSize <= 0 || expectedSize > kMaxArchiveBytes || archiveBytes.size() != expectedSize
        || !matchesPattern(QStringLiteral("^[0-9a-f]{64}$"), expectedSha256)
        || QCryptographicHash::hash(archiveBytes, QCryptographicHash::Sha256).toHex() != expectedSha256.toUtf8()) {
        return {QStringLiteral("INTEGRITY_FAILED"), QStringLiteral("Downloaded plugin archive hash or size does not match."), {}};
    }

    if (!QDir().mkpath(installRoot)) {
        return {QStringLiteral("PERMISSION_DENIED"), QStringLiteral("Cannot create widget installation directory."), {}};
    }

    const QString uuid = QUuid::createUuid().toString(QUuid::WithoutBraces);
    const QString stagingDir = installRoot + QStringLiteral("/.staging-") + uuid;
    const auto cleanupStaging = qScopeGuard([stagingDir] {
        QDir(stagingDir).removeRecursively();
    });
    if (!QDir().mkpath(stagingDir + QStringLiteral("/extract"))
        || !QDir().mkpath(stagingDir + QStringLiteral("/verify-data/kos/widgets"))) {
        return {QStringLiteral("PERMISSION_DENIED"), QStringLiteral("Cannot prepare temporary staging directory."), {}};
    }

    const QString archivePath = stagingDir + QLatin1Char('/') + QFileInfo(assetName).fileName();
    if (!writeFileBytes(archivePath, archiveBytes)) {
        return {QStringLiteral("DISK_FULL"), QStringLiteral("Failed to write downloaded plugin archive."), {}};
    }

    QByteArray listing;
    QString toolError;
    const QString tarExe = QStandardPaths::findExecutable(QStringLiteral("tar"));
    const QString bsdTarExe = QStandardPaths::findExecutable(QStringLiteral("bsdtar"));
    const QString unzipExe = QStandardPaths::findExecutable(QStringLiteral("unzip"));
    if (isTarGzAsset(assetName)) {
        if (!runTool(tarExe, {QStringLiteral("-tzf"), archivePath}, &listing, &toolError))
            return {QStringLiteral("INVALID_PACKAGE"), toolError, {}};
        if (!validateArchiveMembers(listing))
            return {QStringLiteral("INVALID_PACKAGE"), QStringLiteral("Archive contains unsafe or invalid paths."), {}};
        if (!runTool(tarExe, {QStringLiteral("--no-same-owner"), QStringLiteral("--no-same-permissions"), QStringLiteral("-xzf"), archivePath, QStringLiteral("-C"), stagingDir + QStringLiteral("/extract")}, nullptr, &toolError))
            return {QStringLiteral("INVALID_PACKAGE"), toolError, {}};
    } else {
        if (!bsdTarExe.isEmpty()) {
            if (!runTool(bsdTarExe, {QStringLiteral("-tf"), archivePath}, &listing, &toolError))
                return {QStringLiteral("INVALID_PACKAGE"), toolError, {}};
            if (!validateArchiveMembers(listing))
                return {QStringLiteral("INVALID_PACKAGE"), QStringLiteral("Archive contains unsafe or invalid paths."), {}};
            if (!runTool(bsdTarExe, {QStringLiteral("--no-same-owner"), QStringLiteral("--no-same-permissions"), QStringLiteral("-xf"), archivePath, QStringLiteral("-C"), stagingDir + QStringLiteral("/extract")}, nullptr, &toolError))
                return {QStringLiteral("INVALID_PACKAGE"), toolError, {}};
        } else {
            if (!runTool(unzipExe, {QStringLiteral("-Z1"), archivePath}, &listing, &toolError))
                return {QStringLiteral("INVALID_PACKAGE"), toolError, {}};
            if (!validateArchiveMembers(listing))
                return {QStringLiteral("INVALID_PACKAGE"), QStringLiteral("Archive contains unsafe or invalid paths."), {}};
            if (!runTool(unzipExe, {QStringLiteral("-qq"), QStringLiteral("-o"), archivePath, QStringLiteral("-d"), stagingDir + QStringLiteral("/extract")}, nullptr, &toolError))
                return {QStringLiteral("INVALID_PACKAGE"), toolError, {}};
        }
    }

    const QString extractDir = stagingDir + QStringLiteral("/extract");
    qint64 totalExtractedBytes = 0;
    QDirIterator walker(extractDir, QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (walker.hasNext()) {
        walker.next();
        const QFileInfo info = walker.fileInfo();
        if (info.isSymLink()) {
            return {QStringLiteral("INVALID_PACKAGE"), QStringLiteral("Symlinks are not permitted inside widget packages."), {}};
        }
        if (info.isFile()) {
            totalExtractedBytes += info.size();
            if (totalExtractedBytes > kMaxExtractedBytes)
                return {QStringLiteral("INVALID_PACKAGE"), QStringLiteral("Extracted plugin package exceeds maximum allowed size."), {}};
        }
    }

    QString packageRoot;
    if (QFileInfo::exists(extractDir + QStringLiteral("/metadata.json"))) {
        packageRoot = extractDir;
    } else {
        QStringList topDirs;
        for (const auto& entry : QDir(extractDir).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot)) {
            if (entry.fileName() == QLatin1String("__MACOSX"))
                continue;
            topDirs.append(entry.fileName());
        }
        if (topDirs.size() == 1 && QFileInfo::exists(extractDir + QLatin1Char('/') + topDirs.first() + QStringLiteral("/metadata.json"))) {
            packageRoot = extractDir + QLatin1Char('/') + topDirs.first();
        }
    }
    if (packageRoot.isEmpty()) {
        return {QStringLiteral("INVALID_PACKAGE"), QStringLiteral("Archive does not contain a valid plugin metadata.json root."), {}};
    }

    const QString verifyRoot = stagingDir + QStringLiteral("/verify-data/kos/widgets/") + appId;
    if (!QDir().rename(packageRoot, verifyRoot)) {
        return {QStringLiteral("INVALID_PACKAGE"), QStringLiteral("Failed to stage extracted plugin directory for validation."), {}};
    }

    const QJsonObject indexSnapshot = KosPlatform::WidgetPackageIndex::snapshotForRoots({stagingDir + QStringLiteral("/verify-data")});
    const QJsonArray invalid = indexSnapshot.value(QStringLiteral("invalidPackages")).toArray();
    if (!invalid.isEmpty()) {
        const auto firstInvalid = invalid.first().toObject();
        return {QStringLiteral("INVALID_PACKAGE"), firstInvalid.value(QStringLiteral("reason")).toString(), {}};
    }
    const QJsonArray packages = indexSnapshot.value(QStringLiteral("packages")).toArray();
    if (packages.isEmpty()) {
        return {QStringLiteral("INVALID_PACKAGE"), QStringLiteral("No valid widget package entries were indexed."), {}};
    }
    for (const auto& value : packages) {
        const auto pkg = value.toObject();
        if (pkg.value(QStringLiteral("packageId")).toString() != appId
            || pkg.value(QStringLiteral("version")).toString() != expectedVersion) {
            return {QStringLiteral("INVALID_PACKAGE"),
                    QStringLiteral("Plugin metadata id or version does not match the signed release manifest."), {}};
        }
    }

    const QString targetDir = installRoot + QLatin1Char('/') + appId;
    const QFileInfo existingTarget(targetDir);
    if (existingTarget.exists() || existingTarget.isSymLink()) {
        if (!requireUpgrade || existingTarget.isSymLink()) {
            return {QStringLiteral("EXTERNAL_INSTALL"), QStringLiteral("Target plugin directory already exists outside managed updates."), {}};
        }
        const QString backupDir = installRoot + QStringLiteral("/.backup-") + uuid;
        if (!QDir().rename(targetDir, backupDir)) {
            return {QStringLiteral("PERMISSION_DENIED"), QStringLiteral("Failed to back up previous plugin installation."), {}};
        }
        if (!QDir().rename(verifyRoot, targetDir)) {
            QDir().rename(backupDir, targetDir);
            return {QStringLiteral("PERMISSION_DENIED"), QStringLiteral("Failed to swap updated plugin directory into place."), {}};
        }
        QDir(backupDir).removeRecursively();
    } else {
        if (!QDir().rename(verifyRoot, targetDir)) {
            return {QStringLiteral("PERMISSION_DENIED"), QStringLiteral("Failed to move verified plugin into installation directory."), {}};
        }
    }

    return {QString(), QString(), expectedVersion};
}

WidgetPackages::DeployResult WidgetPackages::removeManagedPackage(const QString& appId, const QString& installRoot)
{
    if (!matchesPattern(QStringLiteral("^[A-Za-z][A-Za-z0-9_-]*(\\.[A-Za-z][A-Za-z0-9_-]*){2,}$"), appId)
        || appId.size() > 200) {
        return {QStringLiteral("UNINSTALL_FAILED"), QStringLiteral("Invalid plugin identifier."), {}};
    }
    const QString targetDir = installRoot + QLatin1Char('/') + appId;
    const QFileInfo info(targetDir);
    if (!info.exists() && !info.isSymLink())
        return {};
    if (info.isSymLink()) {
        return {QStringLiteral("NOT_MANAGED"), QStringLiteral("Externally linked plugins cannot be uninstalled from Settings."), {}};
    }
    const QString trashDir = installRoot + QStringLiteral("/.trash-") + QUuid::createUuid().toString(QUuid::WithoutBraces);
    if (!QDir().rename(targetDir, trashDir)) {
        return {QStringLiteral("UNINSTALL_FAILED"), QStringLiteral("Failed to remove plugin directory."), {}};
    }
    QDir(trashDir).removeRecursively();
    return {};
}

void WidgetPackages::syncCatalog()
{
    const auto context = AppCatalog::contextToken();
    if (context != m_catalogContext) {
        m_widgets.clear();
        m_results.clear();
        m_catalogContext = context;
    }

    QVariantList next;
    for (const auto& value : AppCatalog::widgets()) {
        const auto entry = value.toMap();
        const auto appId = entry.value(QStringLiteral("appId")).toString();
        const auto key = entry.value(QStringLiteral("key")).toString();
        const auto id = entry.value(QStringLiteral("sourceId")).toString() == QLatin1String("nextkde") ? key : appId;
        QVariantMap state;
        for (const auto& previous : m_widgets) {
            if (previous.toMap().value(QStringLiteral("appId")).toString() == appId)
                state = previous.toMap();
        }
        state[QStringLiteral("id")] = id;
        state[QStringLiteral("appId")] = appId;
        state[QStringLiteral("name")] = entry.value(QStringLiteral("name")).toMap().value(QStringLiteral("en"));
        state[QStringLiteral("nameLocales")] = entry.value(QStringLiteral("name"));
        state[QStringLiteral("description")] = entry.value(QStringLiteral("description")).toMap().value(QStringLiteral("en"));
        state[QStringLiteral("descriptionLocales")] = entry.value(QStringLiteral("description"));
        state[QStringLiteral("repositoryPath")] = entry.value(QStringLiteral("repository"));
        state[QStringLiteral("repository")] = QStringLiteral("https://github.com/") + entry.value(QStringLiteral("repository")).toString();
        state[QStringLiteral("sourceId")] = entry.value(QStringLiteral("sourceId"));
        state[QStringLiteral("catalogActive")] = entry.value(QStringLiteral("active"));
        state[QStringLiteral("catalogError")] = entry.value(QStringLiteral("error"));
        state[QStringLiteral("format")] = entry.value(QStringLiteral("format"));
        state[QStringLiteral("releaseTag")] = entry.value(QStringLiteral("releaseTag"));
        state[QStringLiteral("testInstalled")] = AppCatalog::widgetReceipt(appId).value(QStringLiteral("entry")).toMap().value(QStringLiteral("testMode")).toBool();
        state[QStringLiteral("developerSignature")] = !entry.value(QStringLiteral("publisher")).toMap().isEmpty();
        state[QStringLiteral("iconName")] = QStringLiteral("grid");
        state[QStringLiteral("iconSource")] = AppCatalog::iconFile(entry);
        state[QStringLiteral("catalogVersion")] = entry.value(QStringLiteral("release")).toMap().value(QStringLiteral("version"));
        state[QStringLiteral("latestVersion")] = state.value(QStringLiteral("catalogVersion"));
        state[QStringLiteral("catalogApproved")] = !entry.value(QStringLiteral("release")).toMap().isEmpty();
        state[QStringLiteral("manifestName")] = entry.value(QStringLiteral("manifest"));
        state[QStringLiteral("rawEntry")] = entry;
        next.append(state);
    }
    m_widgets = next;
}

QVariantList WidgetPackages::widgets() const
{
    const QJsonObject indexSnapshot = KosPlatform::WidgetPackageIndex::snapshotForRoots({dataHomeRoot()});
    QMap<QString, QString> indexedVersions;
    for (const auto& value : indexSnapshot.value(QStringLiteral("packages")).toArray()) {
        const auto pkg = value.toObject();
        const auto pkgId = pkg.value(QStringLiteral("packageId")).toString();
        if (!pkgId.isEmpty() && !indexedVersions.contains(pkgId))
            indexedVersions.insert(pkgId, pkg.value(QStringLiteral("version")).toString());
    }
    QMap<QString, QString> invalidReasons;
    for (const auto& value : indexSnapshot.value(QStringLiteral("invalidPackages")).toArray()) {
        const auto inv = value.toObject();
        invalidReasons.insert(inv.value(QStringLiteral("id")).toString(), inv.value(QStringLiteral("reason")).toString());
    }

    const QString root = widgetInstallRoot();
    QVariantList visible;
    for (const auto& value : m_widgets) {
        auto state = value.toMap();
        const auto appId = state.value(QStringLiteral("appId")).toString();
        const QFileInfo dirInfo(root + QLatin1Char('/') + appId);
        const bool exists = dirInfo.exists() || dirInfo.isSymLink();
        const auto receipt = AppCatalog::widgetReceipt(appId);
        const bool installed = exists;
        const bool managed = exists && !dirInfo.isSymLink() && !receipt.isEmpty();
        const QString installedVersion = indexedVersions.contains(appId)
            ? indexedVersions.value(appId)
            : receipt.value(QStringLiteral("version")).toString();
        const QString latestVersion = state.value(QStringLiteral("latestVersion")).toString();
        const bool catalogActive = state.value(QStringLiteral("catalogActive")).toBool();
        const QString releaseTag = state.value(QStringLiteral("releaseTag")).toString();
        const bool updateAvailable = installed && managed && catalogActive
            && (AppCatalog::testMode()
                ? (!releaseTag.isEmpty() || (!latestVersion.isEmpty() && compareSemver(latestVersion, installedVersion) != 0))
                : (!latestVersion.isEmpty() && compareSemver(latestVersion, installedVersion) > 0));

        state[QStringLiteral("installed")] = installed;
        state[QStringLiteral("managed")] = managed;
        state[QStringLiteral("statusKnown")] = true;
        state[QStringLiteral("version")] = installed ? installedVersion : QString();
        state[QStringLiteral("updateAvailable")] = updateAvailable;
        state[QStringLiteral("available")] = catalogActive
            && state.value(QStringLiteral("format")).toString() == QLatin1String("qml-widget")
            && (state.value(QStringLiteral("catalogApproved")).toBool() || AppCatalog::testMode());
        state[QStringLiteral("invalidReason")] = installed ? invalidReasons.value(appId) : QString();
        state[QStringLiteral("busy")] = m_watcher.isRunning() && m_activeId == appId;
        state[QStringLiteral("stage")] = state.value(QStringLiteral("busy")).toBool()
            ? (m_cancelled.load() ? QStringLiteral("cancelling") : m_stage)
            : QString();

        if (m_results.contains(appId)) {
            const auto outcome = m_results.value(appId);
            state[QStringLiteral("code")] = outcome.value(QStringLiteral("code"));
            state[QStringLiteral("message")] = outcome.value(QStringLiteral("message"));
        } else if (installed && !managed) {
            state[QStringLiteral("code")] = QStringLiteral("EXTERNALLY_MANAGED");
        } else {
            state.remove(QStringLiteral("code"));
            state.remove(QStringLiteral("message"));
        }
        state.remove(QStringLiteral("rawEntry"));

        if (catalogActive || installed || !state.value(QStringLiteral("catalogError")).toString().isEmpty())
            visible.append(state);
    }
    return visible;
}

bool WidgetPackages::busy() const
{
    return m_watcher.isRunning();
}

bool WidgetPackages::hasActiveMutation() const
{
    return m_watcher.isRunning();
}

int WidgetPackages::indexOf(const QString& id) const
{
    for (int i = 0; i < m_widgets.size(); ++i) {
        if (m_widgets[i].toMap().value(QStringLiteral("id")).toString() == id)
            return i;
    }
    return -1;
}

void WidgetPackages::refresh()
{
    syncCatalog();
    emit changed();
}

void WidgetPackages::perform(const QString& id, const QString& action)
{
    const int index = indexOf(id);
    if (index < 0 || busy())
        return;
    if (action != QLatin1String("install") && action != QLatin1String("update") && action != QLatin1String("uninstall"))
        return;

    const auto descriptor = m_widgets[index].toMap();
    const auto appId = descriptor.value(QStringLiteral("appId")).toString();
    const auto rawEntry = descriptor.value(QStringLiteral("rawEntry")).toMap();
    const bool catalogActive = descriptor.value(QStringLiteral("catalogActive")).toBool();
    if (action != QLatin1String("uninstall") && (!catalogActive || descriptor.value(QStringLiteral("format")).toString() != QLatin1String("qml-widget")))
        return;

    // Evaluate live disk + receipt state before mutating.
    QVariantMap currentState;
    for (const auto& item : widgets()) {
        if (item.toMap().value(QStringLiteral("appId")).toString() == appId) {
            currentState = item.toMap();
            break;
        }
    }
    const bool installed = currentState.value(QStringLiteral("installed")).toBool();
    const bool managed = currentState.value(QStringLiteral("managed")).toBool();
    const QString currentVersion = currentState.value(QStringLiteral("version")).toString();

    if (action == QLatin1String("install") && installed) {
        m_results[appId] = QVariantMap{{QStringLiteral("code"), QStringLiteral("ALREADY_INSTALLED")},
                                       {QStringLiteral("message"), QStringLiteral("This plugin is already installed.")}};
        emit changed();
        return;
    }
    if ((action == QLatin1String("update") || action == QLatin1String("uninstall")) && (!installed || !managed)) {
        m_results[appId] = QVariantMap{{QStringLiteral("code"), QStringLiteral("NOT_MANAGED")},
                                       {QStringLiteral("message"), QStringLiteral("Installed outside Settings.")}};
        emit changed();
        return;
    }

    m_results.remove(appId);
    m_cancelled.store(false);
    m_activeId = appId;
    m_activeName = descriptor.value(QStringLiteral("name")).toString();
    m_stage = action;
    const QString installRoot = widgetInstallRoot();
    const bool testModeNow = AppCatalog::testMode();

    emit changed();

    m_watcher.setFuture(QtConcurrent::run([this, appId, action, rawEntry, currentVersion, installRoot, testModeNow]() -> DeployResult {
        const auto cancelled = [this] { return m_cancelled.load(); };
        if (cancelled())
            return {QStringLiteral("CANCELLED"), QStringLiteral("Operation cancelled"), {}};

        QDir().mkpath(AppCatalog::stateDirectory());
        QLockFile lock(AppCatalog::stateDirectory() + QStringLiteral("/widget-mutation.lock"));
        if (!lock.tryLock(0))
            return {QStringLiteral("BUSY"), QStringLiteral("Another plugin operation is already running."), {}};

        if (action == QLatin1String("uninstall")) {
            if (AppCatalog::widgetReceipt(appId).isEmpty())
                return {QStringLiteral("NOT_MANAGED"), QStringLiteral("Installed outside Settings."), {}};
            const auto res = removeManagedPackage(appId, installRoot);
            if (!res.code.isEmpty())
                return res;
            if (!AppCatalog::forgetWidgetInstallation(appId))
                return {QStringLiteral("RECEIPT_WRITE_FAILED"), QStringLiteral("Plugin files were removed, but its receipt could not be cleared."), {}};
            return {};
        }

        const bool updating = (action == QLatin1String("update"));
        const QString repository = rawEntry.value(QStringLiteral("repository")).toString();
        const QString manifestAssetName = rawEntry.value(QStringLiteral("manifest")).toString();
        const auto publisher = rawEntry.value(QStringLiteral("publisher")).toMap();
        const QByteArray pubKeys = QByteArray::fromBase64(publisher.value(QStringLiteral("publicKey")).toByteArray());
        const QString pubFingerprint = publisher.value(QStringLiteral("fingerprint")).toString();

        QString tag;
        QByteArray manifestBytes;
        QByteArray publisherSig;
        if (testModeNow && (!rawEntry.value(QStringLiteral("releaseTag")).toString().isEmpty() || rawEntry.value(QStringLiteral("release")).toMap().isEmpty())) {
            const QString selectedTag = rawEntry.value(QStringLiteral("releaseTag")).toString();
            const QUrl releaseApi(QStringLiteral("https://api.github.com/repos/") + repository
                + (selectedTag.isEmpty() ? QStringLiteral("/releases/latest") : QStringLiteral("/releases/tags/") + selectedTag));
            QString netErr;
            const QByteArray releaseBytes = AppCatalog::fetch(releaseApi, repository, 4 * 1024 * 1024, &netErr, cancelled);
            if (cancelled())
                return {QStringLiteral("CANCELLED"), QStringLiteral("Operation cancelled"), {}};
            if (!netErr.isEmpty())
                return {netErr.contains(QLatin1String("rate limit")) ? QStringLiteral("RATE_LIMITED") : QStringLiteral("NETWORK_ERROR"), netErr, {}};
            const auto releaseObj = QJsonDocument::fromJson(releaseBytes).object();
            tag = releaseObj.value(QStringLiteral("tag_name")).toString();
            if (releaseObj.value(QStringLiteral("draft")).toBool(true)
                || (releaseObj.value(QStringLiteral("prerelease")).toBool(true) && selectedTag.isEmpty())
                || (!selectedTag.isEmpty() && tag != selectedTag)
                || !AppCatalog::releaseTag(tag)) {
                return {QStringLiteral("NO_RELEASE"), QStringLiteral("No eligible GitHub release found."), {}};
            }
            const auto fetchReleaseAsset = [&](const QString& assetName, qint64 maxBytes, QString* errOut) -> QByteArray {
                const QString expectedUrl = QStringLiteral("https://github.com/") + repository + QStringLiteral("/releases/download/") + tag + QLatin1Char('/') + assetName;
                int hits = 0;
                for (const auto& item : releaseObj.value(QStringLiteral("assets")).toArray()) {
                    const auto obj = item.toObject();
                    if (obj.value(QStringLiteral("name")).toString() == assetName
                        && obj.value(QStringLiteral("browser_download_url")).toString() == expectedUrl) {
                        ++hits;
                    }
                }
                if (hits != 1) {
                    *errOut = QStringLiteral("Missing unique release asset: ") + assetName;
                    return {};
                }
                return AppCatalog::fetch(QUrl(expectedUrl), repository, maxBytes, errOut, cancelled);
            };
            QString assetErr;
            manifestBytes = fetchReleaseAsset(manifestAssetName, 1024 * 1024, &assetErr);
            if (!assetErr.isEmpty())
                return {cancelled() ? QStringLiteral("CANCELLED") : QStringLiteral("INVALID_RELEASE"), assetErr, {}};
            if (!publisher.isEmpty()) {
                publisherSig = fetchReleaseAsset(manifestAssetName + QStringLiteral(".sig"), 65536, &assetErr);
                if (!assetErr.isEmpty())
                    return {cancelled() ? QStringLiteral("CANCELLED") : QStringLiteral("INVALID_RELEASE"), assetErr, {}};
            }
        } else {
            const auto release = rawEntry.value(QStringLiteral("release")).toMap();
            if (release.isEmpty())
                return {QStringLiteral("RELEASE_UNAVAILABLE"), QStringLiteral("No approved catalog release is available."), {}};
            tag = release.value(QStringLiteral("tag")).toString();
            manifestBytes = QByteArray::fromBase64(release.value(QStringLiteral("manifest")).toByteArray());
            publisherSig = QByteArray::fromBase64(release.value(QStringLiteral("signature")).toByteArray());
        }

        if (!publisher.isEmpty() && !AppCatalog::verify(manifestBytes, publisherSig, pubKeys, pubFingerprint)) {
            return {QStringLiteral("INVALID_RELEASE"), QStringLiteral("Publisher signature verification failed."), {}};
        }

        const auto manifestObj = QJsonDocument::fromJson(manifestBytes).object();
        const QString version = manifestObj.value(QStringLiteral("version")).toString();
        const auto pkgObj = manifestObj.value(QStringLiteral("package")).toObject();
        const QString asset = pkgObj.value(QStringLiteral("asset")).toString();
        const QString sha256 = pkgObj.value(QStringLiteral("sha256")).toString();
        const double sizeDouble = pkgObj.value(QStringLiteral("size")).toDouble();
        const qint64 size = qint64(sizeDouble);
        if (manifestObj.value(QStringLiteral("schemaVersion")).toInt() != 2
            || manifestObj.value(QStringLiteral("appId")).toString() != appId
            || !parseSemver(version).valid
            || tag.isEmpty() || !safeArchiveAssetName(asset)
            || !matchesPattern(QStringLiteral("^[0-9a-f]{64}$"), sha256)
            || size <= 0 || size > kMaxArchiveBytes || sizeDouble != double(size)) {
            return {QStringLiteral("INVALID_RELEASE"), QStringLiteral("Invalid widget release manifest."), {}};
        }

        if (updating && !testModeNow && compareSemver(version, currentVersion) <= 0) {
            return {QStringLiteral("VERSION_CONFLICT"), QStringLiteral("The release version does not upgrade the installed plugin."), {}};
        }

        QString downloadErr;
        const QUrl downloadUrl(QStringLiteral("https://github.com/") + repository + QStringLiteral("/releases/download/") + tag + QLatin1Char('/') + asset);
        const QByteArray archiveBytes = AppCatalog::fetch(downloadUrl, repository, kMaxArchiveBytes, &downloadErr, cancelled);
        if (cancelled())
            return {QStringLiteral("CANCELLED"), QStringLiteral("Operation cancelled"), {}};
        if (!downloadErr.isEmpty()) {
            const QString code = downloadErr.contains(QLatin1String("large")) ? QStringLiteral("RESPONSE_TOO_LARGE")
                : downloadErr.contains(QLatin1String("rate limit")) ? QStringLiteral("RATE_LIMITED")
                : QStringLiteral("DOWNLOAD_FAILED");
            return {code, downloadErr, {}};
        }

        const auto deployed = deployVerifiedArchive(appId, version, asset, sha256, size, archiveBytes,
                                                    installRoot, updating, currentVersion, testModeNow);
        if (!deployed.code.isEmpty())
            return deployed;

        const QVariantMap receipt{
            {QStringLiteral("entry"), rawEntry},
            {QStringLiteral("sourceId"), rawEntry.value(QStringLiteral("sourceId"))},
            {QStringLiteral("version"), version},
            {QStringLiteral("tag"), tag},
            {QStringLiteral("sha256"), sha256},
            {QStringLiteral("installedAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}
        };
        if (!AppCatalog::recordWidgetInstallation(appId, receipt)) {
            return {QStringLiteral("RECEIPT_WRITE_FAILED"),
                    QStringLiteral("Plugin was installed, but its source receipt could not be saved."), version};
        }
        return deployed;
    }));
}

void WidgetPackages::cancel(const QString& id)
{
    const int index = indexOf(id);
    if (index < 0)
        return;
    const auto appId = m_widgets[index].toMap().value(QStringLiteral("appId")).toString();
    if (m_watcher.isRunning() && m_activeId == appId) {
        m_cancelled.store(true);
        emit changed();
    }
}

void WidgetPackages::openRepository(const QString& id)
{
    const int index = indexOf(id);
    if (index >= 0)
        QDesktopServices::openUrl(QUrl(m_widgets[index].toMap().value(QStringLiteral("repository")).toString()));
}
