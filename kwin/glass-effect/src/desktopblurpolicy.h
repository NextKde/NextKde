#pragma once

#include <optional>

namespace KWin
{
// DeskCenter is a Below-layer Quickshell Dock so native Overview cannot
// mistake its transparent surface for wallpaper. Top/Overlay panels retain
// their independent Dock material and empty-region policy.
inline bool isDesktopWidgetSurface(bool isQuickshell, bool isDock, bool isBelowLayer)
{
    return isQuickshell && isDock && isBelowLayer;
}

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
