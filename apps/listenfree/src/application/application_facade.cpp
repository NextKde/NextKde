#include "application/application_facade.h"

namespace listenfree::application {

ApplicationFacade::ApplicationFacade(QObject* parent) : QObject(parent) {}

void ApplicationFacade::initializeMock() {
    if (ready_) return;

    domain::Track first;
    first.id = domain::TrackId("mock-track-1");
    first.title = "Mock Sunrise";
    first.artists.push_back({"mock-artist-1", "ListenFree"});
    first.duration = std::chrono::seconds(183);

    domain::Track second;
    second.id = domain::TrackId("mock-track-2");
    second.title = "Mock Night Drive";
    second.artists.push_back({"mock-artist-2", "ListenFree"});
    second.duration = std::chrono::seconds(211);

    tracks_ = {first, second};
    queue_.enqueue(domain::PlaybackItem{first, std::nullopt});
    queue_.enqueue(domain::PlaybackItem{second, std::nullopt});
    ready_ = true;
    emit readyChanged();
}

} // namespace listenfree::application
