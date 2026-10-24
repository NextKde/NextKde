#pragma once

#include <optional>

namespace KWin
{
// Desktop surfaces must opt in with bounded client content. In the legacy KDE
// protocol an empty region means the whole window, which is unsafe for a
// fullscreen desktop: it would frost the wallpaper and the spaces between cards.
template<typename Region>
bool desktopSurfaceRequestsBlur(bool isQuickshell, bool explicitlyRequested,
                                const std::optional<Region> &content)
{
    return isQuickshell && explicitlyRequested && content.has_value() && !content->isEmpty();
}
}
