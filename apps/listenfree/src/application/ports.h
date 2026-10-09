#pragma once

#include "domain/domain.h"

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace listenfree::application {

enum class PlaybackCapability : std::uint32_t {
    LocalFile = 1U << 0U,
    HttpStream = 1U << 1U,
    Seek = 1U << 2U,
    Volume = 1U << 3U,
    Mute = 1U << 4U,
    DeviceSelection = 1U << 5U,
    Equalizer = 1U << 6U,
    Gapless = 1U << 7U,
    Crossfade = 1U << 8U,
    ReplayGain = 1U << 9U,
    HighResolution = 1U << 10U
};

constexpr std::uint32_t capabilityMask(PlaybackCapability capability) noexcept {
    return static_cast<std::uint32_t>(capability);
}

struct LocalFileFingerprint {
    std::filesystem::path canonicalPath;
    std::uintmax_t sizeBytes{0};
    std::int64_t modifiedMs{0};
    std::string duplicateHash;
    std::filesystem::path keeperPath;
    bool excluded{false};
};

struct LibraryFolder {
    std::int64_t id{0};
    std::filesystem::path path;
};

struct ScanRequest {
    std::vector<std::filesystem::path> roots;
    bool recursive{true};
    std::vector<LocalFileFingerprint> knownFiles;
};

using ScanId = std::uint64_t;

enum class ScanStatus { Completed, Cancelled, Failed };

struct ScanOutcome {
    ScanStatus status{ScanStatus::Completed};
    std::string error;
};

struct ScanCallbacks {
    std::function<void(std::vector<domain::Track>)> onBatch;
    std::function<void(ScanOutcome)> onFinished;
};

struct PlaybackEvents {
    // Callbacks run serially on the player's owner thread and may call player
    // methods. Replacing the set prevents further old callbacks from starting;
    // a callback already on the stack owns a safe local snapshot until it returns.
    std::function<void(domain::PlaybackState)> onStateChanged;
    std::function<void(std::chrono::milliseconds)> onPositionChanged;
    std::function<void(std::chrono::milliseconds)> onDurationChanged;
    std::function<void(bool)> onSeekableChanged;
    std::function<void(float)> onVolumeChanged;
    std::function<void(bool)> onMutedChanged;
    std::function<void()> onFinished;
    std::function<void(std::optional<domain::PlaybackError>)> onErrorChanged;
    std::function<void(std::optional<domain::AudioFormatInfo>)> onAudioFormatChanged;
};

struct PlaybackBackendEvents {
    std::function<void(std::uint32_t)> onCapabilitiesChanged;
};

struct AudioDeviceInfo {
    std::string id;
    std::string name;
    bool isDefault{false};
    bool isSelected{false};
};

struct AudioDeviceEvents {
    // Same owner-thread, replaceable-subscription contract as PlaybackEvents.
    std::function<void()> onDevicesChanged;
    std::function<void(std::string)> onSelectedDeviceChanged;
};

class ITrackRepository {
public:
    virtual ~ITrackRepository() = default;
    virtual bool upsert(std::span<const domain::Track> tracks) = 0;
    virtual std::optional<domain::Track> find(const domain::TrackId& id) = 0;
    virtual std::vector<domain::Track> search(const std::string& query) = 0;
    virtual std::uint64_t count() = 0;
    virtual std::vector<LocalFileFingerprint> localFiles() = 0;
};

class ILibraryFolderRepository {
public:
    virtual ~ILibraryFolderRepository() = default;
    virtual std::vector<LibraryFolder> roots() = 0;
    virtual bool add(const std::filesystem::path& path) = 0;
    virtual bool remove(std::int64_t id, const std::filesystem::path& path) = 0;
};

class IPlaylistRepository {
public:
    virtual ~IPlaylistRepository() = default;
    virtual std::vector<domain::Playlist> list() = 0;
    virtual bool save(const domain::Playlist& playlist) = 0;
    virtual bool remove(const domain::PlaylistId& id) = 0;
};

class ISettingsRepository {
public:
    virtual ~ISettingsRepository() = default;
    virtual std::optional<std::string> get(const std::string& key) = 0;
    virtual bool set(const std::string& key, const std::string& value) = 0;
};

class IPlayHistoryRepository {
public:
    virtual ~IPlayHistoryRepository() = default;
    virtual bool record(const domain::TrackId& id, std::chrono::system_clock::time_point when) = 0;
};

class ILocalLibraryScanner {
public:
    virtual ~ILocalLibraryScanner() = default;
    virtual ScanId start(const ScanRequest&, ScanCallbacks callbacks) = 0;
    virtual void cancel(ScanId id) noexcept = 0;
};

class IMetadataReader {
public:
    virtual ~IMetadataReader() = default;
    virtual std::optional<domain::Track> read(const std::filesystem::path& path) = 0;
};

class IAudioPlayer {
public:
    virtual ~IAudioPlayer() = default;
    virtual void open(const domain::PlaybackItem&) = 0;
    virtual void clear() = 0;
    virtual void play() = 0;
    virtual void pause() = 0;
    virtual void stop() = 0;
    virtual void seek(std::chrono::milliseconds) = 0;
    virtual void setVolume(float normalized) = 0;
    [[nodiscard]] virtual float volume() const noexcept = 0;
    virtual void setMuted(bool muted) = 0;
    [[nodiscard]] virtual bool muted() const noexcept = 0;
    [[nodiscard]] virtual domain::PlaybackState state() const noexcept = 0;
    [[nodiscard]] virtual std::chrono::milliseconds position() const noexcept = 0;
    [[nodiscard]] virtual std::chrono::milliseconds duration() const noexcept = 0;
    [[nodiscard]] virtual bool seekable() const noexcept = 0;
    [[nodiscard]] virtual std::optional<domain::PlaybackError> lastError() const = 0;
    [[nodiscard]] virtual std::optional<domain::AudioFormatInfo> audioFormat() const = 0;
    virtual void setEvents(PlaybackEvents events) = 0;
};

class IPlaybackBackend {
public:
    virtual ~IPlaybackBackend() = default;
    [[nodiscard]] virtual std::string_view name() const noexcept = 0;
    [[nodiscard]] virtual bool available() const noexcept = 0;
    virtual std::uint32_t capabilities() const noexcept = 0;
    virtual void setBackendEvents(PlaybackBackendEvents events) = 0;
};

class IAudioDeviceService {
public:
    virtual ~IAudioDeviceService() = default;
    [[nodiscard]] virtual std::vector<AudioDeviceInfo> devices() const = 0;
    [[nodiscard]] virtual std::string selectedDeviceId() const = 0;
    virtual bool select(std::string_view id) = 0;
    virtual void refresh() = 0;
    virtual void setDeviceEvents(AudioDeviceEvents events) = 0;
};

class IEqualizerService {
public:
    virtual ~IEqualizerService() = default;
    virtual bool supported() const noexcept = 0;
    // Optional DSP controls.  Backends that do not expose a given effect may
    // keep the default false implementation without widening the player port.
    virtual bool setBandGain(std::size_t, float) { return false; }
    virtual bool setReverb(float) { return false; }
};

class IOnlineProvider {
public:
    virtual ~IOnlineProvider() = default;
    virtual domain::ProviderId id() const = 0;
    virtual std::vector<domain::Track> search(const std::string& query) const = 0;
    virtual std::vector<domain::Playlist> playlists() const = 0;
};

class ISourceHostClient {
public:
    virtual ~ISourceHostClient() = default;
    virtual bool start() = 0;
    virtual void stop() noexcept = 0;
    virtual bool loadPlugin(const std::filesystem::path& path) = 0;
    virtual void cancel(const std::string& requestId) = 0;
};

} // namespace listenfree::application
