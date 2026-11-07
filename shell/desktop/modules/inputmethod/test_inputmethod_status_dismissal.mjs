import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const statusQml = readFileSync(join(here, "InputMethodStatus.qml"), "utf8");
const popupQml = readFileSync(join(here, "InputMethodPopup.qml"), "utf8");

// 1. Outside-press dismissal catcher
assert.match(statusQml, /id:\s*dismissalCatcher/,
    "InputMethodStatus declares an outside-press dismissal catcher");
assert.match(statusQml, /screen:\s*root\.targetScreen/,
    "the dismissal catcher binds to targetScreen");
assert.match(statusQml, /onPressed:\s*root\.menuOpen\s*=\s*false/,
    "the dismissal catcher closes menu on outside click");
assert.match(statusQml, /WlrLayershell\.layer:\s*WlrLayer\.Top/,
    "the dismissal catcher is placed on WlrLayer.Top");
assert.match(statusQml, /WlrLayershell\.keyboardFocus:\s*WlrKeyboardFocus\.None/,
    "the dismissal catcher does not steal keyboard focus");

// 2. Window focus loss handling
assert.match(statusQml, /target:\s*WindowService[\s\S]*?onActiveWindowIdChanged/,
    "InputMethodStatus monitors WindowService.activeWindowIdChanged to auto-dismiss on focus loss");

// 3. Context menu coordination
assert.match(statusQml, /ContextMenuCoordinator\.open\(menuCoordinatorAdapter\)/,
    "InputMethodStatus registers with ContextMenuCoordinator on open");
assert.match(statusQml, /ContextMenuCoordinator\.release\(menuCoordinatorAdapter\)/,
    "InputMethodStatus releases from ContextMenuCoordinator on close");
assert.match(statusQml, /target:\s*ContextMenuCoordinator[\s\S]*?onActiveMenuChanged/,
    "InputMethodStatus monitors ContextMenuCoordinator to auto-dismiss when another menu opens");

// 4. Escape key dismissal
assert.match(statusQml, /Shortcut\s*\{[\s\S]*?sequence:\s*"Escape"/,
    "InputMethodStatus defines an Escape shortcut");

// 5. Global blur inheritance (no hardcoded 40% floor)
assert.doesNotMatch(statusQml, /blurStrength:\s*Math\.max\(0\.40/,
    "InputMethodStatus does not hardcode a 0.40 blurStrength floor");
assert.doesNotMatch(popupQml, /blurStrength:\s*Math\.max\(0\.40/,
    "InputMethodPopup does not hardcode a 0.40 blurStrength floor");

console.log("input method status dismissal & blur contract: ok");
