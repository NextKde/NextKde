import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

// The desktop menu, the persisted setting and the free-slot grid must agree
// on the alignment contract. The pure column mapping is exercised by
// tests/desktop-density/test_metrics.mjs; this check keeps the QML wiring in
// place so the menu cannot silently set a value the grid ignores.
const deskcenter = readFileSync(
    new URL("../../shell/desktop/modules/deskcenter/DeskCenterWindow.qml", import.meta.url), "utf8");
const freeslot = readFileSync(
    new URL("../../shell/desktop/modules/deskcenter/FreeSlotDesktopDemo.qml", import.meta.url), "utf8");
const service = readFileSync(
    new URL("../../shell/desktop/modules/deskcenter/DesktopFilesService.qml", import.meta.url), "utf8");

assert.match(deskcenter, /function setShortcutAlignment\(alignment\)/);
assert.match(deskcenter, /case "setShortcutAlignment": setShortcutAlignment\(v\)/);
assert.ok(!deskcenter.includes('I18n.tr("Shortcut Alignment")'),
    'alignment belongs in the Arrange submenu, not a separate one');
const arrangeStart = deskcenter.indexOf("const arrange = [");
const arrangeEnd = deskcenter.indexOf('items.push(_ctxSub(I18n.tr("Arrange"), arrange');
assert.ok(arrangeStart >= 0 && arrangeEnd > arrangeStart,
    'Arrange submenu construction moved; update this test');
const arrange = deskcenter.slice(arrangeStart, arrangeEnd);
assert.match(arrange, /I18n\.tr\("Align Left"\)/);
assert.match(arrange, /I18n\.tr\("Align Right"\)/);
assert.match(deskcenter,
    /alignment: desktopFileGrid\.desktopLayout\.shortcutAlignment/);
assert.match(service, /property string shortcutAlignment: "right"/);
assert.match(freeslot, /property string alignment: "right"/);
assert.match(freeslot, /alignment === "left"/);
assert.match(freeslot, /DesktopGridMetrics\.columnForSlot/);
assert.match(freeslot, /DesktopGridMetrics\.slotForCell/);

console.log("Desktop shortcut alignment: menu, persistence and grid agree");
