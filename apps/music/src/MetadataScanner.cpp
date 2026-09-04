#include "MetadataScanner.h"

#include <QCryptographicHash>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QSet>
#include <QUrl>

#include <taglib/attachedpictureframe.h>
#include <taglib/audioproperties.h>
#include <taglib/fileref.h>
#include <taglib/flacfile.h>
#include <taglib/flacpicture.h>
#include <taglib/id3v2tag.h>
#include <taglib/mp4coverart.h>
#include <taglib/mp4file.h>
#include <taglib/mp4item.h>
#include <taglib/mp4tag.h>
#include <taglib/mpegfile.h>
#include <taglib/opusfile.h>
#include <taglib/tag.h>
#include <taglib/tpropertymap.h>
#include <taglib/vorbisfile.h>
#include <taglib/xiphcomment.h>

#include <algorithm>
#include <optional>

namespace {

constexpr qsizetype maximumArtworkBytes = 20 * 1024 * 1024;
constexpr qsizetype maximumWarnings = 100;

struct Artwork {
    QByteArray data;
    QString mimeType;
};

QString fromTagString(const TagLib::String &value)
{
    return QString::fromUtf8(value.to8Bit(true));
}

QString firstProperty(TagLib::PropertyMap properties, const char *name)
{
    const TagLib::StringList values = properties[TagLib::String(name)];
    return values.isEmpty() ? QString{} : fromTagString(values.front()).trimmed();
}

int leadingNumber(const QString &value)
{
    bool ok = false;
    const int number = value.section(QLatin1Char('/'), 0, 0).trimmed().toInt(&ok);
    return ok ? number : 0;
}

Artwork artworkFromPicture(const TagLib::FLAC::Picture *picture)
{
    if (!picture)
        return {};
    const TagLib::ByteVector bytes = picture->data();
    if (bytes.isEmpty() || bytes.size() > maximumArtworkBytes)
        return {};
    return {QByteArray(bytes.data(), static_cast<qsizetype>(bytes.size())),
            fromTagString(picture->mimeType())};
}

Artwork embeddedArtwork(TagLib::File *file)
{
    if (auto *mpeg = dynamic_cast<TagLib::MPEG::File *>(file)) {
        if (TagLib::ID3v2::Tag *tag = mpeg->ID3v2Tag()) {
            const TagLib::ID3v2::FrameList frames = tag->frameListMap()["APIC"];
            TagLib::ID3v2::AttachedPictureFrame *fallback = nullptr;
            for (TagLib::ID3v2::Frame *frame : frames) {
                auto *picture = dynamic_cast<TagLib::ID3v2::AttachedPictureFrame *>(frame);
                if (!picture)
                    continue;
                if (!fallback)
                    fallback = picture;
                if (picture->type() != TagLib::ID3v2::AttachedPictureFrame::FrontCover)
                    continue;
                fallback = picture;
                break;
            }
            if (fallback) {
                const TagLib::ByteVector bytes = fallback->picture();
                if (!bytes.isEmpty() && bytes.size() <= maximumArtworkBytes) {
                    return {QByteArray(bytes.data(), static_cast<qsizetype>(bytes.size())),
                            fromTagString(fallback->mimeType())};
                }
            }
        }
    }
    if (auto *flac = dynamic_cast<TagLib::FLAC::File *>(file)) {
        const auto pictures = flac->pictureList();
        const TagLib::FLAC::Picture *fallback = pictures.isEmpty() ? nullptr : pictures.front();
        for (const TagLib::FLAC::Picture *picture : pictures) {
            if (picture && picture->type() == TagLib::FLAC::Picture::FrontCover) {
                fallback = picture;
                break;
            }
        }
        const Artwork result = artworkFromPicture(fallback);
        if (!result.data.isEmpty())
            return result;
    }
    if (auto *mp4 = dynamic_cast<TagLib::MP4::File *>(file)) {
        TagLib::MP4::Tag *tag = mp4->tag();
        if (tag && tag->contains("covr")) {
            const TagLib::MP4::CoverArtList covers = tag->item("covr").toCoverArtList();
            if (!covers.isEmpty()) {
                const TagLib::ByteVector bytes = covers.front().data();
                if (!bytes.isEmpty() && bytes.size() <= maximumArtworkBytes)
                    return {QByteArray(bytes.data(), static_cast<qsizetype>(bytes.size())), {}};
            }
        }
    }

    TagLib::Ogg::XiphComment *comment = nullptr;
    if (auto *vorbis = dynamic_cast<TagLib::Ogg::Vorbis::File *>(file))
        comment = vorbis->tag();
    else if (auto *opus = dynamic_cast<TagLib::Ogg::Opus::File *>(file))
        comment = opus->tag();
    if (comment) {
        const auto pictures = comment->pictureList();
        const TagLib::FLAC::Picture *fallback = pictures.isEmpty() ? nullptr : pictures.front();
        for (const TagLib::FLAC::Picture *picture : pictures) {
            if (picture && picture->type() == TagLib::FLAC::Picture::FrontCover) {
                fallback = picture;
                break;
            }
        }
        return artworkFromPicture(fallback);
    }
    return {};
}

QString artworkExtension(const Artwork &artwork)
{
    const QByteArray prefix = artwork.data.left(12);
    if (prefix.startsWith("\x89PNG"))
        return QStringLiteral("png");
    if (prefix.startsWith("\xff\xd8"))
        return QStringLiteral("jpg");
    if (prefix.startsWith("GIF8"))
        return QStringLiteral("gif");
    if (prefix.startsWith("BM"))
        return QStringLiteral("bmp");
    if (artwork.mimeType.contains(QStringLiteral("png"), Qt::CaseInsensitive))
        return QStringLiteral("png");
    if (artwork.mimeType.contains(QStringLiteral("gif"), Qt::CaseInsensitive))
        return QStringLiteral("gif");
    return QStringLiteral("jpg");
}

QString persistArtwork(const Artwork &artwork, const QString &sourcePath,
                       qint64 modifiedMs, qint64 fileSize, const QString &cachePath)
{
    if (artwork.data.isEmpty() || !QDir().mkpath(cachePath))
        return {};
    QCryptographicHash hash(QCryptographicHash::Sha256);
    hash.addData(sourcePath.toUtf8());
    hash.addData(QByteArray::number(modifiedMs));
    hash.addData(QByteArray::number(fileSize));
    const QString destination = QDir(cachePath).filePath(
        QString::fromLatin1(hash.result().toHex()) + QLatin1Char('.')
        + artworkExtension(artwork));
    if (!QFileInfo::exists(destination)) {
        QSaveFile file(destination);
        if (!file.open(QIODevice::WriteOnly)
            || file.write(artwork.data) != artwork.data.size() || !file.commit()) {
            return {};
        }
    }
    return QUrl::fromLocalFile(destination).toString();
}

std::optional<TrackRecord> readTrackFile(const QFileInfo &inputInfo,
                                         const QString &artworkCachePath,
                                         QString *warning)
{
    QString path = inputInfo.canonicalFilePath();
    if (path.isEmpty())
        path = inputInfo.absoluteFilePath();
    const QByteArray encodedPath = QFile::encodeName(path);
    TagLib::FileRef file(encodedPath.constData(), true, TagLib::AudioProperties::Fast);
    if (file.isNull() || !file.file() || !file.audioProperties()) {
        if (warning) {
            *warning = QStringLiteral("Unsupported or unreadable audio file: %1")
                           .arg(path);
        }
        return std::nullopt;
    }
    TagLib::Tag *tag = file.tag();
    const TagLib::PropertyMap properties = file.properties();
    TrackRecord track;
    track.path = path;
    track.url = QUrl::fromLocalFile(path).toString();
    track.title = tag ? fromTagString(tag->title()).trimmed() : QString{};
    if (track.title.isEmpty())
        track.title = inputInfo.completeBaseName();
    track.artist = tag ? fromTagString(tag->artist()).trimmed() : QString{};
    track.album = tag ? fromTagString(tag->album()).trimmed() : QString{};
    track.genre = tag ? fromTagString(tag->genre()).trimmed() : QString{};
    track.year = tag ? static_cast<int>(tag->year()) : 0;
    track.trackNumber = tag ? static_cast<int>(tag->track()) : 0;
    track.albumArtist = firstProperty(properties, "ALBUMARTIST");
    if (track.albumArtist.isEmpty())
        track.albumArtist = firstProperty(properties, "ALBUM ARTIST");
    if (track.albumArtist.isEmpty())
        track.albumArtist = track.artist;
    track.discNumber = leadingNumber(firstProperty(properties, "DISCNUMBER"));
    track.durationMs = file.audioProperties()->lengthInMilliseconds();
    track.fileSize = inputInfo.size();
    track.modifiedMs = inputInfo.lastModified().toMSecsSinceEpoch();
    track.format = inputInfo.suffix().toUpper();
    track.artworkUrl = persistArtwork(embeddedArtwork(file.file()), path,
                                      track.modifiedMs, track.fileSize,
                                      artworkCachePath);
    return track;
}

void addWarning(ScanResult *result, const QString &warning)
{
    if (result->warnings.size() < maximumWarnings)
        result->warnings.append(warning);
}

} // namespace

QStringList MetadataScanner::supportedExtensions()
{
    return {
        QStringLiteral("aac"), QStringLiteral("aif"), QStringLiteral("aiff"),
        QStringLiteral("ape"), QStringLiteral("asf"), QStringLiteral("dff"),
        QStringLiteral("dsf"), QStringLiteral("flac"), QStringLiteral("m4a"),
        QStringLiteral("m4b"), QStringLiteral("mp3"), QStringLiteral("mp4"),
        QStringLiteral("mpc"), QStringLiteral("oga"), QStringLiteral("ogg"),
        QStringLiteral("opus"), QStringLiteral("spx"), QStringLiteral("tta"),
        QStringLiteral("wav"), QStringLiteral("wave"), QStringLiteral("wma"),
        QStringLiteral("wv"),
    };
}

std::optional<TrackRecord> MetadataScanner::scanFile(const QString &path,
                                                     const QString &artworkCachePath,
                                                     QString *warning)
{
    const QFileInfo info(path);
    if (!info.isFile() || !info.isReadable()
        || !supportedExtensions().contains(info.suffix().toLower())) {
        if (warning)
            *warning = QStringLiteral("Unsupported or unreadable audio file: %1").arg(path);
        return std::nullopt;
    }
    return readTrackFile(info, artworkCachePath, warning);
}

ScanResult MetadataScanner::scan(const QString &rootPath,
                                 const FingerprintMap &knownFiles,
                                 const QString &artworkCachePath)
{
    ScanResult result;
    result.rootPath = rootPath;
    const QStringList supported = supportedExtensions();
    const QSet<QString> extensions(supported.cbegin(), supported.cend());
    QDirIterator iterator(rootPath,
                          QDir::Files | QDir::Readable | QDir::NoDotAndDotDot,
                          QDirIterator::Subdirectories);
    while (iterator.hasNext()) {
        iterator.next();
        const QFileInfo info = iterator.fileInfo();
        if (!extensions.contains(info.suffix().toLower()))
            continue;
        QString path = info.canonicalFilePath();
        if (path.isEmpty())
            path = info.absoluteFilePath();
        result.visitedPaths.append(path);
        const FileFingerprint fingerprint = knownFiles.value(path);
        const qint64 modifiedMs = info.lastModified().toMSecsSinceEpoch();
        if (knownFiles.contains(path) && fingerprint.modifiedMs == modifiedMs
            && fingerprint.fileSize == info.size()) {
            continue;
        }

        QString warning;
        const std::optional<TrackRecord> track = readTrackFile(info, artworkCachePath,
                                                               &warning);
        if (!track) {
            addWarning(&result, warning);
            continue;
        }
        result.changedTracks.append(*track);
    }
    result.visitedPaths.removeDuplicates();
    return result;
}
