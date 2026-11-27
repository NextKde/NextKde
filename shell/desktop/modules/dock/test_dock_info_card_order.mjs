import assert from "node:assert/strict";
import { DEFAULT_INFO_CARD_ORDER, cardIdOf, isValidInfoCardId, isValidPackageId,
    migrateInfoCardId, normalizeInfoCardOrder, supportsContainer } from "./DockInfoCardOrder.mjs";

assert.deepEqual(DEFAULT_INFO_CARD_ORDER, [
    "org.nextkde.dock.music", "org.nextkde.dock.weather",
    "org.nextkde.dock.clock", "org.nextkde.dock.system"]);
assert.equal(isValidPackageId("org.nextkde.example.clock"), true);
assert.equal(isValidPackageId("invalid"), false);
assert.equal(isValidPackageId("bad_underscore.example.a"), false);
assert.equal(migrateInfoCardId("clock"), "org.nextkde.dock.clock");
assert.equal(migrateInfoCardId("temperature"), "org.nextkde.dock.system");
assert.equal(isValidInfoCardId("clock"), true);
assert.equal(isValidInfoCardId("org.nextkde.example.clock"), true);
assert.equal(isValidInfoCardId("unknown"), false);

assert.deepEqual(
    normalizeInfoCardOrder(["temperature", "org.nextkde.example.clock", "clock", "bad_id", "org.nextkde.example.clock"]),
    ["org.nextkde.dock.system", "org.nextkde.example.clock", "org.nextkde.dock.clock"]
);
assert.deepEqual(normalizeInfoCardOrder({ 0: "music", 1: "org.a.b", length: 2 }), ["org.nextkde.dock.music", "org.a.b"]);
assert.equal(cardIdOf({ id: "org.a.b.macos", dockCardId: "org.a.b" }), "org.a.b");
assert.equal(cardIdOf({ id: "org.a.b" }), "org.a.b");

assert.equal(supportsContainer({ id: "a" }, "desktop"), true);
assert.equal(supportsContainer({ id: "a" }, "dock"), false);
assert.equal(supportsContainer({ id: "a", containers: { 0: "desktop", 1: "dock", length: 2 } }, "dock"), true);
assert.equal(supportsContainer({ id: "a", containers: ["dock"] }, "desktop"), false);

console.log("Dock info card order tests passed");
