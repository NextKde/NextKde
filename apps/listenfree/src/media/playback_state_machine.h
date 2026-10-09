#pragma once

#include "domain/domain.h"

namespace listenfree::media {

enum class BackendMediaStatus {
    NoMedia,
    Loading,
    Loaded,
    Stalled,
    Buffering,
    Buffered,
    EndOfMedia,
    Invalid
};

enum class BackendPlaybackState { Stopped, Playing, Paused };

struct PlaybackObservation {
    BackendMediaStatus mediaStatus{BackendMediaStatus::NoMedia};
    BackendPlaybackState playbackState{BackendPlaybackState::Stopped};
    bool hasSource{false};
    bool hasError{false};
    bool stoppedByUser{false};
    bool opening{false};
};

struct PlaybackReduction {
    domain::PlaybackState state{domain::PlaybackState::Idle};
    bool finished{false};
};

[[nodiscard]] PlaybackReduction reducePlaybackState(PlaybackObservation observation) noexcept;

} // namespace listenfree::media
