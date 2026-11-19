import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

// The desktop icon-size menu and its persistence setter must expose the same
// tiers. A check on the real source catches an option the setter silently
// rejects, or a tier that cannot be reached from the UI.
const source = readFileSync(
    new URL("../../shell/desktop/modules/deskcenter/DeskCenterWindow.qml", import.meta.url), "utf8");

for (const size of [32, 40, 56, 72]) {
    assert.ok(source.includes(`size !== ${size}`),
        `setIconSize must accept ${size}`);
    assert.ok(source.includes(`[${size}, I18n.tr(`),
        `icon-size menu must expose ${size}`);
}
assert.ok(source.includes('[32, I18n.tr("Extra Small")]'),
    "Extra Small must be the 32 px tier");

console.log("Desktop icon sizes: menu and setter expose the same four tiers");
