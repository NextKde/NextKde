#pragma once

#include "application/ports.h"

#include <functional>
#include <optional>
#include <utility>
#include <vector>

namespace listenfree::application {

struct PlaybackServiceEvents {
    std::function<void()> onStateChanged;
    std::function<void()> onPositionChanged;
    std::function<void()> onDurationChanged;
    std::function<void()> onSeekableChanged;
    std::function<void()> onVolumeChanged;
    std::function<void()> onMutedChanged;
    std::function<void()> onErrorChanged;
    std::function<void()> onAudioFormatChanged;
    std::function<void()> onQueueChanged;
    std::function<void()> onCurrentItemChanged;
    std::function<void()> onLyricsChanged;
    std::function<void()> onCurrentLyricChanged;
};

class PlaybackService final {
public:
    explicit PlaybackService(IAudioPlayer& player);
    ~PlaybackService();

    PlaybackService(const PlaybackService&) = delete;
    PlaybackService& operator=(const PlaybackService&) = delete;

    void setQueue(std::vector<domain::PlaybackItem> items, std::size_t currentIndex = 0);
    [[nodiscard]] const domain::PlaybackQueue& queue() const noexcept { return queue_; }
    [[nodiscard]] const domain::PlaybackItem* currentItem() const noexcept;
    bool select(std::size_t index, bool playImmediately = false);
    bool remove(std::size_t index);
    bool move(std::size_t from, std::size_t to);
    bool playCurrent();
    bool next();

    void setLyrics(std::vector<domain::LyricLine> lyrics);
    [[nodiscard]] const std::vector<domain::LyricLine>& lyrics() const noexcept { return lyrics_; }
    [[nodiscard]] std::optional<std::size_t> currentLyricIndex() const noexcept {
        return currentLyricIndex_;
    }
    [[nodiscard]] std::optional<domain::LyricLine> currentLyricLine() const;

    void setEvents(PlaybackServiceEvents events) { events_ = std::move(events); }

private:
    void handleFinished();
    void updateLyricPosition(std::chrono::milliseconds position);
    void notifyQueueSelectionChanged();
    void clearLyrics();

    IAudioPlayer& player_;
    domain::PlaybackQueue queue_;
    std::vector<domain::LyricLine> lyrics_;
    std::optional<std::size_t> currentLyricIndex_;
    PlaybackServiceEvents events_;
};

} // namespace listenfree::application
