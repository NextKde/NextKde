#include "WidgetPackageIndex.h"

#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QStandardPaths>

namespace KosPlatform::WidgetPackageIndex {
namespace {
constexpr int kMaxPackages = 512;
constexpr int kMaxWidgetsPerPackage = 32;
constexpr int kMaxRevisionScanFiles = 64;
constexpr int kMaxWatchDirs = 256;
constexpr int kMaxWatchFiles = 1024;
constexpr int kDebounceMs = 200;
constexpr qint64 kMaxMetadataBytes = 64 * 1024;

QStringList defaultDataRoots()
{
    QStringList roots = QStandardPaths::standardLocations(QStandardPaths::GenericDataLocation);
    if (roots.isEmpty())
        roots.append(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation));
    return roots;
}

bool validId(const QString &id)
{
    if (id.isEmpty() || id.size() > 192 || id.startsWith('.') || id.endsWith('.'))
        return false;
    const auto labels = id.split('.');
    if (labels.size() < 3)
        return false;
    for (const QString &label : labels) {
        if (label.isEmpty() || label.size() > 63 || !label.front().isLetterOrNumber()
            || !label.back().isLetterOrNumber())
            return false;
        for (const QChar ch : label) {
            if (!ch.isLetterOrNumber() && ch != QLatin1Char('-'))
                return false;
        }
    }
    return true;
}

bool validSize(const QJsonValue &value)
{
    if (!value.isArray()) return false;
    const QJsonArray pair = value.toArray();
    if (pair.size() != 2) return false;
    for (const QJsonValue &axis : pair) {
        if (!axis.isDouble()) return false;
        const double number = axis.toDouble();
        if (number < 1 || number > 4 || number != static_cast<int>(number)) return false;
    }
    return true;
}

bool isSafePackageFile(const QFileInfo &info, const QString &canonicalRoot)
{
    if (!info.exists() || !info.isFile() || info.isSymLink())
        return false;
    const QString canonicalFile = info.canonicalFilePath();
    if (canonicalFile.isEmpty())
        return false;
    return canonicalFile.startsWith(canonicalRoot + QLatin1Char('/'));
}

QString computePackageRevision(const QString &canonicalRoot)
{
    qint64 maxMtimeMs = 0;
    qint64 totalBytes = 0;
    int scanned = 0;
    QDirIterator it(canonicalRoot, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        it.next();
        const QFileInfo info = it.fileInfo();
        if (info.isSymLink() || !info.canonicalFilePath().startsWith(canonicalRoot + QLatin1Char('/')))
            continue;
        maxMtimeMs = qMax(maxMtimeMs, info.lastModified().toMSecsSinceEpoch());
        totalBytes += info.size();
        if (++scanned >= kMaxRevisionScanFiles)
            break;
    }
    return QStringLiteral("%1-%2").arg(maxMtimeMs).arg(totalBytes);
}

QJsonObject buildWidgetEntry(const QJsonObject &source,
                             const QJsonObject *packageDefaults,
                             const QString &widgetId,
                             const QString &packageId,
                             const QString &version,
                             int minApiRevision,
                             const QString &canonicalRoot,
                             const QString &revision,
                             const QString &packageSource,
                             QString *errorCode,
                             QString *errorReason)
{
    auto fail = [errorCode, errorReason](const QString &code, const QString &reason) -> QJsonObject {
        if (errorCode)
            *errorCode = code;
        if (errorReason)
            *errorReason = reason;
        return {};
    };

    QJsonObject merged = packageDefaults ? *packageDefaults : source;
    if (packageDefaults) {
        merged.remove(QStringLiteral("widgets"));
        for (auto it = source.constBegin(); it != source.constEnd(); ++it) {
            if (it.key() == QLatin1String("i18n"))
                continue;
            merged.insert(it.key(), it.value());
        }
        const QJsonValue baseI18nVal = packageDefaults->value(QStringLiteral("i18n"));
        const QJsonValue childI18nVal = source.value(QStringLiteral("i18n"));
        if (!baseI18nVal.isUndefined() && !baseI18nVal.isNull() && !baseI18nVal.isObject())
            return fail(QStringLiteral("invalid-metadata"), QStringLiteral("metadata.json 'i18n' must be an object"));
        if (!childI18nVal.isUndefined() && !childI18nVal.isNull() && !childI18nVal.isObject())
            return fail(QStringLiteral("invalid-metadata"), QStringLiteral("metadata.json 'i18n' must be an object"));

        QJsonObject mergedI18n = baseI18nVal.isObject() ? baseI18nVal.toObject() : QJsonObject();
        const QString defaultPkgName = packageDefaults->value(QStringLiteral("name")).toString();
        for (auto it = mergedI18n.begin(); it != mergedI18n.end(); ++it) {
            if (!it.value().isObject()) continue;
            QJsonObject locBlock = it.value().toObject();
            if (!locBlock.contains(QStringLiteral("packageName"))) {
                const QString locName = locBlock.value(QStringLiteral("name")).toString();
                if (!locName.isEmpty())
                    locBlock.insert(QStringLiteral("packageName"), locName);
                else if (!defaultPkgName.isEmpty())
                    locBlock.insert(QStringLiteral("packageName"), defaultPkgName);
            }
            it.value() = locBlock;
        }
        if (childI18nVal.isObject()) {
            const QJsonObject childI18n = childI18nVal.toObject();
            for (auto it = childI18n.constBegin(); it != childI18n.constEnd(); ++it) {
                if (it.value().isObject()) {
                    QJsonObject locBlock = mergedI18n.value(it.key()).toObject();
                    const QJsonObject childBlock = it.value().toObject();
                    for (auto cit = childBlock.constBegin(); cit != childBlock.constEnd(); ++cit)
                        locBlock.insert(cit.key(), cit.value());
                    mergedI18n.insert(it.key(), locBlock);
                } else {
                    mergedI18n.insert(it.key(), it.value());
                }
            }
        }
        if (!mergedI18n.isEmpty())
            merged.insert(QStringLiteral("i18n"), mergedI18n);
    }

    const QJsonValue styleValue = merged.value(QStringLiteral("style"));
    const QString style = styleValue.toString();
    if (!styleValue.isString() || (style != QLatin1String("material") && style != QLatin1String("macos")))
        return fail(QStringLiteral("invalid-metadata"), QStringLiteral("metadata.json 'style' must be \"material\" or \"macos\""));

    if (!merged.value(QStringLiteral("name")).isString() || merged.value(QStringLiteral("name")).toString().isEmpty())
        return fail(QStringLiteral("invalid-metadata"), QStringLiteral("metadata.json 'name' must be a non-empty string"));

    const QJsonValue i18nValue = merged.value(QStringLiteral("i18n"));
    if (!i18nValue.isUndefined() && !i18nValue.isNull() && !i18nValue.isObject())
        return fail(QStringLiteral("invalid-metadata"), QStringLiteral("metadata.json 'i18n' must be an object"));

    QJsonArray containers;
    const QJsonValue containersValue = merged.value(QStringLiteral("containers"));
    if (containersValue.isUndefined() || containersValue.isNull()) {
        containers.append(QStringLiteral("desktop"));
    } else {
        if (!containersValue.isArray() || containersValue.toArray().isEmpty())
            return fail(QStringLiteral("invalid-metadata"), QStringLiteral("metadata.json 'containers' must be a non-empty array"));
        QSet<QString> seenContainers;
        for (const QJsonValue &item : containersValue.toArray()) {
            const QString c = item.toString();
            if (!item.isString() || (c != QLatin1String("desktop") && c != QLatin1String("dock")))
                return fail(QStringLiteral("invalid-metadata"), QStringLiteral("metadata.json 'containers' entries must be \"desktop\" or \"dock\""));
            if (seenContainers.contains(c))
                return fail(QStringLiteral("invalid-metadata"), QStringLiteral("metadata.json 'containers' contains duplicate entry '%1'").arg(c));
            seenContainers.insert(c);
            containers.append(c);
        }
    }

    int dockUnits = 4;
    const QJsonValue dockUnitsValue = merged.value(QStringLiteral("dockUnits"));
    if (!dockUnitsValue.isUndefined() && !dockUnitsValue.isNull()) {
        if (!dockUnitsValue.isDouble())
            return fail(QStringLiteral("invalid-metadata"), QStringLiteral("metadata.json 'dockUnits' must be an integer between 2 and 4"));
        const double unitsDouble = dockUnitsValue.toDouble();
        if (unitsDouble < 2 || unitsDouble > 4 || unitsDouble != static_cast<int>(unitsDouble))
            return fail(QStringLiteral("invalid-metadata"), QStringLiteral("metadata.json 'dockUnits' must be an integer between 2 and 4"));
        dockUnits = static_cast<int>(unitsDouble);
    }

    const bool isDockOnly = (containers.size() == 1 && containers.first().toString() == QLatin1String("dock"));

    QJsonArray sizes;
    const QJsonValue sizesValue = merged.value(QStringLiteral("sizes"));
    if (isDockOnly && (sizesValue.isUndefined() || sizesValue.isNull())) {
        sizes.append(QJsonArray{dockUnits, 1});
    } else {
        if (!sizesValue.isArray() || sizesValue.toArray().isEmpty())
            return fail(QStringLiteral("invalid-metadata"), QStringLiteral("metadata.json 'sizes' must be a non-empty array of [cols, rows]"));
        sizes = sizesValue.toArray();
    }

    QSet<QString> seenSizes;
    for (const QJsonValue &size : sizes) {
        if (!validSize(size))
            return fail(QStringLiteral("invalid-metadata"),
                        QStringLiteral("metadata.json 'sizes' contains an invalid [cols, rows] entry (integers 1..4 required)"));
        const QString key = QString::fromUtf8(QJsonDocument(size.toArray()).toJson(QJsonDocument::Compact));
        if (seenSizes.contains(key))
            return fail(QStringLiteral("invalid-metadata"),
                        QStringLiteral("metadata.json 'sizes' contains duplicate entry %1").arg(key));
        seenSizes.insert(key);
    }

    QJsonValue defaultSize = merged.value(QStringLiteral("defaultSize"));
    if (isDockOnly && (defaultSize.isUndefined() || defaultSize.isNull()))
        defaultSize = sizes.first();
    if (!validSize(defaultSize))
        return fail(QStringLiteral("invalid-metadata"),
                    QStringLiteral("metadata.json 'defaultSize' is missing or invalid (expected [cols, rows] with integers 1..4)"));
    const QString defaultKey = QString::fromUtf8(QJsonDocument(defaultSize.toArray()).toJson(QJsonDocument::Compact));
    if (!seenSizes.contains(defaultKey))
        return fail(QStringLiteral("invalid-metadata"),
                    QStringLiteral("metadata.json 'defaultSize' %1 must be listed in 'sizes'").arg(defaultKey));

    merged.insert(QStringLiteral("sizes"), sizes);
    merged.insert(QStringLiteral("defaultSize"), defaultSize);

    auto resolveEntryRel = [](const QJsonObject &obj, const QString &key, const QString &fallback, bool *ok) -> QString {
        *ok = true;
        if (!obj.contains(key) || obj.value(key).isUndefined() || obj.value(key).isNull())
            return fallback;
        const QJsonValue val = obj.value(key);
        if (!val.isString() || val.toString().isEmpty() || QDir::isAbsolutePath(val.toString())) {
            *ok = false;
            return {};
        }
        return val.toString();
    };

    bool widgetRelOk = true;
    bool snapshotRelOk = true;
    const QString widgetRel = resolveEntryRel(source, QStringLiteral("widgetEntry"), QStringLiteral("Widget.qml"), &widgetRelOk);
    const QString snapshotRel = resolveEntryRel(source, QStringLiteral("snapshotEntry"), QStringLiteral("Snapshot.qml"), &snapshotRelOk);
    if (!widgetRelOk)
        return fail(QStringLiteral("missing-entry"), QStringLiteral("Invalid 'widgetEntry' relative path"));
    if (!snapshotRelOk)
        return fail(QStringLiteral("missing-entry"), QStringLiteral("Invalid 'snapshotEntry' relative path"));

    const QDir packageDir(canonicalRoot);
    const QFileInfo widget(packageDir.filePath(widgetRel));
    const QFileInfo snapshot(packageDir.filePath(snapshotRel));
    if (!isSafePackageFile(widget, canonicalRoot))
        return fail(QStringLiteral("missing-entry"),
                    QStringLiteral("Missing or unsafe %1 (symlinks and paths escaping package root are not allowed)").arg(widgetRel));
    if (!isSafePackageFile(snapshot, canonicalRoot))
        return fail(QStringLiteral("missing-entry"),
                    QStringLiteral("Missing or unsafe %1 (symlinks and paths escaping package root are not allowed)").arg(snapshotRel));

    bool hasSettings = false;
    QFileInfo settings;
    if (source.contains(QStringLiteral("settingsEntry"))
        && !source.value(QStringLiteral("settingsEntry")).isUndefined()
        && !source.value(QStringLiteral("settingsEntry")).isNull()) {
        bool settingsRelOk = true;
        const QString settingsRel = resolveEntryRel(source, QStringLiteral("settingsEntry"), QString(), &settingsRelOk);
        if (!settingsRelOk || settingsRel.isEmpty())
            return fail(QStringLiteral("missing-entry"), QStringLiteral("Invalid 'settingsEntry' relative path"));
        settings = QFileInfo(packageDir.filePath(settingsRel));
        if (!isSafePackageFile(settings, canonicalRoot))
            return fail(QStringLiteral("missing-entry"),
                        QStringLiteral("Missing or unsafe %1 (symlinks and paths escaping package root are not allowed)").arg(settingsRel));
        hasSettings = true;
    } else {
        settings = QFileInfo(widget.dir().filePath(QStringLiteral("Settings.qml")));
        if (settings.exists() || settings.isSymLink()) {
            if (isSafePackageFile(settings, canonicalRoot)) {
                hasSettings = true;
            } else {
                qWarning().noquote() << "[WidgetPackageIndex] Ignoring unsafe Settings.qml for"
                                     << widgetId << "at" << settings.filePath();
            }
        }
    }

    bool hasPopup = false;
    QFileInfo popup;
    if (source.contains(QStringLiteral("popupEntry"))
        && !source.value(QStringLiteral("popupEntry")).isUndefined()
        && !source.value(QStringLiteral("popupEntry")).isNull()) {
        bool popupRelOk = true;
        const QString popupRel = resolveEntryRel(source, QStringLiteral("popupEntry"), QString(), &popupRelOk);
        if (!popupRelOk || popupRel.isEmpty())
            return fail(QStringLiteral("missing-entry"), QStringLiteral("Invalid 'popupEntry' relative path"));
        popup = QFileInfo(packageDir.filePath(popupRel));
        if (!isSafePackageFile(popup, canonicalRoot))
            return fail(QStringLiteral("missing-entry"),
                        QStringLiteral("Missing or unsafe %1 (symlinks and paths escaping package root are not allowed)").arg(popupRel));
        hasPopup = true;
    } else {
        popup = QFileInfo(widget.dir().filePath(QStringLiteral("Popup.qml")));
        if (popup.exists() || popup.isSymLink()) {
            if (isSafePackageFile(popup, canonicalRoot)) {
                hasPopup = true;
            } else {
                qWarning().noquote() << "[WidgetPackageIndex] Ignoring unsafe Popup.qml for"
                                     << widgetId << "at" << popup.filePath();
            }
        }
    }

    QJsonObject result = merged;
    result.insert(QStringLiteral("id"), widgetId);
    result.insert(QStringLiteral("packageId"), packageId);
    if (packageDefaults && packageDefaults->value(QStringLiteral("name")).isString())
        result.insert(QStringLiteral("packageName"), packageDefaults->value(QStringLiteral("name")).toString());
    result.insert(QStringLiteral("source"), packageSource);
    result.insert(QStringLiteral("version"), version);
    result.insert(QStringLiteral("minApiRevision"), minApiRevision);
    result.insert(QStringLiteral("containers"), containers);
    result.insert(QStringLiteral("dockUnits"), dockUnits);
    result.insert(QStringLiteral("available"), true);
    result.insert(QStringLiteral("rootPath"), canonicalRoot);
    result.insert(QStringLiteral("widgetEntry"), widget.canonicalFilePath());
    result.insert(QStringLiteral("snapshotEntry"), snapshot.canonicalFilePath());
    result.insert(QStringLiteral("revision"), revision);
    result.insert(QStringLiteral("hasSettings"), hasSettings);
    if (hasSettings)
        result.insert(QStringLiteral("settingsEntry"), settings.canonicalFilePath());
    else
        result.remove(QStringLiteral("settingsEntry"));
    result.insert(QStringLiteral("hasPopup"), hasPopup);
    if (hasPopup)
        result.insert(QStringLiteral("popupEntry"), popup.canonicalFilePath());
    else
        result.remove(QStringLiteral("popupEntry"));
    return result;
}

void readPackageEntries(const QString &dataRoot, const QString &subdir, const QString &packageSource,
                        const QString &directoryName,
                        int minSdkVersion, int maxSdkVersion, int currentApiRevision,
                        QSet<QString> &seenWidgetIds,
                        QJsonArray &packages,
                        QJsonArray &invalidPackages)
{
    const QString root = QDir(dataRoot).filePath(subdir + QLatin1Char('/') + directoryName);
    auto recordInvalid = [&invalidPackages](const QString &id, const QString &path,
                                            const QString &code, const QString &reason) {
        qWarning().noquote() << "[WidgetPackageIndex] Rejected widget package"
                             << id << "[" << code << "]"
                             << "(" << path << "):" << reason;
        invalidPackages.append(QJsonObject{
            {QStringLiteral("id"), id},
            {QStringLiteral("path"), path},
            {QStringLiteral("code"), code},
            {QStringLiteral("reason"), reason}
        });
    };

    if (!validId(directoryName)) {
        recordInvalid(directoryName, root, QStringLiteral("invalid-id"),
                      QStringLiteral("Invalid package directory ID '%1' (must be reverse-domain with >= 3 dot-separated alphanumeric/hyphen segments)").arg(directoryName));
        return;
    }

    const QFileInfo dirInfo(root);
    if (!dirInfo.exists() || !dirInfo.isDir()) {
        recordInvalid(directoryName, root, QStringLiteral("broken-root"),
                      dirInfo.isSymLink()
                          ? QStringLiteral("Package root is a broken or non-directory symlink")
                          : QStringLiteral("Package root is not a directory"));
        return;
    }

    const QString canonicalRoot = dirInfo.canonicalFilePath();
    if (canonicalRoot.isEmpty() || !QFileInfo(canonicalRoot).isDir()) {
        recordInvalid(directoryName, root, QStringLiteral("broken-root"),
                      QStringLiteral("Unable to resolve canonical directory for package root"));
        return;
    }

    const QDir packageDir(canonicalRoot);
    const QFileInfo metadataInfo(packageDir.filePath(QStringLiteral("metadata.json")));
    if (!isSafePackageFile(metadataInfo, canonicalRoot)) {
        recordInvalid(directoryName, root, QStringLiteral("missing-metadata"),
                      QStringLiteral("Missing or unsafe metadata.json (symlinks and paths escaping package root are not allowed)"));
        return;
    }
    if (metadataInfo.size() <= 0 || metadataInfo.size() > kMaxMetadataBytes) {
        recordInvalid(directoryName, root, QStringLiteral("missing-metadata"),
                      QStringLiteral("metadata.json is empty or exceeds %1 bytes").arg(kMaxMetadataBytes));
        return;
    }

    QFile file(metadataInfo.canonicalFilePath());
    if (!file.open(QIODevice::ReadOnly)) {
        recordInvalid(directoryName, root, QStringLiteral("missing-metadata"),
                      QStringLiteral("Failed to open metadata.json: %1").arg(file.errorString()));
        return;
    }
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        recordInvalid(directoryName, root, QStringLiteral("invalid-json"),
                      QStringLiteral("Invalid metadata.json: %1").arg(
                          parseError.error != QJsonParseError::NoError ? parseError.errorString() : QStringLiteral("root value must be a JSON object")));
        return;
    }

    const QJsonObject metadata = document.object();
    const QString packageId = metadata.value(QStringLiteral("id")).toString();
    if (!validId(packageId)) {
        recordInvalid(directoryName, root, QStringLiteral("invalid-metadata"),
                      QStringLiteral("metadata.json 'id' is missing or invalid"));
        return;
    }
    if (packageId != directoryName) {
        recordInvalid(directoryName, root, QStringLiteral("invalid-metadata"),
                      QStringLiteral("metadata.json 'id' ('%1') does not match directory name ('%2')").arg(packageId, directoryName));
        return;
    }

    const QJsonValue versionValue = metadata.value(QStringLiteral("version"));
    if (!versionValue.isString() || versionValue.toString().isEmpty()) {
        recordInvalid(packageId, root, QStringLiteral("invalid-metadata"),
                      QStringLiteral("metadata.json 'version' must be a non-empty string"));
        return;
    }
    const QString version = versionValue.toString();

    const QJsonValue sdkVersionValue = metadata.value(QStringLiteral("sdkVersion"));
    if (!sdkVersionValue.isDouble()) {
        recordInvalid(packageId, root, QStringLiteral("invalid-metadata"),
                      QStringLiteral("metadata.json 'sdkVersion' must be a positive integer"));
        return;
    }
    const double sdkVersionDouble = sdkVersionValue.toDouble();
    if (sdkVersionDouble < 1 || sdkVersionDouble != static_cast<int>(sdkVersionDouble)) {
        recordInvalid(packageId, root, QStringLiteral("invalid-metadata"),
                      QStringLiteral("metadata.json 'sdkVersion' must be a positive integer"));
        return;
    }
    const int sdkVersion = static_cast<int>(sdkVersionDouble);
    if (sdkVersion < minSdkVersion) {
        recordInvalid(packageId, root, QStringLiteral("sdk-too-old"),
                      QStringLiteral("Package targets sdkVersion %1, but this system requires >= %2").arg(sdkVersion).arg(minSdkVersion));
        return;
    }
    if (sdkVersion > maxSdkVersion) {
        recordInvalid(packageId, root, QStringLiteral("sdk-too-new"),
                      QStringLiteral("Package targets sdkVersion %1, which is newer than supported max %2").arg(sdkVersion).arg(maxSdkVersion));
        return;
    }

    int minApiRevision = 1;
    const QJsonValue minApiValue = metadata.value(QStringLiteral("minApiRevision"));
    if (!minApiValue.isUndefined() && !minApiValue.isNull()) {
        if (!minApiValue.isDouble()) {
            recordInvalid(packageId, root, QStringLiteral("invalid-metadata"),
                          QStringLiteral("metadata.json 'minApiRevision' must be a positive integer"));
            return;
        }
        const double apiDouble = minApiValue.toDouble();
        if (apiDouble < 1 || apiDouble != static_cast<int>(apiDouble)) {
            recordInvalid(packageId, root, QStringLiteral("invalid-metadata"),
                          QStringLiteral("metadata.json 'minApiRevision' must be a positive integer"));
            return;
        }
        minApiRevision = static_cast<int>(apiDouble);
        if (minApiRevision > currentApiRevision) {
            recordInvalid(packageId, root, QStringLiteral("api-too-old"),
                          QStringLiteral("Package requires API revision %1, but this system supports up to %2")
                              .arg(minApiRevision).arg(currentApiRevision));
            return;
        }
    }

    const QString revision = computePackageRevision(canonicalRoot);

    if (metadata.contains(QStringLiteral("widgets")) && !metadata.value(QStringLiteral("widgets")).isNull()) {
        const QJsonValue widgetsValue = metadata.value(QStringLiteral("widgets"));
        if (!widgetsValue.isArray() || widgetsValue.toArray().isEmpty()) {
            recordInvalid(packageId, root, QStringLiteral("invalid-metadata"),
                          QStringLiteral("metadata.json 'widgets' must be a non-empty array"));
            return;
        }
        const QJsonArray widgetList = widgetsValue.toArray();
        if (widgetList.size() > kMaxWidgetsPerPackage) {
            recordInvalid(packageId, root, QStringLiteral("invalid-metadata"),
                          QStringLiteral("metadata.json 'widgets' exceeds maximum of %1 entries").arg(kMaxWidgetsPerPackage));
            return;
        }
        for (const QJsonValue &childVal : widgetList) {
            if (packages.size() >= kMaxPackages)
                break;
            if (!childVal.isObject()) {
                recordInvalid(packageId, root, QStringLiteral("invalid-metadata"),
                              QStringLiteral("Each entry in 'widgets' must be a JSON object"));
                continue;
            }
            const QJsonObject childObj = childVal.toObject();
            const QString widgetId = childObj.value(QStringLiteral("id")).toString();
            if (!validId(widgetId)) {
                recordInvalid(widgetId.isEmpty() ? packageId : widgetId, root, QStringLiteral("invalid-metadata"),
                              QStringLiteral("Child widget 'id' is missing or invalid"));
                continue;
            }
            if (widgetId != packageId && !widgetId.startsWith(packageId + QLatin1Char('.'))) {
                recordInvalid(widgetId, root, QStringLiteral("invalid-metadata"),
                              QStringLiteral("Child widget id '%1' must equal or start with package id '%2.'").arg(widgetId, packageId));
                continue;
            }
            if (seenWidgetIds.contains(widgetId)) {
                recordInvalid(widgetId, root, QStringLiteral("duplicate-widget-id"),
                              QStringLiteral("Widget id '%1' is already provided by another widget or package").arg(widgetId));
                continue;
            }
            QString errCode;
            QString errReason;
            const QJsonObject built = buildWidgetEntry(
                childObj, &metadata, widgetId, packageId, version, minApiRevision,
                canonicalRoot, revision, packageSource, &errCode, &errReason);
            if (built.isEmpty()) {
                recordInvalid(widgetId, root, errCode, errReason);
                continue;
            }
            seenWidgetIds.insert(widgetId);
            packages.append(built);
        }
        return;
    }

    if (seenWidgetIds.contains(packageId)) {
        recordInvalid(packageId, root, QStringLiteral("duplicate-widget-id"),
                      QStringLiteral("Widget id '%1' is already provided by another package").arg(packageId));
        return;
    }
    QString errCode;
    QString errReason;
    const QJsonObject built = buildWidgetEntry(
        metadata, nullptr, packageId, packageId, version, minApiRevision,
        canonicalRoot, revision, packageSource, &errCode, &errReason);
    if (built.isEmpty()) {
        recordInvalid(packageId, root, errCode, errReason);
        return;
    }
    seenWidgetIds.insert(packageId);
    packages.append(built);
}
}

QJsonObject snapshotForRoots(const QStringList &dataRoots,
                             int minSdkVersion,
                             int maxSdkVersion,
                             int currentApiRevision)
{
    QJsonArray packages;
    QJsonArray invalidPackages;
    QSet<QString> seenPackages;
    QSet<QString> seenWidgetIds;

    // Two-pass scan: user-installed/customized packages (`kos/widgets`) always
    // take precedence over bundled official defaults (`kos/default-widgets`).
    struct Layer {
        QString subdir;
        QString source;
    };
    const QList<Layer> layers = {
        {QStringLiteral("kos/widgets"), QStringLiteral("user")},
        {QStringLiteral("kos/default-widgets"), QStringLiteral("default")}
    };

    for (const Layer &layer : layers) {
        for (const QString &dataRoot : dataRoots) {
            QDir widgets(QDir(dataRoot).filePath(layer.subdir));
            if (!widgets.exists()) continue;
            for (const QString &name : widgets.entryList(QDir::Dirs | QDir::System | QDir::NoDotAndDotDot, QDir::Name)) {
                if (seenPackages.contains(name)) continue;
                const int beforeCount = packages.size();
                readPackageEntries(dataRoot, layer.subdir, layer.source, name,
                                   minSdkVersion, maxSdkVersion, currentApiRevision,
                                   seenWidgetIds, packages, invalidPackages);
                if (packages.size() > beforeCount)
                    seenPackages.insert(name);
                if (packages.size() >= kMaxPackages) break;
            }
            if (packages.size() >= kMaxPackages) break;
        }
        if (packages.size() >= kMaxPackages) break;
    }
    return {
        {QStringLiteral("sdkVersion"), maxSdkVersion},
        {QStringLiteral("minSdkVersion"), minSdkVersion},
        {QStringLiteral("maxSdkVersion"), maxSdkVersion},
        {QStringLiteral("apiRevision"), currentApiRevision},
        {QStringLiteral("packages"), packages},
        {QStringLiteral("invalidPackages"), invalidPackages}
    };
}

QJsonObject snapshot()
{
    return snapshotForRoots(defaultDataRoots());
}

WidgetPackageWatcher::WidgetPackageWatcher(QObject *parent)
    : WidgetPackageWatcher(defaultDataRoots(), parent)
{
}

WidgetPackageWatcher::WidgetPackageWatcher(const QStringList &dataRoots, QObject *parent)
    : QObject(parent), m_dataRoots(dataRoots)
{
    m_debounceTimer.setSingleShot(true);
    m_debounceTimer.setInterval(kDebounceMs);

    connect(&m_watcher, &QFileSystemWatcher::directoryChanged,
            this, &WidgetPackageWatcher::onWatchEvent);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged,
            this, &WidgetPackageWatcher::onWatchEvent);
    connect(&m_debounceTimer, &QTimer::timeout,
            this, &WidgetPackageWatcher::handleDebouncedChange);

    m_lastSnapshotBytes = QJsonDocument(snapshotForRoots(m_dataRoots)).toJson(QJsonDocument::Compact);
    resyncWatches();
}

void WidgetPackageWatcher::onWatchEvent()
{
    m_debounceTimer.start();
}

void WidgetPackageWatcher::resyncWatches()
{
    QSet<QString> desiredDirs;
    QSet<QString> desiredFiles;

    static const QStringList kWatchedFiles = {
        QStringLiteral("metadata.json"),
        QStringLiteral("Widget.qml"),
        QStringLiteral("Snapshot.qml"),
        QStringLiteral("Settings.qml"),
        QStringLiteral("Popup.qml")
    };

    for (const QString &dataRoot : std::as_const(m_dataRoots)) {
        for (const QLatin1String subdir : {QLatin1String("kos/widgets"), QLatin1String("kos/default-widgets")}) {
            const QFileInfo widgetsInfo(QDir(dataRoot).filePath(subdir));
            if (widgetsInfo.exists() && widgetsInfo.isDir()) {
                const QString widgetsCanonical = widgetsInfo.canonicalFilePath();
                if (!widgetsCanonical.isEmpty() && desiredDirs.size() < kMaxWatchDirs)
                    desiredDirs.insert(widgetsCanonical);
                QDir widgetsDir(widgetsCanonical);
                for (const QString &name : widgetsDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
                    const QFileInfo pkgInfo(widgetsDir.filePath(name));
                    const QString canonicalPkg = pkgInfo.canonicalFilePath();
                    if (canonicalPkg.isEmpty() || !QFileInfo(canonicalPkg).isDir())
                        continue;
                    if (desiredDirs.size() < kMaxWatchDirs)
                        desiredDirs.insert(canonicalPkg);
                    const QDir pkgDir(canonicalPkg);
                    for (const QString &fileName : kWatchedFiles) {
                        if (desiredFiles.size() >= kMaxWatchFiles)
                            break;
                        const QFileInfo fileInfo(pkgDir.filePath(fileName));
                        if (isSafePackageFile(fileInfo, canonicalPkg))
                            desiredFiles.insert(fileInfo.canonicalFilePath());
                    }
                }
            } else {
                const QFileInfo kosInfo(QDir(dataRoot).filePath(QStringLiteral("kos")));
                if (kosInfo.exists() && kosInfo.isDir()) {
                    const QString kosCanonical = kosInfo.canonicalFilePath();
                    if (!kosCanonical.isEmpty() && desiredDirs.size() < kMaxWatchDirs)
                        desiredDirs.insert(kosCanonical);
                } else {
                    const QFileInfo rootInfo(dataRoot);
                    if (rootInfo.exists() && rootInfo.isDir()) {
                        const QString rootCanonical = rootInfo.canonicalFilePath();
                        if (!rootCanonical.isEmpty() && desiredDirs.size() < kMaxWatchDirs)
                            desiredDirs.insert(rootCanonical);
                    }
                }
            }
        }
    }

    // Include nested entry directories and files for multi-widget packages.
    const QJsonObject snap = snapshotForRoots(m_dataRoots);
    const QJsonArray pkgs = snap.value(QStringLiteral("packages")).toArray();
    for (const QJsonValue &val : pkgs) {
        const QJsonObject obj = val.toObject();
        for (const QLatin1String key : {
                 QLatin1String("widgetEntry"),
                 QLatin1String("snapshotEntry"),
                 QLatin1String("settingsEntry")}) {
            const QString filePath = obj.value(key).toString();
            if (filePath.isEmpty())
                continue;
            const QFileInfo info(filePath);
            const QString parentDir = info.canonicalPath();
            if (!parentDir.isEmpty() && desiredDirs.size() < kMaxWatchDirs)
                desiredDirs.insert(parentDir);
            if (desiredFiles.size() < kMaxWatchFiles)
                desiredFiles.insert(filePath);
        }
    }

    const QStringList currentDirsList = m_watcher.directories();
    const QSet<QString> currentDirs(currentDirsList.cbegin(), currentDirsList.cend());
    QStringList dirsToRemove;
    for (const QString &dir : currentDirs) {
        if (!desiredDirs.contains(dir))
            dirsToRemove.append(dir);
    }
    if (!dirsToRemove.isEmpty())
        m_watcher.removePaths(dirsToRemove);

    QStringList dirsToAdd;
    for (const QString &dir : desiredDirs) {
        if (!currentDirs.contains(dir))
            dirsToAdd.append(dir);
    }
    if (!dirsToAdd.isEmpty())
        m_watcher.addPaths(dirsToAdd);

    const QStringList currentFilesList = m_watcher.files();
    const QSet<QString> currentFiles(currentFilesList.cbegin(), currentFilesList.cend());
    QStringList filesToRemove;
    for (const QString &file : currentFiles) {
        if (!desiredFiles.contains(file))
            filesToRemove.append(file);
    }
    if (!filesToRemove.isEmpty())
        m_watcher.removePaths(filesToRemove);

    QStringList filesToAdd;
    for (const QString &file : desiredFiles) {
        if (!currentFiles.contains(file))
            filesToAdd.append(file);
    }
    if (!filesToAdd.isEmpty())
        m_watcher.addPaths(filesToAdd);
}

void WidgetPackageWatcher::handleDebouncedChange()
{
    resyncWatches();
    const QJsonObject snap = snapshotForRoots(m_dataRoots);
    const QByteArray bytes = QJsonDocument(snap).toJson(QJsonDocument::Compact);
    if (bytes == m_lastSnapshotBytes)
        return;
    m_lastSnapshotBytes = bytes;
    emit snapshotChanged(snap);
}
}
