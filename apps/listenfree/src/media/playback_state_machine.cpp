#include "media/playback_state_machine.h"

namespace listenfree::media {

PlaybackReduction reducePlaybackState(PlaybackObservation observation) noexcept {
    if (!observation.hasSource) return {domain::PlaybackState::Idle, false};
    if (observation.hasError || observation.mediaStatus == BackendMediaStatus::Invalid) {
        return {domain::PlaybackState::Error, false};
    }
    if (observation.stoppedByUser) return {domain::PlaybackState::Stopped, false};

    switch (observation.mediaStatus) {
    case BackendMediaStatus::NoMedia:
    case BackendMediaStatus::Loading:
        return {domain::PlaybackState::Loading, false};
    case BackendMediaStatus::Stalled:
    case BackendMediaStatus::Buffering:
        return {domain::PlaybackState::Buffering, false};
    case BackendMediaStatus::EndOfMedia:
        return {domain::PlaybackState::Stopped, true};
    case BackendMediaStatus::Invalid:
        return {domain::PlaybackState::Error, false};
    case BackendMediaStatus::Loaded:
    case BackendMediaStatus::Buffered:
        break;
    }

    // Qt can report the previous source's Loaded+Stopped pair while setSource()
    // is opening a replacement. Preserve Loading until the new status arrives.
    if (observation.opening) return {domain::PlaybackState::Loading, false};

    switch (observation.playbackState) {
    case BackendPlaybackState::Playing: return {domain::PlaybackState::Playing, false};
    case BackendPlaybackState::Paused: return {domain::PlaybackState::Paused, false};
    case BackendPlaybackState::Stopped: return {domain::PlaybackState::Stopped, false};
    }
    return {domain::PlaybackState::Error, false};
}

} // namespace listenfree::media
