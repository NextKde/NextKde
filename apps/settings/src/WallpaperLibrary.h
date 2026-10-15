#pragma once

#include <QFileInfo>
#include <QHash>
#include <QMutex>
#include <QObject>
#include <QSet>
#include <QStringList>
#include <QThread>
#include <QThreadPool>

// Local resources only: no Shell IPC, QML context or feature snapshot state.
// Thumbnail work is bounded to two workers; folder imports run on one
// dedicated worker. importGalleryImage stays synchronous for single-file
// callers and for the worker itself.
class WallpaperLibrary final : public QObject {
    Q_OBJECT
public:
    explicit WallpaperLibrary(QObject* parent = nullptr);
    ~WallpaperLibrary() override;
    static QString thumbnailCacheDirectory();
    QStringList wallpaperCatalog() const;
    QString wallpaperThumbnail(
        const QString& urlOrPath, int width, int height, int radius, bool generate = true);
    QStringList galleryImages() const;
    QString importGalleryImage(const QString& urlOrPath);
    // Returns -1 when the folder is unreadable (reported synchronously via
    // errorOccurred), otherwise the number of images already in the gallery
    // when this folder was last imported (0 for a fresh import). The copy
    // work itself runs in the background; galleryImportFinished reports the
    // final count and galleryImportProgress ticks per accepted image.
    int importGalleryFolder(const QString& urlOrPath);
    bool deleteGalleryImage(const QString& urlOrPath);
    void migrateGalleryFromLibrary(const QString& libraryJson);
signals:
    void errorOccurred(const QString& message);
    void thumbnailReady();
    void galleryImportProgress(int imported);
    void galleryImportFinished(int imported);

private:
    struct GalleryFingerprint {
        qint64 size = 0;
        qint64 mtime = 0;
        QByteArray md5;
    };
    static bool isGalleryImage(const QFileInfo& info);
    QByteArray galleryFileMd5(const QString& path);
    static QByteArray transcodeJpegBaseline(const QString& path);
    QHash<QString, GalleryFingerprint> m_galleryFingerprints;
    QMutex m_thumbnailMutex;
    QSet<QString> m_thumbnailInFlight;
    QSet<QString> m_thumbnailFailed;
    QThreadPool m_thumbnailPool;
    bool m_galleryMigrated = false;
    // One worker at a time keeps m_galleryFingerprints single-threaded without
    // a lock; a second request while one runs is answered immediately with the
    // running import's folder rather than queued.
    QThread* m_galleryImportThread = nullptr;
    QString m_galleryImportFolder;
};
