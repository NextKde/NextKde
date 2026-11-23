// LauncherGeometry.mjs — pure sizing/placement math for AppLauncherWindow.
//
// Everything here is a plain function of screen, Dock and display-mode
// numbers, so the geometry can be unit tested without a compositor.
// AppLauncherWindow.qml only feeds these functions and renders the result.

const MINIMUM_LAUNCHER_HEIGHT = 500;

function dimension(value, fallback) {
    return value && value > 0 ? value : fallback;
}

// The compact presentations solve one landscape card for the bottom edge and
// transpose it beside a side Dock: a landscape card floating next to a
// vertical Dock reads as the wrong shape.
export function compactCardWidth({ isBottomWideMode, screenWidth, dockWidth,
    minimumLauncherWidth }) {
    const width = dimension(screenWidth, 1920);
    if (isBottomWideMode)
        return Math.round(width * 0.50);
    return dockWidth < minimumLauncherWidth ? minimumLauncherWidth : dockWidth;
}

export function compactCardHeight({ usesMinimumSize, screenHeight }) {
    if (usesMinimumSize)
        return MINIMUM_LAUNCHER_HEIGHT;
    return Math.round(dimension(screenHeight, 1080) * 0.50);
}

// A taskbar/relaxed side Dock reports its whole edge length as dockWidth
// (~screen height), so sizing the card from that number stretched the side
// presentation to 85% of the output. The side card is instead the transposed
// compact card, widened a touch and capped at two thirds of the output.
export function launcherSize({ displayMode, screenWidth, screenHeight,
    dockPosition, dockWidth }) {
    const width = dimension(screenWidth, 1920);
    const height = dimension(screenHeight, 1080);
    const isFullscreenMode = displayMode === "fullscreen";
    const isCenterMode = displayMode === "center";
    const isBottomWideMode = displayMode === "bottomWide";
    const dockAtBottom = dockPosition !== "left" && dockPosition !== "right";

    if (isFullscreenMode)
        return { width, height };
    if (isCenterMode) {
        return {
            width: Math.min(Math.max(680, Math.round(width * 0.65)), 1040),
            height: Math.min(Math.max(520, Math.round(height * 0.68)), 760),
        };
    }

    const minimumLauncherWidth = Math.round(width * 0.50);
    const usesMinimumSize = dockWidth < minimumLauncherWidth;
    const cardWidth = compactCardWidth({
        isBottomWideMode, screenWidth: width, dockWidth, minimumLauncherWidth,
    });
    const cardHeight = compactCardHeight({ usesMinimumSize, screenHeight: height });

    if (dockAtBottom)
        return { width: cardWidth, height: cardHeight };
    return {
        width: Math.max(cardHeight, Math.round(height * 0.55)),
        height: Math.min(cardWidth, Math.round(height * 2 / 3)),
    };
}

// Explicit placement, never a runtime anchor-set switch: Qt can retain the
// previous anchor set for a frame, which froze the card at the old output
// size after the Dock returned from a side edge.
export function revealRect({ isFullscreenMode, isCenterMode, dockPosition,
    width, height, parentWidth, parentHeight }) {
    if (isFullscreenMode)
        return { x: 0, y: 0, width: parentWidth, height: parentHeight };
    const x = (isCenterMode || dockPosition !== "left" && dockPosition !== "right")
        ? Math.round((parentWidth - width) / 2)
        : (dockPosition === "right" ? parentWidth - width : 0);
    const y = isCenterMode
        ? Math.round((parentHeight - height) / 2)
        : (dockPosition === "left" || dockPosition === "right"
            ? Math.round((parentHeight - height) / 2)
            : parentHeight - height);
    return { x, y, width, height };
}
