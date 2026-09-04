#pragma once

#include "MusicTypes.h"

#include <QSqlDatabase>
#include <QVariantList>

#include <optional>

class MusicDatabase {
public:
    MusicDatabase() = default;
    ~MusicDatabase();

    MusicDatabase(const MusicDatabase &) = delete;
    MusicDatabase &operator=(const MusicDatabase &) = delete;

    bool open(const QString &databasePath, QString *errorMessage = nullptr);
    bool isOpen() const;
    QString databasePath() const;

    QStringList libraryRoots(QString *errorMessage = nullptr) const;
    bool addLibraryRoot(const QString &path, QString *errorMessage = nullptr);
    bool removeLibraryRoot(const QString &path, QString *errorMessage = nullptr);
    FingerprintMap fingerprints(const QString &rootPath,
                                QString *errorMessage = nullptr) const;
    bool applyScan(const ScanResult &result, QString *errorMessage = nullptr);

    QList<TrackRecord> allTracks(QString *errorMessage = nullptr) const;
    std::optional<TrackRecord> track(qint64 id, QString *errorMessage = nullptr) const;
    std::optional<TrackRecord> trackForPath(const QString &path,
                                            QString *errorMessage = nullptr) const;
    qint64 addExternalTrack(const TrackRecord &track, QString *errorMessage = nullptr);
    bool recordPlayed(qint64 trackId, QString *errorMessage = nullptr);

    QVariantList playlists(QString *errorMessage = nullptr) const;
    qint64 createPlaylist(const QString &name, QString *errorMessage = nullptr);
    bool renamePlaylist(qint64 playlistId, const QString &name,
                        QString *errorMessage = nullptr);
    bool removePlaylist(qint64 playlistId, QString *errorMessage = nullptr);
    QList<qint64> playlistTrackIds(qint64 playlistId,
                                   QString *errorMessage = nullptr) const;
    bool addTrackToPlaylist(qint64 playlistId, qint64 trackId,
                            QString *errorMessage = nullptr);
    bool removeTrackFromPlaylist(qint64 playlistId, qint64 trackId,
                                 QString *errorMessage = nullptr);

    QList<qint64> queueTrackIds(QString *errorMessage = nullptr) const;
    bool setQueueTrackIds(const QList<qint64> &trackIds,
                          QString *errorMessage = nullptr);

    QString setting(const QString &key, const QString &fallback = {},
                    QString *errorMessage = nullptr) const;
    bool setSetting(const QString &key, const QString &value,
                    QString *errorMessage = nullptr);

private:
    bool migrate(QString *errorMessage);
    qint64 rootId(const QString &path, QString *errorMessage) const;
    static TrackRecord readTrack(const class QSqlQuery &query);
    static bool fail(const class QSqlQuery &query, QString *errorMessage);

    QString m_connectionName;
    QSqlDatabase m_database;
};
