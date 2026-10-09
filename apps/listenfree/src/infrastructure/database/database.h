#pragma once

#include "application/ports.h"

#include <QSqlDatabase>
#include <QSqlQuery>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>
#include <functional>

namespace listenfree::infrastructure::database {

// Prepared once per transaction and reused for every track, mirroring fooyin's
// TrackDatabase::storeTracks statement handling; per-track prepare+finalize was
// the dominant write cost for large scans.
struct UpsertStatements {
    QSqlQuery track;
    QSqlQuery clearArtists;
    QSqlQuery clearAlbums;
    QSqlQuery clearFiles;
    QSqlQuery artist;
    QSqlQuery linkArtist;
    QSqlQuery album;
    QSqlQuery linkAlbum;
    QSqlQuery localFile;

    explicit UpsertStatements(QSqlDatabase& database);
};

struct CatalogSnapshotState {
    std::int64_t revision = 0;
    std::int64_t resetRevision = 0;
};

struct CatalogTrackChange {
    std::string trackId;
    // An absent track is a committed deletion, not a query failure.
    std::optional<domain::Track> track;
};

struct CatalogDelta {
    CatalogSnapshotState state;
    bool requiresFullReload = false;
    std::vector<CatalogTrackChange> changes;
};

struct CatalogJournal;

class Database final {
public:
    Database() = default;
    ~Database();
    Database(const Database&) = delete;
    Database& operator=(const Database&) = delete;

    bool open(const QString& path);
    // Opens a secondary connection to an already-migrated database file for a
    // worker thread (fooyin DbConnectionPool pattern): schema setup stays with
    // the primary connection; this one only applies per-connection pragmas.
    bool openExisting(const QString& path);
    void close() noexcept;
    [[nodiscard]] bool isOpen() const noexcept { return db_.isValid() && db_.isOpen(); }
    bool migrate();
    bool upsertTrack(const domain::Track& track);
    bool upsertTracks(std::span<const domain::Track> tracks, bool fromScan = false);
    // Recheck missing relations under the write lock; never restore a deleted
    // track or overwrite an edit made while its tags were read in the worker.
    bool restoreMissingRelations(std::span<const domain::Track> tracks);
    [[nodiscard]] std::optional<domain::Track> findTrack(const domain::TrackId& id) const;
    [[nodiscard]] std::vector<domain::Track> searchTracks(const QString& queryText) const;
    [[nodiscard]] std::uint64_t trackCount() const;
    [[nodiscard]] std::vector<domain::Track> loadTracks() const;
    // Visits tracks in loadTracks() order while keeping only one hydrated track
    // in application memory. The callback must not change this connection.
    [[nodiscard]] bool forEachTrack(const std::function<void(domain::Track&&)>& callback) const;
    // State and rows come from one SQLite read snapshot. A false result means
    // the transaction or a query failed; callers must discard partial rows.
    [[nodiscard]] bool forEachTrackWithRevision(
        const std::function<void(domain::Track&&)>& callback, CatalogSnapshotState& out) const;
    // maxChanges bounds both the journal scan and hydration. A missing track
    // appears as a change with nullopt; SQL failures return false.
    [[nodiscard]] bool readCatalogDelta(std::int64_t afterRevision, std::size_t maxChanges,
                                        CatalogDelta& out) const;
    [[nodiscard]] std::vector<application::LocalFileFingerprint> loadLocalFiles() const;
    [[nodiscard]] QVariantList loadLibraryFolders() const;
    bool addLibraryFolder(const QString& path);
    bool removeLibraryFolder(std::int64_t id, const QString& path);
    [[nodiscard]] std::vector<domain::Playlist> loadPlaylists() const;
    bool savePlaylist(const domain::Playlist& playlist);
    bool removePlaylist(const domain::PlaylistId& id);
    bool clearLibraryIndex();
    bool removeTrack(const QString& id);
    bool removeLocalTrack(const QString& path, bool excludeFromScan);
    bool restoreExcludedFiles(const QStringList& roots);
    bool pruneMissingLocalFiles(const QStringList& roots, bool recursive);
    bool recordPlayHistory(const domain::TrackId& id,
                           std::chrono::system_clock::time_point when);
    [[nodiscard]] std::optional<std::string> getSetting(const QString& key) const;
    bool setSetting(const QString& key, const QString& value, const QString& valueType = QStringLiteral("string"));
    bool applySettings(const QVariantMap& values, const QStringList& addedRoots = {}, const std::function<bool()>& applyRuntime = {});
    bool clearScrollPositions();
    bool mergeDuplicate(const QVariantMap& duplicate, const QVariantMap& keeper, const QString& hash, bool alias);

private:
    bool connect(const QString& path);
    bool upsertTrackRows(const domain::Track& track, UpsertStatements& statements,
                         CatalogJournal& journal);

    QSqlDatabase db_;
    QString connectionName_;
};

} // namespace listenfree::infrastructure::database
