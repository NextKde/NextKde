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
assert.doesNotMatch(closeSubmenu, /activeSubmenu\s*=\s*""/)

const submenuMotion = panel.slice(
    panel.indexOf("id: submenuCard"),
    panel.indexOf("// Navigation Header")
)
assert.match(submenuMotion, /cardShown:\s*panel\.submenuOpen/)
assert.match(submenuMotion, /onMotionClosed:/)
assert.match(submenuMotion, /panel\.activeSubmenu\s*=\s*""/)
assert.match(submenuMotion, /coordinator\.modalActive\s*=\s*false/)

assert.match(card, /root\.cardShown \|\| root\.motionMapped/)
assert.match(card, /root\.managedByCoordinator[\s\S]*root\.cardShown \|\| root\.motionMapped/)

console.log("control-center submenu state contract: ok")
