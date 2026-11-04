#pragma once

#include <algorithm>
#include <array>

namespace KWin {

// Keep the fixed overlay during desktop navigation, while other fullscreen
// effects (overview, lock/logout, etc.) retain exclusive screen ownership.
template<typename Effect>
bool stageOverlayAllowed(bool locked, const Effect *active,
                         const std::array<const Effect *, 3> &desktopEffects)
{
    return !locked && (!active
        || std::find(desktopEffects.begin(), desktopEffects.end(), active) != desktopEffects.end());
}

} // namespace KWin
