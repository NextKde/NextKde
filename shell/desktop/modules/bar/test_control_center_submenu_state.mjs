import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

// The Control Center is one window now. The per-card motion model that used to
// gate this contract (a card reporting motionClosed so the panel could clear
// activeSubmenu and unpin the primary cards) is gone, so the assertions below
// follow the closed-form state machine that replaced it:
//
// There is no outgoing submenu animation in the single-window implementation.
// Both close paths must synchronously clear activeSubmenu; otherwise toggle()
// sees an invisible stale page as open and consumes the next button press.
const here = dirname(fileURLToPath(import.meta.url))
const panel = readFileSync(join(here, "ControlCenterPanel.qml"), "utf8")
const card = readFileSync(join(here, "ControlCenterCard.qml"), "utf8")

const closeSubmenu = panel.slice(
    panel.indexOf("function closeSubmenu()"),
    panel.indexOf("function openSettingsModule")
)
assert.match(closeSubmenu, /submenuOpen\s*=\s*false/)
assert.match(closeSubmenu, /activeSubmenu\s*=\s*""/,
    "back navigation clears the page identity synchronously")

const closePanel = panel.slice(
    panel.indexOf("function close()"),
    panel.indexOf("function openSessionPanel")
)
assert.match(closePanel, /activeSubmenu\s*=\s*""/,
    "closing the panel always clears stale submenu identity")
assert.match(closePanel, /submenuOpen\s*=\s*false/,
    "close() always drops the submenu-open flag")

// The retired per-card motion model must stay retired: a reappearing
// motionClosed gate would silently reintroduce a second source of truth.
assert.doesNotMatch(panel, /onMotionClosed/,
    "the per-card motion gate stays removed")
assert.doesNotMatch(panel, /motionMapped/,
    "cards no longer mirror the panel's motion state")

assert.match(panel, /signal wifiNetworkSelected\(var network\)/,
    "the real control-center Wi-Fi list exposes its credential-dialog route")
assert.match(panel, /panel\.wifiNetworkSelected\(network\)/,
    "unknown secured networks are routed to the credential dialog")

const submenuCard = panel.slice(
    panel.indexOf("id: submenuCard"),
    panel.indexOf("// Navigation Header")
)
assert.match(submenuCard, /cardShown:\s*panel\.submenuOpen/,
    "the submenu page is driven straight off submenuOpen")
assert.match(submenuCard, /coordinator:\s*coordinator/)
assert.match(submenuCard, /managedByCoordinator:\s*false/,
    "the submenu card opts out of the retired coordinator model")

// A card's visibility is exactly its own flag; no suppression veil remains.
assert.match(card, /visible:\s*root\.cardShown\b/,
    "card visibility is exactly cardShown")
assert.doesNotMatch(card, /visuallySuppressed|motionMapped/,
    "cards carry no leftover suppression state")

console.log("control-center submenu state contract: ok")
