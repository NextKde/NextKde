// What a notification click means. Kept pure so the decision can be tested
// without a compositor: the click raises the window the app already has, starts
// the app when nothing is running, and otherwise lets the notification act for
// itself.

export function desktopIdOf(notification) {
    return String(notification?.desktopEntry || "").trim().replace(/\.desktop$/i, "")
}

export function chooseWindow(windows) {
    if (!windows || windows.length === 0)
        return ""
    // A window that is already on screen is what the click asks to raise;
    // restoring a minimized twin instead would cover the visible one. Window
    // records arrive most recently used first.
    for (const window of windows) {
        if (!window?.toplevel?.minimized)
            return String(window.windowId || "")
    }
    return String(windows[0]?.windowId || "")
}

export function planClick(notification, windows) {
    const desktopId = desktopIdOf(notification)
    const windowId = chooseWindow(windows)
    if (windowId)
        return { kind: "activate", desktopId, windowId }
    if (desktopId)
        return { kind: "launch", desktopId, windowId: "" }
    // Some daemons send only an app name, so there is nothing to launch. Let
    // the notification act for itself when it carries a default action.
    const actions = Array.isArray(notification?.actions) ? notification.actions : []
    if (actions.some(action => action?.identifier === "default"))
        return { kind: "defaultAction", desktopId: "", windowId: "" }
    return { kind: "none", desktopId: "", windowId: "" }
}
