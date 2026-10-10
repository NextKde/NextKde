#include "CacheMaintenance.h"
#include "WindowSettings.h"

#include <LiquidAI/ModelManager.h>

#include <QGuiApplication>
#include <QCryptographicHash>
#include <QColor>
#include <QDateTime>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusArgument>
#include <QDBusPendingCallWatcher>
#include <QDebug>
#include <QDesktopServices>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QImage>
#include <QImageWriter>
#include <QBuffer>
#include <QSaveFile>
#include <QPainter>
#include <QPainterPath>
#include <QLinearGradient>
#include <cmath>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPointer>
#include <QProcess>
#include <QImageReader>
#include <QMutex>
#include <QSet>
#include <QThreadPool>
#include <QRegularExpression>
#include <QSaveFile>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QStandardPaths>
#include <QSettings>
#include <QThread>
#include <QTimer>
#include <QVariantMap>
#include <QUrl>
#include <algorithm>
#include <functional>

namespace {

// Quickshell IPC parses each CLI argument as JSON. An array literal is
// expanded into multiple function arguments, so a JSON list destined for a
// QML string parameter must itself be passed as a JSON string literal.
QString ipcStringArgument(const QString &value)
{
    const QByteArray wrapped = QJsonDocument(QJsonArray{value}).toJson(
        QJsonDocument::Compact);
    return QString::fromUtf8(wrapped.mid(1, wrapped.size() - 2));
}

bool cachedModelVerified(const QString &path, const char *expectedSha256)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return false;
    QCryptographicHash hash(QCryptographicHash::Sha256);
    while (!file.atEnd()) {
        const QByteArray chunk = file.read(1024 * 1024);
        if (chunk.isEmpty() && file.error() != QFileDevice::NoError)
            return false;
        hash.addData(chunk);
    }
    return hash.result().toHex() == QByteArray(expectedSha256);
}

// The 材质 group of the debug page is the editor for the shell's glass presets,
// not for raw kwinrc values. The shell re-writes every one of those keys from
// the active preset on each appearance sync (theme.sync-glass), so a direct
// kwinrc write here is reverted the moment any blur/liquid/style control moves;
// these rows therefore read and write the preset through the shell, which also
// reconfigures the effect, keeping the live feedback a raw write used to give.
//
// `toKwinrc` converts preset units into kwinrc units. Only Refraction differs:
// it lives as 0..1 in the preset and reaches kwinrc as RefractionStrength 0..20
// through round(globalLiquidStrength * Refraction * 20).
struct PresetDebugKey {
    const char *key;
    const char *parameter;
    double toKwinrc;
};

const PresetDebugKey kPresetDebugKeys[] = {
    {"RefractionStrength", "Refraction", 20.0},
    {"RefractionEdgeSize", "EdgeSize", 1.0},
    {"RefractionNormalPow", "NormalPow", 1.0},
    {"RefractionRGBFringing", "RGBFringing", 1.0},
    {"RefractionOffsetStrength", "OffsetStrength", 1.0},
    {"MaterialSoftness", "Softness", 1.0},
    {"MaterialReflectionStrength", "Reflection", 1.0},
};

const PresetDebugKey *presetDebugKey(const QString &key)
{
    for (const PresetDebugKey &candidate : kPresetDebugKeys) {
        if (key == QLatin1String(candidate.key))
            return &candidate;
    }
    return nullptr;
}

// Rows that belong to neither side of this window: the shell rewrites them from
// a design value on every appearance sync, so a Settings edit would take effect
// and then silently revert. CornerExponent is the one such key today -- the
// shell writes it from AppearanceTokens.shape.cornerExponent, which is a source
// constant, not user configuration. Those rows are reported read-only so the UI
// stops offering a control that cannot hold its value; the write path is refused
// as well, so a stale UI cannot reintroduce the double write.
bool isReadOnlyDebugKey(const QString &key)
{
    return key == QLatin1String("CornerExponent");
}

} // namespace

// 托管图集目录(GNOME 模式:导入=复制进来,图集=枚举本目录,移除=进回收站)。
// shell 侧 WallpaperService.migrateLibraryOnce 迁移旧图集时复制到同一路径,
// 两处路径必须同步修改。
static QString galleryDirPath() {
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
        + QStringLiteral("/kos/gallery");
}

// 壁纸缩略图缓存目录,确保存在。生成(wallpaperThumbnail)与启动清理
// (CacheMaintenance::schedule)共用;以后新增缓存目录照此模式各起一个助手。
static QString wallpaperThumbCacheDir() {
    const QString dir = QStandardPaths::writableLocation(
        QStandardPaths::GenericCacheLocation) + QStringLiteral("/kos/wallpaper-thumbs/");
    if (!QDir(dir).exists())
        QDir().mkpath(dir);
    return dir;
}

class SettingsBridge final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(bool developmentSession READ isDevelopmentSession NOTIFY sessionChanged)
    Q_PROPERTY(QString sessionShellDir READ sessionShellDir NOTIFY sessionChanged)
    Q_PROPERTY(bool sourceTreeEntry READ sourceTreeEntry NOTIFY entryChanged)
    Q_PROPERTY(bool developmentBannerDismissed READ isDevelopmentBannerDismissed
                   WRITE setDevelopmentBannerDismissed NOTIFY bannerDismissedChanged)

public:

    explicit SettingsBridge(QObject *parent = nullptr) : QObject(parent) {
        // The Shell's own Settings entry goes through the platform daemon, which
        // exports KOS_SHELL_DIR for the session it belongs to. That is the one
        // launch path that can answer before the window exists, so it is taken
        // as the starting answer and corrected below if a call lands somewhere
        // else.
        const QString configured = qEnvironmentVariable("KOS_SHELL_DIR");
        if (!configured.isEmpty())
            m_sessionShellDir = configured;
        // 缩略图生成专用池:并发 2。全局池按核数开满,几十张 4K 壁纸同时
        // 解码能把内存顶到几百 MB(每张全尺寸 RGBA ~33MB)。
        m_thumbnailPool.setMaxThreadCount(2);
    }

    ~SettingsBridge() override {
        // 析构等在飞的探测线程落地：worker 读 QPointer guard 与 UI 线程
        // 析构是数据竞争（QPointer 非线程安全，注释原以为"只捕获指针"
        // 就绕开了，读它本身就在竞争）；QThread 无父对象不等则退出时
        // "Destroyed while thread is still running"。finished→removeAll
        // 经 queued 也在 UI 线程跑，列表自身无竞争。
        const QList<QThread *> threads = m_probeThreads;
        for (QThread *thread : threads)
            thread->wait();
        m_thumbnailPool.clear();
        m_thumbnailPool.waitForDone();
    }

    QString lastError() const { return m_lastError; }

    // Whether this window is driving a Shell started from a checkout
    // (`kosctl dev`, `qs -p <checkout>/shell`) rather than the installed `kos`
    // configuration. It decides which QML tree is loaded and whether the window
    // reports itself as a development session, so it is derived from the
    // session itself and never from this binary's own location.
    bool isDevelopmentSession() const {
        return !m_sessionShellDir.isEmpty() && !isInstalledShellDirectory(m_sessionShellDir);
    }

    QString sessionShellDir() const { return m_sessionShellDir; }

    // Whether the pages on screen actually came from a checkout: the fact the
    // banner has to report. Deliberately not `developmentSession`, which only
    // says which Shell answered IPC. A .desktop launch (app grid, KRunner)
    // starts with no KOS_SHELL_DIR and loads the installed copy, then the first
    // successful call discovers the checkout session and flips that one to true
    // -- keying the banner off the session would announce hot reloading on a
    // window that is reloading nothing.
    bool sourceTreeEntry() const { return m_sourceTreeEntry; }

    // Called once from main() with the entry point it picked, before the engine
    // loads it. Constant for the life of the window: the pages cannot change
    // trees mid-run.
    void setSourceTreeEntry(bool value) {
        if (m_sourceTreeEntry == value)
            return;
        m_sourceTreeEntry = value;
        emit entryChanged();
    }

    // Whether the user closed the development banner. Held here rather than in
    // the window because the window is rebuilt on every QML reload, and a reload
    // is not a new session: without this the banner would come back the moment
    // anyone edited the page they were told to edit. The flag lives for the
    // process, so reopening Settings starts from a visible banner again.
    bool isDevelopmentBannerDismissed() const { return m_bannerDismissed; }

    void setDevelopmentBannerDismissed(bool dismissed) {
        if (m_bannerDismissed == dismissed)
            return;
        m_bannerDismissed = dismissed;
        emit bannerDismissedChanged();
    }

    // Every shell call is asynchronous: the request returns at once and the
    // reply is delivered on the UI thread through the matching *Changed
    // signal. Before this, each call spawned `quickshell ipc call` and blocked
    // the GUI thread in waitForStarted/waitForFinished plus a retry sleep, so
    // one failed request froze the window for ~11s and the eagerly
    // instantiated pages froze startup entirely while the shell was down.
    Q_INVOKABLE void dockSnapshot() {
        callDock({QStringLiteral("snapshot")});
    }

    Q_INVOKABLE void wallpaperSnapshot() {
        callWallpaper({QStringLiteral("snapshot")});
    }

    Q_INVOKABLE QStringList wallpaperCatalog() const {
        QStringList catalog;
        const QStringList formats{QStringLiteral("*.jpg"), QStringLiteral("*.jpeg"),
                                  QStringLiteral("*.png"), QStringLiteral("*.webp"),
                                  QStringLiteral("*.avif"), QStringLiteral("*.bmp")};
        for (const QString &location : QStandardPaths::standardLocations(
                 QStandardPaths::GenericDataLocation)) {
            const QDir wallpapers(location + QStringLiteral("/wallpapers"));
            if (!wallpapers.exists())
                continue;
            const QFileInfoList entries = wallpapers.entryInfoList(
                QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot,
                QDir::Name | QDir::IgnoreCase);
            for (const QFileInfo &entry : entries) {
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
                const QDir images(entry.absoluteFilePath()
                                  + QStringLiteral("/contents/images"));
                if (!images.exists())
                    continue;
                const QFileInfoList candidates = images.entryInfoList(
                    formats, QDir::Files, QDir::Name | QDir::IgnoreCase);
                if (candidates.isEmpty())
                    continue;
                QFileInfo chosen = candidates.first();
                double bestScore = -1e9;
                for (const QFileInfo &candidate : candidates) {
                    const QStringList size = candidate.completeBaseName().split('x');
                    const double width = size.value(0).toDouble();
                    const double height = size.value(1).toDouble();
                    if (width < 1 || height < 1)
                        continue;
                    const double score = -qAbs(width / height - 16.0 / 9.0) * 10000
                        - qAbs(width - 3840) / 100.0;
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

    // 磁盘缩略图缓存:键 = 源路径+mtime+目标尺寸+圆角的 SHA1,落盘 WebP q72
    // (带 alpha;无 webp 编码器的机器退回 PNG)。圆角直接烘进图里(角外透明),
    // 瓦片端不需要 MultiEffect 蒙版图层——那是展开全部时每瓦片一层的 FBO
    // 内存大头。命中→立即返回;未命中→返回空串让瓦片先用原图,同时线程池
    // 后台生成,完成发 wallpaperThumbnailChanged。
    Q_INVOKABLE QString wallpaperThumbnail(const QString &urlOrPath,
                                           int width, int height, int radius, bool generate = true) {
        const QString path = urlOrPath.startsWith(QStringLiteral("file:"))
            ? QUrl(urlOrPath).toLocalFile() : urlOrPath;
        const QFileInfo info(path);
        if (path.isEmpty() || !info.isFile() || !info.isReadable()
                || width < 1 || height < 1 || width > 2048 || height > 2048)
            return {};
        const QString key = QString::fromLatin1(
            QCryptographicHash::hash(
                QStringLiteral("thumb-v2|%1|%2|%3x%4r%5").arg(path,
                    QString::number(info.lastModified().toMSecsSinceEpoch()),
                    QString::number(width), QString::number(height),
                    QString::number(radius)).toUtf8(),
                QCryptographicHash::Sha1).toHex());
        // WebP 带 alpha 且几十 KB;无 webp 编码器的机器退回 PNG(大些但可用)。
        static const bool webpWritable =
            QImageWriter::supportedImageFormats().contains("webp");
        const QString thumbFile = wallpaperThumbCacheDir() + key
            + (webpWritable ? QStringLiteral(".webp") : QStringLiteral(".png"));
        if (QFileInfo(thumbFile).size() > 0)
            return QUrl::fromLocalFile(thumbFile).toString();
        if (!generate) return {};
        const QString source = info.absoluteFilePath();
        {
            QMutexLocker locker(&m_thumbnailMutex);
            if (m_thumbnailFailed.contains(key) || m_thumbnailInFlight.size() >= 64
                || m_thumbnailInFlight.contains(key))
                return {};
            m_thumbnailInFlight.insert(key);
        }
        const QString keyCopy = key;
        // QPointer 守护:窗口退出后对象销毁,后台任务收尾时不再 emit。
        QPointer<SettingsBridge> self(this);
        m_thumbnailPool.start([self, source, thumbFile, keyCopy, width, height,
                               radius]() {
            // 按目标尺寸降采样解码(QImageReader):4K 原图全尺寸解码要
            // ~33MB/张,降采样后中间产物 <1MB,内存和速度都差一个量级。
            QImageReader reader(source);
            reader.setAutoTransform(true);
            const QSize originalSize = reader.size();
            if (originalSize.width() > 0 && originalSize.height() > 0) {
                // Bound the intermediate canvas even for panoramas. Crop
                // before the final resize instead of expanding a thin image
                // to an arbitrarily long buffer.
                reader.setScaledSize(originalSize.scaled(
                    QSize(width * 2, height * 2), Qt::KeepAspectRatio));
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
                QImage thumb = image.copy((image.width() - crop.width()) / 2,
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
                emit self->wallpaperThumbnailChanged();
        });
        return {};
    }

    // ===== 托管图集(GNOME 模式):导入=复制进 galleryDir,图集=枚举该目录,
    // 移除=移入回收站。全部本地操作,不经 shell IPC、无快照回填。

    static bool isGalleryImage(const QFileInfo &info) {
        static const QStringList formats{
            QStringLiteral("jpg"), QStringLiteral("jpeg"), QStringLiteral("png"),
            QStringLiteral("webp"), QStringLiteral("avif"), QStringLiteral("bmp")};
        return formats.contains(info.suffix().toLower());
    }

    // 内容指纹缓存:键=路径,附 (大小, mtime) 校验——文件没变就直接复用,
    // 不重复读盘。仅 UI 线程访问(导入是同步 Q_INVOKABLE),无需加锁。
    struct GalleryFingerprint {
        qint64 size = 0;
        qint64 mtime = 0;
        QByteArray md5;
    };
    QHash<QString, GalleryFingerprint> m_galleryFingerprints;

    QByteArray galleryFileMd5(const QString &path) {
        const QFileInfo info(path);
        const qint64 size = info.size();
        const qint64 mtime = info.lastModified().toMSecsSinceEpoch();
        const auto it = m_galleryFingerprints.constFind(path);
        if (it != m_galleryFingerprints.constEnd()
                && it->size == size && it->mtime == mtime)
            return it->md5;
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly))
            return {};
        QCryptographicHash hash(QCryptographicHash::Md5);
        char buffer[1 << 16];
        while (!file.atEnd()) {
            const qint64 read = file.read(buffer, sizeof(buffer));
            if (read <= 0)
                return {};
            hash.addData(QByteArrayView(buffer, qsizetype(read)));
        }
        const QByteArray md5 = hash.result();
        if (m_galleryFingerprints.size() >= 4096)
            m_galleryFingerprints.clear();
        m_galleryFingerprints.insert(path, {size, mtime, md5});
        return md5;
    }

    // 枚举托管图集,按 mtime 降序 = 新导入置顶。同步但目录只有自己的副本,
    // 单次几百 stat 以内,代价可控。
    Q_INVOKABLE QStringList galleryImages() const {
        const QDir dir(galleryDirPath());
        QFileInfoList entries = dir.entryInfoList(QDir::Files | QDir::Readable);
        entries.erase(std::remove_if(entries.begin(), entries.end(),
                          [](const QFileInfo &info) { return !isGalleryImage(info); }),
            entries.end());
        std::sort(entries.begin(), entries.end(),
            [](const QFileInfo &a, const QFileInfo &b) {
                return a.lastModified() > b.lastModified();
            });
        QStringList images;
        images.reserve(entries.size());
        for (const QFileInfo &entry : entries)
            images.append(entry.absoluteFilePath());
        return images;
    }

    // 复制单张图片进托管图集;JPEG 统一转基线编码(见 transcodeJpegBaseline);
    // 重名自动加 " (n)"。返回目标路径,失败返回空串。
    // 解码并按基线(baseline)编码重存 JPEG,失败返回空。图库素材以库存图为
    // 主,其中大量是 progressive 编码:libjpeg 解码 progressive 必须缓存全部
    // 系数块,一张 7680x4320 的渐进图解码时临时占 20-30MB 解压工作区。导入时
    // 统一转成基线,同一份像素数据、解码内存可控。EXIF 方向直接烘进像素,质量
    // 95 的再编码折损肉眼不可见。已知取舍:非 sRGB 源(如 Display P3)写入时
    // 不带色域标签,宽色域屏上可能有轻微饱和度偏移;Qt 6.11 的 QtGui 没有导出
    // ICC 写入 API,无法在转码时保留。
    static QByteArray transcodeJpegBaseline(const QString &path) {
        QImageReader reader(path);
        reader.setAutoTransform(true);
        const QImage image = reader.read();
        if (image.isNull())
            return {};
        QByteArray bytes;
        QBuffer buffer(&bytes);
        if (!buffer.open(QIODevice::WriteOnly))
            return {};
        QImageWriter writer(&buffer, "jpeg");
        writer.setQuality(95);
        if (!writer.write(image))
            return {};
        return bytes;
    }

    Q_INVOKABLE QString importGalleryImage(const QString &urlOrPath) {
        const QString path = urlOrPath.startsWith(QStringLiteral("file:"))
            ? QUrl(urlOrPath).toLocalFile() : urlOrPath;
        const QFileInfo info(path);
        if (path.isEmpty() || !info.isFile() || !info.isReadable()
                || !isGalleryImage(info) || !QImageReader(info.absoluteFilePath()).canRead()) {
            setLastError(QStringLiteral("请选择本机可读取的图片"));
            return {};
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
            setLastError(QStringLiteral("无法读取图片内容"));
            return {};
        }
        const bool isJpeg = info.suffix().compare(QLatin1String("jpg"), Qt::CaseInsensitive) == 0
            || info.suffix().compare(QLatin1String("jpeg"), Qt::CaseInsensitive) == 0;
        QByteArray payload;
        if (isJpeg)
            payload = transcodeJpegBaseline(info.absoluteFilePath());
        // 转码失败不阻塞导入:回退为原始字节复制,行为与未转码时一致。
        const QByteArray candidateMd5 = payload.isEmpty()
            ? QByteArray{} : QCryptographicHash::hash(payload, QCryptographicHash::Md5);
        for (const QFileInfo &entry : dir.entryInfoList(QDir::Files)) {
            if (entry.size() != info.size()
                    && (payload.isEmpty() || entry.size() != qsizetype(payload.size())))
                continue;
            const QByteArray entryMd5 = galleryFileMd5(entry.absoluteFilePath());
            if (entryMd5 == sourceMd5
                    || (!candidateMd5.isEmpty() && entryMd5 == candidateMd5))
                return entry.absoluteFilePath();
        }
        const QString base = info.completeBaseName();
        const QString suffix = info.suffix();
        QString target = dir.filePath(info.fileName());
        for (int n = 1; QFileInfo::exists(target); ++n)
            target = dir.filePath(QStringLiteral("%1 (%2).%3")
                                      .arg(base, QString::number(n), suffix));
        if (!payload.isEmpty()) {
            QSaveFile out(target);
            if (!out.open(QIODevice::WriteOnly)
                    || out.write(payload) != qsizetype(payload.size()) || !out.commit()) {
                out.cancelWriting();
                setLastError(QStringLiteral("复制图片失败:%1").arg(info.fileName()));
                return {};
            }
        } else if (!QFile::copy(info.absoluteFilePath(), target)) {
            setLastError(QStringLiteral("复制图片失败:%1").arg(info.fileName()));
            return {};
        }
        return target;
    }

    // 复制文件夹内全部图片进托管图集(一次性快照,之后文件夹新增不会自动
    // 出现),返回成功张数,上限 200。
    Q_INVOKABLE int importGalleryFolder(const QString &urlOrPath) {
        const QString path = urlOrPath.startsWith(QStringLiteral("file:"))
            ? QUrl(urlOrPath).toLocalFile() : urlOrPath;
        const QDir folder(path);
        if (path.isEmpty() || !folder.exists()) {
            setLastError(QStringLiteral("文件夹不存在或不可读取"));
            return -1;
        }
        constexpr int kMaxFolderImages = 200;
        int imported = 0;
        const QFileInfoList entries = folder.entryInfoList(
            QDir::Files | QDir::Readable, QDir::Name | QDir::IgnoreCase);
        for (const QFileInfo &entry : entries) {
            if (imported >= kMaxFolderImages)
                break;
            if (!isGalleryImage(entry))
                continue;
            if (!importGalleryImage(entry.absoluteFilePath()).isEmpty())
                ++imported;
        }
        return imported;
    }

    // 移入回收站，只允许操作托管目录内的图片。
    Q_INVOKABLE bool deleteGalleryImage(const QString &urlOrPath) {
        const QString path = urlOrPath.startsWith(QStringLiteral("file:"))
            ? QUrl(urlOrPath).toLocalFile() : urlOrPath;
        const QString canonical = QFileInfo(path).canonicalFilePath();
        const QString managed = QFileInfo(galleryDirPath()).canonicalFilePath();
        if (canonical.isEmpty() || managed.isEmpty()
                || !canonical.startsWith(managed + QLatin1Char('/'))) {
            setLastError(QStringLiteral("只能移除图集内的图片"));
            return false;
        }
        if (!QFile::moveToTrash(canonical)) {
            setLastError(QStringLiteral("移入回收站失败:%1")
                             .arg(QFileInfo(canonical).fileName()));
            return false;
        }
        return true;
    }

    // 打开图片所在文件夹是设置程序自己的本地动作,不经 shell、无快照回填。
    Q_INVOKABLE void revealWallpaperImage(const QString &urlOrPath) {
        const QString path = urlOrPath.startsWith(QStringLiteral("file:"))
            ? QUrl(urlOrPath).toLocalFile() : urlOrPath;
        const QFileInfo info(path);
        if (!info.exists()) {
            setLastError(QStringLiteral("文件不存在,无法打开所在文件夹"));
            emit wallpaperSnapshotChanged({});
            return;
        }
        QDesktopServices::openUrl(QUrl::fromLocalFile(info.isDir()
            ? info.absoluteFilePath() : info.absolutePath()));
    }

    Q_INVOKABLE void chooseWallpaperImage(const QString &urlOrPath) {        const QString path = urlOrPath.startsWith(QStringLiteral("file:"))
            ? QUrl(urlOrPath).toLocalFile() : urlOrPath;
        const QFileInfo image(path);
        if (!image.isFile() || !image.isReadable()) {
            setLastError(QStringLiteral("请选择本机可读取的图片"));
            emit wallpaperSnapshotChanged({});
            return;
        }
        callWallpaper({QStringLiteral("chooseImage"), image.absoluteFilePath()});
    }

    Q_INVOKABLE void previewWallpaperImage(const QString &urlOrPath,
                                            const QStringList &images) {
        const QString path = urlOrPath.startsWith(QStringLiteral("file:"))
            ? QUrl(urlOrPath).toLocalFile() : urlOrPath;
        if (!QFileInfo(path).isFile() || !QFileInfo(path).isReadable()) {
            setLastError(QStringLiteral("请选择本机可读取的图片"));
            emit wallpaperSnapshotChanged({});
            return;
        }
        QJsonArray paths;
        for (const QString &image : images.mid(0, 2000)) paths.append(image);
        const QString listJson = QString::fromUtf8(
            QJsonDocument(paths).toJson(QJsonDocument::Compact));
        callWallpaper({QStringLiteral("previewImage"), QFileInfo(path).absoluteFilePath(),
            ipcStringArgument(listJson)});
    }

    // Generated colors are internal cache entries, never added to the user's library.
    Q_INVOKABLE QString wallpaperColorImage(const QString &start, const QString &end,
                                             int angle) {
        const QRegularExpression format(QStringLiteral("^#[0-9a-fA-F]{6}$"));
        if (!format.match(start).hasMatch() || !format.match(end).hasMatch()) {
            setLastError(QStringLiteral("请输入有效的六位十六进制颜色，例如 #A8C8F0"));
            return {};
        }
        angle = ((angle % 360) + 360) % 360;
        const QString folder = QStandardPaths::writableLocation(
            QStandardPaths::GenericCacheLocation) + QStringLiteral("/kos/wallpaper-colors");
        const QString key = start == end ? start.mid(1).toLower()
            : QStringLiteral("gradient-%1-%2-%3").arg(start.mid(1).toLower(),
                end.mid(1).toLower(), QString::number(angle));
        const QString path = folder + QLatin1Char('/') + key + QStringLiteral(".png");
        if (QFileInfo::exists(path)) return path;
        if (!QDir().mkpath(folder)) {
            setLastError(QStringLiteral("无法创建颜色壁纸缓存"));
            return {};
        }
        QImage image(start == end ? QSize(16, 16) : QSize(1920, 1080), QImage::Format_RGB32);
        if (start == end) image.fill(QColor(start));
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
            setLastError(QStringLiteral("无法生成颜色壁纸"));
            return {};
        }
        setLastError({});
        return path;
    }

    Q_INVOKABLE void chooseWallpaperColor(const QString &hex) {
        chooseWallpaperGradient(hex, hex, 0);
    }

    Q_INVOKABLE void chooseWallpaperGradient(const QString &start, const QString &end, int angle) {
        const QString path = wallpaperColorImage(start, end, angle);
        if (path.isEmpty()) { emit wallpaperSnapshotChanged({}); return; }
        callWallpaper({QStringLiteral("chooseColor"), path});
    }

    Q_INVOKABLE QString wallpaperCustomColors() {
        QSettings settings;
        return settings.value(QStringLiteral("wallpaper/customColors"), QStringLiteral("[]")).toString();
    }
    Q_INVOKABLE void saveWallpaperCustomColors(const QString &json) {
        const QJsonDocument document = QJsonDocument::fromJson(json.toUtf8());
        if (!document.isArray()) return;
        QSettings settings;
        settings.setValue(QStringLiteral("wallpaper/customColors"), json);
    }

    Q_INVOKABLE void pickWallpaperColor() {
        QDBusInterface picker(QStringLiteral("org.kde.KWin"), QStringLiteral("/ColorPicker"),
                              QStringLiteral("org.kde.kwin.ColorPicker"), QDBusConnection::sessionBus());
        auto *watcher = new QDBusPendingCallWatcher(picker.asyncCall(QStringLiteral("pick")), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
            const QDBusMessage reply = watcher->reply();
            watcher->deleteLater();
            if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().isEmpty()) {
                emit wallpaperColorPickFailed(QStringLiteral("取色已取消或当前桌面不支持屏幕取色"));
                return;
            }
            const QDBusArgument value = reply.arguments().first().value<QDBusArgument>();
            quint32 rgba = 0;
            value.beginStructure(); value >> rgba; value.endStructure();
            emit wallpaperColorPicked(QColor::fromRgba(rgba).name(QColor::HexRgb));
        });
    }

    Q_INVOKABLE void previewWallpaperSession(const QString &path, const QVariantMap &session) {
        const QString json = QString::fromUtf8(QJsonDocument(
            QJsonObject::fromVariantMap(session)).toJson(QJsonDocument::Compact));
        callWallpaper({QStringLiteral("previewSession"), path, ipcStringArgument(json)});
    }

    Q_INVOKABLE void updateWallpaperPreviewThumbnails(const QVariantMap &thumbnails) {
        const QString json = QString::fromUtf8(QJsonDocument(
            QJsonObject::fromVariantMap(thumbnails)).toJson(QJsonDocument::Compact));
        callWallpaper({QStringLiteral("setPreviewThumbnails"), ipcStringArgument(json)});
    }

    Q_INVOKABLE void updateWallpaperTransitionOptions(const QVariantMap &options) {
        const QString json = QString::fromUtf8(QJsonDocument(
            QJsonObject::fromVariantMap(options)).toJson(QJsonDocument::Compact));
        callWallpaper({QStringLiteral("setTransitionOptions"), ipcStringArgument(json)});
    }

    Q_INVOKABLE void updateWallpaperFitMode(const QString &mode) {
        callWallpaper({QStringLiteral("setFitMode"), mode});
    }

    Q_INVOKABLE void updateWallpaperTakeoverEnabled(bool enabled) {
        callWallpaper({QStringLiteral("setTakeoverEnabled"),
                       enabled ? QStringLiteral("true") : QStringLiteral("false")});
    }

    Q_INVOKABLE void updateWallpaperTransition(const QString &style) {
        callWallpaper({QStringLiteral("setTransition"), style});
    }

    Q_INVOKABLE void updateWallpaperSlideshow(bool enabled, int minutes,
                                              const QStringList &images,
                                              const QString &folder) {
        QJsonArray paths;
        for (const QString &path : images.mid(0, 2000))
            paths.append(path);
        const QString listJson = QString::fromUtf8(
            QJsonDocument(paths).toJson(QJsonDocument::Compact));
        callWallpaper({QStringLiteral("setSlideshow"),
                       enabled ? QStringLiteral("true") : QStringLiteral("false"),
                       QString::number(minutes),
                       ipcStringArgument(listJson),
                       folder});
    }

    Q_INVOKABLE void updateWallpaperSpatialEnabled(bool enabled) {
        callWallpaper({QStringLiteral("setSpatialEnabled"),
                       enabled ? QStringLiteral("true") : QStringLiteral("false")});
    }

    // 主题包(marketplace)清单扫描:~/.local/share/kos/wallpaper-themes/<id>/
    // manifest.json,字段与兜底规则和壳侧 ThemePackService 一致(缺 id 用目录
    // 名,缺 name 用 id,entry/preview 拒绝路径分隔符)。同步但只在打开壁纸
    // 页时调用,目录规模是个位数,代价可控。
    Q_INVOKABLE QVariantList themePackCatalog() const {
        QVariantList packs;
        const QString override = qEnvironmentVariable("KOS_WALLPAPER_PACKS");
        const QString root = override.trimmed().isEmpty()
            ? qEnvironmentVariable("HOME") + QStringLiteral("/.local/share/kos/wallpaper-themes")
            : override.trimmed();
        const QFileInfoList entries = QDir(root).entryInfoList(
            QDir::Dirs | QDir::Readable | QDir::NoDotAndDotDot, QDir::Name | QDir::IgnoreCase);
        static const QRegularExpression validId(QStringLiteral("^[A-Za-z0-9_-]+$"));
        for (const QFileInfo &entry : entries) {
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
            const QString entryName = object.value(QStringLiteral("entry")).toString(QStringLiteral("main.qml"));
            QString preview = object.value(QStringLiteral("preview")).toString();
            if (entryName.isEmpty() || entryName.contains(QLatin1Char('/')) || entryName.contains(QStringLiteral("..")))
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
            pack.insert(QStringLiteral("entryPath"), entry.absoluteFilePath() + QLatin1Char('/') + entryName);
            pack.insert(QStringLiteral("previewPath"),
                        preview.isEmpty() ? QString()
                                          : entry.absoluteFilePath() + QLatin1Char('/') + preview);
            packs.append(pack);
        }
        return packs;
    }

    Q_INVOKABLE void chooseWallpaperTheme(const QString &id) {
        if (id != "starfield" && id != "blackhole" && id != "weather"
            && id != "underwater" && id != "forest") {
            // 包主题(marketplace)不在内置名单里:只做格式守卫,存在性由壳侧
            // ThemePackService / WallpaperService.chooseTheme 校验。
            static const QRegularExpression validId(QStringLiteral("^[A-Za-z0-9_-]+$"));
            if (!validId.match(id).hasMatch()) return;
        }
        callWallpaper({QStringLiteral("chooseTheme"), id});
    }
    Q_INVOKABLE void updateWallpaperThemeEconomical(bool enabled) {
        callWallpaper({QStringLiteral("setThemeEconomical"), enabled ? QStringLiteral("true") : QStringLiteral("false")});
    }

    Q_INVOKABLE void updateWallpaperThemeMotion(bool animated, double speed, int count) {
        callWallpaper({QStringLiteral("setThemeMotion"), animated ? QStringLiteral("true") : QStringLiteral("false"),
                       QString::number(qBound(0.1, speed, 1.5)), QString::number(qBound(24, count, 160))});
    }

    Q_INVOKABLE void prepareWallpaperSpatial() {
        callWallpaper({QStringLiteral("prepareSpatial")});
    }

    Q_INVOKABLE void initializeSpatialService() { callWallpaper({QStringLiteral("initializeSpatialService")}); }
    Q_INVOKABLE void disableSpatialService() { callWallpaper({QStringLiteral("disableSpatialService")}); }
    Q_INVOKABLE void cancelWallpaperSpatial() { callWallpaper({QStringLiteral("cancelSpatial")}); }
    Q_INVOKABLE void inspectSpatialService() { callWallpaper({QStringLiteral("inspectSpatialService")}); }
    Q_INVOKABLE void clearSpatialCache(const QString &kind) {
        if (kind != "generated" && kind != "models" && kind != "all") return;
        callWallpaper({QStringLiteral("clearSpatialCache"), kind});
    }

    Q_INVOKABLE void inspectWallpaperModels() {
        if (m_modelInspectionPending)
            return;
        m_modelInspectionPending = true;
        const QString directory = QStandardPaths::writableLocation(
            QStandardPaths::GenericCacheLocation)
            + QStringLiteral("/liquid-shell/models/");
        const QPointer<SettingsBridge> guard(this);
        auto *thread = QThread::create([guard, directory] {
            const bool depth = cachedModelVerified(
                directory + QStringLiteral("depth-anything-v2-small-vits.onnx"),
                LiquidAI::ModelManager::modelSha256);
            const bool foreground = cachedModelVerified(
                directory + QStringLiteral("isnet-general-use.onnx"),
                LiquidAI::ModelManager::foregroundModelSha256);
            if (guard) {
                QMetaObject::invokeMethod(guard.data(), [guard, depth, foreground] {
                    if (!guard)
                        return;
                    guard->m_modelInspectionPending = false;
                    emit guard->wallpaperModelsChecked(depth, foreground);
                }, Qt::QueuedConnection);
            }
        });
        connect(thread, &QThread::finished, thread, &QObject::deleteLater);
        thread->start();
    }

    Q_INVOKABLE void updateDockLayout(double height) {
        callDock({QStringLiteral("updateLayout"),
                  QString::number(height, 'f', 2)});
    }

    Q_INVOKABLE void updateDockPosition(const QString &position) {
        callDock({QStringLiteral("updatePosition"), position});
    }

    Q_INVOKABLE void updateDockBuiltinVisibility(const QString &id, bool visible) {
        callShell(QStringLiteral("dock-settings"),
                  {QStringLiteral("updateBuiltinVisibility"), id,
                   visible ? QStringLiteral("true") : QStringLiteral("false")},
                  QStringLiteral("Dock 图标显示设置请求失败"),
                  RequestKind::DockBuiltinVisibility);
    }

    Q_INVOKABLE void updateDockNotificationBadgeVisibility(bool visible) {
        callShell(QStringLiteral("dock-settings"),
                  {QStringLiteral("updateNotificationBadgeVisibility"),
                   visible ? QStringLiteral("true") : QStringLiteral("false")},
                  QStringLiteral("Dock 通知角标设置请求失败"),
                  RequestKind::DockNotificationBadgeVisibility);
    }

    Q_INVOKABLE void updateDockRevealIndicatorVisibility(bool visible) {
        callShell(QStringLiteral("dock-settings"),
                  {QStringLiteral("updateRevealIndicatorVisibility"),
                   visible ? QStringLiteral("true") : QStringLiteral("false")},
                  QStringLiteral("Dock 隐藏提示条设置请求失败"),
                  RequestKind::DockRevealIndicatorVisibility);
    }

    Q_INVOKABLE void updateDockContentStyle(const QString &style) {
        callDock({QStringLiteral("updateContentStyle"), style});
    }

    Q_INVOKABLE void updateDockStyle(const QString &style) {
        callDock({QStringLiteral("updateDockStyle"), style});
    }

    Q_INVOKABLE void updateDockIconMode(const QString &mode) {
        callDock({QStringLiteral("updateIconMode"), mode});
    }

    Q_INVOKABLE void updateDockIconOpacity(double opacity) {
        callDock({QStringLiteral("updateIconOpacity"),
                  QString::number(opacity, 'f', 2)});
    }

    Q_INVOKABLE void updateDockIconTintColor(const QString &color) {
        callDock({QStringLiteral("updateIconTintColor"), color});
    }

    Q_INVOKABLE void updateDockVisibilityMode(const QString &mode) {
        callDock({QStringLiteral("updateVisibilityMode"), mode});
    }

    Q_INVOKABLE void updateDockWindowGrouping(const QString &mode) {
        callDock({QStringLiteral("updateWindowGrouping"), mode});
    }

    Q_INVOKABLE void appearanceSnapshot() {
        callAppearance({QStringLiteral("snapshot")});
    }

    Q_INVOKABLE void updateBlurStrength(double strength) {
        callAppearance({
            QStringLiteral("updateGlobalBlurStrength"),
            QString::number(strength, 'f', 3)});
    }

    Q_INVOKABLE void updateLiquidStrength(double strength) {
        callAppearance({
            QStringLiteral("updateGlobalLiquidStrength"),
            QString::number(strength, 'f', 3)});
    }

    Q_INVOKABLE void updateGlobalBlurStrength(double strength) {
        callAppearance({
            QStringLiteral("updateGlobalBlurStrength"),
            QString::number(strength, 'f', 3)});
    }

    Q_INVOKABLE void updateGlobalLiquidStrength(double strength) {
        callAppearance({
            QStringLiteral("updateGlobalLiquidStrength"),
            QString::number(strength, 'f', 3)});
    }

    Q_INVOKABLE void updateGlassStyle(const QString &style) {
        callAppearance({QStringLiteral("updateGlassStyle"), style});
    }

    Q_INVOKABLE void updateWidgetStyle(const QString &style) {
        callAppearance({QStringLiteral("updateWidgetStyle"), style});
    }

    Q_INVOKABLE void updateGlassPresetParameter(const QString &name, double value) {
        callAppearance({
            QStringLiteral("updateGlassPresetParameter"), name,
            QString::number(value, 'f', 3)});
    }

    Q_INVOKABLE void resetGlassPreset(const QString &style) {
        callAppearance({QStringLiteral("resetGlassPreset"), style});
    }

    // ── 台前调度（fg-sched）页 ──
    // 配置就是 ~/.config/fg-sched/config.json：直接读写，root 守护对 mtime
    // 轮询自动应用（≤5s），无需任何信号/特权通道。knownApps 来自守护维护的
    // known-apps.json（出现过的 resourceClass）。
    static QString fgSchedConfigPath() {
        return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
            + QStringLiteral("/fg-sched/config.json");
    }
    static QString fgSchedKnownAppsPath() {
        return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
            + QStringLiteral("/fg-sched/known-apps.json");
    }

    static bool writeFgSchedConfig(
            const std::function<void(QJsonObject &)> &mutate) {
        QJsonObject obj;
        {
            QFile in(fgSchedConfigPath());
            if (in.open(QIODevice::ReadOnly))
                obj = QJsonDocument::fromJson(in.readAll()).object();
        }
        mutate(obj);
        if (!QDir().mkpath(QFileInfo(fgSchedConfigPath()).absolutePath()))
            return false;
        QSaveFile out(fgSchedConfigPath());
        if (!out.open(QIODevice::WriteOnly))
            return false;
        out.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
        return out.commit();
    }

    // 实时运行应用清单：走 shell 的 fg-sched IPC（WindowService 全量窗口，
    // 去重成 {name, appId}），供"从运行应用添加"下拉框使用。
    Q_INVOKABLE void fgSchedRunningApps() {
        callShell(QStringLiteral("fg-sched"), {QStringLiteral("runningApps")},
                  QStringLiteral("运行应用清单请求失败"), RequestKind::FgSchedApps);
    }

    Q_INVOKABLE void fgSchedSnapshot() {
        QVariantMap out;
        out.insert(QStringLiteral("resourceSchedulingAvailable"),
                   !QStandardPaths::findExecutable(QStringLiteral("fg-schedd")).isEmpty()
                   || QFileInfo(QStringLiteral("/usr/local/sbin/fg-schedd")).isExecutable()
                   || QFileInfo(QStringLiteral("/usr/sbin/fg-schedd")).isExecutable());
        QJsonObject obj;
        {
            QFile in(fgSchedConfigPath());
            if (in.open(QIODevice::ReadOnly))
                obj = QJsonDocument::fromJson(in.readAll()).object();
        }
        out.insert(QStringLiteral("freezeEnabled"),
                   obj.value(QStringLiteral("freeze_minimized_after_s")).toInt() > 0);
        out.insert(QStringLiteral("reclaimMode"),
                   obj.value(QStringLiteral("reclaim")).toObject()
                       .value(QStringLiteral("mode")).toString(QStringLiteral("once")));
        QStringList full;
        const auto fullArray = obj.value(QStringLiteral("never_demote_apps")).toArray();
        for (const auto &v : fullArray)
            full << v.toString();
        out.insert(QStringLiteral("fullResources"), full);
        const auto bg = obj.value(QStringLiteral("background")).toObject();
        out.insert(QStringLiteral("bgNice"), bg.value(QStringLiteral("nice")).toDouble());
        // affinity_cpus 三态：显式数组原样列出；"auto"/缺省 = 守护启动时
        // 自动探测（异构→效率核，同构→不限核）。UI 只需知道模式不必知道
        // 具体核号，跨机器通用。
        const auto cpuValue = bg.value(QStringLiteral("affinity_cpus"));
        if (cpuValue.isArray()) {
            QStringList cpus;
            const auto cpuArray = cpuValue.toArray();
            for (const auto &v : cpuArray)
                cpus << QString::number(v.toInt());
            out.insert(QStringLiteral("bgCpus"), cpus.join(QStringLiteral(",")));
            out.insert(QStringLiteral("bgCpusAuto"), false);
        } else {
            out.insert(QStringLiteral("bgCpus"), QStringLiteral("auto"));
            out.insert(QStringLiteral("bgCpusAuto"), true);
        }
        QStringList known;
        QFile knownFile(fgSchedKnownAppsPath());
        if (knownFile.open(QIODevice::ReadOnly)) {
            const auto arr = QJsonDocument::fromJson(knownFile.readAll()).array();
            for (const auto &v : arr)
                known << v.toString();
        }
        out.insert(QStringLiteral("knownApps"), known);
        // 台前侧栏总开关的落盘态（StageModeService 的 stage-mode flag）
        QFile stageFlag(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
                        + QStringLiteral("/fg-sched/stage-mode"));
        if (stageFlag.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const QString flagValue = QString::fromUtf8(stageFlag.readAll())
                                          .trimmed();
            out.insert(QStringLiteral("stageEnabled"),
                       flagValue == QStringLiteral("1"));
        } else {
            out.insert(QStringLiteral("stageEnabled"), false);
        }
        emit fgSchedSnapshotChanged(out);
    }

    Q_INVOKABLE void fgSchedSetFreeze(bool on) {
        if (!writeFgSchedConfig([&](QJsonObject &obj) {
                obj.insert(QStringLiteral("freeze_minimized_after_s"), on ? 180 : 0);
            }))
            return;
        fgSchedSnapshot();
    }

    // 后台内存压缩模式：off=不动内存；once=切后台压一次；aggressive=持续压到最低
    Q_INVOKABLE void fgSchedSetReclaim(const QString &mode) {
        if (mode != QStringLiteral("off") && mode != QStringLiteral("once")
                && mode != QStringLiteral("aggressive")
                && mode != QStringLiteral("kill"))
            return;
        if (!writeFgSchedConfig([&](QJsonObject &obj) {
                QJsonObject rec = obj.value(QStringLiteral("reclaim")).toObject();
                rec.insert(QStringLiteral("mode"), mode);
                obj.insert(QStringLiteral("reclaim"), rec);
            }))
            return;
        fgSchedSnapshot();
    }

    // ── 台前调度（stage）参数：全部走 shell 的 stage-config IPC ──
    // set 的应答就是整份新快照；shell 侧负责钳位/持久化/kwinrc 投影
    // （窗口动画时长与曲线经 reconfigureEffect 即时生效）。
    void callStage(const QStringList &arguments) {
        callShell(QStringLiteral("stage-config"), arguments,
                  QStringLiteral("台前调度参数请求失败"), RequestKind::StageConfig);
    }

    Q_INVOKABLE void stageConfigSnapshot() {
        callStage({QStringLiteral("snapshot")});
    }

    Q_INVOKABLE void stageConfigSet(const QString &key, const QString &value) {
        callStage({QStringLiteral("set"), key, value});
    }

    // 台前侧栏总开关：stage-sidebar 的 enable/disable（show/hide 经 CLI
    // 永不可派发，见函数内注释）
    Q_INVOKABLE void stageSidebarSet(bool on) {
        // ⚠️ 必须 enable/disable：quickshell 的 ipc CLI 把 "show" 当自己
        // 的关键字（ipc show = 列 verb），`ipc call <t> show` 只打印列表
        // 不派发——旧实现发 show 的那一半永远到不了 shell（开关"开不
        // 了"的真根因之一）
        callShell(QStringLiteral("stage-sidebar"),
                  {on ? QStringLiteral("enable") : QStringLiteral("disable")},
                  QStringLiteral("台前侧栏开关请求失败"), RequestKind::StageSidebar);
    }

    QVariantMap stageConfigFromReply(const QString &payload) {
        // 空应答 = void IPC 复用本 Kind（stage-sidebar enable/disable）或
        // 传输失败——不是"参数被清空"。回 last-good，别把整页滑杆打成
        // 默认值
        if (payload.isEmpty())
            return m_lastStageConfig;
        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(
            payload.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            setLastError(QStringLiteral("台前调度参数返回无效"));
            return m_lastStageConfig;
        }
        const QJsonObject object = document.object();
        // set 失败应答 {ok:false,error:...} 不带参数：报错并保持 last-good
        if (object.value(QStringLiteral("ok")).toBool(false) == false
                && object.contains(QStringLiteral("error"))
                && !object.contains(QStringLiteral("revision"))) {
            setLastError(object.value(QStringLiteral("error")).toString(
                QStringLiteral("台前调度参数写入失败")));
            return m_lastStageConfig;
        }
        setLastError({});
        QVariantMap out;
        for (auto it = object.begin(); it != object.end(); ++it)
            out.insert(it.key(), it.value().toVariant());
        m_lastStageConfig = out;
        return out;
    }

    // 内存状态：/proc/meminfo + 宿主 zram mm_stat（bytes: orig compr ...）
    Q_INVOKABLE void fgSchedMemStatus() {
        QVariantMap out;
        QFile f(QStringLiteral("/proc/meminfo"));
        if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const auto lines = QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'));
            for (const QString &line : lines) {
                const int colon = line.indexOf(QLatin1Char(':'));
                if (colon <= 0)
                    continue;
                const QString key = line.left(colon);
                const qint64 kb = line.mid(colon + 1)
                                      .split(QLatin1Char(' '), Qt::SkipEmptyParts)
                                      .value(0).toLongLong();
                if (key == QLatin1String("MemTotal"))
                    out.insert(QStringLiteral("memTotalKb"), kb);
                else if (key == QLatin1String("MemAvailable"))
                    out.insert(QStringLiteral("memAvailableKb"), kb);
                else if (key == QLatin1String("SwapTotal"))
                    out.insert(QStringLiteral("swapTotalKb"), kb);
                else if (key == QLatin1String("SwapFree"))
                    out.insert(QStringLiteral("swapFreeKb"), kb);
            }
        }
        QFile z(QStringLiteral("/sys/block/zram0/mm_stat"));
        if (z.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const auto fields = QString::fromUtf8(z.readAll())
                                    .split(QLatin1Char(' '), Qt::SkipEmptyParts);
            if (fields.size() >= 3) {
                out.insert(QStringLiteral("zramOrigKb"),
                           fields.value(0).toLongLong() / 1024);
                out.insert(QStringLiteral("zramComprKb"),
                           fields.value(1).toLongLong() / 1024);
            }
        }
        emit fgSchedMemStatusChanged(out);
    }

    Q_INVOKABLE void fgSchedAddFull(const QString &klass) {
        const QString trimmed = klass.trimmed();
        if (trimmed.isEmpty())
            return;
        if (!writeFgSchedConfig([&](QJsonObject &obj) {
                auto arr = obj.value(QStringLiteral("never_demote_apps")).toArray();
                for (const auto &v : arr) {
                    if (v.toString() == trimmed)
                        return;
                }
                arr.append(trimmed);
                obj.insert(QStringLiteral("never_demote_apps"), arr);
            }))
            return;
        fgSchedSnapshot();
    }

    Q_INVOKABLE void fgSchedRemoveFull(const QString &klass) {
        if (!writeFgSchedConfig([&](QJsonObject &obj) {
                auto arr = obj.value(QStringLiteral("never_demote_apps")).toArray();
                QJsonArray kept;
                for (const auto &v : arr) {
                    if (v.toString() != klass)
                        kept.append(v);
                }
                obj.insert(QStringLiteral("never_demote_apps"), kept);
            }))
            return;
        fgSchedSnapshot();
    }

    // One appearance request feeds both products the debug page needs: the
    // spec table is local (kwinrc + the cached shell snapshot), while the
    // preset style label names which preset that snapshot belongs to, so it
    // is only meaningful once the snapshot reply arrives. Both are delivered
    // together on glassDebugSnapshotChanged.
    Q_INVOKABLE void glassDebugSnapshot() {
        callShell(QStringLiteral("appearance-settings"),
                  {QStringLiteral("snapshot")},
                  QStringLiteral("外观设置请求失败"), RequestKind::GlassDebug);
    }

    // Fire-and-forget: the reply (a full snapshot for preset-backed keys)
    // lands on glassDebugSnapshotChanged, which re-reads the stored values
    // through the shell's own clamping, so the page never needed the return
    // value it used to wait on.
    Q_INVOKABLE void updateGlassDebugValue(const QString &key, const QVariant &value) {
        const QVariantMap match = glassDebugSpec(key);
        if (match.isEmpty()) {
            setLastError(QStringLiteral("未知的 KWin 参数：%1").arg(key));
            emit glassDebugSnapshotChanged(glassDebugSpecs(), glassPresetStyle());
            return;
        }
        QVariant stored = value;
        // A design-value row has no writable home: the shell re-derives it on
        // every appearance sync. Refuse the write rather than let the value
        // silently revert, and say why so the failure is not a mystery.
        if (match.value(QStringLiteral("readOnly")).toBool()) {
            setLastError(QStringLiteral("该参数由外观设计值决定，无法在此修改"));
            emit glassDebugSnapshotChanged(glassDebugSpecs(), glassPresetStyle());
            return;
        }

        const QString type = match.value(QStringLiteral("type")).toString();        if (type == QStringLiteral("bool")) stored = value.toBool();
        else if (type != QStringLiteral("string")) {
            const double number = qBound(match.value(QStringLiteral("min")).toDouble(),
                value.toDouble(), match.value(QStringLiteral("max")).toDouble());
            stored = type == QStringLiteral("int") ? QVariant(qRound(number)) : QVariant(number);
        }
        // A preset-backed key belongs to the shell: writing kwinrc directly
        // would be undone by the next appearance sync. Hand it the value in
        // preset units and let it persist the preset and reconfigure the
        // effect; the reply is a full snapshot, so a rejected write (bad name,
        // shell down) reports why.
        if (const PresetDebugKey *preset = presetDebugKey(key)) {
            callShell(QStringLiteral("appearance-settings"),
                      {QStringLiteral("updateGlassPresetParameter"),
                       QString::fromLatin1(preset->parameter),
                       QString::number(stored.toDouble() / preset->toKwinrc, 'f', 3)},
                      QStringLiteral("外观设置请求失败"), RequestKind::GlassDebug);
            return;
        }
        QSettings config(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
            + QStringLiteral("/kwinrc"), QSettings::IniFormat);
        config.beginGroup(QStringLiteral("Effect-blurplus"));
        config.setValue(key, stored); config.endGroup(); config.sync();
        QDBusInterface effects(QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
            QStringLiteral("org.kde.kwin.Effects"));
        if (effects.isValid())
            effects.asyncCall(QStringLiteral("reconfigureEffect"), QStringLiteral("glass"));
        if (config.status() != QSettings::NoError) {
            setLastError(QStringLiteral("写入 KWin 配置失败"));
            emit glassDebugSnapshotChanged(glassDebugSpecs(), glassPresetStyle());
            return;
        }
        glassDebugSnapshot();
    }

    Q_INVOKABLE void updateGlobalIconMode(const QString &mode) {
        callAppearance({QStringLiteral("updateGlobalIconMode"), mode});
    }

    Q_INVOKABLE void updateGlobalIconOpacity(double opacity) {
        callAppearance({
            QStringLiteral("updateGlobalIconOpacity"),
            QString::number(opacity, 'f', 3)});
    }

    Q_INVOKABLE void updateGlobalIconTintColor(const QString &color) {
        callAppearance({QStringLiteral("updateGlobalIconTintColor"), color});
    }

    Q_INVOKABLE void updateShellStyle(const QString &style) {
        callAppearance({QStringLiteral("updateShellStyle"), style});
    }

    Q_INVOKABLE void updateMaterialColorScheme(const QString &scheme) {
        callAppearance({QStringLiteral("updateMaterialColorScheme"), scheme});
    }

    Q_INVOKABLE void updateBarIntegratedWithDock(bool enabled) {
        callAppearance({
            QStringLiteral("updateBarIntegratedWithDock"),
            enabled ? QStringLiteral("true") : QStringLiteral("false")});
    }

    Q_INVOKABLE void updateGlassFollowsAppearanceMode(bool enabled) {
        callAppearance({
            QStringLiteral("updateGlassFollowsAppearanceMode"),
            enabled ? QStringLiteral("true") : QStringLiteral("false")});
    }

    Q_INVOKABLE void updateSpatialWallpaperEnabled(bool enabled) {
        callAppearance({
            QStringLiteral("updateSpatialWallpaperEnabled"),
            enabled ? QStringLiteral("true") : QStringLiteral("false")});
    }

    Q_INVOKABLE void updateBarVisibilityMode(const QString &mode) {
        callAppearance({QStringLiteral("updateBarVisibilityMode"), mode});
    }

    Q_INVOKABLE void updateBarLayoutMode(const QString &mode) {
        callAppearance({QStringLiteral("updateBarLayoutMode"), mode});
    }

    Q_INVOKABLE void updateDockWindowAnimationStyle(const QString &style) {
        callAppearance({QStringLiteral("updateDockWindowAnimationStyle"), style});
    }

    Q_INVOKABLE void resetAppearanceStrengths() {
        callAppearance({QStringLiteral("resetStrengths")});
    }

    Q_INVOKABLE void launcherSnapshot() {
        callLauncher({QStringLiteral("snapshot")});
    }

    Q_INVOKABLE void shortcutsSnapshot() {
        callShortcuts({QStringLiteral("snapshot")});
    }

    Q_INVOKABLE void updateShortcut(const QString &id, const QString &combo) {
        callShortcuts({QStringLiteral("updateShortcut"), id, combo});
    }

    Q_INVOKABLE void resetShortcut(const QString &id) {
        callShortcuts({QStringLiteral("resetShortcut"), id});
    }

    Q_INVOKABLE void updateLauncherDisplayMode(const QString &mode) {
        callLauncher({QStringLiteral("updateDisplayMode"), mode});
    }

    Q_INVOKABLE void updateLauncherProfileIconSize(const QString &mode,
                                                    const QString &size) {
        callLauncher({
            QStringLiteral("updateProfileIconSize"), mode, size});
    }

    Q_INVOKABLE void updateLauncherProfileDensity(const QString &mode,
                                                    const QString &density) {
        callLauncher({
            QStringLiteral("updateProfileDensity"), mode, density});
    }

    Q_INVOKABLE void updateLauncherProfileFontWeight(const QString &mode,
                                                      const QString &weight) {
        callLauncher({
            QStringLiteral("updateProfileFontWeight"), mode, weight});
    }

    Q_INVOKABLE void resetLauncherLayoutProfile(const QString &mode) {
        callLauncher({QStringLiteral("resetProfile"), mode});
    }

    Q_INVOKABLE void applySystemAppearance(bool dark) {
        callShell(QStringLiteral("appearance-settings"),
                  {QStringLiteral("applySystemAppearance"),
                   dark ? QStringLiteral("true") : QStringLiteral("false")},
                  QStringLiteral("外观设置请求失败"),
                  RequestKind::ApplySystemAppearance);
    }

    // Only the request is issued here; the reply handler folds in the D-Bus
    // and /proc probes (off the UI thread) before emitting the snapshot.
    Q_INVOKABLE void integrationSnapshot() {
        if (m_integrationPending)
            return;
        m_integrationPending = true;
        callShell(QStringLiteral("integration-status"), {QStringLiteral("snapshot")},
                  QStringLiteral("接入状态请求失败"), RequestKind::Integration);
    }

signals:
    void wallpaperColorPicked(const QString &color);
    void wallpaperColorPickFailed(const QString &message);
    void lastErrorChanged();
    void sessionChanged();
    void entryChanged();
    void bannerDismissedChanged();
    void dockSnapshotChanged(const QVariantMap &snapshot);
    void dockBuiltinVisibilityChanged(const QVariantMap &snapshot);
    void wallpaperSnapshotChanged(const QVariantMap &snapshot);
    void wallpaperModelsChecked(bool depthReady, bool foregroundReady);
    void dockNotificationBadgeVisibilityChanged(const QVariantMap &snapshot);
    void dockRevealIndicatorVisibilityChanged(const QVariantMap &snapshot);
    void appearanceSnapshotChanged(const QVariantMap &snapshot);
    void launcherSnapshotChanged(const QVariantMap &snapshot);
    void shortcutsSnapshotChanged(const QVariantMap &snapshot);
    void glassDebugSnapshotChanged(const QVariantList &controls,
                                   const QString &presetStyle);
    void integrationSnapshotChanged(const QVariantMap &snapshot);
    void systemAppearanceApplied(bool accepted);
    // 后台缩略图生成完毕;页面收到后重新求值瓦片缩略图绑定,下次直接命中缓存。
    void wallpaperThumbnailChanged();
    void fgSchedSnapshotChanged(const QVariantMap &snapshot);
    void fgSchedRunningAppsChanged(const QVariantList &apps);
    void fgSchedMemStatusChanged(const QVariantMap &status);
    void stageConfigChanged(const QVariantMap &snapshot);

private:
    // What the requesting page wants back once the IPC reply lands: every
    // request maps to exactly one signal.
    enum class RequestKind {
        Dock,
        DockBuiltinVisibility,
        Wallpaper,
        DockNotificationBadgeVisibility,
        DockRevealIndicatorVisibility,
        Appearance,
        Launcher,
        Shortcuts,
        Integration,
        GlassDebug,
        ApplySystemAppearance,
        FgSchedApps,
        StageConfig,
        StageSidebar,
    };

    QVariantMap snapshotFromReply(const QString &payload) {
        if (payload.isEmpty())
            return {};

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            setLastError(QStringLiteral("桌面环境返回了无效的 Dock 配置"));
            return {};
        }

        const QJsonObject object = document.object();
        if (!object.contains(QStringLiteral("baseHeight"))
                || !object.contains(QStringLiteral("windowGrouping"))) {
            setLastError(QStringLiteral("桌面环境返回的 Dock 配置不完整"));
            return {};
        }

        setLastError({});
        return {
            {QStringLiteral("baseHeight"), object.value(QStringLiteral("baseHeight")).toDouble()},
            {QStringLiteral("position"), object.value(QStringLiteral("position")).toString()},
            // contentStyle/dockStyle are read straight back by the dock page's
            // applyState; without them the two pickers snap back to index 0 on
            // every snapshot refresh.
            {QStringLiteral("contentStyle"), object.value(QStringLiteral("contentStyle")).toString()},
            {QStringLiteral("dockStyle"), object.value(QStringLiteral("dockStyle")).toString()},
            {QStringLiteral("iconMode"), object.value(QStringLiteral("iconMode")).toString()},
            {QStringLiteral("iconOpacity"), object.value(QStringLiteral("iconOpacity")).toDouble()},
            {QStringLiteral("iconTintColor"), object.value(QStringLiteral("iconTintColor")).toString()},
            {QStringLiteral("visibilityMode"), object.value(QStringLiteral("visibilityMode")).toString()},
            {QStringLiteral("windowGrouping"), object.value(QStringLiteral("windowGrouping")).toString()},
            {QStringLiteral("showLauncher"), object.value(QStringLiteral("showLauncher")).toBool(true)},
            {QStringLiteral("showTrash"), object.value(QStringLiteral("showTrash")).toBool(true)},
            {QStringLiteral("showNotificationBadges"), object.value(QStringLiteral("showNotificationBadges")).toBool(true)},
            {QStringLiteral("showRevealIndicator"), object.value(QStringLiteral("showRevealIndicator")).toBool(true)},
        };
    }

    QVariantMap wallpaperSnapshotFromReply(const QString &payload) {
        if (payload.isEmpty())
            return {};
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
            setLastError(QStringLiteral("壁纸 IPC 返回内容无法解析（%1）：%2")
                .arg(parseError.errorString(), detail.isEmpty()
                    ? QStringLiteral("空响应") : detail));
            return {};
        }
        const QJsonObject object = document.object();
        if (!object.contains(QStringLiteral("fitMode"))
                || !object.contains(QStringLiteral("transition"))) {
            setLastError(QStringLiteral("桌面环境返回的壁纸配置不完整"));
            return {};
        }
        setLastError({});
        return {
            {QStringLiteral("previewImage"), object.value(QStringLiteral("previewImage")).toString()},
            {QStringLiteral("previewMode"), object.value(QStringLiteral("previewMode")).toString()},
            {QStringLiteral("previewSelection"), object.value(QStringLiteral("previewSelection")).toString()},
            {QStringLiteral("previewCatalog"), object.value(QStringLiteral("previewCatalog")).toString()},
            {QStringLiteral("previewColors"), object.value(QStringLiteral("previewColors")).toString()},
            {QStringLiteral("transitionOptions"), object.value(QStringLiteral("transitionOptions")).toString()},
            {QStringLiteral("slideshowImages"), object.value(QStringLiteral("slideshowImages")).toString()},
            {QStringLiteral("previewInterval"), object.value(QStringLiteral("previewInterval")).toInt()},
            {QStringLiteral("previewActive"), object.value(QStringLiteral("previewActive")).toBool()},
            {QStringLiteral("previewPending"), object.value(QStringLiteral("previewPending")).toBool()},
            {QStringLiteral("previewError"), object.value(QStringLiteral("previewError")).toString()},
            {QStringLiteral("previewAvailable"), object.value(QStringLiteral("previewAvailable")).toBool()},
            {QStringLiteral("image"), object.value(QStringLiteral("image")).toString()},
            {QStringLiteral("wallpaperMode"), object.value(QStringLiteral("wallpaperMode")).toString()},
            {QStringLiteral("themeId"), object.value(QStringLiteral("themeId")).toString()},
            {QStringLiteral("themeEconomical"), object.value(QStringLiteral("themeEconomical")).toBool()},
            {QStringLiteral("themeAnimated"), object.value(QStringLiteral("themeAnimated")).toBool()},
            {QStringLiteral("themeSpeed"), object.value(QStringLiteral("themeSpeed")).toDouble(0.5)},
            {QStringLiteral("themeParticleCount"), object.value(QStringLiteral("themeParticleCount")).toInt(80)},
            {QStringLiteral("fitMode"), object.value(QStringLiteral("fitMode")).toString()},
            {QStringLiteral("transition"), object.value(QStringLiteral("transition")).toString()},
            {QStringLiteral("library"), object.value(QStringLiteral("library")).toString()},
            {QStringLiteral("slideshowEnabled"), object.value(QStringLiteral("slideshowEnabled")).toBool()},
            {QStringLiteral("slideshowIntervalMinutes"), object.value(QStringLiteral("slideshowIntervalMinutes")).toInt()},
            {QStringLiteral("slideshowFolder"), object.value(QStringLiteral("slideshowFolder")).toString()},
            {QStringLiteral("takeoverEnabled"), object.value(QStringLiteral("takeoverEnabled")).toBool()},
            {QStringLiteral("takeoverPending"), object.value(QStringLiteral("takeoverPending")).toBool()},
            {QStringLiteral("takeoverError"), object.value(QStringLiteral("takeoverError")).toString()},
            {QStringLiteral("takeoverAvailable"), object.value(QStringLiteral("takeoverAvailable")).toBool()},
            {QStringLiteral("spatialResources"), object.value(QStringLiteral("spatialResources")).toObject().toVariantMap()},
            {QStringLiteral("spatialEnabled"), object.value(QStringLiteral("spatialEnabled")).toBool()},
            {QStringLiteral("spatialReady"), object.value(QStringLiteral("spatialReady")).toBool()},
            {QStringLiteral("spatialPrepared"), object.value(QStringLiteral("spatialPrepared")).toBool()},
            {QStringLiteral("spatialBusy"), object.value(QStringLiteral("spatialBusy")).toBool()},
            {QStringLiteral("spatialPreparing"), object.value(QStringLiteral("spatialPreparing")).toBool()},
            {QStringLiteral("spatialError"), object.value(QStringLiteral("spatialError")).toString()},
        };
    }

    QVariantMap appearanceSnapshotFromReply(const QString &payload) {
        if (payload.isEmpty())
            return {};

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            setLastError(QStringLiteral("桌面环境返回了无效的外观配置"));
            return {};
        }

        const QJsonObject object = document.object();
        if ((!object.contains(QStringLiteral("globalBlurStrength"))
                    && !object.contains(QStringLiteral("dockBlurStrength"))
                    && !object.contains(QStringLiteral("blurStrength")))
                || (!object.contains(QStringLiteral("globalLiquidStrength"))
                    && !object.contains(QStringLiteral("dockLiquidStrength"))
                    && !object.contains(QStringLiteral("liquidStrength")))
                || !object.contains(QStringLiteral("shellStyle"))
                || !object.contains(QStringLiteral("barIntegratedWithDock"))
                || !object.contains(QStringLiteral("dockWindowAnimationStyle"))) {
            setLastError(QStringLiteral("桌面环境返回的外观配置不完整"));
            return {};
        }

        const double globalBlur = object.contains(QStringLiteral("globalBlurStrength"))
            ? object.value(QStringLiteral("globalBlurStrength")).toDouble()
            : (object.contains(QStringLiteral("dockBlurStrength"))
                ? object.value(QStringLiteral("dockBlurStrength")).toDouble()
                : object.value(QStringLiteral("blurStrength")).toDouble());
        const double globalLiquid = object.contains(QStringLiteral("globalLiquidStrength"))
            ? object.value(QStringLiteral("globalLiquidStrength")).toDouble()
            : (object.contains(QStringLiteral("dockLiquidStrength"))
                ? object.value(QStringLiteral("dockLiquidStrength")).toDouble()
                : object.value(QStringLiteral("liquidStrength")).toDouble());

        const QString barVisibility = object.value(QStringLiteral("barVisibilityMode")).toString(QStringLiteral("always"));

        setLastError({});
        // Also the source glassDebugSpecs() reads the active preset from: this
        // object carries every preset field, while the map below hand-picks the
        // ones the appearance pages consume.
        m_appearanceSnapshot = object;
        return {
            {QStringLiteral("globalBlurStrength"), globalBlur},
            {QStringLiteral("globalLiquidStrength"), globalLiquid},
            {QStringLiteral("glassStyle"),
                object.value(QStringLiteral("glassStyle")).toString(QStringLiteral("liquid"))},
            {QStringLiteral("activePresetRefraction"),
                object.value(QStringLiteral("activePresetRefraction")).toDouble(1.0)},
            {QStringLiteral("activePresetSoftness"),
                object.value(QStringLiteral("activePresetSoftness")).toDouble()},
            {QStringLiteral("activePresetReflection"),
                object.value(QStringLiteral("activePresetReflection")).toDouble()},
            {QStringLiteral("effectiveDockBlur"), globalBlur},
            {QStringLiteral("effectiveDockLiquid"), globalLiquid},
            {QStringLiteral("effectiveBarBlur"), globalBlur},
            {QStringLiteral("effectiveBarLiquid"), globalLiquid},
            {QStringLiteral("effectiveLauncherBlur"), globalBlur},
            {QStringLiteral("effectiveLauncherLiquid"), globalLiquid},
            {QStringLiteral("blurStrength"), globalBlur},
            {QStringLiteral("liquidStrength"), globalLiquid},
            {QStringLiteral("iconMode"), object.value(QStringLiteral("iconMode")).toString(QStringLiteral("color"))},
            {QStringLiteral("iconOpacity"), object.value(QStringLiteral("iconOpacity")).toDouble(0.5)},
            {QStringLiteral("iconTintColor"), object.value(QStringLiteral("iconTintColor")).toString(QStringLiteral("#a855f7"))},
            {QStringLiteral("shellStyle"), object.value(QStringLiteral("shellStyle")).toString()},
            {QStringLiteral("widgetStyle"), object.value(QStringLiteral("widgetStyle")).toString(QStringLiteral("color"))},
            {QStringLiteral("materialColorScheme"),
                object.value(QStringLiteral("materialColorScheme")).toString(QStringLiteral("monet"))},
            {QStringLiteral("materialAccentName"),
                object.value(QStringLiteral("materialAccentName")).toString()},
            // Swatch previews for the colour-source picker, as a JSON string.
            // The QML side parses it; passing the nested structure through
            // QVariantList/QVariantMap instead left the picker empty.
            {QStringLiteral("materialColorSwatches"),
                object.value(QStringLiteral("materialColorSwatches")).toString()},
            {QStringLiteral("barIntegratedWithDock"),
                object.value(QStringLiteral("barIntegratedWithDock")).toBool()},
            {QStringLiteral("glassFollowsAppearanceMode"),
                object.value(QStringLiteral("glassFollowsAppearanceMode")).toBool(true)},
            {QStringLiteral("spatialWallpaperEnabled"),
                object.value(QStringLiteral("spatialWallpaperEnabled")).toBool(false)},
            {QStringLiteral("barVisibilityMode"),
                barVisibility.isEmpty() ? QStringLiteral("always") : barVisibility},
            {QStringLiteral("barLayoutMode"),
                object.value(QStringLiteral("barLayoutMode")).toString(QStringLiteral("transparent"))},
            {QStringLiteral("dockWindowAnimationStyle"),
                object.value(QStringLiteral("dockWindowAnimationStyle")).toString()},
            {QStringLiteral("tokenVersion"), object.value(QStringLiteral("tokenVersion")).toInt()},
        };
    }

    QVariantMap launcherSnapshotFromReply(const QString &payload) {
        if (payload.isEmpty())
            return {};

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            setLastError(QStringLiteral("桌面环境返回了无效的启动台配置"));
            return {};
        }

        const QJsonObject object = document.object();
        if (!object.contains(QStringLiteral("displayMode"))) {
            setLastError(QStringLiteral("桌面环境返回的启动台配置不完整"));
            return {};
        }

        setLastError({});
        return {
            {QStringLiteral("displayMode"), object.value(QStringLiteral("displayMode")).toString()},
            {QStringLiteral("layoutProfiles"),
                object.value(QStringLiteral("layoutProfiles")).toObject().toVariantMap()},
        };
    }

    QVariantMap integrationSnapshotFromReply(const QString &payload) {
        if (payload.isEmpty())
            return {{QStringLiteral("shellReady"), false}};

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            setLastError(QStringLiteral("桌面环境返回了无效的接入状态"));
            return {{QStringLiteral("shellReady"), false}};
        }
        setLastError({});
        return document.object().toVariantMap();
    }

    QVariantMap shortcutsSnapshotFromReply(const QString &payload) {
        if (payload.isEmpty())
            return {};

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            setLastError(QStringLiteral("桌面环境返回了无效的快捷键配置"));
            return {};
        }

        const QJsonObject object = document.object();
        if (!object.contains(QStringLiteral("shortcuts"))) {
            setLastError(QStringLiteral("桌面环境返回的快捷键配置不完整"));
            return {};
        }

        QVariantList shortcuts;
        for (const QJsonValue &value : object.value(QStringLiteral("shortcuts")).toArray()) {
            const QJsonObject item = value.toObject();
            shortcuts.append(QVariantMap{
                {QStringLiteral("id"), item.value(QStringLiteral("id")).toString()},
                {QStringLiteral("description"), item.value(QStringLiteral("description")).toString()},
                {QStringLiteral("defaultCombo"), item.value(QStringLiteral("defaultCombo")).toString()},
                {QStringLiteral("combo"), item.value(QStringLiteral("combo")).toString()},
                {QStringLiteral("custom"), item.value(QStringLiteral("custom")).toBool()},
            });
        }

        // The Shell validates rebinding requests and reports rejections
        // (unknown id, malformed combo, duplicate binding) inline instead of
        // failing the IPC call, so surface it the same way as transport errors.
        const QString error = object.value(QStringLiteral("error")).toString();
        setLastError(error);
        return {
            {QStringLiteral("shortcuts"), shortcuts},
            {QStringLiteral("error"), error},
        };
    }

    // The 材质 rows' spec table, read from kwinrc with preset values overlaid
    // from the last appearance snapshot. Local file + cached state only, so
    // it is safe to build on the UI thread when the IPC reply lands.
    QVariantList glassDebugSpecs() const {
        const QString path = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
            + QStringLiteral("/kwinrc");
        QSettings config(path, QSettings::IniFormat);
        config.beginGroup(QStringLiteral("Effect-blurplus"));
        QVariantList result;
        const auto add = [&](const char *key, const char *label, const char *section,
                             const char *type, double minimum, double maximum,
                             double step, const QVariant &fallback) {
            // Preset-backed rows report the preset's own value, converted into
            // kwinrc units so the ranges below stay meaningful, and are marked so
            // updateGlassDebugValue() knows to write the preset rather than kwinrc.
            bool presetBacked = false;
            const bool readOnly = isReadOnlyDebugKey(QString::fromLatin1(key));
            QVariant value = config.value(QString::fromLatin1(key), fallback);
            if (const PresetDebugKey *preset = presetDebugKey(QString::fromLatin1(key))) {
                const QJsonValue stored = m_appearanceSnapshot.value(
                    QStringLiteral("activePreset") + QString::fromLatin1(preset->parameter));
                if (stored.isDouble()) {
                    presetBacked = true;
                    value = stored.toDouble() * preset->toKwinrc;
                }
            }
            result.append(QVariantMap{{QStringLiteral("key"), QString::fromLatin1(key)},
                {QStringLiteral("label"), QString::fromUtf8(label)},
                {QStringLiteral("section"), QString::fromUtf8(section)},
                {QStringLiteral("type"), QString::fromLatin1(type)},
                {QStringLiteral("min"), minimum}, {QStringLiteral("max"), maximum},
                {QStringLiteral("step"), step},
                {QStringLiteral("presetBacked"), presetBacked},
                {QStringLiteral("readOnly"), readOnly},
                {QStringLiteral("value"), value}});
        };
        add("BlurFinetune", "模糊精调", "模糊", "int", 0, 10, 1, 3);
        add("NoiseStrength", "内容噪点", "模糊", "int", 0, 100, 1, 5);
        add("DecorationNoiseStrength", "窗口装饰噪点", "模糊", "int", 0, 100, 1, 5);
        add("DockNoiseStrength", "Dock 噪点", "模糊", "int", 0, 100, 1, 5);
        add("BlurSaturationCompensation", "模糊饱和度补偿", "模糊", "bool", 0, 1, 1, true);
        add("Brightness", "亮度", "色彩", "real", 0, 2, .01, 1.0);
        add("Saturation", "饱和度", "色彩", "real", 0, 3, .01, 1.0);
        add("Contrast", "对比度", "色彩", "real", 0, 2, .01, 1.0);
        add("OklabSaturation", "使用 OKLab 饱和度", "色彩", "bool", 0, 1, 1, false);
        add("RefractionStrength", "折射强度", "材质", "real", 0, 20, .1, 0.0);
        add("RefractionEdgeSize", "折射边缘范围", "材质", "real", 0, 50, .1, 20.0);
        add("RefractionNormalPow", "折射法线曲线", "材质", "real", .1, 10, .1, 2.0);
        add("RefractionRGBFringing", "RGB 色散", "材质", "real", 0, 20, .1, 1.0);
        add("RefractionOffsetStrength", "主体折射强度", "材质", "real", 0, 20, .1, 0.0);
        add("MaterialSoftness", "柔和度", "材质", "real", 0, 1, .01, 0.0);
        add("MaterialReflectionStrength", "宽反射强度", "材质", "real", 0, 1, .01, 0.0);
        add("ExcludeDecorations", "窗口装饰不应用染色", "适用范围", "bool", 0, 1, 1, false);
        add("MenuCornerRadius", "菜单圆角", "圆角", "real", 0, 100, 1, 0.0);
        add("DockCornerRadius", "Dock 圆角", "圆角", "real", 0, 100, 1, 0.0);
        add("CornerExponent", "圆角连续度", "圆角", "real", 2, 8, .1, 3.0);
        add("UseDeclaredCornerRadius", "优先使用应用声明圆角", "圆角", "bool", 0, 1, 1, false);
        add("IgnoreContentBlurRegion", "忽略内容模糊区域", "圆角", "bool", 0, 1, 1, false);
        add("DynamicCorners", "动态圆角", "圆角", "bool", 0, 1, 1, false);
        add("DynamicCornersExcludeDocks", "动态圆角排除 Dock", "圆角", "bool", 0, 1, 1, false);
        add("DynamicCornersExcludeTooltips", "动态圆角排除 Tooltip", "圆角", "bool", 0, 1, 1, false);
        add("DynamicCornersExcludeMenus", "动态圆角排除菜单", "圆角", "bool", 0, 1, 1, false);
        add("OnlyQuickshell", "仅处理 Quickshell", "窗口匹配", "bool", 0, 1, 1, true);
        add("WindowClasses", "窗口类列表", "窗口匹配", "string", 0, 0, 0, QStringLiteral("quickshell"));
        add("BlurMatching", "匹配列表内窗口", "窗口匹配", "bool", 0, 1, 1, true);
        add("BlurDecorations", "强制模糊窗口装饰", "窗口匹配", "bool", 0, 1, 1, false);
        add("BlurMenus", "强制模糊菜单", "窗口匹配", "bool", 0, 1, 1, false);
        add("BlurDocks", "强制模糊 Dock", "窗口匹配", "bool", 0, 1, 1, false);
        add("SkipEmptyDockBlurRegions", "跳过空 Dock 模糊区域", "窗口匹配", "bool", 0, 1, 1, true);
        config.endGroup();
        return result;
    }

    // Which style's preset the debug page's 材质 rows edit, as of the last
    // appearance snapshot. Shown next to them so a tuned value is not
    // mistaken for a global one.
    QString glassPresetStyle() const {
        return m_appearanceSnapshot.value(QStringLiteral("glassStyle"))
            .toString(QStringLiteral("liquid"));
    }

    // Spec lookup for updateGlassDebugValue(): the spec table itself does not
    // depend on the shell snapshot, so this reuses whatever the last reply
    // cached instead of paying for another round trip per edit.
    QVariantMap glassDebugSpec(const QString &key) const {
        const QVariantList specs = glassDebugSpecs();
        for (const QVariant &item : specs) {
            const QVariantMap spec = item.toMap();
            if (spec.value(QStringLiteral("key")).toString() == key)
                return spec;
        }
        return {};
    }

    // The notification-owner and KWin probes use blocking D-Bus calls and a
    // /proc read, so they run on a worker thread; the finished snapshot is
    // delivered back on the UI thread through a queued invocation, which is
    // the only place QML-visible state is touched.
    void startIntegrationProbe(const QVariantMap &replyMap) {
        // The bridge may be destroyed while the probe is still running, so the
        // worker only captures a QPointer: no member of this is touched off the
        // UI thread, and the queued delivery is skipped once it is gone.
        const QPointer<SettingsBridge> guard(this);
        QThread *thread = QThread::create([guard, replyMap]() {
            QVariantMap result = replyMap;

            const QDBusConnection sessionBus = QDBusConnection::sessionBus();
            auto *busInterface = sessionBus.interface();
            QString notificationProvider = QStringLiteral("none");
            QString notificationOwner;
            uint notificationPid = 0;
            if (busInterface) {
                const QDBusReply<QString> ownerReply = busInterface->serviceOwner(
                    QStringLiteral("org.freedesktop.Notifications"));
                if (ownerReply.isValid() && !ownerReply.value().isEmpty()) {
                    notificationOwner = ownerReply.value();
                    const QDBusReply<uint> pidReply = busInterface->servicePid(notificationOwner);
                    if (pidReply.isValid())
                        notificationPid = pidReply.value();

                    QFile commandLine(QStringLiteral("/proc/%1/cmdline").arg(notificationPid));
                    QString command;
                    if (commandLine.open(QIODevice::ReadOnly)) {
                        QByteArray raw = commandLine.readAll();
                        raw.replace('\0', ' ');
                        command = QString::fromLocal8Bit(raw).trimmed();
                    }
                    if (command.contains(QStringLiteral("plasmashell"))) {
                        notificationProvider = QStringLiteral("plasma");
                    } else if (command.contains(QStringLiteral("/qs"))
                               || command.contains(QStringLiteral("quickshell"))) {
                        notificationProvider = QStringLiteral("kos");
                    } else {
                        notificationProvider = QStringLiteral("other");
                    }
                    result.insert(QStringLiteral("notificationCommand"), command);
                }
            }
            result.insert(QStringLiteral("notificationProvider"), notificationProvider);
            result.insert(QStringLiteral("notificationOwner"), notificationOwner);
            result.insert(QStringLiteral("notificationPid"), notificationPid);

            QDBusInterface effects(QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
                                   QStringLiteral("org.kde.kwin.Effects"), sessionBus);
            const QStringList loadedEffects = effects.isValid()
                ? effects.property("loadedEffects").toStringList() : QStringList{};
            result.insert(QStringLiteral("kwinAvailable"), effects.isValid());
            result.insert(QStringLiteral("glassLoaded"),
                          loadedEffects.contains(QStringLiteral("glass")));
            result.insert(QStringLiteral("dockAnimationLoaded"),
                          loadedEffects.contains(QStringLiteral("kos_dock_window_animation")));
            result.insert(QStringLiteral("contextMenuInputLoaded"),
                          loadedEffects.contains(QStringLiteral("kos_context_menu_input")));
            result.insert(QStringLiteral("updatedAt"),
                          QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss")));

            if (guard) {
                QMetaObject::invokeMethod(guard.data(), [guard, result]() {
                    if (!guard)
                        return;
                    guard->m_integrationPending = false;
                    emit guard->integrationSnapshotChanged(result);
                }, Qt::QueuedConnection);
            }
        });
        connect(thread, &QThread::finished, thread, [this, thread]() {
            m_probeThreads.removeAll(thread);
            thread->deleteLater();
        });
        m_probeThreads.append(thread);
        thread->start();
    }


    void callDock(const QStringList &arguments) {
        callShell(QStringLiteral("dock-settings"), arguments,
                  QStringLiteral("Dock 设置请求失败"), RequestKind::Dock);
    }

    void callWallpaper(const QStringList &arguments) {
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

    void pumpWallpaperRequests() {
        if (m_wallpaperBusy || m_wallpaperQueue.isEmpty()) return;
        m_wallpaperBusy = true;
        callShell(QStringLiteral("wallpaper-settings"), m_wallpaperQueue.takeFirst(),
                  QStringLiteral("壁纸设置请求失败"), RequestKind::Wallpaper);
    }

    void callAppearance(const QStringList &arguments) {
        callShell(QStringLiteral("appearance-settings"), arguments,
                  QStringLiteral("外观设置请求失败"), RequestKind::Appearance);
    }

    void callLauncher(const QStringList &arguments) {
        callShell(QStringLiteral("applauncher-settings"), arguments,
                  QStringLiteral("启动台设置请求失败"), RequestKind::Launcher);
    }

    void callShortcuts(const QStringList &arguments) {
        callShell(QStringLiteral("shortcuts-settings"), arguments,
                  QStringLiteral("快捷键设置请求失败"), RequestKind::Shortcuts);
    }

    static QString installedShellDirectory() {
        return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
            + QStringLiteral("/quickshell/kos");
    }

    // The session directory equals the installed one only when the Shell was
    // started as `-c kos`. Compared cleaned, because the value arrives from the
    // environment and a trailing slash would otherwise read as a checkout.
    static bool isInstalledShellDirectory(const QString &shellPath) {
        if (shellPath.isEmpty())
            return false;
        return QDir::cleanPath(shellPath) == QDir::cleanPath(installedShellDirectory());
    }

    // Recorded from the candidate that actually answered, so a window opened
    // without KOS_SHELL_DIR (app grid, KRunner) still learns which session it is
    // serving instead of guessing from the fallback order.
    void setSessionShell(const QString &shellPath) {
        if (m_sessionShellDir == shellPath)
            return;
        m_sessionShellDir = shellPath;
        emit sessionChanged();
    }

    // Candidate Shell directories, most specific first. A Settings window is
    // started from two different places and only one of them can pass the
    // environment down: the Shell's own Settings entry goes through the
    // platform daemon, which exports KOS_SHELL_DIR for the session it belongs
    // to, while a .desktop launch (app grid, KRunner, menu) inherits nothing.
    // The list is therefore a preference order, and an ordinary launch (no
    // KOS_SHELL_DIR) has to reach the running session on its first try.
    static QStringList shellDirectories() {
        QStringList directories;
        const QString configured = qEnvironmentVariable("KOS_SHELL_DIR");
        if (!configured.isEmpty())
            directories.append(configured);

        // Then the installed session: an end user only ever runs that one, and
        // it is the session this binary belongs to. Its directory is an
        // absolute path under the config location, so it does not depend on
        // the current working directory or on any inherited environment.
        directories.append(installedShellDirectory());

        // The compile-time source tree is a fallback for `qs -p <dir>`
        // sessions, NOT a first choice: it exists on any machine that built
        // this binary (a Nix store copy, or the checkout itself), so trying it
        // first would aim every ordinary launch at a Shell that is not
        // running. Both spellings of the literal are offered because
        // Quickshell matches instances by the path it was launched with, and
        // only comparably-spelled paths hit: the cleaned form handles the `..`
        // segments (apps/settings/../../shell), the canonical form handles a
        // checkout reached through a symlink (a synced or linked folder).
        const QString declared = QDir::cleanPath(QStringLiteral(SETTINGS_SHELL_DIR));
        const QString canonical = QFileInfo(declared).canonicalFilePath();
        for (const QString &source : {declared, canonical}) {
            if (source.isEmpty() || directories.contains(source))
                continue;
            if (QFileInfo::exists(QDir(source).filePath(QStringLiteral("shell.qml"))))
                directories.append(source);
        }

        directories.removeDuplicates();
        return directories;
    }

    // Quickshell tracks instances by how they identify their config: a Shell
    // launched as `-c kos` is NOT matched by `--path <same dir>`. The installed
    // session runs as `-c kos`, so address it by name; development sessions
    // (`-p <dir>`) take the explicit path.
    static QStringList connectArgsFor(const QString &shellPath) {
        if (shellPath == installedShellDirectory())
            return {QStringLiteral("-c"), QStringLiteral("kos")};
        return {QStringLiteral("--path"), shellPath};
    }

    // Quickshell's `ipc call` exits 0 while printing one of these diagnostics,
    // so a zero exit code on its own cannot be trusted: a wrong instance -- one
    // without the target, or a stale build without the function -- would
    // otherwise answer with an error sentence as if it were the value.
    static bool isIpcDiagnostic(const QString &reply) {
        static const QStringList diagnostics = {
            QStringLiteral("Target not found."),
            QStringLiteral("Function not found."),
            QStringLiteral("Function required to send message."),
        };
        return diagnostics.contains(reply);
    }

    void callShell(const QString &target, const QStringList &arguments,
                   const QString &fallbackError, RequestKind kind) {
        startShellAttempt(target, arguments, fallbackError, kind,
                          shellDirectories(), 0, 0, {});
    }

    // One asynchronous attempt at one candidate. On a diagnostic reply or a
    // transport failure the next attempt/candidate is chained from the
    // process's finished signal, so the UI thread never waits: the preferred
    // candidate gets one retry (the Shell can still be registering IPC
    // targets during the first moments of a development launch); later
    // candidates are fallbacks, where a second attempt buys nothing.
    void startShellAttempt(const QString &target, const QStringList &arguments,
                           const QString &fallbackError, RequestKind kind,
                           const QStringList &shellPaths, int index, int attempt,
                           const QString &failure) {
        const QString shellPath = shellPaths.at(index);
        QStringList command = connectArgsFor(shellPath);
        command << QStringLiteral("ipc") << QStringLiteral("call") << target;
        command.append(arguments);

        auto *process = new QProcess(this);
        // A hung `quickshell ipc call` used to sit inside waitForFinished() on
        // the UI thread; now the timeout is a timer, so the worst case is a
        // killed stale process, not a frozen window.
        auto *watchdog = new QTimer(process);
        watchdog->setSingleShot(true);
        watchdog->setInterval(5000);
        connect(process, &QProcess::started, watchdog, qOverload<>(&QTimer::start));
        connect(watchdog, &QTimer::timeout, process, [process]() {
            process->setProperty("timedOut", true);
            process->kill();
        });
        connect(process, &QProcess::finished, this,
                [this, process, kind, target, arguments, shellPath, fallbackError,
                 shellPaths, index, attempt, failure](int exitCode,
                                                      QProcess::ExitStatus exitStatus) {
            const QString output = QString::fromUtf8(
                process->readAllStandardOutput()).trimmed();
            const bool preferred = index == 0;
            const int maxAttempts = preferred ? 2 : 1;
            // Retry the preferred candidate, fall through to the next one, and
            // only report failure once every candidate has been tried.
            const auto advance = [&](const QString &reason) {
                if (attempt + 1 < maxAttempts) {
                    startShellAttempt(target, arguments, fallbackError, kind,
                                      shellPaths, index, attempt + 1, reason);
                } else if (index + 1 < shellPaths.size()) {
                    startShellAttempt(target, arguments, fallbackError, kind,
                                      shellPaths, index + 1, 0, reason);
                } else {
                    setLastError(QStringLiteral("%1（IPC：%2；Shell：%3）")
                                     .arg(reason, target, shellPath));
                    failKind(kind);
                }
            };
            if (exitStatus == QProcess::NormalExit && exitCode == 0) {
                if (!isIpcDiagnostic(output)) {
                    setSessionShell(QDir::cleanPath(shellPath));
                    handleReply(kind, output);
                } else {
                    // A diagnostic reply means this candidate is not the Shell
                    // serving us, so treat it like a hard failure.
                    advance(fallbackError);
                }
            } else {
                QString reason = QString::fromUtf8(
                    process->readAllStandardError()).trimmed();
                if (process->property("timedOut").toBool())
                    reason = QStringLiteral("桌面环境没有响应（超过 5 秒）");
                else if (reason.isEmpty())
                    reason = fallbackError;
                advance(reason);
            }
            process->deleteLater();
        });
        // FailedToStart never emits finished; crashes do, and are reported
        // there so a dead process is not counted twice.
        connect(process, &QProcess::errorOccurred, this,
                [this, process, kind, target, arguments, shellPath, shellPaths,
                 index, attempt, failure](QProcess::ProcessError error) {
            if (error != QProcess::FailedToStart)
                return;
            const bool preferred = index == 0;
            const int maxAttempts = preferred ? 2 : 1;
            const QString reason = QStringLiteral("无法启动 Quickshell IPC");
            if (attempt + 1 < maxAttempts) {
                startShellAttempt(target, arguments, reason, kind,
                                  shellPaths, index, attempt + 1, reason);
            } else if (index + 1 < shellPaths.size()) {
                startShellAttempt(target, arguments, reason, kind,
                                  shellPaths, index + 1, 0, reason);
            } else {
                setLastError(QStringLiteral("%1（IPC：%2；Shell：%3）")
                                 .arg(reason, target, shellPath));
                failKind(kind);
            }
            process->deleteLater();
        });
        process->start(QStringLiteral("quickshell"), command);
    }

    // Dispatch the reply to the signal the requesting page listens to.
    // 旧 libraryJson 引用的一次性迁移:首次拿到带 library 字段的快照时,把
    // 引用的单图/文件夹内容复制进托管图集(GNOME 模式的起点)。按进程一次;
    // 按内容去重，同名但内容不同的文件也保留。持久化迁移标记，防止下一次
    // 打开设置时把已移除的图片重新从旧引用导入。
    void migrateGalleryFromLibrary(const QString &libraryJson) {
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
        for (const QVariant &entryVar : entries) {
            if (copied >= kMaxMigratedImages)
                break;
            const QVariantMap entry = entryVar.toMap();
            const QString type = entry.value(QStringLiteral("type")).toString();
            QString path = entry.value(QStringLiteral("path")).toString();
            if (path.startsWith(QStringLiteral("file:")))
                path = QUrl(path).toLocalFile();
            if (type != QLatin1String("image") && type != QLatin1String("folder"))
                continue;
            QStringList sources{path};
            if (type == QLatin1String("folder")) {
                sources.clear();
                const QDir folder(path);
                if (!folder.exists())
                    continue;
                for (const QFileInfo &file : folder.entryInfoList(
                         QDir::Files | QDir::Readable, QDir::Name | QDir::IgnoreCase)) {
                    if (copied >= kMaxMigratedImages)
                        break;
                    if (isGalleryImage(file))
                        sources.append(file.absoluteFilePath());
                }
            }
            for (const QString &source : sources) {
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

    void handleReply(RequestKind kind, const QString &payload) {
        switch (kind) {
        case RequestKind::Dock:
            emit dockSnapshotChanged(snapshotFromReply(payload));
            break;
        case RequestKind::DockBuiltinVisibility:
            emit dockBuiltinVisibilityChanged(snapshotFromReply(payload));
            break;
        case RequestKind::Wallpaper: {
            const QVariantMap state = wallpaperSnapshotFromReply(payload);
            m_wallpaperBusy = false;
            migrateGalleryFromLibrary(
                state.value(QStringLiteral("library")).toString());
            // Intermediate replies must not overwrite a newer selection in the UI.
            if (m_wallpaperQueue.isEmpty()) emit wallpaperSnapshotChanged(state);
            pumpWallpaperRequests();
            break;
        }
        case RequestKind::DockNotificationBadgeVisibility:
            emit dockNotificationBadgeVisibilityChanged(snapshotFromReply(payload));
            break;
        case RequestKind::DockRevealIndicatorVisibility:
            emit dockRevealIndicatorVisibilityChanged(snapshotFromReply(payload));
            break;
        case RequestKind::Appearance:
            emit appearanceSnapshotChanged(appearanceSnapshotFromReply(payload));
            break;
        case RequestKind::Launcher:
            emit launcherSnapshotChanged(launcherSnapshotFromReply(payload));
            break;
        case RequestKind::Shortcuts:
            emit shortcutsSnapshotChanged(shortcutsSnapshotFromReply(payload));
            break;
        case RequestKind::Integration:
            startIntegrationProbe(integrationSnapshotFromReply(payload));
            break;
        case RequestKind::GlassDebug:
            appearanceSnapshotFromReply(payload);
            emit glassDebugSnapshotChanged(glassDebugSpecs(), glassPresetStyle());
            break;
        case RequestKind::ApplySystemAppearance: {
            QJsonParseError parseError;
            const QJsonDocument document = QJsonDocument::fromJson(
                payload.toUtf8(), &parseError);
            bool accepted = false;
            if (parseError.error == QJsonParseError::NoError && document.isObject())
                accepted = document.object()
                    .value(QStringLiteral("accepted")).toBool();
            if (!accepted && m_lastError.isEmpty())
                setLastError(QStringLiteral("桌面环境拒绝了主题切换请求"));
            emit systemAppearanceApplied(accepted);
            break;
        }
        case RequestKind::FgSchedApps: {
            QVariantList apps;
            QJsonParseError parseError;
            const QJsonDocument document = QJsonDocument::fromJson(
                payload.toUtf8(), &parseError);
            if (parseError.error == QJsonParseError::NoError && document.isArray()) {
                const auto arr = document.array();
                for (const auto &v : arr) {
                    const auto o = v.toObject();
                    apps.append(QVariantMap{
                        {QStringLiteral("name"),
                         o.value(QStringLiteral("name")).toString()},
                        {QStringLiteral("appId"),
                         o.value(QStringLiteral("appId")).toString()},
                    });
                }
            }
            emit fgSchedRunningAppsChanged(apps);
            break;
        }
        case RequestKind::StageConfig:
            emit stageConfigChanged(stageConfigFromReply(payload));
            break;
        case RequestKind::StageSidebar:
            // 侧栏开关是 void 动词（stage-sidebar enable/disable）：立即
            // 回读 + 延迟补读。⚠️ shell 落盘是 enqueueBashChain 异步链，
            // void 应答返回时 printf 很可能还没执行——只读一次会拿到旧
            // 值（开关延迟到下个 5s tick 才翻转＝"点了没反应"的残余），
            // 1.2s 后补读一次覆盖落盘完成时刻。此前完全没有回读时，快
            // 照停在页面加载时刻，点击发的都是"已是态"的 no-op
            fgSchedSnapshot();
            QTimer::singleShot(1200, this, [this] { fgSchedSnapshot(); });
            break;
        }
    }

    // A transport failure produces no payload, but the page still needs its
    // signal so it can leave the pending state and show lastError.
    void failKind(RequestKind kind) {
        switch (kind) {
        case RequestKind::Dock:
            emit dockSnapshotChanged({});
            break;
        case RequestKind::DockBuiltinVisibility:
            emit dockBuiltinVisibilityChanged({});
            break;
        case RequestKind::Wallpaper:
            m_wallpaperBusy = false;
            emit wallpaperSnapshotChanged({});
            pumpWallpaperRequests();
            break;
        case RequestKind::DockNotificationBadgeVisibility:
            emit dockNotificationBadgeVisibilityChanged({});
            break;
        case RequestKind::DockRevealIndicatorVisibility:
            emit dockRevealIndicatorVisibilityChanged({});
            break;
        case RequestKind::Appearance:
            emit appearanceSnapshotChanged({});
            break;
        case RequestKind::Launcher:
            emit launcherSnapshotChanged({});
            break;
        case RequestKind::Shortcuts:
            emit shortcutsSnapshotChanged({});
            break;
        case RequestKind::Integration:
            startIntegrationProbe(integrationSnapshotFromReply({}));
            break;
        case RequestKind::GlassDebug:
            emit glassDebugSnapshotChanged(glassDebugSpecs(), glassPresetStyle());
            break;
        case RequestKind::ApplySystemAppearance:
            emit systemAppearanceApplied(false);
            break;
        case RequestKind::FgSchedApps:
            emit fgSchedRunningAppsChanged({});
            break;
        case RequestKind::StageConfig:
            // 传输失败同样回 last-good：QML 只需要信号离开 pending 态
            emit stageConfigChanged(stageConfigFromReply({}));
            break;
        case RequestKind::StageSidebar:
            // 失败也回读：快照读的是磁盘真值（调用可能已落地），给出
            // 真实态好过停在陈旧态
            fgSchedSnapshot();
            break;
        }
    }

    void setLastError(const QString &error) {
        if (m_lastError == error)
            return;
        m_lastError = error;
        emit lastErrorChanged();
    }

    bool m_wallpaperBusy = false;
    QList<QStringList> m_wallpaperQueue;
    QString m_lastError;
    // The Shell directory this window is talking to: seeded from KOS_SHELL_DIR,
    // replaced by whichever candidate answers. Empty until one of the two has
    // happened, which is also the state that reads as "not a development
    // session" rather than guessing.
    // 缩略图后台生成的去重:同一 key 只允许一个在途任务,防止首开 200 张
    // 瓦片的解码风暴重复排队。
    QMutex m_thumbnailMutex;
    QSet<QString> m_thumbnailInFlight;
    QSet<QString> m_thumbnailFailed;
    QThreadPool m_thumbnailPool;
    // 旧图集引用 → 托管目录的一次性迁移,每进程只跑一次。
    bool m_galleryMigrated = false;
    QString m_sessionShellDir;
    // Set once, from the entry point main() chose, before the engine loads it.
    bool m_sourceTreeEntry = false;
    // Set from the banner's close control. Survives a QML reload on purpose --
    // see isDevelopmentBannerDismissed().
    bool m_bannerDismissed = false;
    // Last appearance snapshot the shell sent. Kept for glassDebugSpecs(), which
    // reads the active preset out of it, and refreshed on every glass debug
    // snapshot so the style it names is the one being edited right now.
    QJsonObject m_appearanceSnapshot;
    // The integration probe is a worker thread: while one is running the 5s
    // page poll must not pile up another.
    bool m_integrationPending = false;
    bool m_modelInspectionPending = false;

    // Last-good stage config snapshot. Void IPCs routed through this request
    // kind (stage-sidebar enable/disable) and failed set() replies produce no
    // payload — echoing them back would blank the page's sliders down to
    // schema defaults while the shell-side state is untouched.
    QVariantMap m_lastStageConfig;
    // In-flight integration probe threads (see ~SettingsBridge for why they
    // must be joined on destruction).
    QList<QThread *> m_probeThreads;
};

namespace {

// Which QML tree this window runs. A development session must show the checkout
// the Shell in front of the user was started from -- the point of `kosctl dev`
// is to see source edits without reinstalling, and the QML half of Settings is
// the only half that can be iterated on that way (the binary is installed by
// `kosctl install` and is not rebuilt by `dev`). The copy installed beside the
// binary stays the answer for the service session. The compile-time tree is
// last: a binary built in a checkout has no copy next to it, an installed one
// has no checkout to point at.
struct SettingsEntry {
    QString qmlPath;
    // Non-empty only when qmlPath lies in a checkout: the root whose edits are
    // watched while the window is open. Empty means "load once, never reload",
    // which is every case the user is not developing against.
    QString checkoutRoot;
    // Named in the log line, which is the only thing that tells the three trees
    // apart from the outside -- they render identically, so a wrong choice shows
    // up as nothing at all.
    QString source;
};

SettingsEntry chooseSettingsEntry(bool developmentSession, const QString &sessionShellDir)
{
    SettingsEntry entry;
    if (developmentSession && !sessionShellDir.isEmpty()) {
        // `KOS_SHELL_DIR` names the Shell directory, so the checkout is one
        // level up from it and the pages sit in `apps/settings`. Derived from
        // the session rather than from SETTINGS_QML_DIR, so the window runs the
        // same tree as the Shell it is editing even when the two were built from
        // different paths.
        const QString qmlPath = QDir::cleanPath(
            QDir(sessionShellDir).filePath(QStringLiteral("../apps/settings/main.qml")));
        if (QFileInfo::exists(qmlPath)) {
            entry.qmlPath = qmlPath;
            entry.checkoutRoot = QDir::cleanPath(
                QDir(sessionShellDir).filePath(QStringLiteral("..")));
            entry.source = QStringLiteral("session checkout");
            return entry;
        }
    }

    // Cleaned so the logged path is the one a reader can paste into a shell:
    // `~/.local/bin/../share/...` is what the join produces, not what exists.
    const QString installedCopy = QDir::cleanPath(
        QDir(QCoreApplication::applicationDirPath()).filePath(
            QStringLiteral("../share/kos/settings/main.qml")));
    if (QFileInfo::exists(installedCopy)) {
        entry.qmlPath = installedCopy;
        entry.source = QStringLiteral("installed copy");
        return entry;
    }

    entry.qmlPath = QDir::cleanPath(QDir(QStringLiteral(SETTINGS_QML_DIR)).filePath(
        QStringLiteral("main.qml")));
    entry.source = QStringLiteral("build tree");
    return entry;
}

// Rebuilds the window when the checkout it was loaded from changes. Two rules
// keep this from being a way to lose the window: the reload is debounced,
// because one editor save is not one event (a write plus a rename), and the new
// text is compiled before anything is torn down, so a file that does not parse
// reports its errors and leaves the current UI on screen.
class SettingsQmlReloader final : public QObject {
public:
    SettingsQmlReloader(QQmlApplicationEngine *engine, const QUrl &entryPoint,
                        const QString &checkoutRoot, QObject *parent = nullptr)
        : QObject(parent), m_engine(engine), m_entryPoint(entryPoint) {
        // Only a checkout is watched. The installed copy is a destination, not
        // an edit surface: it changes when someone installs, and rebuilding the
        // window under a running user at that moment would be a surprise rather
        // than a feature -- with the shell's own copy the same `kosctl install`
        // is explicitly kept from hot-reloading anything.
        if (checkoutRoot.isEmpty())
            return;

        const QString pages = QFileInfo(entryPoint.toLocalFile()).absolutePath();
        if (!pages.isEmpty())
            m_directories.append(pages);
        // The pages import the shared tree by relative path, so both halves of
        // the window are part of the same edit loop. Only the directory itself
        // is listed here; qmlFiles() walks it.
        const QString shared = QDir(checkoutRoot).filePath(QStringLiteral("shared/qml"));
        if (QFileInfo(shared).isDir())
            m_directories.append(shared);
    }

    void start() {
        if (m_directories.isEmpty())
            return;

        m_debounce.setSingleShot(true);
        m_debounce.setInterval(300);
        connect(&m_debounce, &QTimer::timeout, this, [this] { reload(); });
        connect(&m_watcher, &QFileSystemWatcher::fileChanged, this,
                [this](const QString &) { m_debounce.start(); });
        connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this,
                [this](const QString &) {
                    refreshWatches();
                    m_debounce.start();
                });
        refreshWatches();
    }

private:
    // Both suffixes matter: the pages also import plain .mjs helpers (the
    // Material colour implementation), and those are edited the same way.
    static QStringList qmlFiles(const QString &directory) {
        QStringList files;
        QDirIterator iterator(directory,
                              {QStringLiteral("*.qml"), QStringLiteral("*.mjs")},
                              QDir::Files, QDirIterator::Subdirectories);
        while (iterator.hasNext())
            files.append(iterator.next());
        return files;
    }

    // Watches are per path, not per directory, so they have to be re-listed
    // after every change: an editor that saves by writing a new file over the
    // old one drops the watch on the old inode.
    void refreshWatches() {
        QStringList missingFiles;
        QStringList missingDirectories;
        for (const QString &directory : m_directories) {
            if (!QFileInfo(directory).isDir())
                continue;
            if (!m_watcher.directories().contains(directory))
                missingDirectories.append(directory);
            for (const QString &file : qmlFiles(directory)) {
                if (!m_watcher.files().contains(file))
                    missingFiles.append(file);
            }
        }
        if (!missingDirectories.isEmpty())
            m_watcher.addPaths(missingDirectories);
        if (!missingFiles.isEmpty())
            m_watcher.addPaths(missingFiles);
    }

    // Compiled on a throwaway engine on purpose: the live one caches compiled
    // QML by URL, so asking it about the file it already loaded answers from the
    // cache -- it would pass text that no longer compiles, and the reload that
    // followed would tear the window down. A fresh engine reads the file from
    // disk, which is the whole question here.
    bool compiles() {
        QQmlEngine validator;
        validator.setImportPathList(m_engine->importPathList());
        QQmlComponent component(&validator, m_entryPoint);
        if (!component.isError())
            return true;
        qWarning().noquote()
            << "kos-settings: QML changed but does not compile, keeping the window"
               " as it is:"
            << component.errorString().trimmed();
        return false;
    }

    void reload() {
        if (!compiles())
            return;

        const QList<QObject *> roots = m_engine->rootObjects();
        for (QObject *root : roots)
            delete root;
        m_engine->clearComponentCache();
        m_engine->load(m_entryPoint);
        if (m_engine->rootObjects().isEmpty()) {
            // Only reachable for text that compiles and still fails to build its
            // root object. Say so instead of leaving an empty screen behind: the
            // watcher is still live, so the next change that works brings the
            // window back.
            qWarning().noquote()
                << "kos-settings: reload failed, the window is gone until the next"
                   " change that loads";
            return;
        }
        qInfo().noquote() << "kos-settings: reloaded" << m_entryPoint.toLocalFile();
        refreshWatches();
    }

    QQmlApplicationEngine *m_engine = nullptr;
    QUrl m_entryPoint;
    QStringList m_directories;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
};

} // namespace

int main(int argc, char *argv[]) {
    for (int i = 1; i < argc; ++i) {
        const QByteArray argument(argv[i]);
        if (argument == "--install-window-defaults" || argument == "--restore-window-defaults") {
            QCoreApplication application(argc, argv);
            WindowSettings settings;
            const bool accepted = argument == "--install-window-defaults"
                ? settings.installDefaults() : settings.setTakeover(false);
            if (!accepted) qWarning().noquote() << settings.error();
            return accepted ? 0 : 1;
        }
    }
    QGuiApplication application(argc, argv);
    // Keep this window out of the Shell's KWin rules. This must match the
    // installed desktop entry basename: kos-settings.desktop.
    application.setApplicationName(QStringLiteral("kos-settings"));
    application.setApplicationDisplayName(QStringLiteral(""));
    application.setDesktopFileName(QStringLiteral("kos-settings"));
    application.setOrganizationName(QStringLiteral("Quickshell"));

    SettingsBridge bridge;
    WindowSettings windowSettings;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("settingsBridge"), &bridge);
    engine.rootContext()->setContextProperty(QStringLiteral("windowSettings"), &windowSettings);

    const SettingsEntry entry = chooseSettingsEntry(bridge.isDevelopmentSession(),
                                                    bridge.sessionShellDir());
    // Recorded before the engine loads anything, so the banner and the reloader
    // cannot disagree about which tree the window is running.
    bridge.setSourceTreeEntry(!entry.checkoutRoot.isEmpty());
    if (entry.qmlPath.isEmpty()) {
        qWarning() << "kos-settings: no QML entry point found; looked beside the binary"
                      " and in" << QStringLiteral(SETTINGS_QML_DIR);
        return 1;
    }
    qInfo().noquote() << "kos-settings: loading QML from" << entry.qmlPath
                      << QStringLiteral("(%1%2)").arg(
                             entry.source,
                             entry.checkoutRoot.isEmpty()
                                 ? QString()
                                 : QStringLiteral(", reloads on change"));
    const QUrl entrypoint = QUrl::fromLocalFile(entry.qmlPath);
    engine.load(entrypoint);
    if (engine.rootObjects().isEmpty())
        return 1;
    if (application.arguments().contains(QStringLiteral("--page=windows")))
        engine.rootObjects().constFirst()->setProperty("currentPage", 11);
    if (application.arguments().contains(QStringLiteral("--smoke-test-windows"))) {
        engine.rootObjects().constFirst()->setProperty("currentPage", 11);
        QTimer::singleShot(1000, &application, [&engine, &application]() {
            auto *loader = engine.rootObjects().constFirst()->findChild<QObject *>(
                QStringLiteral("windowPageLoader"));
            if (!loader || loader->property("status").toInt() != 1
                || !engine.rootObjects().constFirst()->findChild<QObject *>(
                    QStringLiteral("windowAppearancePage"))) {
                qWarning() << "Window settings page did not instantiate";
                application.exit(1);
                return;
            }
            application.quit();
        });
    }

    // Inert unless the QML came from a checkout, which is the only case where
    // there is something to watch.
    SettingsQmlReloader reloader(&engine, entrypoint, entry.checkoutRoot);
    reloader.start();

    // 缓存维护:启动时调度一次(线程池内执行,阈值内零开销)。以后新增缓存
    // 目录都从这里追加 schedule 调用。
    CacheMaintenance::schedule(wallpaperThumbCacheDir(),
                               64 * 1024 * 1024, 500);

    // --smoke-test is the build-side check that the settings window loads:
    // run one event loop turn (as ApplicationRunner does for the apps) and
    // exit, so CI can prove main.qml instantiates without a display.
    if (application.arguments().contains(QStringLiteral("--smoke-test")))
        QTimer::singleShot(250, &application, &QCoreApplication::quit);
    return application.exec();
}

#include "main.moc"
