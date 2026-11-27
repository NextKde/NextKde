import assert from "node:assert/strict";
import { MAX_INSTANCE_CONFIG_BYTES, getInstanceConfig, parseConfigMap,
    removeInstanceConfig, setInstanceConfig, utf8ByteLength }
    from "./WidgetInstanceConfig.mjs";

// 1. parseConfigMap ignores invalid entries and non-object roots.
assert.deepEqual(parseConfigMap("[]"), {});
assert.deepEqual(parseConfigMap("bad-json"), {});
assert.deepEqual(parseConfigMap('{"a":{"x":1},"b":[1,2],"": {"x":2}}'), { a: { x: 1 } });

// 2. Per-instance isolation and deep-copy safety.
let map = {};
const input1 = { format24h: false, nested: { city: "Beijing" } };
const res1 = setInstanceConfig(map, "org.example.clock#1", input1);
assert.equal(res1.ok, true);
map = res1.map;
input1.format24h = true;
input1.nested.city = "Shanghai";
assert.deepEqual(getInstanceConfig(map, "org.example.clock#1"), { format24h: false, nested: { city: "Beijing" } });

const res2 = setInstanceConfig(map, "org.example.clock#2", { format24h: true });
assert.equal(res2.ok, true);
map = res2.map;
assert.deepEqual(getInstanceConfig(map, "org.example.clock#2"), { format24h: true });
assert.equal(getInstanceConfig(map, "org.example.clock#3"), null);

// 3. Rejects non-objects, arrays, and payloads > 64 KB (including multibyte UTF-8).
assert.equal(setInstanceConfig(map, "org.example.clock#1", [1, 2]).ok, false);
assert.equal(setInstanceConfig(map, "org.example.clock#1", "str").ok, false);
assert.equal(setInstanceConfig(map, "", { a: 1 }).ok, false);
const hugeAscii = { blob: "a".repeat(MAX_INSTANCE_CONFIG_BYTES + 1) };
assert.equal(setInstanceConfig(map, "org.example.clock#1", hugeAscii).ok, false);
const hugeUtf8 = { blob: "中".repeat(22000) };
assert.ok(utf8ByteLength(JSON.stringify(hugeUtf8)) > MAX_INSTANCE_CONFIG_BYTES);
assert.equal(setInstanceConfig(map, "org.example.clock#1", hugeUtf8).ok, false);

// 4. Removal cleans only the target instance.
const removed = removeInstanceConfig(map, "org.example.clock#1");
assert.equal(removed.changed, true);
assert.equal(getInstanceConfig(removed.map, "org.example.clock#1"), null);
assert.deepEqual(getInstanceConfig(removed.map, "org.example.clock#2"), { format24h: true });
assert.equal(removeInstanceConfig(removed.map, "org.example.clock#1").changed, false);

console.log("DeskCenter widget instance config tests passed");
