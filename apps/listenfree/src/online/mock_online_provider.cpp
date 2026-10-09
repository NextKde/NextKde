#include "online/mock_online_provider.h"

namespace listenfree::online {

std::vector<domain::Track> MockOnlineProvider::search(const std::string& query) const {
    domain::Track track;
    track.id = domain::TrackId("mock-online-1");
    track.title = query.empty() ? "Mock Recommendation" : "Mock " + query;
    track.artists.push_back({"mock-online-artist", "ListenFree Provider"});
    track.duration = std::chrono::seconds(200);
    return {track};
}

std::vector<domain::Playlist> MockOnlineProvider::playlists() const {
    domain::Playlist playlist;
    playlist.id = domain::PlaylistId("mock-playlist");
    playlist.title = "Mock Playlist";
    return {playlist};
}

} // namespace listenfree::online
