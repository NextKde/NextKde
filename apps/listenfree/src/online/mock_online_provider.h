#pragma once

#include "application/ports.h"

#include <vector>

namespace listenfree::online {

class MockOnlineProvider final : public application::IOnlineProvider {
public:
    [[nodiscard]] domain::ProviderId id() const override { return domain::ProviderId("mock"); }
    [[nodiscard]] std::vector<domain::Track> search(const std::string& query) const override;
    [[nodiscard]] std::vector<domain::Playlist> playlists() const override;
};

} // namespace listenfree::online
