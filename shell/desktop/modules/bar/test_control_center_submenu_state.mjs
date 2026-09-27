import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

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
assert.match(submenuCard, /cardShown:\s*panel\.submenuShownPage\s*!==\s*""/,
    "the submenu card stays mapped while its page renders on either side of a crossfade")
assert.match(submenuCard, /pageTag:\s*panel\.submenuShownPage/,
    "the submenu card belongs to the page it is currently rendering")
assert.match(panel, /visible:\s*popupMotion\.mapped/,
    "the window remains mapped for its exit animation")
assert.match(panel, /readonly property bool open:\s*popupMotion\.requestedOpen/,
    "toggle state uses intent rather than the still-mapped closing surface")
assert.match(panel, /PageMotion\s*\{[\s\S]*?page:\s*panel\.requestedPage/,
    "one page motion owns presentation independently from logical navigation")
assert.match(submenuCard, /coordinator:\s*coordinator/)
assert.match(submenuCard, /managedByCoordinator:\s*false/,
    "the submenu card opts out of the retired coordinator model")

// A card's visibility is exactly its own flag; no suppression veil remains.
assert.match(card, /visible:\s*root\.cardShown\b/,
    "card visibility is exactly cardShown")
assert.doesNotMatch(card, /visuallySuppressed|motionMapped/,
    "cards carry no leftover suppression state")
assert.match(card, /Item\s*\{\s*id: root\s*default property alias content: cardContent\.data/,
    "external card content belongs to the animated host")
assert.match(card, /opacity:\s*root\.contentOpacity/,
    "content opacity is independent of the native glass")
const placement = panel.slice(panel.indexOf("function placeCard"), panel.indexOf("property bool _internalTransition"))
assert.match(placement, /c\.opacity = Qt\.binding\(function\(\)\s*\{\s*return panel\.pageFactor\(c\.pageTag\)\s*\}/,
    "a card fades glass and content together with its page")
assert.match(panel, /crossfade:\s*true/,
    "page navigation is a single continuous crossfade, not exit-then-enter")
assert.doesNotMatch(panel, /popupMotion\.progress > 0 && pageMotion\.progress > 0/,
    "navigation never drops the compositor blur region")
assert.match(card, /scrimOpacity:\\s*root\\.glassOpacity/,
    \"the KWin scrim fades with the card's page factor, not just its content\")
assert.match(placement, /c\\.glassOpacity = Qt\\.binding\\(function\\(\\)\\s*\\{\\s*return panel\\.pageFactor\\(c\\.pageTag\\)\\s*\\}/,
    \"a card's compositor glass fades with its page so no blurred ghost is left\")

console.log("control-center submenu state contract: ok")
