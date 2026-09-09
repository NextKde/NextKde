import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

// Execute the production QML functions, mocking only provider and ListModel.
const source = readFileSync(new URL("WindowService.qml", import.meta.url), "utf8");
// Also exercise the same update path after the independent indexing PR lands.
const usesIndex = source.includes("WindowRecordIndex.indexWindowRecords");
const WindowRecordIndex = usesIndex ? await import("./WindowRecordIndex.mjs") : null;
const names = ["_newWindowId", "_presentationEqual", "_placementEqual",
    "_updatePlacement", "geometriesEqual", "_rebuild"];
if (!usesIndex) names.push("_findOldRecord");
const functions = names.map(name => {
    const match = source.match(new RegExp(`^    function ${name}\\([^]*?^    }`, "m"));
    assert.ok(match, name);
    return match[0];
}).join("\n");
let writes = 0;
const rows = [];
const windowModel = {
    get count() { return rows.length; },
    get: i => rows[i],
    append: row => { writes++; rows.push(row); },
    remove: i => { writes++; rows.splice(i, 1); },
    setProperty: (i, key, value) => { writes++; rows[i][key] = value; },
};
const svc = { records: [], _kwinWindows: [], _nextWindowNumber: 1,
    revision: 0, placementRevision: 0, _recordsById: {} };
const context = vm.createContext({ svc, windowModel, WindowRecordIndex,
    _collectToplevels: () => [],
    AppIdentityService: { resolve: id => ({ desktopId: id, rawAppId: id, iconSource: id }) },
});
vm.runInContext(functions, context);
for (const name of names) svc[name] = context[name];
const window = id => ({ id, appId: id, title: id, desktops: ["desktop-1"],
    geometry: { x: 0, y: 0, width: 100, height: 100 }, visible: true });
svc._kwinWindows = [window("one"), window("two")];
svc._rebuild();
assert.equal(svc.revision, 1);
assert.equal(svc.placementRevision, 1);
const records = svc.records;
const record = records[0];
const byId = svc._recordsById;
writes = 0;
// All placement-only fields, including geometry loss and restoration.
for (const patch of [
    { geometry: { x: 500, y: 20, width: 90, height: 80 } },
    { outputName: "DP-2" }, { maximized: true }, { visible: false },
    { geometry: null }, { geometry: { x: 0, y: 0, width: 100, height: 100 } },
]) {
    svc._kwinWindows[0] = { ...svc._kwinWindows[0], ...patch };
    const previous = svc.placementRevision;
    svc._rebuild();
    assert.equal(svc.placementRevision, previous + 1);
    assert.equal(svc.revision, 1);
    assert.equal(svc.records, records);
    assert.equal(svc.records[0], record);
    assert.equal(svc._recordsById, byId);
    assert.equal(writes, 0);
}
assert.equal(record.geometry.x, 0);
assert.equal(record.screenName, "DP-2");
assert.equal(record.toplevel.outputName, "DP-2");
assert.equal(record.isVisible, false);
const unchanged = svc.placementRevision;
svc._rebuild();
assert.equal(svc.placementRevision, unchanged);
// Each presentation field must still wake both presentation and collision.
for (const patch of [{ title: "renamed" }, { activated: true }, { minimized: true },
    { fullscreen: true }, { urgent: true }, { desktops: ["desktop-2"] },
    { onAllDesktops: true }, { appId: "new-app" }, { iconPath: "/new.png" }, { pid: 123 }]) {
    const revision = svc.revision, placement = svc.placementRevision;
    svc._kwinWindows[0] = { ...svc._kwinWindows[0], ...patch };
    svc._rebuild();
    assert.equal(svc.revision, revision + 1);
    assert.equal(svc.placementRevision, placement + 1);
}
// Earlier placement differences must not hide a later presentation change.
svc._kwinWindows[0] = { ...svc._kwinWindows[0], geometry: null };
svc._kwinWindows[1] = { ...svc._kwinWindows[1], title: "second changed" };
let revision = svc.revision;
svc._rebuild();
assert.equal(svc.revision, revision + 1);
assert.equal(rows[1].title, "second changed");
const firstId = svc.records[0].windowId;
svc._kwinWindows.reverse();
svc._rebuild();
assert.equal(svc.records[1].windowId, firstId);
svc._kwinWindows = [];
svc._rebuild();
assert.equal(rows.length, 0);
assert.equal(svc.activeWindowId, "");
// Provider-owned foreign objects are read-only; placement updates cannot
// assign to them. Their normalized record still receives the new placement.
const foreign = { provider: "foreign", toplevel: Object.freeze({ visible: true }) };
svc._updatePlacement(foreign, { geometry: null, screenName: "", isMaximized: false,
    isVisible: false, toplevel: { visible: false } });
assert.equal(foreign.toplevel.visible, true);
assert.equal(foreign.isVisible, false);
for (const file of ["DockAutoHideController.qml", "../bar/BarAutoHideController.qml"]) {
    const controller = readFileSync(new URL(file, import.meta.url), "utf8");
    assert.match(controller, /function onPlacementRevisionChanged\(\)/);
    assert.match(controller, /function onCurrentDesktopIdChanged\(\)/);
}
console.log("window placement updates: passed");
