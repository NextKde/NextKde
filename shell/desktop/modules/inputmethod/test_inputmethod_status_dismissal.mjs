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
assert.match(statusQml, /onPressed:\s*root\.menuOpen\s*=\s*false/,
    "the dismissal catcher closes menu on outside click");
assert.match(statusQml, /WlrLayershell\.layer:\s*WlrLayer\.Overlay/,
    "the dismissal catcher is placed on WlrLayer.Overlay");
assert.match(statusQml, /WlrLayershell\.keyboardFocus:\s*WlrKeyboardFocus\.None/,
    "the dismissal catcher does not steal keyboard focus");
assert.match(statusQml, /grabFocus:\s*true/,
    "menuPopup requests Wayland grabFocus for native modal dismissal");

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

// 5. Global blur inheritance (blurOverrideEnabled + AppearanceConfigService.globalBlurStrength)
assert.match(statusQml, /blurOverrideEnabled:\s*true/,
    "InputMethodStatus enables blurOverrideEnabled to drive per-surface blur channel");
assert.match(statusQml, /blurStrength:\s*AppearanceConfigService\.globalBlurStrength/,
    "InputMethodStatus binds blurStrength to globalBlurStrength");
assert.match(popupQml, /blurOverrideEnabled:\s*true/,
    "InputMethodPopup enables blurOverrideEnabled to drive per-surface blur channel");
assert.match(popupQml, /blurStrength:\s*AppearanceConfigService\.globalBlurStrength/,
    "InputMethodPopup binds blurStrength to globalBlurStrength");
assert.doesNotMatch(statusQml, /blurStrength:\s*Math\.max\(0\.40/,
    "InputMethodStatus does not hardcode a 0.40 blurStrength floor");
assert.doesNotMatch(popupQml, /blurStrength:\s*Math\.max\(0\.40/,
    "InputMethodPopup does not hardcode a 0.40 blurStrength floor");

// 6. Clean tip text (strips virtual caret | in tip mode)
assert.match(popupQml, /cleanTipText/,
    "InputMethodPopup defines cleanTipText to strip orphan | cursors from tips");
assert.match(popupQml, /replace\(\/\\\|\/g,\s*""\)/,
    "cleanTipText strips | characters");

// 7. Stable motion & no positioner conflicts
assert.doesNotMatch(popupQml, /anchors\.baseline:\s*mainText\.baseline/,
    "InputMethodPopup avoids anchors.baseline inside Row positioner");
assert.doesNotMatch(popupQml, /anchors\.baseline:\s*vMainText\.baseline/,
    "InputMethodPopup avoids anchors.baseline inside vertical candidate Row positioner");
assert.doesNotMatch(popupQml, /transform:\s*Translate/,
    "InputMethodPopup eliminates jarring Translate motion on candidate popup");

console.log("input method status dismissal & blur contract: ok");
