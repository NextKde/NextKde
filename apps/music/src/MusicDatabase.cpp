#include "MusicDatabase.h"

#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QSqlError>
#include <QSqlQuery>
#include <QUuid>

#include <algorithm>

namespace {

constexpr int schemaVersion = 1;

void setError(QString *target, const QString &message)
{
    if (target)
        *target = message;
}

bool execute(QSqlQuery &query, const QString &statement, QString *errorMessage)
{
    if (query.exec(statement))
        return true;
    setError(errorMessage, query.lastError().text());
    return false;
}

QString nonNull(const QString &value)
{
    return value.isNull() ? QStringLiteral("") : value;
}

} // namespace

MusicDatabase::~MusicDatabase()
{
    if (!m_connectionName.isEmpty()) {
        m_database.close();
        m_database = {};
        QSqlDatabase::removeDatabase(m_connectionName);
    }
}

bool MusicDatabase::open(const QString &databasePath, QString *errorMessage)
{
    if (m_database.isOpen())
        return true;
    const QFileInfo info(databasePath);
    if (!QDir().mkpath(info.absolutePath())) {
        setError(errorMessage, QStringLiteral("Unable to create the music data directory"));
        return false;
    }

    m_connectionName = QStringLiteral("kos-music-%1").arg(
        QUuid::createUuid().toString(QUuid::WithoutBraces));
    m_database = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), m_connectionName);
    m_database.setDatabaseName(info.absoluteFilePath());
    m_database.setConnectOptions(QStringLiteral("QSQLITE_BUSY_TIMEOUT=5000"));
    if (!m_database.open()) {
        setError(errorMessage, m_database.lastError().text());
        return false;
    }

    QSqlQuery query(m_database);
    if (!execute(query, QStringLiteral("PRAGMA foreign_keys = ON"), errorMessage)
        || !execute(query, QStringLiteral("PRAGMA journal_mode = WAL"), errorMessage)
        || !execute(query, QStringLiteral("PRAGMA synchronous = NORMAL"), errorMessage)) {
        return false;
    }
    return migrate(errorMessage);
}

bool MusicDatabase::isOpen() const
{
    return m_database.isOpen();
}

QString MusicDatabase::databasePath() const
{
    return m_database.databaseName();
}

bool MusicDatabase::migrate(QString *errorMessage)
{
    QSqlQuery versionQuery(m_database);
    if (!versionQuery.exec(QStringLiteral("PRAGMA user_version")) || !versionQuery.next())
        return fail(versionQuery, errorMessage);
    const int currentVersion = versionQuery.value(0).toInt();
    if (currentVersion > schemaVersion) {
        setError(errorMessage, QStringLiteral("The music library was created by a newer version"));
        return false;
    }
    if (currentVersion == schemaVersion)
        return true;

    if (!m_database.transaction()) {
        setError(errorMessage, m_database.lastError().text());
        return false;
    }
    const QStringList statements{
        QStringLiteral("CREATE TABLE IF NOT EXISTS library_roots ("
                       "id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE, "
                       "added_at INTEGER NOT NULL, last_scan INTEGER NOT NULL DEFAULT 0)"),
        QStringLiteral("CREATE TABLE IF NOT EXISTS tracks ("
                       "id INTEGER PRIMARY KEY, "
                       "root_id INTEGER REFERENCES library_roots(id) ON DELETE CASCADE, "
                       "path TEXT NOT NULL UNIQUE, url TEXT NOT NULL, title TEXT NOT NULL, "
                       "artist TEXT NOT NULL DEFAULT '', album TEXT NOT NULL DEFAULT '', "
                       "album_artist TEXT NOT NULL DEFAULT '', genre TEXT NOT NULL DEFAULT '', "
                       "artwork_url TEXT NOT NULL DEFAULT '', format TEXT NOT NULL DEFAULT '', "
                       "duration_ms INTEGER NOT NULL DEFAULT 0, file_size INTEGER NOT NULL, "
                       "modified_ms INTEGER NOT NULL, added_at INTEGER NOT NULL, "
                       "last_seen INTEGER NOT NULL, track_number INTEGER NOT NULL DEFAULT 0, "
                       "disc_number INTEGER NOT NULL DEFAULT 0, year INTEGER NOT NULL DEFAULT 0, "
                       "play_count INTEGER NOT NULL DEFAULT 0, "
                       "last_played_at INTEGER NOT NULL DEFAULT 0)"),
        QStringLiteral("CREATE INDEX IF NOT EXISTS tracks_title_idx ON tracks(title COLLATE NOCASE)"),
        QStringLiteral("CREATE INDEX IF NOT EXISTS tracks_album_idx ON tracks(album COLLATE NOCASE)"),
        QStringLiteral("CREATE INDEX IF NOT EXISTS tracks_artist_idx ON tracks(artist COLLATE NOCASE)"),
        QStringLiteral("CREATE TABLE IF NOT EXISTS playlists ("
                       "id INTEGER PRIMARY KEY, name TEXT NOT NULL, created_at INTEGER NOT NULL, "
                       "modified_at INTEGER NOT NULL)"),
        QStringLiteral("CREATE TABLE IF NOT EXISTS playlist_items ("
                       "playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE, "
                       "track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE, "
                       "position INTEGER NOT NULL, added_at INTEGER NOT NULL, "
                       "PRIMARY KEY (playlist_id, track_id))"),
        QStringLiteral("CREATE TABLE IF NOT EXISTS queue ("
                       "position INTEGER PRIMARY KEY, "
                       "track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE)"),
        QStringLiteral("CREATE TABLE IF NOT EXISTS settings ("
                       "key TEXT PRIMARY KEY, value TEXT NOT NULL)"),
        QStringLiteral("PRAGMA user_version = 1"),
    };
    QSqlQuery query(m_database);
    for (const QString &statement : statements) {
        if (!query.exec(statement)) {
            setError(errorMessage, query.lastError().text());
            m_database.rollback();
            return false;
        }
    }
    if (!m_database.commit()) {
        setError(errorMessage, m_database.lastError().text());
        return false;
    }
    return true;
}

QStringList MusicDatabase::libraryRoots(QString *errorMessage) const
{
    QStringList result;
    QSqlQuery query(m_database);
    if (!query.exec(QStringLiteral("SELECT path FROM library_roots ORDER BY added_at, path"))) {
        fail(query, errorMessage);
        return result;
    }
    while (query.next())
        result.append(query.value(0).toString());
    return result;
}

bool MusicDatabase::addLibraryRoot(const QString &path, QString *errorMessage)
{
    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("INSERT OR IGNORE INTO library_roots(path, added_at) VALUES(?, ?)"));
    query.addBindValue(path);
    query.addBindValue(QDateTime::currentMSecsSinceEpoch());
    return query.exec() ? true : fail(query, errorMessage);
}

bool MusicDatabase::removeLibraryRoot(const QString &path, QString *errorMessage)
{
    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("DELETE FROM library_roots WHERE path = ?"));
    query.addBindValue(path);
    return query.exec() ? true : fail(query, errorMessage);
}

qint64 MusicDatabase::rootId(const QString &path, QString *errorMessage) const
{
    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("SELECT id FROM library_roots WHERE path = ?"));
    query.addBindValue(path);
    if (!query.exec() || !query.next()) {
        fail(query, errorMessage);
        return -1;
    }
    return query.value(0).toLongLong();
}

FingerprintMap MusicDatabase::fingerprints(const QString &rootPath,
                                           QString *errorMessage) const
{
    FingerprintMap result;
    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("SELECT path, modified_ms, file_size FROM tracks "
                                 "WHERE root_id = (SELECT id FROM library_roots WHERE path = ?)"));
    query.addBindValue(rootPath);
    if (!query.exec()) {
        fail(query, errorMessage);
        return result;
    }
    while (query.next()) {
        result.insert(query.value(0).toString(),
                      {query.value(1).toLongLong(), query.value(2).toLongLong()});
    }
    return result;
}

bool MusicDatabase::applyScan(const ScanResult &result, QString *errorMessage)
{
    const qint64 libraryRootId = rootId(result.rootPath, errorMessage);
    if (libraryRootId < 0)
        return false;
    qint64 scanToken = QDateTime::currentMSecsSinceEpoch();
    QSqlQuery tokenQuery(m_database);
    tokenQuery.prepare(QStringLiteral("SELECT COALESCE(MAX(last_seen), 0) FROM tracks "
                                      "WHERE root_id = ?"));
    tokenQuery.addBindValue(libraryRootId);
    if (!tokenQuery.exec() || !tokenQuery.next())
        return fail(tokenQuery, errorMessage);
    scanToken = std::max(scanToken, tokenQuery.value(0).toLongLong() + 1);
    if (!m_database.transaction()) {
        setError(errorMessage, m_database.lastError().text());
        return false;
    }

    QSqlQuery seen(m_database);
    seen.prepare(QStringLiteral("UPDATE tracks SET last_seen = ? WHERE root_id = ? AND path = ?"));
    for (const QString &path : result.visitedPaths) {
        seen.bindValue(0, scanToken);
        seen.bindValue(1, libraryRootId);
        seen.bindValue(2, path);
        if (!seen.exec()) {
            fail(seen, errorMessage);
            m_database.rollback();
            return false;
        }
    }

    QSqlQuery upsert(m_database);
    upsert.prepare(QStringLiteral(
        "INSERT INTO tracks(root_id, path, url, title, artist, album, album_artist, genre, "
        "artwork_url, format, duration_ms, file_size, modified_ms, added_at, last_seen, "
        "track_number, disc_number, year) "
        "VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
        "ON CONFLICT(path) DO UPDATE SET root_id=excluded.root_id, url=excluded.url, "
        "title=excluded.title, artist=excluded.artist, album=excluded.album, "
        "album_artist=excluded.album_artist, genre=excluded.genre, "
        "artwork_url=excluded.artwork_url, format=excluded.format, "
        "duration_ms=excluded.duration_ms, file_size=excluded.file_size, "
        "modified_ms=excluded.modified_ms, last_seen=excluded.last_seen, "
        "track_number=excluded.track_number, disc_number=excluded.disc_number, "
        "year=excluded.year"));
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    for (const TrackRecord &track : result.changedTracks) {
        const QVariantList values{
            libraryRootId, nonNull(track.path), nonNull(track.url), nonNull(track.title),
            nonNull(track.artist), nonNull(track.album), nonNull(track.albumArtist),
            nonNull(track.genre), nonNull(track.artworkUrl), nonNull(track.format),
            track.durationMs, track.fileSize, track.modifiedMs, now, scanToken,
            track.trackNumber, track.discNumber, track.year,
        };
        for (qsizetype index = 0; index < values.size(); ++index)
            upsert.bindValue(static_cast<int>(index), values.at(index));
        if (!upsert.exec()) {
            fail(upsert, errorMessage);
            m_database.rollback();
            return false;
        }
    }

    QSqlQuery removeMissing(m_database);
    removeMissing.prepare(QStringLiteral("DELETE FROM tracks WHERE root_id = ? AND last_seen <> ?"));
    removeMissing.addBindValue(libraryRootId);
    removeMissing.addBindValue(scanToken);
    if (!removeMissing.exec()) {
        fail(removeMissing, errorMessage);
        m_database.rollback();
        return false;
    }
    QSqlQuery updateRoot(m_database);
    updateRoot.prepare(QStringLiteral("UPDATE library_roots SET last_scan = ? WHERE id = ?"));
    updateRoot.addBindValue(now);
    updateRoot.addBindValue(libraryRootId);
    if (!updateRoot.exec()) {
        fail(updateRoot, errorMessage);
        m_database.rollback();
        return false;
    }
    if (!m_database.commit()) {
        setError(errorMessage, m_database.lastError().text());
        return false;
    }
    return true;
}

QList<TrackRecord> MusicDatabase::allTracks(QString *errorMessage) const
{
    QList<TrackRecord> result;
    QSqlQuery query(m_database);
    if (!query.exec(QStringLiteral(
            "SELECT id, root_id, path, url, title, artist, album, album_artist, genre, "
            "artwork_url, format, duration_ms, file_size, modified_ms, added_at, "
            "last_played_at, track_number, disc_number, year, play_count FROM tracks"))) {
        fail(query, errorMessage);
        return result;
    }
    while (query.next())
        result.append(readTrack(query));
    return result;
}

std::optional<TrackRecord> MusicDatabase::track(qint64 id, QString *errorMessage) const
{
    QSqlQuery query(m_database);
    query.prepare(QStringLiteral(
        "SELECT id, root_id, path, url, title, artist, album, album_artist, genre, "
        "artwork_url, format, duration_ms, file_size, modified_ms, added_at, "
        "last_played_at, track_number, disc_number, year, play_count FROM tracks WHERE id = ?"));
    query.addBindValue(id);
    if (!query.exec()) {
        fail(query, errorMessage);
        return std::nullopt;
    }
    return query.next() ? std::optional<TrackRecord>(readTrack(query)) : std::nullopt;
}

std::optional<TrackRecord> MusicDatabase::trackForPath(const QString &path,
                                                       QString *errorMessage) const
{
    QSqlQuery query(m_database);
    query.prepare(QStringLiteral(
        "SELECT id, root_id, path, url, title, artist, album, album_artist, genre, "
        "artwork_url, format, duration_ms, file_size, modified_ms, added_at, "
        "last_played_at, track_number, disc_number, year, play_count FROM tracks WHERE path = ?"));
    query.addBindValue(path);
    if (!query.exec()) {
        fail(query, errorMessage);
        return std::nullopt;
    }
    return query.next() ? std::optional<TrackRecord>(readTrack(query)) : std::nullopt;
}

qint64 MusicDatabase::addExternalTrack(const TrackRecord &track, QString *errorMessage)
{
    QSqlQuery query(m_database);
    query.prepare(QStringLiteral(
        "INSERT INTO tracks(root_id, path, url, title, artist, album, album_artist, genre, "
        "artwork_url, format, duration_ms, file_size, modified_ms, added_at, last_seen, "
        "track_number, disc_number, year) "
        "VALUES(NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?) "
        "ON CONFLICT(path) DO UPDATE SET url=excluded.url, title=excluded.title, "
        "artist=excluded.artist, album=excluded.album, album_artist=excluded.album_artist, "
        "genre=excluded.genre, artwork_url=excluded.artwork_url, format=excluded.format, "
        "duration_ms=excluded.duration_ms, file_size=excluded.file_size, "
        "modified_ms=excluded.modified_ms, track_number=excluded.track_number, "
        "disc_number=excluded.disc_number, year=excluded.year"));
    const QVariantList values{
        nonNull(track.path), nonNull(track.url), nonNull(track.title),
        nonNull(track.artist), nonNull(track.album), nonNull(track.albumArtist),
        nonNull(track.genre), nonNull(track.artworkUrl), nonNull(track.format),
        track.durationMs, track.fileSize, track.modifiedMs,
        QDateTime::currentMSecsSinceEpoch(), track.trackNumber, track.discNumber, track.year,
    };
    for (qsizetype index = 0; index < values.size(); ++index)
        query.bindValue(static_cast<int>(index), values.at(index));
    if (!query.exec()) {
        fail(query, errorMessage);
        return -1;
    }
    const std::optional<TrackRecord> stored = trackForPath(track.path, errorMessage);
    return stored ? stored->id : -1;
}

bool MusicDatabase::recordPlayed(qint64 trackId, QString *errorMessage)
{
    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("UPDATE tracks SET play_count = play_count + 1, "
                                 "last_played_at = ? WHERE id = ?"));
    query.addBindValue(QDateTime::currentMSecsSinceEpoch());
    query.addBindValue(trackId);
    return query.exec() ? true : fail(query, errorMessage);
}

QVariantList MusicDatabase::playlists(QString *errorMessage) const
{
    QVariantList result;
    QSqlQuery query(m_database);
    if (!query.exec(QStringLiteral(
            "SELECT p.id, p.name, COUNT(i.track_id) FROM playlists p "
            "LEFT JOIN playlist_items i ON i.playlist_id = p.id "
            "GROUP BY p.id, p.name ORDER BY p.name COLLATE NOCASE"))) {
        fail(query, errorMessage);
        return result;
    }
    while (query.next()) {
        result.append(QVariantMap{{QStringLiteral("id"), query.value(0)},
                                  {QStringLiteral("name"), query.value(1)},
                                  {QStringLiteral("count"), query.value(2)}});
    }
    return result;
}

qint64 MusicDatabase::createPlaylist(const QString &name, QString *errorMessage)
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("INSERT INTO playlists(name, created_at, modified_at) VALUES(?, ?, ?)"));
    query.addBindValue(name);
    query.addBindValue(now);
    query.addBindValue(now);
    if (!query.exec()) {
        fail(query, errorMessage);
        return -1;
    }
    return query.lastInsertId().toLongLong();
}

bool MusicDatabase::renamePlaylist(qint64 playlistId, const QString &name,
                                   QString *errorMessage)
{
    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("UPDATE playlists SET name = ?, modified_at = ? WHERE id = ?"));
    query.addBindValue(name);
    query.addBindValue(QDateTime::currentMSecsSinceEpoch());
    query.addBindValue(playlistId);
    return query.exec() ? true : fail(query, errorMessage);
}

bool MusicDatabase::removePlaylist(qint64 playlistId, QString *errorMessage)
{
    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("DELETE FROM playlists WHERE id = ?"));
    query.addBindValue(playlistId);
    return query.exec() ? true : fail(query, errorMessage);
}

QList<qint64> MusicDatabase::playlistTrackIds(qint64 playlistId,
                                              QString *errorMessage) const
{
    QList<qint64> result;
    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("SELECT track_id FROM playlist_items "
                                 "WHERE playlist_id = ? ORDER BY position"));
    query.addBindValue(playlistId);
    if (!query.exec()) {
        fail(query, errorMessage);
        return result;
    }
    while (query.next())
        result.append(query.value(0).toLongLong());
    return result;
}

bool MusicDatabase::addTrackToPlaylist(qint64 playlistId, qint64 trackId,
                                       QString *errorMessage)
{
    QSqlQuery query(m_database);
    query.prepare(QStringLiteral(
        "INSERT OR IGNORE INTO playlist_items(playlist_id, track_id, position, added_at) "
        "VALUES(?, ?, COALESCE((SELECT MAX(position) + 1 FROM playlist_items "
        "WHERE playlist_id = ?), 0), ?)"));
    query.addBindValue(playlistId);
    query.addBindValue(trackId);
    query.addBindValue(playlistId);
    query.addBindValue(QDateTime::currentMSecsSinceEpoch());
    return query.exec() ? true : fail(query, errorMessage);
}

bool MusicDatabase::removeTrackFromPlaylist(qint64 playlistId, qint64 trackId,
                                            QString *errorMessage)
{
    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("DELETE FROM playlist_items WHERE playlist_id = ? AND track_id = ?"));
    query.addBindValue(playlistId);
    query.addBindValue(trackId);
    return query.exec() ? true : fail(query, errorMessage);
}

QList<qint64> MusicDatabase::queueTrackIds(QString *errorMessage) const
{
    QList<qint64> result;
    QSqlQuery query(m_database);
    if (!query.exec(QStringLiteral("SELECT track_id FROM queue ORDER BY position"))) {
        fail(query, errorMessage);
        return result;
    }
    while (query.next())
        result.append(query.value(0).toLongLong());
    return result;
}

bool MusicDatabase::setQueueTrackIds(const QList<qint64> &trackIds,
                                     QString *errorMessage)
{
    if (!m_database.transaction()) {
        setError(errorMessage, m_database.lastError().text());
        return false;
    }
    QSqlQuery clear(m_database);
    if (!clear.exec(QStringLiteral("DELETE FROM queue"))) {
        fail(clear, errorMessage);
        m_database.rollback();
        return false;
    }
    QSqlQuery insert(m_database);
    insert.prepare(QStringLiteral("INSERT INTO queue(position, track_id) VALUES(?, ?)"));
    for (qsizetype index = 0; index < trackIds.size(); ++index) {
        insert.bindValue(0, index);
        insert.bindValue(1, trackIds.at(index));
        if (!insert.exec()) {
            fail(insert, errorMessage);
            m_database.rollback();
            return false;
        }
    }
    if (!m_database.commit()) {
        setError(errorMessage, m_database.lastError().text());
        return false;
    }
    return true;
}

QString MusicDatabase::setting(const QString &key, const QString &fallback,
                               QString *errorMessage) const
{
    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("SELECT value FROM settings WHERE key = ?"));
    query.addBindValue(key);
    if (!query.exec()) {
        fail(query, errorMessage);
        return fallback;
    }
    return query.next() ? query.value(0).toString() : fallback;
}

bool MusicDatabase::setSetting(const QString &key, const QString &value,
                               QString *errorMessage)
{
    QSqlQuery query(m_database);
    query.prepare(QStringLiteral("INSERT INTO settings(key, value) VALUES(?, ?) "
                                 "ON CONFLICT(key) DO UPDATE SET value = excluded.value"));
    query.addBindValue(key);
    query.addBindValue(value);
    return query.exec() ? true : fail(query, errorMessage);
}

TrackRecord MusicDatabase::readTrack(const QSqlQuery &query)
{
    TrackRecord track;
    track.id = query.value(0).toLongLong();
    track.rootId = query.value(1).toLongLong();
    track.path = query.value(2).toString();
    track.url = query.value(3).toString();
    track.title = query.value(4).toString();
    track.artist = query.value(5).toString();
    track.album = query.value(6).toString();
    track.albumArtist = query.value(7).toString();
    track.genre = query.value(8).toString();
    track.artworkUrl = query.value(9).toString();
    track.format = query.value(10).toString();
    track.durationMs = query.value(11).toLongLong();
    track.fileSize = query.value(12).toLongLong();
    track.modifiedMs = query.value(13).toLongLong();
    track.addedAt = query.value(14).toLongLong();
    track.lastPlayedAt = query.value(15).toLongLong();
    track.trackNumber = query.value(16).toInt();
    track.discNumber = query.value(17).toInt();
    track.year = query.value(18).toInt();
    track.playCount = query.value(19).toInt();
    return track;
}

bool MusicDatabase::fail(const QSqlQuery &query, QString *errorMessage)
{
    setError(errorMessage, query.lastError().text());
    return false;
}
