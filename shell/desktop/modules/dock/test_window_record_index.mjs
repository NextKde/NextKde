import assert from "node:assert/strict";
import { indexWindowRecords } from "./WindowRecordIndex.mjs";

const foreignTop = {};
const records = [
    { provider: "kwin", handleId: "__proto__", windowId: "first" },
    { provider: "kwin", handleId: "__proto__", windowId: "duplicate" },
    { provider: "foreign", toplevel: foreignTop, windowId: "foreign" },
    { provider: "foreign", toplevel: {}, windowId: "other-object" },
    { provider: "unknown", handleId: "ignored" },
];
const index = indexWindowRecords(records);
assert.equal(index.kwin.get("__proto__"), records[0]);
assert.equal(index.foreign.get(foreignTop), records[2]);
assert.equal(index.foreign.get({}), undefined);
assert.equal(index.kwin.get("ignored"), undefined);
assert.equal(indexWindowRecords([]).kwin.size, 0);

// Differential check against the previous strict-identity scan, including
// reordered snapshots, missing IDs and distinct objects with the same fields.
const tops = Array.from({ length: 100 }, () => ({}));
const many = tops.flatMap((top, i) => [
    { provider: "foreign", toplevel: top, windowId: `f${i}` },
    { provider: "kwin", handleId: String(i), windowId: `k${i}` },
]).reverse();
const indexed = indexWindowRecords(many);
for (let i = 0; i <= 100; i++) {
    assert.equal(indexed.kwin.get(String(i)), many.find(record =>
        record.provider === "kwin" && record.handleId === String(i)));
    assert.equal(indexed.foreign.get(tops[i]), many.find(record =>
        record.provider === "foreign" && record.toplevel === tops[i]));
}
// One record-key read per input, not one whole-list scan per incoming window.
let keyReads = 0;
indexWindowRecords(Array.from({ length: 1000 }, (_, i) => ({
    provider: "kwin", get handleId() { keyReads++; return String(i); },
})));
assert.equal(keyReads, 1000);

console.log("window record index: passed");
