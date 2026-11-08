// Only the Dock's pinned presentation is substituted. Explicit launcher
// choices and running KDE windows retain their own identities.
const legacyRoles = {
    "org.kde.dolphin.desktop": "finder",
    "org.kde.konsole.desktop": "terminal",
    "org.kde.kate.desktop": "text",
    "org.kde.kwrite.desktop": "text",
    "org.kde.gwenview.desktop": "photos",
    "org.kde.dragonplayer.desktop": "video",
    "org.kde.elisa.desktop": "music",
    "org.kde.kcalc.desktop": "calculator",
    "org.kde.plasma-systemmonitor.desktop": "taskmanager",
    "org.kde.spectacle.desktop": "screenshot",
    "org.kde.discover.desktop": "appstore",
    "org.kde.kmail2.desktop": "mail"
};

export function preferredId(state, role) {
    if (state?.enabled !== true)
        return "";
    const app = (state.applications || []).find(app => app.role === role && app.installed === true);
    return app?.desktopId || "";
}

export function resolvePinnedId(state, desktopId) {
    const id = String(desktopId || "");
    // KOS's settings entry is never replaced by the optional Forma suite,
    // including a pre-existing Forma Settings pin left by an older setup.
    if (id === "io.github.egely1337.Mayonnaise.Settings.desktop")
        return "kos-settings.desktop";
    if (state?.enabled !== true)
        return id;
    if (id === "systemsettings.desktop" || id === "kdesystemsettings.desktop")
        return "kos-settings.desktop";
    return preferredId(state, legacyRoles[id]) || id;
}
