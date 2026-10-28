#include "WallpaperLibrary.h"

#include <QBuffer>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QImageReader>
#include <QImageWriter>
#include <QJsonArray>
#include <QJsonDocument>
#include <QPainter>
#include <QPainterPath>
#include <QPointer>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>
#include <algorithm>
#include <memory>

namespace {
static QString galleryDirPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
        + QStringLiteral("/kos/gallery");
}

// 壁纸缩略图缓存目录,确保存在。生成(wallpaperThumbnail)与启动清理
// (CacheMaintenance::schedule)共用;以后新增缓存目录照此模式各起一个助手。
QString wallpaperThumbCacheDir()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
        + QStringLiteral("/kos/wallpaper-thumbs/");
    if (!QDir(dir).exists())
        QDir().mkpath(dir);
    return dir;
}

} // namespace

WallpaperLibrary::WallpaperLibrary(QObject* parent)
    : QObject(parent)
{
    m_thumbnailPool.setMaxThreadCount(2);
}

WallpaperLibrary::~WallpaperLibrary()
{
    if (m_galleryImportThread) {
        disconnect(m_galleryImportThread, nullptr, this, nullptr);
        m_galleryImportThread->requestInterruption();
        m_galleryImportThread->wait();
    }
    m_thumbnailPool.clear();
    m_thumbnailPool.waitForDone();
}

QString WallpaperLibrary::thumbnailCacheDirectory() { return wallpaperThumbCacheDir(); }

QStringList WallpaperLibrary::wallpaperCatalog() const
{
    QStringList catalog;
    const QStringList formats { QStringLiteral("*.jpg"), QStringLiteral("*.jpeg"),
        QStringLiteral("*.png"), QStringLiteral("*.webp"), QStringLiteral("*.avif"),
        QStringLiteral("*.bmp") };
    for (const QString& location :
        QStandardPaths::standardLocations(QStandardPaths::GenericDataLocation)) {
        const QDir wallpapers(location + QStringLiteral("/wallpapers"));
        if (!wallpapers.exists())
            continue;
        const QFileInfoList entries = wallpapers.entryInfoList(
            QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot, QDir::Name | QDir::IgnoreCase);
        for (const QFileInfo& entry : entries) {
            // These tiny solid images exist only as Plasma placeholders
            // while KOS owns the actual wallpaper. They are not user
            // wallpapers and make the gallery look like broken tiles.
            if (entry.fileName().startsWith(QStringLiteral("KOS-Backdrop-")))
                continue;
            if (entry.isFile()) {
                if (formats.contains(QStringLiteral("*.") + entry.suffix().toLower()))
                    catalog.append(entry.absoluteFilePath());
                continue;
            }
            const QDir images(entry.absoluteFilePath() + QStringLiteral("/contents/images"));
            if (!images.exists())
                continue;
            const QFileInfoList candidates
                = images.entryInfoList(formats, QDir::Files, QDir::Name | QDir::IgnoreCase);
            if (candidates.isEmpty())
                continue;
            QFileInfo chosen = candidates.first();
            double bestScore = -1e9;
            for (const QFileInfo& candidate : candidates) {
                const QStringList size = candidate.completeBaseName().split('x');
                const double width = size.value(0).toDouble();
                const double height = size.value(1).toDouble();
                if (width < 1 || height < 1)
                    continue;
                const double score
                    = -qAbs(width / height - 16.0 / 9.0) * 10000 - qAbs(width - 3840) / 100.0;
                if (score > bestScore) {
                    bestScore = score;
                    chosen = candidate;
                }
            }
            catalog.append(chosen.absoluteFilePath());
        }
    }
    return catalog;
}

QString WallpaperLibrary::wallpaperThumbnail(
    const QString& urlOrPath, int width, int height, int radius, bool generate)
{
    const QString path
        = urlOrPath.startsWith(QStringLiteral("file:")) ? QUrl(urlOrPath).toLocalFile() : urlOrPath;
    const QFileInfo info(path);
    if (path.isEmpty() || !info.isFile() || !info.isReadable() || width < 1 || height < 1
        || width > 2048 || height > 2048)
        return { };
    const QString key = QString::fromLatin1(QCryptographicHash::hash(
        QStringLiteral("thumb-v2|%1|%2|%3x%4r%5")
            .arg(path, QString::number(info.lastModified().toMSecsSinceEpoch()),
                QString::number(width), QString::number(height), QString::number(radius))
            .toUtf8(),
        QCryptographicHash::Sha1)
            .toHex());
    // WebP 带 alpha 且几十 KB;无 webp 编码器的机器退回 PNG(大些但可用)。
    static const bool webpWritable = QImageWriter::supportedImageFormats().contains("webp");
    const QString thumbFile = wallpaperThumbCacheDir() + key
        + (webpWritable ? QStringLiteral(".webp") : QStringLiteral(".png"));
    if (QFileInfo(thumbFile).size() > 0)
        return QUrl::fromLocalFile(thumbFile).toString();
    if (!generate)
        return { };
    const QString source = info.absoluteFilePath();
    {
        QMutexLocker locker(&m_thumbnailMutex);
        if (m_thumbnailFailed.contains(key) || m_thumbnailInFlight.size() >= 64
            || m_thumbnailInFlight.contains(key))
            return { };
        m_thumbnailInFlight.insert(key);
    }
    const QString keyCopy = key;
    // QPointer 守护:窗口退出后对象销毁,后台任务收尾时不再 emit。
    QPointer<WallpaperLibrary> self(this);
    m_thumbnailPool.start([self, source, thumbFile, keyCopy, width, height, radius]() {
        // 按目标尺寸降采样解码(QImageReader):4K 原图全尺寸解码要
        // ~33MB/张,降采样后中间产物 <1MB,内存和速度都差一个量级。
        QImageReader reader(source);
        reader.setAutoTransform(true);
        const QSize originalSize = reader.size();
        if (originalSize.width() > 0 && originalSize.height() > 0) {
            // Bound the intermediate canvas even for panoramas. Crop
            // before the final resize instead of expanding a thin image
            // to an arbitrarily long buffer.
            reader.setScaledSize(
                originalSize.scaled(QSize(width * 2, height * 2), Qt::KeepAspectRatio));
        }
        bool written = false;
        QImage image = reader.read();
        if (!image.isNull()) {
            QSize crop = image.size();
            const double targetAspect = double(width) / height;
            if (double(image.width()) / image.height() > targetAspect)
                crop.setWidth(qMax(1, qRound(image.height() * targetAspect)));
            else
                crop.setHeight(qMax(1, qRound(image.width() / targetAspect)));
            QImage thumb
                = image
                      .copy((image.width() - crop.width()) / 2,
                          (image.height() - crop.height()) / 2, crop.width(), crop.height())
                      .scaled(width, height, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
            if (radius > 0 && radius * 2 <= width && radius * 2 <= height) {
                // 圆角烘进图里(角外清成透明),需要 alpha 通道。
                thumb = thumb.convertToFormat(QImage::Format_ARGB32_Premultiplied);
                QPainter p(&thumb);
                p.setRenderHint(QPainter::Antialiasing);
                QPainterPath rounded;
                rounded.addRoundedRect(0, 0, width, height, radius, radius);
                QPainterPath outside;
                outside.addRect(QRectF(0, 0, width, height));
                outside = outside.subtracted(rounded);
                p.setCompositionMode(QPainter::CompositionMode_Clear);
                p.fillPath(outside, Qt::black);
                p.end();
            }
            // WebP q72 带 alpha 仍几十 KB;PNG 退路大些但完整可用。
            QSaveFile output(thumbFile);
            if (output.open(QIODevice::WriteOnly)
                && thumb.save(&output, webpWritable ? "WEBP" : "PNG", 72))
                written = output.commit();
            else
                output.cancelWriting();
        }
        if (self) {
            QMutexLocker locker(&self->m_thumbnailMutex);
            self->m_thumbnailInFlight.remove(keyCopy);
            if (!written) {
                if (self->m_thumbnailFailed.size() >= 512)
                    self->m_thumbnailFailed.clear();
                self->m_thumbnailFailed.insert(keyCopy);
            }
        }
        if (self)
            emit self->thumbnailReady();
    });
    return { };
}

bool WallpaperLibrary::isGalleryImage(const QFileInfo& info)
{
    static const QStringList formats { QStringLiteral("jpg"), QStringLiteral("jpeg"),
        QStringLiteral("png"), QStringLiteral("webp"), QStringLiteral("avif"),
        QStringLiteral("bmp") };
    return formats.contains(info.suffix().toLower());
}

QByteArray WallpaperLibrary::galleryFileMd5(const QString& path)
{
    const QFileInfo info(path);
    const qint64 size = info.size();
    const qint64 mtime = info.lastModified().toMSecsSinceEpoch();
    {
        // Folder imports hash on the worker while single imports hash on the
        // owning thread; m_thumbnailMutex is the class's gallery-data lock.
        QMutexLocker locker(&m_thumbnailMutex);
        const auto it = m_galleryFingerprints.constFind(path);
        if (it != m_galleryFingerprints.constEnd() && it->size == size && it->mtime == mtime)
            return it->md5;
    }
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return { };
    QCryptographicHash hash(QCryptographicHash::Md5);
    char buffer[1 << 16];
    while (!file.atEnd()) {
        const qint64 read = file.read(buffer, sizeof(buffer));
        if (read <= 0)
            return { };
        hash.addData(QByteArrayView(buffer, qsizetype(read)));
    }
    const QByteArray md5 = hash.result();
    QMutexLocker locker(&m_thumbnailMutex);
    if (m_galleryFingerprints.size() >= 4096)
        m_galleryFingerprints.clear();
    m_galleryFingerprints.insert(path, { size, mtime, md5 });
    return md5;
}

QStringList WallpaperLibrary::galleryImages() const
{
    const QDir dir(galleryDirPath());
    QFileInfoList entries = dir.entryInfoList(QDir::Files | QDir::Readable);
    entries.erase(std::remove_if(entries.begin(), entries.end(),
                      [](const QFileInfo& info) { return !isGalleryImage(info); }),
        entries.end());
    std::sort(entries.begin(), entries.end(),
        [](const QFileInfo& a, const QFileInfo& b) { return a.lastModified() > b.lastModified(); });
    QStringList images;
    images.reserve(entries.size());
    for (const QFileInfo& entry : entries)
        images.append(entry.absoluteFilePath());
    return images;
}

QByteArray WallpaperLibrary::transcodeJpegBaseline(const QString& path)
{
    QImageReader reader(path);
    reader.setAutoTransform(true);
    const QImage image = reader.read();
    if (image.isNull())
        return { };
    QByteArray bytes;
    QBuffer buffer(&bytes);
    if (!buffer.open(QIODevice::WriteOnly))
        return { };
    QImageWriter writer(&buffer, "jpeg");
    writer.setQuality(95);
    if (!writer.write(image))
        return { };
    return bytes;
}

QString WallpaperLibrary::importGalleryImage(const QString& urlOrPath)
{
    const QString path
        = urlOrPath.startsWith(QStringLiteral("file:")) ? QUrl(urlOrPath).toLocalFile() : urlOrPath;
    const QFileInfo info(path);
    if (path.isEmpty() || !info.isFile() || !info.isReadable() || !isGalleryImage(info)
        || !QImageReader(info.absoluteFilePath()).canRead()) {
        emit errorOccurred(QStringLiteral("Select an image readable on this machine"));
        return { };
    }
    QDir dir(galleryDirPath());
    if (!dir.exists())
        QDir().mkpath(dir.absolutePath());
    // 内容去重(两级):同内容必同大小,所以先按文件大小筛出候选(通常
    // 0~1 个),只对候选算 MD5 比对——不必全目录扫哈希。命中即视为同一
    // 张,跳过复制直接返回已有路径,重复导入幂等。JPEG 转码会改变字节,
    // 所以转码候选的输出 MD5 也参与比对:同一张源图无论以何种编码形态
    // 已在库中,都能命中。
    const QByteArray sourceMd5 = galleryFileMd5(info.absoluteFilePath());
    if (sourceMd5.isEmpty()) {
        emit errorOccurred(QStringLiteral("Could not read the image content"));
        return { };
    }
    const bool isJpeg = info.suffix().compare(QLatin1String("jpg"), Qt::CaseInsensitive) == 0
        || info.suffix().compare(QLatin1String("jpeg"), Qt::CaseInsensitive) == 0;
    QByteArray payload;
    if (isJpeg)
        payload = transcodeJpegBaseline(info.absoluteFilePath());
    // 转码失败不阻塞导入:回退为原始字节复制,行为与未转码时一致。
    const QByteArray candidateMd5 = payload.isEmpty()
        ? QByteArray { }
        : QCryptographicHash::hash(payload, QCryptographicHash::Md5);
    // Single-image imports share the gallery with the folder worker. Keep
    // deduplication, filename selection and writes in one transaction.
    QMutexLocker galleryLock(&m_galleryMutex);
    for (const QFileInfo& entry : dir.entryInfoList(QDir::Files)) {
        if (entry.size() != info.size()
            && (payload.isEmpty() || entry.size() != qsizetype(payload.size())))
            continue;
        const QByteArray entryMd5 = galleryFileMd5(entry.absoluteFilePath());
        if (entryMd5 == sourceMd5 || (!candidateMd5.isEmpty() && entryMd5 == candidateMd5))
            return entry.absoluteFilePath();
    }
    const QString base = info.completeBaseName();
    const QString suffix = info.suffix();
    QString target = dir.filePath(info.fileName());
    for (int n = 1; QFileInfo::exists(target); ++n)
        target = dir.filePath(QStringLiteral("%1 (%2).%3").arg(base, QString::number(n), suffix));
    if (!payload.isEmpty()) {
        QSaveFile out(target);
        if (!out.open(QIODevice::WriteOnly) || out.write(payload) != qsizetype(payload.size())
            || !out.commit()) {
            out.cancelWriting();
            emit errorOccurred(QStringLiteral("Failed to copy image: %1").arg(info.fileName()));
            return { };
        }
    } else if (!QFile::copy(info.absoluteFilePath(), target)) {
        emit errorOccurred(QStringLiteral("Failed to copy image: %1").arg(info.fileName()));
        return { };
    }
    return target;
}

int WallpaperLibrary::importGalleryFolder(const QString& urlOrPath)
{
    const QString path
        = urlOrPath.startsWith(QStringLiteral("file:")) ? QUrl(urlOrPath).toLocalFile() : urlOrPath;
    const QDir folder(path);
    if (path.isEmpty() || !folder.exists()) {
        emit errorOccurred(QStringLiteral("The folder does not exist or is not readable"));
        return -1;
    }
    if (m_galleryImportThread) {
        // One import at a time (see the header): -2 tells the caller a run is
        // already in flight; its galleryImportFinished will carry the count.
        return -2;
    }

    // Snapshot the file list here; the hashing/decoding/copy loop then runs on
    // the worker. galleryFileMd5 touches m_galleryFingerprints, so exactly one
    // import thread may run — guarded by m_galleryImportThread below.
    QStringList sources;
    constexpr int kMaxFolderImages = 200;
    const QFileInfoList entries
        = folder.entryInfoList(QDir::Files | QDir::Readable, QDir::Name | QDir::IgnoreCase);
    for (const QFileInfo& entry : entries) {
        if (sources.size() >= kMaxFolderImages)
            break;
        if (isGalleryImage(entry))
            sources.append(entry.absoluteFilePath());
    }

    auto imported = std::make_shared<int>(0);
    auto* worker = QThread::create([this, sources, imported] {
        for (const QString& source : sources) {
            if (QThread::currentThread()->isInterruptionRequested())
                break;
            if (!importGalleryImage(source).isEmpty()) {
                ++*imported;
                emit galleryImportProgress(*imported);
            }
        }
    });
    worker->setParent(this);
    m_galleryImportThread = worker;
    QObject::connect(worker, &QThread::finished, this,
        [this, worker, imported] {
            m_galleryImportThread = nullptr;
            worker->deleteLater();
            emit galleryImportFinished(*imported);
        });
    worker->start();
    return 0;
}

bool WallpaperLibrary::deleteGalleryImage(const QString& urlOrPath)
{
    QMutexLocker galleryLock(&m_galleryMutex);
    const QString path
        = urlOrPath.startsWith(QStringLiteral("file:")) ? QUrl(urlOrPath).toLocalFile() : urlOrPath;
    const QString canonical = QFileInfo(path).canonicalFilePath();
    const QString managed = QFileInfo(galleryDirPath()).canonicalFilePath();
    if (canonical.isEmpty() || managed.isEmpty()
        || !canonical.startsWith(managed + QLatin1Char('/'))) {
        emit errorOccurred(QStringLiteral("Only images inside the gallery can be removed"));
        return false;
    }
    if (!QFile::moveToTrash(canonical)) {
        emit errorOccurred(
            QStringLiteral("Failed to move to trash: %1").arg(QFileInfo(canonical).fileName()));
        return false;
    }
    return true;
}

void WallpaperLibrary::migrateGalleryFromLibrary(const QString& libraryJson)
{
    if (m_galleryMigrated)
        return;
    QSettings migration;
    if (migration.value(QStringLiteral("wallpaper/galleryMigrationVersion"), 0).toInt() >= 1) {
        m_galleryMigrated = true;
        return;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(libraryJson.toUtf8());
    if (!doc.isArray())
        return;
    m_galleryMigrated = true;
    const QVariantList entries = doc.array().toVariantList();
    constexpr int kMaxMigratedImages = 200;
    int copied = 0;
    for (const QVariant& entryVar : entries) {
        if (copied >= kMaxMigratedImages)
            break;
        const QVariantMap entry = entryVar.toMap();
        const QString type = entry.value(QStringLiteral("type")).toString();
        QString path = entry.value(QStringLiteral("path")).toString();
        if (path.startsWith(QStringLiteral("file:")))
            path = QUrl(path).toLocalFile();
        if (type != QLatin1String("image") && type != QLatin1String("folder"))
            continue;
        QStringList sources { path };
        if (type == QLatin1String("folder")) {
            sources.clear();
            const QDir folder(path);
            if (!folder.exists())
                continue;
            for (const QFileInfo& file :
                folder.entryInfoList(QDir::Files | QDir::Readable, QDir::Name | QDir::IgnoreCase)) {
                if (copied >= kMaxMigratedImages)
                    break;
                if (isGalleryImage(file))
                    sources.append(file.absoluteFilePath());
            }
        }
        for (const QString& source : sources) {
            if (copied >= kMaxMigratedImages)
                break;
            if (!importGalleryImage(source).isEmpty())
                ++copied;
        }
    }
    migration.setValue(QStringLiteral("wallpaper/galleryMigrationVersion"), 1);
    migration.sync();
    if (copied > 0)
        qDebug() << "gallery migration accepted" << copied << "images";
}
