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
assert.match(card, /scrimOpacity:\s*root\.glassOpacity/,
    "the KWin scrim fades with the card's page factor, not just its content")
assert.match(placement, /c\.glassOpacity = Qt\.binding\(function\(\)\s*\{\s*return panel\.pageFactor\(c\.pageTag\)\s*\}/,
    "a card's compositor glass fades with its page so no blurred ghost is left")

// A PopupWindow anchored to the layer-shell Bar cannot take a Wayland popup
// grab here, so an explicit full-screen catcher has to stay behind the panel:
// without it a press on the desktop or on the Bar leaves the panel open.
assert.match(panel, /id:\s*dismissalCatcher/,
    "the outside-press catcher stays declared")
assert.match(panel, /onPressed:\s*panel\.close\(\)/,
    "the outside-press catcher dismisses the panel")
assert.match(panel, /visible:[\s\S]{0,200}panel\.isOpen/,
    "the catcher covers a deferred open as well as a mapped panel")

// A popup measures its anchor once, when its window is created, so an open
// request that arrives while the auto-hiding Bar is still put away must wait
// for the Bar to settle before the window exists -- otherwise the panel
// anchors to the hidden Bar and overlaps it once the Bar slides back.
assert.match(panel, /readonly property bool anchorSettled:[\s\S]{0,80}barRevealProgress/,
    "the panel gates its window on the Bar's settled reveal")
assert.match(panel, /onAnchorSettledChanged:[\s\S]{0,160}coordinator\.openAll\(\)/,
    "the deferred open runs once the Bar settles")
assert.match(panel, /readonly property bool isOpen:\s*coordinator\.open \|\| panel\.pendingOpen/,
    "a deferred open already reads as open, so the Bar reveals for it")

console.log("control-center submenu state contract: ok")
