#pragma once

#include <chrono>
#include <cstdint>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace listenfree::domain {

template <typename Tag>
class StrongId {
public:
    StrongId() = default;
    explicit StrongId(std::string value) : value_(std::move(value)) {}
    [[nodiscard]] bool empty() const noexcept { return value_.empty(); }
    [[nodiscard]] const std::string& value() const noexcept { return value_; }
    friend bool operator==(const StrongId&, const StrongId&) = default;
private:
    std::string value_;
};

struct ProviderIdTag {};
struct TrackIdTag {};
struct PlaylistIdTag {};
using ProviderId = StrongId<ProviderIdTag>;
using TrackId = StrongId<TrackIdTag>;
using PlaylistId = StrongId<PlaylistIdTag>;

struct Artist {
    std::string id;
    std::string name;
    friend bool operator==(const Artist&, const Artist&) = default;
};

struct Album {
    std::string id;
    std::string title;
    std::optional<std::string> artworkUrl;
    friend bool operator==(const Album&, const Album&) = default;
};

struct Track {
    TrackId id;
    std::string title;
    std::vector<Artist> artists;
    std::optional<Album> album;
    std::chrono::milliseconds duration{0};
    std::optional<std::string> localPath;
    std::optional<std::string> remoteUrl;
};

struct PlaylistEntry {
    std::string entryId;
    TrackId trackId;
    std::int32_t position{0};
};

struct Playlist {
    PlaylistId id;
    std::string title;
    std::vector<PlaylistEntry> entries;
};

struct PlaybackItem {
    Track track;
    std::optional<std::string> resolvedUrl;
};

enum class PlaybackState { Idle, Loading, Playing, Paused, Stopped, Buffering, Error };

enum class PlaybackErrorCode { InvalidTransition, OpenFailed, Network, Unsupported, Internal };

struct PlaybackError {
    PlaybackErrorCode code{PlaybackErrorCode::Internal};
    std::string message;
    bool retryable{false};
    friend bool operator==(const PlaybackError&, const PlaybackError&) = default;
};

struct AudioFormatInfo {
    std::string codec;
    std::int32_t sampleRate{0};
    std::int32_t channels{0};
    std::int32_t bitrate{0};
    friend bool operator==(const AudioFormatInfo&, const AudioFormatInfo&) = default;
};

struct LyricLine {
    std::chrono::milliseconds start{0};
    std::chrono::milliseconds end{0};
    std::string text;
};

struct Account {
    ProviderId provider;
    std::string accountId;
    std::string displayName;
    bool loggedIn{false};
};

struct Chart {
    std::string id;
    std::string title;
    std::vector<Track> tracks;
};

class PlaybackQueue {
public:
    [[nodiscard]] const std::vector<PlaybackItem>& items() const noexcept { return items_; }
    [[nodiscard]] std::size_t currentIndex() const noexcept { return currentIndex_; }
    [[nodiscard]] bool empty() const noexcept { return items_.empty(); }
    bool enqueue(PlaybackItem item) {
        items_.push_back(std::move(item));
        return true;
    }
    bool remove(std::size_t index) {
        if (index >= items_.size()) return false;
        const bool beforeCurrent = index < currentIndex_;
        items_.erase(items_.begin() + static_cast<std::ptrdiff_t>(index));
        if (items_.empty()) currentIndex_ = 0;
        else if (beforeCurrent) --currentIndex_;
        else if (currentIndex_ >= items_.size()) currentIndex_ = items_.size() - 1;
        return true;
    }
    bool select(std::size_t index) {
        if (index >= items_.size()) return false;
        currentIndex_ = index;
        return true;
    }
    bool next() {
        if (items_.empty() || currentIndex_ + 1 >= items_.size()) return false;
        ++currentIndex_;
        return true;
    }
    bool move(std::size_t from, std::size_t to) {
        if (from >= items_.size() || to >= items_.size()) return false;
        if (from == to) return true;
        auto item = std::move(items_[from]);
        items_.erase(items_.begin() + static_cast<std::ptrdiff_t>(from));
        items_.insert(items_.begin() + static_cast<std::ptrdiff_t>(to), std::move(item));
        if (currentIndex_ == from) currentIndex_ = to;
        else if (from < currentIndex_ && to >= currentIndex_) --currentIndex_;
        else if (from > currentIndex_ && to <= currentIndex_) ++currentIndex_;
        return true;
    }
    void clear() noexcept { items_.clear(); currentIndex_ = 0; }
private:
    std::vector<PlaybackItem> items_;
    std::size_t currentIndex_{0};
};

} // namespace listenfree::domain
