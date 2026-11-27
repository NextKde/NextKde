import assert from "node:assert/strict";
import { collectUnavailableDesktopInstances, friendlyReason, toList }
    from "./WidgetGalleryDiagnostics.mjs";

// 1. toList handles sequence wrappers and rejects strings.
assert.deepEqual(toList({ 0: "a", 1: "b", length: 2 }), ["a", "b"]);
assert.deepEqual(toList("hello"), []);
assert.deepEqual(toList(null), []);

// 2. friendlyReason translates known codes.
assert.ok(friendlyReason("sdk-too-old", "").includes("过旧"));
assert.ok(friendlyReason("api-too-old", "").includes("系统"));
assert.equal(friendlyReason("unknown", "custom err"), "custom err");

// 3. Style-parked instances are excluded; invalid/crashed/missing are included.
const retired = {
    0: { id: "org.example.mat#1", packageId: "org.example.mat" },
    1: { id: "org.example.old#2", packageId: "org.example.old" },
    2: { id: "org.example.crash#3", packageId: "org.example.crash" },
    3: { id: "org.example.gone#4", packageId: "org.example.gone" },
    length: 4
};
const catalog = [
    { id: "org.example.mat", available: true, style: "material" },
    { id: "org.example.crash", available: true, style: "macos" }
];
const invalid = [
    { id: "org.example.old", code: "sdk-too-old", reason: "old" }
];
const tripped = [
    { id: "org.example.crash", revision: "1-2", reason: "Crashed" }
];

const unavailable = collectUnavailableDesktopInstances(retired, catalog, "macos", invalid, tripped);
assert.equal(unavailable.length, 3);
assert.equal(unavailable[0].packageId, "org.example.old");
assert.equal(unavailable[0].code, "sdk-too-old");
assert.equal(unavailable[1].packageId, "org.example.crash");
assert.equal(unavailable[1].code, "crashed");
assert.equal(unavailable[2].packageId, "org.example.gone");
assert.equal(unavailable[2].code, "missing");

console.log("DeskCenter widget gallery diagnostics tests passed");
