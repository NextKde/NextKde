#pragma once

#include <QHash>
#include <QList>
#include <QMetaType>
#include <QString>
#include <QStringList>

struct TrackRecord {
    qint64 id = -1;
    qint64 rootId = -1;
    QString path;
    QString url;
    QString title;
    QString artist;
    QString album;
    QString albumArtist;
    QString genre;
    QString artworkUrl;
    QString format;
    qint64 durationMs = 0;
    qint64 fileSize = 0;
    qint64 modifiedMs = 0;
    qint64 addedAt = 0;
    qint64 lastPlayedAt = 0;
    int trackNumber = 0;
    int discNumber = 0;
    int year = 0;
    int playCount = 0;
};

struct FileFingerprint {
    qint64 modifiedMs = 0;
    qint64 fileSize = 0;
};

struct ScanResult {
    QString rootPath;
    QList<TrackRecord> changedTracks;
    QStringList visitedPaths;
    QStringList warnings;
};

using FingerprintMap = QHash<QString, FileFingerprint>;

Q_DECLARE_METATYPE(TrackRecord)
Q_DECLARE_METATYPE(ScanResult)
