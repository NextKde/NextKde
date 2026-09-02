// DockAutoHideMath.mjs — Pure collision/policy math for the Dock show modes.
// ES module with no QML/NPM dependencies, mirroring AdaptiveMath.mjs.
//
// Collision judgement ALWAYS uses the static rectangle the dock would occupy at
// full reveal — never the animated transform position — so a controller can
// evaluate without racing its own animation (see docs/DockArchitecture.md,
// "Visibility modes and auto-hide").

export function round(value) {
    return Math.round(value);
}

// ── §7.1 Static fully-visible dock/bar rectangle ──
// Logical coordinates throughout; never multiply by devicePixelRatio.
export function visibleDockRect(screenRect, position, dockWidth, dockHeight, edgeMargin) {
    if (position === "top") {
        return {
            x: screenRect.x + edgeMargin,
            y: screenRect.y,
            width: dockWidth,
            height: dockHeight
        };
    }
    if (position === "bottom") {
        return {
            x: screenRect.x + (screenRect.width - dockWidth) / 2,
            y: screenRect.y + screenRect.height - edgeMargin - dockHeight,
            width: dockWidth,
            height: dockHeight
        };
    }
    if (position === "left") {
        return {
            x: screenRect.x + edgeMargin,
            y: screenRect.y + (screenRect.height - dockHeight) / 2,
            width: dockWidth,
            height: dockHeight
        };
    }
    // right
    return {
        x: screenRect.x + screenRect.width - edgeMargin - dockWidth,
        y: screenRect.y + (screenRect.height - dockHeight) / 2,
        width: dockWidth,
        height: dockHeight
    };
}

// §7.3 The 8px expanded rect is the entry trigger; the 16px expanded rect is
// the exit trigger, so a window parked on the critical few pixels does not make
// the dock flap.
export function avoidanceRect(baseRect) {
    return expandRect(baseRect, 8);
}
export function releaseRect(baseRect) {
    return expandRect(baseRect, 16);
}

export function expandRect(rect, amount) {
    return {
        x: rect.x - amount,
        y: rect.y - amount,
        width: rect.width + amount * 2,
        height: rect.height + amount * 2
    };
}

export function intersects(a, b) {
    return a.x < b.x + b.width
        && b.x < a.x + a.width
        && a.y < b.y + b.height
        && b.y < a.y + a.height;
}

// §7.2 Eligibility. The provider already ran its includeWindow() filter; here
// we only enforce desktop/screen/geometry/minimize membership.
export function windowEligible(window, targetScreen, currentDesktopId) {
    if (!window || typeof window !== "object")
        return false;
    if (!window.geometry || window.geometry.width <= 0 || window.geometry.height <= 0)
        return false;
    if (window.isMinimized)
        return false;
    if (!window.onAllDesktops) {
        const onCurrent = Array.isArray(window.desktopIds)
            && window.desktopIds.indexOf(String(currentDesktopId || "")) >= 0;
        if (!onCurrent)
            return false;
    }
    const onScreen = (window.screenName && window.screenName === targetScreen?.name)
        || intersects(window.geometry, targetScreen);
    return onScreen;
}

// §7.3/§7.6 Returns true when any eligible window overlaps the dock's space.
// Fullscreen windows on the target screen always force a conflict.
export function hasConflict(windows, targetScreen, avoidanceRect, releaseRect, previousConflict, currentDesktopId) {
    if (!Array.isArray(windows))
        return false;
    // Hysteresis: while already conflicting, require the window to leave the
    // wider release rect before declaring the dock's space free again.
    const activeRect = previousConflict ? releaseRect : avoidanceRect;
    for (let i = 0; i < windows.length; i++) {
        const window = windows[i];
        if (!windowEligible(window, targetScreen, currentDesktopId))
            continue;
        // Fullscreen on the target screen is an unconditional conflict.
        if (window.isFullscreen && intersects(window.geometry, targetScreen))
            return true;
        if (window.isFullscreen)
            continue;
        if (intersects(window.geometry, activeRect))
            return true;
    }
    return false;
}

// §8.2 Policy — the single source of truth for a desired visibility.
export function shouldBeVisible(mode, hasConflict, hasInhibitor) {
    if (mode === "always")
        return true;
    if (mode === "persistent")
        return hasInhibitor;
    // smart
    return !hasConflict || hasInhibitor;
}

// Yes: persistent must not become visible just because the desktop is empty.
export function policyWantsHidden(mode, hasConflict) {
    if (mode === "always")
        return false;
    if (mode === "persistent")
        return true;
    return hasConflict; // smart
}

// §6.4 Home Indicator sizes. Bottom: 80% of screen width tall 4px; side:
// 4px wide by 80% of screen height.
export function handleSizes(screenWidth, screenHeight, position) {
    if (position === "bottom") {
        return { width: round(screenWidth * 0.80), height: 4 };
    }
    return { width: 4, height: round(screenHeight * 0.80) };
}

// §6.3 Auxiliary visual values derived from the single reveal progress p.
export function dockOpacity(progress) {
    return 0.30 + 0.70 * progress;
}
export function dockScale(progress) {
    return 0.985 + 0.015 * progress;
}
export function handleOpacity(progress) {
    return Math.max(0, Math.min(1, (0.42 - progress) / 0.24));
}