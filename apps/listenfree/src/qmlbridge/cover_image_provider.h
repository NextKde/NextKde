#pragma once
#include "artwork_texture_factory.h"
#include <QQuickImageProvider>
#include <QUrl>
#include <QJsonArray>
#include <QJsonDocument>
#include <QBuffer>
#include <QImageReader>
#include <QHash>
#include <QReadWriteLock>
#include <QStringList>
#include <memory>
#include <qmmp/metadatamanager.h>
#include <taglib/fileref.h>
#include <taglib/flacfile.h>
#include <taglib/flacpicture.h>
#include <taglib/mpegfile.h>
#include <taglib/id3v2tag.h>
#include <taglib/attachedpictureframe.h>
#include <taglib/tvariant.h>

// TagLib handles embedded MP3/FLAC pictures; Qmmp locates adjacent covers.
// Qt Quick owns the asynchronous request thread and caches size variants.
class CollectionCoverIndex final {
public:
    using Candidates = QHash<QString, QStringList>;

    // The catalog publishes a complete generation before announcing its rows.
    // Returning the old generation lets the caller retire it off the GUI thread.
    Candidates replace(Candidates&& next) {
        QWriteLocker locker(&lock_);
        candidates_.swap(next);
        return std::move(next);
    }

    QStringList candidates(const QString& id) const {
        QReadLocker locker(&lock_);
        // Resolve old URLs for a surviving group against its latest members.
        // The new content version still forces Qt's image cache to refresh.
        // QStringList is implicitly shared. File I/O happens after unlocking.
        return candidates_.value(id.section('/', 0, 1));
    }

private:
    mutable QReadWriteLock lock_;
    Candidates candidates_;
};

class CoverImageProvider final : public QQuickImageProvider {
    static QImage readScaled(QImageReader& reader, const QSize& bounds) {
        const auto original = reader.size();
        // sourceSize is a decode budget, not an instruction to inflate a small
        // embedded cover. Preserve every source pixel and let Qt sample it.
        if (original.isValid() && (original.width() > bounds.width() || original.height() > bounds.height()))
            reader.setScaledSize(original.scaled(bounds, Qt::KeepAspectRatio));
        return reader.read();
    }
    static QImage loadArtwork(const QString& id, const QSize& bounds) {
        const auto path = QUrl::fromPercentEncoding(id.section('?', 0, 0).toUtf8());
#ifdef Q_OS_WIN
        const auto fileName = path.toStdWString();
#else
        const auto fileName = path.toStdString();
#endif
        TagLib::FileRef file(fileName.c_str(), false);
        QImage image;
        if (!file.isNull()) {
            const auto pictures = file.complexProperties("PICTURE");
            for (const bool front : {true, false}) for (const auto& picture : pictures) {
                if ((picture["pictureType"].toString() == "Front Cover") != front) continue;
                const auto bytes = picture["data"].toByteVector();
                QBuffer buffer;
                buffer.setData(QByteArray::fromRawData(bytes.data(), bytes.size()));
                buffer.open(QIODevice::ReadOnly);
                QImageReader reader(&buffer);
                image = readScaled(reader, bounds);
                if (!image.isNull()) return image;
            }
        }
        const auto adjacent = MetaDataManager::instance()->findCoverFile(path);
        if (!adjacent.isEmpty()) {
            QImageReader reader(adjacent);
            image = readScaled(reader, bounds);
        }
        return image;
    }
public:
    explicit CoverImageProvider(std::shared_ptr<CollectionCoverIndex> index = {})
        : QQuickImageProvider(QQuickImageProvider::Texture, QQmlImageProviderBase::ForceAsynchronousImageLoading),
          index_(std::move(index)) {}
    QQuickTextureFactory* requestTexture(const QString& id, QSize* size, const QSize& requested) override {
        return new ArtworkTextureFactory(requestImage(id, size, requested));
    }
    QImage requestImage(const QString& id, QSize* size, const QSize& requested) override {
        QImage image;
        // Qt Quick may supply only one sourceSize axis (the other is zero).
        // QSize::isValid accepts zero, but scaling into it discards the image.
        const QSize bounds = requested.width() > 0 || requested.height() > 0
            ? QSize(requested.width() > 0 ? qMin(requested.width(), 2400) : 2400,
                    requested.height() > 0 ? qMin(requested.height(), 2400) : 2400)
            : QSize(256, 256);
        if (id.startsWith("collection-index/")) {
            const auto candidates = index_ ? index_->candidates(id) : QStringList{};
            for (const auto& candidate : candidates) {
                image = loadArtwork(candidate.mid(15), bounds);
                if (!image.isNull()) break;
            }
        } else if (id.startsWith("collection/")) {
            const auto encoded = id.section('?', 0, 0).mid(11).toLatin1();
            const auto candidates = QJsonDocument::fromJson(QByteArray::fromBase64(encoded, QByteArray::Base64UrlEncoding)).array();
            for (const auto& candidate : candidates) {
                image = loadArtwork(candidate.toString(), bounds);
                if (!image.isNull()) break;
            }
        } else image = loadArtwork(id, bounds);
        // A transparent one-pixel sentinel lets CoverArt distinguish a missing
        // cover from real artwork without emitting an image-loading error.
        if (image.isNull()) { image = QImage(1, 1, QImage::Format_ARGB32_Premultiplied); image.fill(Qt::transparent); }
        else if (image.width() > bounds.width() || image.height() > bounds.height())
            image = image.scaled(bounds, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        if (size) *size = image.size();
        return image;
    }
private:
    std::shared_ptr<CollectionCoverIndex> index_;
};
