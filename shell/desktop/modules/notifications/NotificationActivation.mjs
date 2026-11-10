// What a notification click means. Kept pure so the decision can be tested
// without a compositor: the click raises the window the app already has, starts
// the app when nothing is running, and otherwise lets the notification act for
// itself.
//
// Desktop notifications are unreliable about identity: many apps (Electron
// wrappers such as QQ and QQ Music among them) send only an app name, and some
// send an icon name instead of `desktop-entry`. Falling back to the
// notification's own default action there starts a second copy of an app that
// is already running, so the window search accepts any evidence the
// notification carries and matches it against every tracked window.

function token(value) {
    return String(value ?? "")
        .trim()
        .toLowerCase()
        .replace(/\.desktop$/i, "")
        .replace(/\s+/g, " ");
}

function iconName(value) {
    const text = String(value ?? "").trim();
    if (!text)
        return "";
    // Icons arrive as theme names or absolute file paths; only the basename is
    // an application identifier.
    const base = text.split("/").pop() || "";
    return base.replace(/\.(png|svg|xpm|ico)$/i, "");
}

export function desktopIdOf(notification) {
    return String(notification?.desktopEntry || "").trim().replace(/\.desktop$/i, "");
}

// Every value the notification offers that can name the sending application,
// strongest first.
export function identityCandidates(notification) {
    const values = [];
    const push = value => {
        const text = String(value ?? "").trim();
        if (!text || values.indexOf(text) >= 0)
            return;
        values.push(text);
        const withoutSuffix = text.replace(/\.desktop$/i, "");
        if (withoutSuffix !== text && values.indexOf(withoutSuffix) < 0)
            values.push(withoutSuffix);
    };
    push(notification?.desktopEntry);
    const hints = notification?.hints;
    if (hints && typeof hints === "object") {
        push(hints["desktop-entry"]);
        push(hints.desktopEntry);
    }
    const icon = iconName(notification?.appIcon);
    if (icon)
        push(icon);
    push(notification?.appName);
    return values;
}

function matchTier(window, notification, idCandidates, appNameToken) {
    const ids = [token(window?.desktopId), token(window?.rawAppId)].filter(Boolean);
    if (ids.some(id => idCandidates.indexOf(id) >= 0))
        return 3;
    if (appNameToken) {
        if (token(window?.name) === appNameToken)
            return 2;
        if (ids.indexOf(appNameToken) >= 0)
            return 2;
    }
    return 0;
}

// Best running window for the notification, or "" when nothing matches.
export function matchWindow(windows, notification) {
    if (!windows || windows.length === 0)
        return "";
    const idCandidates = identityCandidates(notification)
        .filter(value => token(value) !== token(notification?.appName))
        .map(token)
        .filter(Boolean);
    const appNameToken = token(notification?.appName);
    let best = null;
    for (const window of windows) {
        const tier = matchTier(window, notification, idCandidates, appNameToken);
        if (tier <= 0)
            continue;
        // Inside a tier, a window that is already on screen is what the click
        // asks to raise; restoring a minimized twin instead would cover it.
        const score = tier * 10 + (window?.minimized === true ? 0 : 1);
        if (!best || score > best.score)
            best = { window, score };
    }
    return best ? String(best.window.windowId || "") : "";
}

export function planClick(notification, windows, resolvedDesktopId = "") {
    const windowId = matchWindow(windows, notification);
    if (windowId)
        return { kind: "activate", desktopId: resolvedDesktopId, windowId };
    // Only the caller's live DesktopEntry lookup authorizes a launch. An
    // arbitrary notification hint (or a synthesized identity) is not an entry.
    const launchId = String(resolvedDesktopId || "").trim();
    if (launchId)
        return { kind: "launch", desktopId: launchId, windowId: "" };
    // Some daemons send only an app name and nothing is installed under it.
    // Let the notification act for itself when it carries a default action.
    if (defaultAction(notification))
        return { kind: "defaultAction", desktopId: "", windowId: "" };
    return { kind: "none", desktopId: "", windowId: "" };
}

export function defaultAction(notification) {
    // Notification.actions is a QML sequence, not necessarily a JS Array.
    const actions = notification?.actions;
    for (let i = 0; i < (actions?.length || 0); ++i) {
        if (actions[i]?.identifier === "default")
            return actions[i];
    }
    return null;
}

let requestSequence = 0;
export function nextTicket() {
    return "notification-open-" + (++requestSequence);
}
