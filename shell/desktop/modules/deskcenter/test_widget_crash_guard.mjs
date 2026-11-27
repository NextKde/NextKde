import assert from "node:assert/strict";
import { isTripped, listTripped, markLoadSettled, markLoadStart, parseMap,
    promotePendingToTripped, pruneRecovered, reEnable } from "./WidgetCrashGuardLogic.mjs";

// 1. Safe JSON parsing.
assert.deepEqual(parseMap("{}"), {});
assert.deepEqual(parseMap("[]"), {});
assert.deepEqual(parseMap("not-json"), {});

// 2. Normal load + settle does not trip on restart.
let pending = markLoadStart({}, "org.example.clock", "100-50", 1000);
const settled = markLoadSettled(pending, "org.example.clock");
assert.equal(settled.changed, true);
assert.deepEqual(settled.pending, {});
const cleanRestart = promotePendingToTripped(settled.pending, {}, 2000);
assert.deepEqual(cleanRestart.newlyTrippedIds, []);
assert.deepEqual(cleanRestart.tripped, {});

// 3. Crash before settle trips the widget on restart.
pending = markLoadStart({}, "org.example.bad", "200-80", 1000);
const crashedRestart = promotePendingToTripped(pending, {}, 5000);
assert.deepEqual(crashedRestart.newlyTrippedIds, ["org.example.bad"]);
assert.deepEqual(crashedRestart.pending, {});
assert.equal(isTripped(crashedRestart.tripped, "org.example.bad", "200-80"), true);
assert.equal(listTripped(crashedRestart.tripped).length, 1);
assert.equal(listTripped(crashedRestart.tripped)[0].id, "org.example.bad");

// 4. Editing/updating package revision auto-recovers the widget.
assert.equal(isTripped(crashedRestart.tripped, "org.example.bad", "201-82"), false);
const pruned = pruneRecovered(crashedRestart.tripped, "org.example.bad", "201-82");
assert.equal(pruned.changed, true);
assert.deepEqual(pruned.tripped, {});

// 5. Manual reEnable removes a tripped entry.
const manual = reEnable(crashedRestart.tripped, "org.example.bad");
assert.equal(manual.changed, true);
assert.deepEqual(manual.tripped, {});
assert.equal(reEnable(manual.tripped, "org.example.bad").changed, false);

console.log("DeskCenter widget crash guard tests passed");
