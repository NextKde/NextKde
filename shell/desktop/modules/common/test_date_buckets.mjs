import assert from "node:assert/strict";
import { dayKey, minuteKey } from "./DateBuckets.mjs";

const base = new Date(2026, 8, 8, 12, 30, 0);
for (let second = 1; second < 60; second++) {
    const next = new Date(2026, 8, 8, 12, 30, second);
    assert.equal(dayKey(base), dayKey(next));
    assert.equal(minuteKey(base), minuteKey(next));
}
for (const next of [new Date(2026, 8, 8, 12, 31), new Date(2026, 8, 8, 13, 30),
    new Date(2026, 8, 8, 11, 30)]) {
    assert.equal(dayKey(base), dayKey(next));
    assert.notEqual(minuteKey(base), minuteKey(next));
}
for (const next of [new Date(2026, 8, 9, 12, 30), new Date(2026, 9, 8, 12, 30),
    new Date(2027, 8, 8, 12, 30)]) {
    assert.notEqual(dayKey(base), dayKey(next));
    assert.notEqual(minuteKey(base), minuteKey(next));
}
// Snapshot keys must notice an offset change even at an unchanged instant.
const before = dayKey(base), beforeMinute = minuteKey(base);
const changedZone = new Date(base);
changedZone.getTimezoneOffset = () => base.getTimezoneOffset() + 60;
assert.notEqual(dayKey(changedZone), before);
assert.notEqual(minuteKey(changedZone), beforeMinute);
// Both occurrences of 01:30 during US fall-back must update the minute lane.
assert.notEqual(minuteKey(new Date("2026-11-01T01:30:00-04:00")),
    minuteKey(new Date("2026-11-01T01:30:00-05:00")));
assert.notEqual(dayKey(new Date(2026, 11, 31, 23, 59, 59)),
    dayKey(new Date(2027, 0, 1, 0, 0, 0)));
console.log("date buckets: passed");
