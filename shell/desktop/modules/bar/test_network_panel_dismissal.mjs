import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const here = dirname(fileURLToPath(import.meta.url))
const panel = readFileSync(join(here, "NetworkPanel.qml"), "utf8")

// 1. Outside-press dismissal catcher
assert.match(panel, /id:\s*dismissalCatcher/,
    "NetworkPanel declares an outside-press dismissal catcher")
assert.match(panel, /screen:\s*panel\.targetScreen/,
    "the dismissal catcher binds to targetScreen")
assert.match(panel, /onPressed:\s*panel\.close\(\)/,
    "the dismissal catcher calls panel.close() on outside click")
assert.match(panel, /visible:[\s\S]*?panel\.requestedOpen[\s\S]*?!networkDialogOverlay\.requestedOpen/,
    "the catcher is visible when requestedOpen and credential dialog is not open")
assert.match(panel, /WlrLayershell\.layer:\s*WlrLayer\.Top/,
    "the dismissal catcher is placed on WlrLayer.Top")
assert.match(panel, /WlrLayershell\.keyboardFocus:\s*WlrKeyboardFocus\.None/,
    "the dismissal catcher does not steal keyboard focus")

// 2. Window focus loss handling
assert.match(panel, /target:\s*WindowService[\s\S]*?onActiveWindowIdChanged/,
    "NetworkPanel monitors WindowService.activeWindowIdChanged to auto-dismiss on focus loss")

// 3. Context menu coordination
assert.match(panel, /target:\s*ContextMenuCoordinator[\s\S]*?onActiveMenuChanged/,
    "NetworkPanel monitors ContextMenuCoordinator to auto-dismiss when menus open")

// 4. Escape key dismissal
assert.match(panel, /Shortcut\s*\{[\s\S]*?sequence:\s*"Escape"/,
    "NetworkPanel defines an Escape shortcut")

console.log("network panel dismissal contract: ok")
