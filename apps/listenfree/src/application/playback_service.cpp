#include "application/playback_service.h"

#include <algorithm>
#include <utility>

namespace listenfree::application {

PlaybackService::PlaybackService(IAudioPlayer& player) : player_(player) {
    PlaybackEvents events;
    events.onStateChanged = [this](domain::PlaybackState) {
        if (events_.onStateChanged) events_.onStateChanged();
    };
    events.onPositionChanged = [this](std::chrono::milliseconds position) {
        updateLyricPosition(position);
        if (events_.onPositionChanged) events_.onPositionChanged();
    };
    events.onDurationChanged = [this](std::chrono::milliseconds) {
        if (events_.onDurationChanged) events_.onDurationChanged();
    };
    events.onSeekableChanged = [this](bool) {
        if (events_.onSeekableChanged) events_.onSeekableChanged();
    };
    events.onVolumeChanged = [this](float) {
        if (events_.onVolumeChanged) events_.onVolumeChanged();
    };
    events.onMutedChanged = [this](bool) {
        if (events_.onMutedChanged) events_.onMutedChanged();
    };
    events.onFinished = [this] { handleFinished(); };
    events.onErrorChanged = [this](std::optional<domain::PlaybackError>) {
        if (events_.onErrorChanged) events_.onErrorChanged();
    };
    events.onAudioFormatChanged = [this](std::optional<domain::AudioFormatInfo>) {
        if (events_.onAudioFormatChanged) events_.onAudioFormatChanged();
    };
    player_.setEvents(std::move(events));
}

PlaybackService::~PlaybackService() {
    player_.setEvents({});
}

void PlaybackService::setQueue(std::vector<domain::PlaybackItem> items, std::size_t currentIndex) {
    player_.clear();
    queue_.clear();
    for (auto& item : items) queue_.enqueue(std::move(item));
    if (!queue_.empty()) queue_.select(std::min(currentIndex, queue_.items().size() - 1));
    notifyQueueSelectionChanged();
}

const domain::PlaybackItem* PlaybackService::currentItem() const noexcept {
    if (queue_.empty()) return nullptr;
    return &queue_.items()[queue_.currentIndex()];
}

bool PlaybackService::select(std::size_t index, bool playImmediately) {
    if (!queue_.select(index)) return false;
    notifyQueueSelectionChanged();
    if (playImmediately) return playCurrent();
    player_.clear();
    return true;
}

bool PlaybackService::remove(std::size_t index) {
    if (index >= queue_.items().size()) return false;
    const bool removedCurrent = index == queue_.currentIndex();
    const bool resumePlayback = player_.state() == domain::PlaybackState::Playing;
    if (!queue_.remove(index)) return false;
    if (events_.onQueueChanged) events_.onQueueChanged();
    if (!removedCurrent) return true;

    clearLyrics();
    if (events_.onCurrentItemChanged) events_.onCurrentItemChanged();
    if (queue_.empty()) {
        player_.clear();
        return true;
    }
    if (resumePlayback) return playCurrent();
    player_.clear();
    return true;
}

bool PlaybackService::move(std::size_t from, std::size_t to) {
    if (!queue_.move(from, to)) return false;
    if (events_.onQueueChanged) events_.onQueueChanged();
    return true;
}

bool PlaybackService::playCurrent() {
    const auto* item = currentItem();
    if (item == nullptr) {
        player_.clear();
        return false;
    }
    player_.open(*item);
    player_.play();
    return true;
}

bool PlaybackService::next() {
    if (!queue_.next()) return false;
    notifyQueueSelectionChanged();
    return playCurrent();
}

void PlaybackService::setLyrics(std::vector<domain::LyricLine> lyrics) {
    std::stable_sort(lyrics.begin(), lyrics.end(), [](const auto& left, const auto& right) {
        return left.start < right.start;
    });
    const bool hadCurrent = currentLyricIndex_.has_value();
    lyrics_ = std::move(lyrics);
    currentLyricIndex_.reset();
    if (events_.onLyricsChanged) events_.onLyricsChanged();
    updateLyricPosition(player_.position());
    if (hadCurrent && !currentLyricIndex_ && events_.onCurrentLyricChanged) {
        events_.onCurrentLyricChanged();
    }
}

std::optional<domain::LyricLine> PlaybackService::currentLyricLine() const {
    if (!currentLyricIndex_) return std::nullopt;
    return lyrics_[*currentLyricIndex_];
}

void PlaybackService::handleFinished() {
    next();
}

void PlaybackService::updateLyricPosition(std::chrono::milliseconds position) {
    std::optional<std::size_t> nextIndex;
    const auto upper = std::upper_bound(lyrics_.begin(), lyrics_.end(), position,
                                        [](auto value, const domain::LyricLine& line) {
                                            return value < line.start;
                                        });
    if (upper != lyrics_.begin()) {
        const auto candidate = static_cast<std::size_t>(std::distance(lyrics_.begin(), upper) - 1);
        const auto& line = lyrics_[candidate];
        if (position >= line.start && position < line.end) nextIndex = candidate;
    }
    if (currentLyricIndex_ == nextIndex) return;
    currentLyricIndex_ = nextIndex;
    if (events_.onCurrentLyricChanged) events_.onCurrentLyricChanged();
}

void PlaybackService::notifyQueueSelectionChanged() {
    clearLyrics();
    if (events_.onQueueChanged) events_.onQueueChanged();
    if (events_.onCurrentItemChanged) events_.onCurrentItemChanged();
}

void PlaybackService::clearLyrics() {
    const bool hadLyrics = !lyrics_.empty();
    const bool hadCurrent = currentLyricIndex_.has_value();
    lyrics_.clear();
    currentLyricIndex_.reset();
    if (hadLyrics && events_.onLyricsChanged) events_.onLyricsChanged();
    if (hadCurrent && events_.onCurrentLyricChanged) events_.onCurrentLyricChanged();
}

} // namespace listenfree::application
