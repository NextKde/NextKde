export function covered(screen, records, desktopId) {
    if (!screen) return true;
    return records.some(window => {
        if ((window.isMinimized ?? window.toplevel?.minimized) || window.isVisible === false) return false;
        const fullscreen = window.isFullscreen ?? window.toplevel?.fullscreen ?? false;
        if (desktopId && !window.onAllDesktops && window.desktopIds?.length
            && !window.desktopIds.includes(desktopId)) return false;
        if (window.screenName && window.screenName !== screen.name) return false;
        const geometry = window.geometry;
        if (fullscreen && window.screenName === screen.name) return true;
        if (!geometry) return false;
        return geometry.x <= screen.x + 8 && geometry.y <= screen.y + 64
            && geometry.x + geometry.width >= screen.x + screen.width - 8
            && geometry.y + geometry.height >= screen.y + screen.height - 100
            && (window.isMaximized || fullscreen);
    });
}
export function cadence(economical, onBattery, reduceMotion, locked, anyVisible) {
    return reduceMotion || locked || !anyVisible ? 0 : economical || onBattery ? 125 : 67;
}

// A normal floating window is enough to keep the desktop still. Windows on
// another virtual desktop and minimized/hidden windows do not block it.
export function hasVisibleWindows(records, desktopId) {
    return records.some(window => {
        if ((window.isMinimized ?? window.toplevel?.minimized) || window.isVisible === false) return false;
        if (desktopId && !window.onAllDesktops && window.desktopIds?.length
            && !window.desktopIds.includes(desktopId)) return false;
        return true;
    });
}
