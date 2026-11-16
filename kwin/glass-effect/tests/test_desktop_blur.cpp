#include "../src/desktopblurpolicy.h"

#include <QRegion>
#include <stdexcept>

using namespace KWin;

static void check(bool condition, const char *message)
{
    if (!condition)
        throw std::runtime_error(message);
}

int main()
{
    check(isDesktopWidgetSurface(true, true, true),
          "Below-layer Quickshell Docks retain the desktop material policy");
    check(!isDesktopWidgetSurface(true, true, false),
          "Top/Overlay Dock and Bar retain the panel material policy");
    check(!isDesktopWidgetSurface(false, true, true),
          "other clients' Docks must not inherit DeskCenter policy");
    check(!isDesktopWidgetSurface(true, false, true),
          "the Stage strip is not a desktop widget surface");
    const std::optional<QRegion> cards = QRegion(QRect(20, 20, 144, 144))
        + QRegion(QRect(184, 20, 144, 144));
    check(desktopSurfaceRequestsBlur(true, true, cards),
          "Quickshell desktop widgets must retain their explicitly declared glass");
    check(!desktopSurfaceRequestsBlur(true, false, cards),
          "forced blur must not turn a desktop into glass");
    check(!desktopSurfaceRequestsBlur(false, true, cards),
          "ordinary Plasma desktops must retain their existing exclusion");
    check(!desktopSurfaceRequestsBlur(true, true, std::optional<QRegion>{}),
          "a wallpaper with no client region must not blur");
    check(!desktopSurfaceRequestsBlur(true, true, std::optional<QRegion>{QRegion()}),
          "legacy empty-region whole-window semantics must not frost a fullscreen desktop");
    check(!desktopSurfaceRequestsBlur(true, true, std::optional<QRegion>{QRect(20, 20, 0, 144)}),
          "hidden or zero-sized cards must not request whole-desktop glass");
    return 0;
}
