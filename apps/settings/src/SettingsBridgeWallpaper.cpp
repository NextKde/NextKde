#include "SettingsBridge.h"

#include <LiquidAI/ModelManager.h>
#include <QColor>
#include <QCryptographicHash>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLinearGradient>
#include <QPainter>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QThread>
#include <QUrl>
#include <cmath>

namespace {

// Quickshell IPC parses each CLI argument as JSON. An array literal is
// expanded into multiple function arguments, so a JSON list destined for a
// QML string parameter must itself be passed as a JSON string literal.
QString ipcStringArgument(const QString& value)
{
    const QByteArray wrapped = QJsonDocument(QJsonArray { value }).toJson(QJsonDocument::Compact);
    return QString::fromUtf8(wrapped.mid(1, wrapped.size() - 2));
}

bool cachedModelVerified(const QString& path, const char* expectedSha256)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return false;
    QCryptographicHash hash(QCryptographicHash::Sha256);
    while (!file.atEnd()) {
        if (QThread::currentThread()->isInterruptionRequested())
            return false;
        const QByteArray chunk = file.read(1024 * 1024);
        if (chunk.isEmpty() && file.error() != QFileDevice::NoError)
            return false;
        hash.addData(chunk);
    }
    return hash.result().toHex() == QByteArray(expectedSha256);
}

} // namespace

void SettingsBridge::wallpaperSnapshot() { callWallpaper({ QStringLiteral("snapshot") }); }

QStringList SettingsBridge::wallpaperCatalog() const
{
    return m_wallpaperLibrary.wallpaperCatalog();
}

QString SettingsBridge::wallpaperThumbnail(
    const QString& urlOrPath, int width, int height, int radius, bool generate)
{
    return m_wallpaperLibrary.wallpaperThumbnail(urlOrPath, width, height, radius, generate);
}

QStringList SettingsBridge::galleryImages() const { return m_wallpaperLibrary.galleryImages(); }

QString SettingsBridge::importGalleryImage(const QString& urlOrPath)
{
    return m_wallpaperLibrary.importGalleryImage(urlOrPath);
}

int SettingsBridge::importGalleryFolder(const QString& urlOrPath)
{
    return m_wallpaperLibrary.importGalleryFolder(urlOrPath);
}

bool SettingsBridge::deleteGalleryImage(const QString& urlOrPath)
{
    return m_wallpaperLibrary.deleteGalleryImage(urlOrPath);
}

void SettingsBridge::revealWallpaperImage(const QString& urlOrPath)
{
    const QString path
        = urlOrPath.startsWith(QStringLiteral("file:")) ? QUrl(urlOrPath).toLocalFile() : urlOrPath;
    const QFileInfo info(path);
    if (!info.exists()) {
        setLastError(QStringLiteral("File does not exist; cannot open its folder"));
        emit wallpaperSnapshotChanged({ });
        return;
    }
    QDesktopServices::openUrl(
        QUrl::fromLocalFile(info.isDir() ? info.absoluteFilePath() : info.absolutePath()));
}

void SettingsBridge::chooseWallpaperImage(const QString& urlOrPath)
{
    const QString path
        = urlOrPath.startsWith(QStringLiteral("file:")) ? QUrl(urlOrPath).toLocalFile() : urlOrPath;
    const QFileInfo image(path);
    if (!image.isFile() || !image.isReadable()) {
        setLastError(QStringLiteral("Select an image readable on this machine"));
        emit wallpaperSnapshotChanged({ });
        return;
    }
    callWallpaper({ QStringLiteral("chooseImage"), image.absoluteFilePath() });
}

void SettingsBridge::previewWallpaperImage(const QString& urlOrPath, const QStringList& images)
{
    const QString path
        = urlOrPath.startsWith(QStringLiteral("file:")) ? QUrl(urlOrPath).toLocalFile() : urlOrPath;
    if (!QFileInfo(path).isFile() || !QFileInfo(path).isReadable()) {
        setLastError(QStringLiteral("Select an image readable on this machine"));
        emit wallpaperSnapshotChanged({ });
        return;
    }
    QJsonArray paths;
    for (const QString& image : images.mid(0, 2000))
        paths.append(image);
    const QString listJson = QString::fromUtf8(QJsonDocument(paths).toJson(QJsonDocument::Compact));
    callWallpaper({ QStringLiteral("previewImage"), QFileInfo(path).absoluteFilePath(),
        ipcStringArgument(listJson) });
}

QString SettingsBridge::wallpaperColorImage(const QString& start, const QString& end, int angle)
{
    const QRegularExpression format(QStringLiteral("^#[0-9a-fA-F]{6}$"));
    if (!format.match(start).hasMatch() || !format.match(end).hasMatch()) {
        setLastError(QStringLiteral("Enter a valid six-digit hex color, e.g. #A8C8F0"));
        return { };
    }
    angle = ((angle % 360) + 360) % 360;
    const QString folder = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
        + QStringLiteral("/kos/wallpaper-colors");
    const QString key = start == end
        ? start.mid(1).toLower()
        : QStringLiteral("gradient-%1-%2-%3")
              .arg(start.mid(1).toLower(), end.mid(1).toLower(), QString::number(angle));
    const QString path = folder + QLatin1Char('/') + key + QStringLiteral(".png");
    if (QFileInfo::exists(path))
        return path;
    if (!QDir().mkpath(folder)) {
        setLastError(QStringLiteral("Could not create the color wallpaper cache"));
        return { };
    }
    QImage image(start == end ? QSize(16, 16) : QSize(1920, 1080), QImage::Format_RGB32);
    if (start == end)
        image.fill(QColor(start));
    else {
        const double radians = angle * 3.14159265358979323846 / 180.0;
        const QPointF direction(std::cos(radians), std::sin(radians));
        const QPointF center(image.width() / 2.0, image.height() / 2.0);
        const double extent = std::abs(direction.x()) * image.width() / 2.0
            + std::abs(direction.y()) * image.height() / 2.0;
        QLinearGradient gradient(center - direction * extent, center + direction * extent);
        gradient.setColorAt(0, QColor(start));
        gradient.setColorAt(1, QColor(end));
        QPainter painter(&image);
        painter.fillRect(image.rect(), gradient);
    }
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly) || !image.save(&file, "PNG") || !file.commit()) {
        setLastError(QStringLiteral("Could not generate the color wallpaper"));
        return { };
    }
    setLastError({ });
    return path;
}

void SettingsBridge::chooseWallpaperColor(const QString& hex)
{
    chooseWallpaperGradient(hex, hex, 0);
}

void SettingsBridge::chooseWallpaperGradient(const QString& start, const QString& end, int angle)
{
    const QString path = wallpaperColorImage(start, end, angle);
    if (path.isEmpty()) {
        emit wallpaperSnapshotChanged({ });
        return;
    }
    callWallpaper({ QStringLiteral("chooseColor"), path });
}

QString SettingsBridge::wallpaperCustomColors()
{
    QSettings settings;
    return settings.value(QStringLiteral("wallpaper/customColors"), QStringLiteral("[]"))
        .toString();
}

void SettingsBridge::saveWallpaperCustomColors(const QString& json)
{
    const QJsonDocument document = QJsonDocument::fromJson(json.toUtf8());
    if (!document.isArray())
        return;
    QSettings settings;
    settings.setValue(QStringLiteral("wallpaper/customColors"), json);
}

void SettingsBridge::pickWallpaperColor()
{
    QDBusInterface picker(QStringLiteral("org.kde.KWin"), QStringLiteral("/ColorPicker"),
        QStringLiteral("org.kde.kwin.ColorPicker"), QDBusConnection::sessionBus());
    auto* watcher = new QDBusPendingCallWatcher(picker.asyncCall(QStringLiteral("pick")), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
        const QDBusMessage reply = watcher->reply();
        watcher->deleteLater();
        if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().isEmpty()) {
            emit wallpaperColorPickFailed(
                QStringLiteral("Color picking was cancelled or the desktop does not support screen "
                               "color picking"));
            return;
        }
        const QDBusArgument value = reply.arguments().first().value<QDBusArgument>();
        quint32 rgba = 0;
        value.beginStructure();
        value >> rgba;
        value.endStructure();
        emit wallpaperColorPicked(QColor::fromRgba(rgba).name(QColor::HexRgb));
    });
}

void SettingsBridge::previewWallpaperSession(const QString& path, const QVariantMap& session)
{
    const QString json = QString::fromUtf8(
        QJsonDocument(QJsonObject::fromVariantMap(session)).toJson(QJsonDocument::Compact));
    callWallpaper({ QStringLiteral("previewSession"), path, ipcStringArgument(json) });
}

void SettingsBridge::updateWallpaperPreviewThumbnails(const QVariantMap& thumbnails)
{
    const QString json = QString::fromUtf8(
        QJsonDocument(QJsonObject::fromVariantMap(thumbnails)).toJson(QJsonDocument::Compact));
    callWallpaper({ QStringLiteral("setPreviewThumbnails"), ipcStringArgument(json) });
}

void SettingsBridge::updateWallpaperTransitionOptions(const QVariantMap& options)
{
    const QString json = QString::fromUtf8(
        QJsonDocument(QJsonObject::fromVariantMap(options)).toJson(QJsonDocument::Compact));
    callWallpaper({ QStringLiteral("setTransitionOptions"), ipcStringArgument(json) });
}

void SettingsBridge::updateWallpaperFitMode(const QString& mode)
{
    callWallpaper({ QStringLiteral("setFitMode"), mode });
}

void SettingsBridge::updateWallpaperTakeoverEnabled(bool enabled)
{
    callWallpaper({ QStringLiteral("setTakeoverEnabled"),
        enabled ? QStringLiteral("true") : QStringLiteral("false") });
}

void SettingsBridge::updateWallpaperTransition(const QString& style)
{
    callWallpaper({ QStringLiteral("setTransition"), style });
}

void SettingsBridge::updateWallpaperSlideshow(
    bool enabled, int minutes, const QStringList& images, const QString& folder)
{
    QJsonArray paths;
    for (const QString& path : images.mid(0, 2000))
        paths.append(path);
    const QString listJson = QString::fromUtf8(QJsonDocument(paths).toJson(QJsonDocument::Compact));
    callWallpaper({ QStringLiteral("setSlideshow"),
        enabled ? QStringLiteral("true") : QStringLiteral("false"), QString::number(minutes),
        ipcStringArgument(listJson), folder });
}

void SettingsBridge::updateWallpaperSpatialEnabled(bool enabled)
{
    callWallpaper({ QStringLiteral("setSpatialEnabled"),
        enabled ? QStringLiteral("true") : QStringLiteral("false") });
}

QVariantList SettingsBridge::themePackCatalog() const
{
    QVariantList packs;
    const QString override = qEnvironmentVariable("KOS_WALLPAPER_PACKS");
    const QString root = override.trimmed().isEmpty()
        ? qEnvironmentVariable("HOME") + QStringLiteral("/.local/share/kos/wallpaper-themes")
        : override.trimmed();
    const QFileInfoList entries = QDir(root).entryInfoList(
        QDir::Dirs | QDir::Readable | QDir::NoDotAndDotDot, QDir::Name | QDir::IgnoreCase);
    static const QRegularExpression validId(QStringLiteral("^[A-Za-z0-9_-]+$"));
    for (const QFileInfo& entry : entries) {
        QFile manifest(entry.absoluteFilePath() + QStringLiteral("/manifest.json"));
        if (!manifest.open(QIODevice::ReadOnly))
            continue;
        const QJsonDocument document = QJsonDocument::fromJson(manifest.readAll());
        if (!document.isObject())
            continue;
        const QJsonObject object = document.object();
        const QString rawId = object.value(QStringLiteral("id")).toString().trimmed();
        const QString id = rawId.isEmpty() ? entry.fileName() : rawId;
        if (!validId.match(id).hasMatch())
            continue;
        const QString entryName
            = object.value(QStringLiteral("entry")).toString(QStringLiteral("main.qml"));
        QString preview = object.value(QStringLiteral("preview")).toString();
        if (entryName.isEmpty() || entryName.contains(QLatin1Char('/'))
            || entryName.contains(QStringLiteral("..")))
            continue;
        if (preview.contains(QLatin1Char('/')) || preview.contains(QStringLiteral("..")))
            preview.clear();
        QVariantMap pack;
        pack.insert(QStringLiteral("id"), id);
        pack.insert(QStringLiteral("dir"), entry.absoluteFilePath());
        pack.insert(QStringLiteral("name"), object.value(QStringLiteral("name")).toString(id));
        pack.insert(QStringLiteral("detail"), object.value(QStringLiteral("detail")).toString());
        pack.insert(QStringLiteral("accent"), object.value(QStringLiteral("accent")).toString());
        pack.insert(QStringLiteral("version"), object.value(QStringLiteral("version")).toInt(1));
        pack.insert(
            QStringLiteral("entryPath"), entry.absoluteFilePath() + QLatin1Char('/') + entryName);
        pack.insert(QStringLiteral("previewPath"),
            preview.isEmpty() ? QString() : entry.absoluteFilePath() + QLatin1Char('/') + preview);
        packs.append(pack);
    }
    return packs;
}

void SettingsBridge::chooseWallpaperTheme(const QString& id)
{
    if (id != "starfield" && id != "blackhole" && id != "weather" && id != "underwater"
        && id != "forest") {
        // 包主题(marketplace)不在内置名单里:只做格式守卫,存在性由壳侧
        // ThemePackService / WallpaperService.chooseTheme 校验。
        static const QRegularExpression validId(QStringLiteral("^[A-Za-z0-9_-]+$"));
        if (!validId.match(id).hasMatch())
            return;
    }
    callWallpaper({ QStringLiteral("chooseTheme"), id });
}

void SettingsBridge::updateWallpaperThemeEconomical(bool enabled)
{
    callWallpaper({ QStringLiteral("setThemeEconomical"),
        enabled ? QStringLiteral("true") : QStringLiteral("false") });
}

void SettingsBridge::updateWallpaperThemeMotion(bool animated, double speed, int count)
{
    callWallpaper({ QStringLiteral("setThemeMotion"),
        animated ? QStringLiteral("true") : QStringLiteral("false"),
        QString::number(qBound(0.1, speed, 1.5)), QString::number(qBound(24, count, 160)) });
}

void SettingsBridge::prepareWallpaperSpatial()
{
    callWallpaper({ QStringLiteral("prepareSpatial") });
}

void SettingsBridge::initializeSpatialService()
{
    callWallpaper({ QStringLiteral("initializeSpatialService") });
}

void SettingsBridge::disableSpatialService()
{
    callWallpaper({ QStringLiteral("disableSpatialService") });
}

void SettingsBridge::cancelWallpaperSpatial()
{
    callWallpaper({ QStringLiteral("cancelSpatial") });
}

void SettingsBridge::inspectSpatialService()
{
    callWallpaper({ QStringLiteral("inspectSpatialService") });
}

void SettingsBridge::clearSpatialCache(const QString& kind)
{
    if (kind != "generated" && kind != "models" && kind != "all")
        return;
    callWallpaper({ QStringLiteral("clearSpatialCache"), kind });
}

void SettingsBridge::inspectWallpaperModels()
{
    if (m_modelInspectionPending)
        return;
    m_modelInspectionPending = true;
    const QString directory = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
        + QStringLiteral("/liquid-shell/models/");
    m_probeTasks.start(
        [directory] {
            const bool depth = cachedModelVerified(
                directory + QStringLiteral("depth-anything-v2-small-vits.onnx"),
                LiquidAI::ModelManager::modelSha256);
            const bool foreground
                = cachedModelVerified(directory + QStringLiteral("isnet-general-use.onnx"),
                    LiquidAI::ModelManager::foregroundModelSha256);
            return QVariantMap { { QStringLiteral("depthReady"), depth },
                { QStringLiteral("foregroundReady"), foreground } };
        },
        [this](const QVariantMap& result) {
            m_modelInspectionPending = false;
            emit wallpaperModelsChecked(result.value(QStringLiteral("depthReady")).toBool(),
                result.value(QStringLiteral("foregroundReady")).toBool());
        });
}

QVariantMap SettingsBridge::wallpaperSnapshotFromReply(const QString& payload)
{
    if (payload.isEmpty())
        return { };
    QJsonParseError parseError;
    QByteArray json = payload.toUtf8();
    QJsonDocument document = QJsonDocument::fromJson(json, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        // Some Quickshell builds may write an informational line before
        // the IPC return value. Recover the JSON object instead of
        // rejecting an otherwise valid wallpaper snapshot.
        const qsizetype firstBrace = json.indexOf('{');
        const qsizetype lastBrace = json.lastIndexOf('}');
        if (firstBrace >= 0 && lastBrace > firstBrace) {
            json = json.mid(firstBrace, lastBrace - firstBrace + 1);
            document = QJsonDocument::fromJson(json, &parseError);
        }
    }
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        QString detail = payload.simplified();
        if (detail.size() > 140)
            detail = detail.left(137) + QStringLiteral("...");
        setLastError(QStringLiteral("Could not parse the wallpaper IPC response (%1): %2")
                .arg(parseError.errorString(),
                    detail.isEmpty() ? QStringLiteral("empty response") : detail));
        return { };
    }
    const QJsonObject object = document.object();
    if (!object.contains(QStringLiteral("fitMode"))
        || !object.contains(QStringLiteral("transition"))) {
        setLastError(QStringLiteral(
            "The wallpaper configuration from the desktop environment is incomplete"));
        return { };
    }
    setLastError({ });
    return {
        { QStringLiteral("previewImage"), object.value(QStringLiteral("previewImage")).toString() },
        { QStringLiteral("previewMode"), object.value(QStringLiteral("previewMode")).toString() },
        { QStringLiteral("previewSelection"),
            object.value(QStringLiteral("previewSelection")).toString() },
        { QStringLiteral("previewCatalog"),
            object.value(QStringLiteral("previewCatalog")).toString() },
        { QStringLiteral("previewColors"),
            object.value(QStringLiteral("previewColors")).toString() },
        { QStringLiteral("transitionOptions"),
            object.value(QStringLiteral("transitionOptions")).toString() },
        { QStringLiteral("slideshowImages"),
            object.value(QStringLiteral("slideshowImages")).toString() },
        { QStringLiteral("previewInterval"),
            object.value(QStringLiteral("previewInterval")).toInt() },
        { QStringLiteral("previewActive"), object.value(QStringLiteral("previewActive")).toBool() },
        { QStringLiteral("previewPending"),
            object.value(QStringLiteral("previewPending")).toBool() },
        { QStringLiteral("previewError"), object.value(QStringLiteral("previewError")).toString() },
        { QStringLiteral("previewAvailable"),
            object.value(QStringLiteral("previewAvailable")).toBool() },
        { QStringLiteral("image"), object.value(QStringLiteral("image")).toString() },
        { QStringLiteral("wallpaperMode"),
            object.value(QStringLiteral("wallpaperMode")).toString() },
        { QStringLiteral("themeId"), object.value(QStringLiteral("themeId")).toString() },
        { QStringLiteral("themeEconomical"),
            object.value(QStringLiteral("themeEconomical")).toBool() },
        { QStringLiteral("themeAnimated"), object.value(QStringLiteral("themeAnimated")).toBool() },
        { QStringLiteral("themeSpeed"), object.value(QStringLiteral("themeSpeed")).toDouble(0.5) },
        { QStringLiteral("themeParticleCount"),
            object.value(QStringLiteral("themeParticleCount")).toInt(80) },
        { QStringLiteral("fitMode"), object.value(QStringLiteral("fitMode")).toString() },
        { QStringLiteral("transition"), object.value(QStringLiteral("transition")).toString() },
        { QStringLiteral("library"), object.value(QStringLiteral("library")).toString() },
        { QStringLiteral("slideshowEnabled"),
            object.value(QStringLiteral("slideshowEnabled")).toBool() },
        { QStringLiteral("slideshowIntervalMinutes"),
            object.value(QStringLiteral("slideshowIntervalMinutes")).toInt() },
        { QStringLiteral("slideshowFolder"),
            object.value(QStringLiteral("slideshowFolder")).toString() },
        { QStringLiteral("takeoverEnabled"),
            object.value(QStringLiteral("takeoverEnabled")).toBool() },
        { QStringLiteral("takeoverPending"),
            object.value(QStringLiteral("takeoverPending")).toBool() },
        { QStringLiteral("takeoverError"),
            object.value(QStringLiteral("takeoverError")).toString() },
        { QStringLiteral("takeoverAvailable"),
            object.value(QStringLiteral("takeoverAvailable")).toBool() },
        { QStringLiteral("spatialResources"),
            object.value(QStringLiteral("spatialResources")).toObject().toVariantMap() },
        { QStringLiteral("spatialEnabled"),
            object.value(QStringLiteral("spatialEnabled")).toBool() },
        { QStringLiteral("spatialReady"), object.value(QStringLiteral("spatialReady")).toBool() },
        { QStringLiteral("spatialPrepared"),
            object.value(QStringLiteral("spatialPrepared")).toBool() },
        { QStringLiteral("spatialBusy"), object.value(QStringLiteral("spatialBusy")).toBool() },
        { QStringLiteral("spatialPreparing"),
            object.value(QStringLiteral("spatialPreparing")).toBool() },
        { QStringLiteral("spatialError"), object.value(QStringLiteral("spatialError")).toString() },
    };
}

void SettingsBridge::callWallpaper(const QStringList& arguments)
{
    // Serialize mutations so rapid multi-selection cannot apply out of order.
    if (arguments.value(0) == QStringLiteral("snapshot") && m_wallpaperBusy)
        return;
    if (!m_wallpaperQueue.isEmpty() && arguments.value(0) == QStringLiteral("setSlideshow")
        && m_wallpaperQueue.last().value(0) == QStringLiteral("setSlideshow"))
        m_wallpaperQueue.last() = arguments;
    else
        m_wallpaperQueue.append(arguments);
    pumpWallpaperRequests();
}

void SettingsBridge::pumpWallpaperRequests()
{
    if (m_wallpaperBusy || m_wallpaperQueue.isEmpty())
        return;
    m_wallpaperBusy = true;
    callShell(QStringLiteral("wallpaper-settings"), m_wallpaperQueue.takeFirst(),
        QStringLiteral("Wallpaper settings request failed"), RequestKind::Wallpaper);
}
