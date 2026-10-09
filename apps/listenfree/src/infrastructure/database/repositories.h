#pragma once

#include "application/ports.h"
#include "infrastructure/database/database.h"

namespace listenfree::infrastructure::database {

class TrackRepository final : public application::ITrackRepository {
public:
    explicit TrackRepository(Database& database) noexcept : database_(database) {}

    bool upsert(std::span<const domain::Track> tracks) override;
    std::optional<domain::Track> find(const domain::TrackId& id) override;
    std::vector<domain::Track> search(const std::string& query) override;
    std::uint64_t count() override;
    std::vector<application::LocalFileFingerprint> localFiles() override;

private:
    Database& database_;
};

class SettingsRepository final : public application::ISettingsRepository {
public:
    explicit SettingsRepository(Database& database) noexcept : database_(database) {}

    std::optional<std::string> get(const std::string& key) override;
    bool set(const std::string& key, const std::string& value) override;

private:
    Database& database_;
};

class PlaylistRepository final : public application::IPlaylistRepository {
public:
    explicit PlaylistRepository(Database& database) noexcept : database_(database) {}

    std::vector<domain::Playlist> list() override;
    bool save(const domain::Playlist& playlist) override;
    bool remove(const domain::PlaylistId& id) override;

private:
    Database& database_;
};

class LibraryFolderRepository final : public application::ILibraryFolderRepository {
public:
    explicit LibraryFolderRepository(Database& database) noexcept : database_(database) {}

    std::vector<application::LibraryFolder> roots() override;
    bool add(const std::filesystem::path& path) override;
    bool remove(std::int64_t id, const std::filesystem::path& path) override;

private:
    Database& database_;
};

class PlayHistoryRepository final : public application::IPlayHistoryRepository {
public:
    explicit PlayHistoryRepository(Database& database) noexcept : database_(database) {}

    bool record(const domain::TrackId& id,
                std::chrono::system_clock::time_point when) override;

private:
    Database& database_;
};

} // namespace listenfree::infrastructure::database
