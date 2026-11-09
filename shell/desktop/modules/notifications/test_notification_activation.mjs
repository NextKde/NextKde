import assert from "node:assert/strict";
import { chooseWindow, desktopIdOf, planClick } from "./NotificationActivation.mjs";

const windowRecord = (windowId, minimized) => ({
    windowId, toplevel: { minimized, activated: false }
});

// Identity
assert.equal(desktopIdOf({ desktopEntry: "org.kde.dolphin.desktop" }), "org.kde.dolphin");
assert.equal(desktopIdOf({ desktopEntry: "  firefox  " }), "firefox");
assert.equal(desktopIdOf({ appName: "Firefox" }), "");
assert.equal(desktopIdOf(null), "");

// A running app is raised, not started.
assert.deepEqual(
    planClick({ desktopEntry: "firefox.desktop" }, [windowRecord("window-2", false)]),
    { kind: "activate", desktopId: "firefox", windowId: "window-2" });

// The visible window wins over a minimized sibling.
assert.equal(chooseWindow([
    windowRecord("minimized-a", true),
    windowRecord("visible-b", false),
    windowRecord("visible-c", false)
]), "visible-b", "prefers a window that is already on screen");

// All windows minimized: restoring any of them is still a clear answer, and the
// most recently used one comes first.
assert.equal(chooseWindow([windowRecord("a", true), windowRecord("b", true)]), "a");
assert.equal(chooseWindow([]), "");
assert.equal(chooseWindow(undefined), "");

// Nothing running: launch through the Dock path so the window still animates in.
assert.deepEqual(
    planClick({ desktopEntry: "org.kde.dolphin.desktop" }, []),
    { kind: "launch", desktopId: "org.kde.dolphin", windowId: "" });

// No app identity at all: fall back to the notification's own default action.
assert.deepEqual(
    planClick({ appName: "Some tray app", actions: [{ identifier: "default" }] }, []),
    { kind: "defaultAction", desktopId: "", windowId: "" });

// Nothing to do: report it so the surface keeps the card instead of closing it.
assert.deepEqual(planClick({ appName: "Some tray app", actions: [] }, []),
    { kind: "none", desktopId: "", windowId: "" });
assert.deepEqual(planClick(null, []), { kind: "none", desktopId: "", windowId: "" });

console.log("Notification activation: plan and window selection tests passed");
