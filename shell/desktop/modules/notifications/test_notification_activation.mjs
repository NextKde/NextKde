import assert from "node:assert/strict";
import { desktopIdOf, identityCandidates, matchWindow, planClick } from "./NotificationActivation.mjs";

const window = (windowId, fields = {}) => Object.assign({
    windowId, desktopId: "", rawAppId: "", name: "", title: "", minimized: false
}, fields);

// ── identity evidence ──
assert.equal(desktopIdOf({ desktopEntry: "org.kde.dolphin.desktop" }), "org.kde.dolphin");
assert.equal(desktopIdOf({ appName: "Firefox" }), "");
assert.equal(desktopIdOf(null), "");

assert.deepEqual(identityCandidates({
    desktopEntry: "org.kde.dolphin.desktop",
    appName: "Dolphin",
    appIcon: "/usr/share/icons/hicolor/512x512/apps/dolphin.png"
}), ["org.kde.dolphin.desktop", "org.kde.dolphin", "dolphin", "Dolphin"]);

// Hints are the only identity some daemons send.
assert.deepEqual(identityCandidates({
    hints: { "desktop-entry": "firefox" }, appName: "Firefox"
}), ["firefox", "Firefox"]);

// ── an exact desktop entry raises the running window ──
assert.deepEqual(
    planClick({ desktopEntry: "firefox.desktop" },
        [window("window-1", { desktopId: "firefox.desktop", rawAppId: "firefox" })]),
    { kind: "activate", desktopId: "", windowId: "window-1" });

// A provider that reports the app as "QQ" still matches the "qq" entry.
assert.deepEqual(
    planClick({ desktopEntry: "qq" },
        [window("window-2", { desktopId: "qq.desktop", rawAppId: "QQ", name: "QQ" })]),
    { kind: "activate", desktopId: "", windowId: "window-2" });

// The visible window wins over a minimized twin inside the same tier.
assert.equal(matchWindow([
    window("minimized-a", { desktopId: "qqmusic.desktop", minimized: true }),
    window("visible-b", { desktopId: "qqmusic.desktop" })
], { desktopEntry: "qqmusic.desktop" }), "visible-b");

// ── missing identity: match the app by name instead of launching again ──
// Electron notifications often carry only an app name. QQ is the case that
// started a second copy of the running chat before this fallback existed.
assert.deepEqual(
    planClick({ appName: "QQ" },
        [window("qq-window", { desktopId: "qq.desktop", rawAppId: "QQ", name: "QQ" })]),
    { kind: "activate", desktopId: "", windowId: "qq-window" });

// The same name fallback covers a localized player name with no hints.
assert.deepEqual(
    planClick({ appName: "QQ音乐" },
        [window("music-window", { desktopId: "qqmusic.desktop", rawAppId: "qqmusic", name: "QQ音乐", minimized: true })]),
    { kind: "activate", desktopId: "", windowId: "music-window" });

// An icon name is identity evidence too.
assert.deepEqual(
    planClick({ appIcon: "/usr/share/icons/hicolor/512x512/apps/telegram.png" },
        [window("tg-window", { desktopId: "telegramdesktop.desktop", rawAppId: "TelegramDesktop" })])
        .kind, "none", "icon name only matches an id that carries it");
assert.deepEqual(
    planClick({ appIcon: "qqmusic" },
        [window("music-window", { desktopId: "qqmusic.desktop", rawAppId: "qqmusic" })]),
    { kind: "activate", desktopId: "", windowId: "music-window" });

// A lookalike name must not steal the click: the chat notification must not
// raise the music player window.
assert.equal(matchWindow([
    window("music-window", { desktopId: "qqmusic.desktop", name: "QQ音乐", title: "QQ音乐" })
], { appName: "QQ" }), "", "app names are compared exactly, not by prefix");

// ── nothing running: launch, using the resolved entry when the notification
//    itself carried no usable id ──
assert.deepEqual(
    planClick({ appName: "QQ" }, [], "qq.desktop"),
    { kind: "launch", desktopId: "qq.desktop", windowId: "" });
assert.deepEqual(
    planClick({ desktopEntry: "org.kde.dolphin.desktop" }, []),
    { kind: "none", desktopId: "", windowId: "" });

// ── no app identity and no running window: let the notification act ──
assert.deepEqual(
    planClick({ appName: "Some tray app", actions: [{ identifier: "default" }] }, []),
    { kind: "defaultAction", desktopId: "", windowId: "" });
assert.deepEqual(planClick({ appName: "Some tray app", actions: [] }, []),
    { kind: "none", desktopId: "", windowId: "" });
assert.deepEqual(planClick(null, []), { kind: "none", desktopId: "", windowId: "" });

console.log("Notification activation: identity, matching and plan tests passed");

// Uninstalled/stale desktop ids must not hide a usable default action.
assert.equal(planClick({ desktopEntry: "not.installed", actions: {
    0: { identifier: "default" }, length: 1
} }, []).kind, "defaultAction");
