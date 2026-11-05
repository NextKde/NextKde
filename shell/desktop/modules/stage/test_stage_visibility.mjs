// Run the production drawer decisions without duplicating their JavaScript.
// QML binding delivery and compositor desktop switching still need a VM.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";
import * as StageGroups from "./stage-groups.mjs";

const sidebar = readFileSync(new URL("StageSidebarWindow.qml", import.meta.url), "utf8");
function source(pattern, label) {
    const match = sidebar.match(pattern);
    assert.ok(match, `${label} moved; update the production source slice`);
    return match[1];
}
function functionBody(name) {
    return source(new RegExp(
        `    function ${name}\\(\\): (?:bool|real) \\{([\\s\\S]*?)\\n    \\}`), name);
}
const overlapBody = functionBody("_computeStripOverlap");
const fullscreenBody = functionBody("_computeDesktopFullscreen");
const overlapChangedBody = source(
    /    on_StripOverlapChanged: \{([\s\S]*?)\n    \}/, "overlap change handler");
const debounceBody = source(
    /property Timer _yieldDebounce: Timer \{[\s\S]*?onTriggered: ([^\n]+)/,
    "yield debounce handler");

function fixture() {
    const service = { records: [], placementRevision: 0, currentDesktopId: "desk1" };
    const reads = new Set();
    const root = {
        rightSide: false, width: 1920, height: 1080, panelW: 240, _stripInset: 20,
        _stripYield: false, _stripOverlap: 0,
        _yieldDebounce: {
            running: false,
            restart() { this.running = true; },
            stop() { this.running = false; },
        },
    };
    const context = vm.createContext({
        root, StageGroups,
        ConfigService: { barHeight: 35, baseHeight: 40 },
        WindowService: new Proxy(service, {
            get(target, key) { reads.add(key); return target[key]; },
        }),
        _yieldEngage: Number(source(/readonly property real _yieldEngage: ([\d.]+)/,
            "yield engage threshold")),
        _yieldRelease: Number(source(/readonly property real _yieldRelease: ([\d.]+)/,
            "yield release threshold")),
        get _stripOverlap() { return root._stripOverlap; },
    });
    const compile = body => vm.runInContext(`(function() {${body}\n})`, context);
    const overlap = compile(overlapBody);
    const fullscreen = compile(fullscreenBody);
    const overlapChanged = compile(overlapChangedBody);
    const debounce = compile(debounceBody);
    return {
        service, root, reads, overlap, fullscreen,
        refreshOverlap() {
            const next = overlap();
            if (next !== root._stripOverlap) {
                root._stripOverlap = next;
                overlapChanged();
            }
        },
        fireDebounce() {
            assert.equal(root._yieldDebounce.running, true);
            root._yieldDebounce.running = false;
            debounce();
        },
    };
}

// WindowService exposes desktop membership on the normalized record as well
// as on its KWin toplevel snapshot.
function record({ desktopIds = ["desk1"], onAllDesktops = false,
    minimized = false, visible = true, fullscreen = false,
    geometry = { x: 20, y: 100, width: 240, height: 800 } } = {}) {
    return { desktopIds, onAllDesktops,
        toplevel: { desktopIds, onAllDesktops, minimized, visible, fullscreen, geometry } };
}

test("empty desktop keeps the drawer expanded", () => {
    const f = fixture();
    assert.equal(f.overlap(), 0);
    assert.equal(f.fullscreen(), false);
    assert.equal(f.root._stripYield, false);
});

test("switching desktop recomputes overlap without a window snapshot", () => {
    const f = fixture();
    const records = [record()];
    f.service.records = records;
    assert.equal(f.overlap(), 1);
    f.service.currentDesktopId = "desk2";
    f.reads.clear();
    assert.equal(f.overlap(), 0);
    assert.equal(f.service.records, records);
    assert.equal(f.service.placementRevision, 0);
    assert.equal(f.reads.has("currentDesktopId"), true);
    assert.equal(f.reads.has("placementRevision"), true);
});

test("switching to a clear desktop cancels a pending retraction", () => {
    const f = fixture();
    f.service.records = [record()];
    f.refreshOverlap();
    assert.equal(f.root._yieldDebounce.running, true);
    f.service.currentDesktopId = "desk2";
    f.refreshOverlap();
    assert.equal(f.root._yieldDebounce.running, false);
    assert.equal(f.root._stripYield, false);
});

test("switching away from an occluded desktop releases an existing yield", () => {
    const f = fixture();
    f.service.records = [record()];
    f.refreshOverlap();
    f.fireDebounce();
    assert.equal(f.root._stripYield, true);
    f.service.currentDesktopId = "desk2";
    f.refreshOverlap();
    assert.equal(f.root._stripYield, false);
    f.service.currentDesktopId = "desk1";
    f.refreshOverlap();
    assert.equal(f.root._yieldDebounce.running, true);
    assert.equal(f.root._stripYield, false);
    f.fireDebounce();
    assert.equal(f.root._stripYield, true);
});

test("windows on all desktops still retract the drawer", () => {
    const f = fixture();
    f.service.currentDesktopId = "desk2";
    f.service.records = [record({ onAllDesktops: true, desktopIds: [], fullscreen: true })];
    assert.equal(f.overlap(), 1);
    assert.equal(f.fullscreen(), true);
});

test("hidden, minimized and other desktop windows do not retract the drawer", () => {
    const f = fixture();
    for (const state of [{ minimized: true }, { visible: false }, { desktopIds: ["desk2"] }]) {
        f.service.records = [record({ ...state, fullscreen: true })];
        assert.equal(f.overlap(), 0, JSON.stringify(state));
        assert.equal(f.fullscreen(), false, JSON.stringify(state));
    }
});

test("moving a covering window away releases yield after a placement-only update", () => {
    const f = fixture();
    f.service.records = [record()];
    f.refreshOverlap();
    f.fireDebounce();
    f.service.records[0].toplevel.geometry.x = 500;
    f.service.placementRevision++;
    f.refreshOverlap();
    assert.equal(f.root._stripOverlap, 0);
    assert.equal(f.root._stripYield, false);
});

test("fullscreen detection observes placement-only visibility changes", () => {
    const f = fixture();
    f.service.records = [record({ fullscreen: true })];
    assert.equal(f.fullscreen(), true);
    f.service.records[0].toplevel.visible = false;
    f.service.placementRevision++;
    f.reads.clear();
    assert.equal(f.fullscreen(), false);
    assert.equal(f.reads.has("placementRevision"), true);
    assert.equal(f.reads.has("currentDesktopId"), true);
});

test("right sidebar detects overlap on the current desktop only", () => {
    const f = fixture();
    f.root.rightSide = true;
    f.service.records = [record({ geometry: { x: 1660, y: 100, width: 240, height: 800 } })];
    assert.equal(f.overlap(), 1);
    f.service.currentDesktopId = "desk2";
    assert.equal(f.overlap(), 0);
});

test("overlap hysteresis keeps its existing engage and release thresholds", () => {
    const f = fixture();
    f.service.records = [record({ geometry: { x: 20, y: 100, width: 144, height: 800 } })];
    f.refreshOverlap();
    assert.equal(f.root._yieldDebounce.running, false, "60% does not engage");
    f.service.records[0].toplevel.geometry.width = 145;
    f.refreshOverlap();
    f.fireDebounce();
    assert.equal(f.root._stripYield, true, "above 60% engages after debounce");
    f.service.records[0].toplevel.geometry.width = 120;
    f.refreshOverlap();
    assert.equal(f.root._stripYield, true, "50% retains yield");
    f.service.records[0].toplevel.geometry.width = 119;
    f.refreshOverlap();
    assert.equal(f.root._stripYield, false, "below 50% releases yield");
});
