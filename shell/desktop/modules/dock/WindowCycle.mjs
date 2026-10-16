// WindowCycle.mjs — pure calculation for cycling application windows on Dock click.

/**
 * Determine which window of an application should be activated next.
 *
 * @param {Array} windows - Array of window records for the app (from WindowService.windowsForApp).
 * @param {string} [activeWindowId] - ID of the currently active window, or null/empty if none.
 * @param {Function} [lastActivatedAtOf] - Function returning last activation timestamp for a windowId.
 * @param {string} [pendingWindowId] - ID of recently requested window for rapid-click lag guard.
 * @param {number} [pendingAgeMs] - Age in milliseconds since pendingWindowId was requested.
 * @returns {object|null} The window record to activate, or null if no windows exist.
 */
export function nextWindowToActivate(windows, activeWindowId, lastActivatedAtOf, pendingWindowId = "", pendingAgeMs = Infinity) {
    if (!windows || windows.length === 0)
        return null;
    if (windows.length === 1)
        return windows[0];

    // Find if any window of this app is currently activated
    let activeIdx = -1;
    for (let i = 0; i < windows.length; i++) {
        const win = windows[i];
        if ((activeWindowId && win.windowId === activeWindowId)
                || (win.toplevel && win.toplevel.activated)) {
            activeIdx = i;
            break;
        }
    }

    // Lag guard for rapid clicks: if we recently requested activation of a
    // window in this group and KWin's snapshot hasn't reflected it yet,
    // advance from that requested window instead of repeating the step.
    if (pendingWindowId && pendingAgeMs < 800) {
        for (let i = 0; i < windows.length; i++) {
            if (windows[i].windowId === pendingWindowId) {
                activeIdx = i;
                break;
            }
        }
    }

    if (activeIdx === -1) {
        // App not currently in foreground: activate MRU window
        if (!lastActivatedAtOf)
            return windows[0];
        return windows.reduce((a, b) =>
            lastActivatedAtOf(a.windowId) >= lastActivatedAtOf(b.windowId) ? a : b);
    }

    // App already active: cycle to next window in group (stable window list order).
    // (Note: dynamically sorting by MRU here would cause an oscillation trap
    // between the top 2 windows because every activation swaps ranks 0 and 1.)
    const nextIdx = (activeIdx + 1) % windows.length;
    return windows[nextIdx];
}
