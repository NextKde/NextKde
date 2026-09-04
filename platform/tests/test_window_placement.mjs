import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const bridgePath = fileURLToPath(new URL("../kwin/window-bridge.js", import.meta.url));
const source = fs.readFileSync(bridgePath, "utf8");
const helpers = source.slice(0, source.indexOf("// Runtime-dependent bridge helpers"));
const context = vm.createContext({ Math, Number, String, JSON });
vm.runInContext(helpers, context, { filename: bridgePath });

const plain = value => JSON.parse(JSON.stringify(value));
const safeArea = layout => plain(context.safeAreaForLayout(layout));
const place = (frame, minimum, safe) =>
    plain(context.calculateInitialPlacement(frame, minimum, safe));

assert.equal(context.isMaximized({ maximizeMode: 3 }), true);
assert.equal(context.isMaximized({ maximizeMode: 1 }), false);
assert.equal(context.isMaximized({ maximizeMode: 2 }), false);
assert.equal(context.isMaximized({ maximized: { horizontal: true, vertical: true } }), true);

assert.deepEqual(safeArea({
    outputRect: { x: -1920, y: 0, width: 1920, height: 1080 },
    barReservedHeight: 35,
    dockPosition: "bottom",
    dockRect: { x: -1400, y: 1000, width: 880, height: 70 },
    workspaceGap: 8
}), { x: -1920, y: 35, width: 1920, height: 965 });

assert.deepEqual(safeArea({
    outputRect: { x: 0, y: -1080, width: 1920, height: 1080 },
    barReservedHeight: 30,
    dockPosition: "left",
    dockRect: { x: 0, y: -800, width: 80, height: 600 },
    workspaceGap: 6
}), { x: 80, y: -1050, width: 1840, height: 1050 });

assert.deepEqual(safeArea({
    outputRect: { x: 0, y: 0, width: 1600, height: 900 },
    barReservedHeight: 0,
    dockPosition: "right",
    dockRect: { x: 1520, y: 200, width: 80, height: 600 },
    workspaceGap: 4
}), { x: 0, y: 0, width: 1520, height: 900 });

assert.deepEqual(place(
    { x: -2100, y: -20, width: 2400, height: 1400 },
    { width: 100, height: 100 },
    { x: -1920, y: 35, width: 1920, height: 965 }
), { x: -1920, y: 35, width: 1920, height: 965 });

// An application's minimum size wins even when it cannot fit. The remaining
// overflow is deterministic and anchored to the safe area's top-left.
assert.deepEqual(place(
    { x: 400, y: 400, width: 500, height: 400 },
    { width: 1800, height: 1000 },
    { x: 0, y: 35, width: 1600, height: 857 }
), { x: 0, y: 35, width: 1800, height: 1000 });

console.log("window placement: ok");
