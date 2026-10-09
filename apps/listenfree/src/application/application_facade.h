#pragma once

#include "domain/domain.h"

#include <QObject>
#include <QString>
#include <vector>

namespace listenfree::application {

class ApplicationFacade final : public QObject {
    Q_OBJECT
public:
    explicit ApplicationFacade(QObject* parent = nullptr);

    void initializeMock();
    [[nodiscard]] bool ready() const noexcept { return ready_; }
    [[nodiscard]] const std::vector<domain::Track>& tracks() const noexcept { return tracks_; }
    [[nodiscard]] const domain::PlaybackQueue& queue() const noexcept { return queue_; }
    [[nodiscard]] domain::PlaybackState playbackState() const noexcept { return playbackState_; }

signals:
    void readyChanged();
    void playbackStateChanged();

private:
    bool ready_{false};
    std::vector<domain::Track> tracks_;
    domain::PlaybackQueue queue_;
    domain::PlaybackState playbackState_{domain::PlaybackState::Idle};
};

} // namespace listenfree::application
