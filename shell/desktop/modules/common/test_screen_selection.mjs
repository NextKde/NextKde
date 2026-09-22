import assert from "node:assert/strict";
import { selectScreen } from "./ScreenSelection.mjs";

const internal = { name: "eDP-1", x: 0, y: 0, width: 1920, height: 1080 };
const external = { name: "DP-2", x: 1920, y: 0, width: 2560, height: 1440 };
const portrait = { name: "HDMI-A-1", x: -1080, y: -420, width: 1080, height: 1920 };
const screens = [internal, external, portrait];

assert.equal(selectScreen(screens, [
    { name: "eDP-1", priority: 2, connected: true, enabled: true },
    { name: "DP-2", priority: 1, connected: true, enabled: true },
], internal), external, "KScreen priority must override Qt screen order");

assert.equal(selectScreen(screens, [
    { name: "missing", priority: 1, connected: true, enabled: true },
], portrait), portrait, "a still-connected current screen must survive missing metadata");

assert.equal(selectScreen([internal, external], [], null), external,
    "the geometric fallback must choose the screen nearest the desktop center");
assert.equal(selectScreen([external], [], null), external);
assert.equal(selectScreen([], [], external), null);

assert.equal(selectScreen(screens, [
    { name: "DP-2", priority: 1, connected: false, enabled: true },
    { name: "HDMI-A-1", priority: 2, connected: true, enabled: false },
], internal), internal, "disabled and disconnected metadata must be ignored");

console.log("Screen selection: priority, order independence and fallbacks passed.");
