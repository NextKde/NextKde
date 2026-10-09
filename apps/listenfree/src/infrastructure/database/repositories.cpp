#include "infrastructure/database/repositories.h"

#include <QString>

#include <algorithm>
#include <iterator>

namespace listenfree::infrastructure::database {

bool TrackRepository::upsert(std::span<const domain::Track> tracks) {
    return database_.upsertTracks(tracks);
}

std::optional<domain::Track> TrackRepository::find(const domain::TrackId& id) {
    return database_.findTrack(id);
}

std::vector<domain::Track> TrackRepository::search(const std::string& query) {
    return database_.searchTracks(QString::fromStdString(query));
}

std::uint64_t TrackRepository::count() {
    return database_.trackCount();
}

std::vector<application::LocalFileFingerprint> TrackRepository::localFiles() {
    return database_.loadLocalFiles();
}

std::vector<application::LibraryFolder> LibraryFolderRepository::roots() {
    const auto folders = database_.loadLibraryFolders();
    std::vector<application::LibraryFolder> result;
    result.reserve(static_cast<std::size_t>(folders.size()));
    std::transform(folders.begin(), folders.end(), std::back_inserter(result), [](const QVariant& folder) {
        const auto values = folder.toList();
        return application::LibraryFolder{values.value(0).toLongLong(),
                                         std::filesystem::path(values.value(1).toString().toStdWString())};
    });
    return result;
}

bool LibraryFolderRepository::add(const std::filesystem::path& path) {
    return database_.addLibraryFolder(QString::fromStdWString(path.wstring()));
}

bool LibraryFolderRepository::remove(std::int64_t id, const std::filesystem::path& path) {
    return database_.removeLibraryFolder(id, QString::fromStdWString(path.wstring()));
}

std::optional<std::string> SettingsRepository::get(const std::string& key) {
    return database_.getSetting(QString::fromStdString(key));
}

bool SettingsRepository::set(const std::string& key, const std::string& value) {
    return database_.setSetting(QString::fromStdString(key), QString::fromStdString(value));
}

std::vector<domain::Playlist> PlaylistRepository::list() { return database_.loadPlaylists(); }

bool PlaylistRepository::save(const domain::Playlist& playlist) { return database_.savePlaylist(playlist); }

bool PlaylistRepository::remove(const domain::PlaylistId& id) { return database_.removePlaylist(id); }

bool PlayHistoryRepository::record(const domain::TrackId& id,
                                   std::chrono::system_clock::time_point when) {
    return database_.recordPlayHistory(id, when);
}

} // namespace listenfree::infrastructure::database
