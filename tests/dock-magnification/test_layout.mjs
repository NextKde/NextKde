import assert from "node:assert/strict";
import { layout, overApps } from "../../shell/desktop/modules/dock/DockMagnification.mjs";

for (const size of [18, 44, 70]) {
    const slot = size * 1.32;
    const gap = size * 0.1;
    const pitch = slot + gap;
    const radius = size * 2;
    const states = Array.from({ length: 24 }, (_, i) => ({
        item: i, cx: i * pitch, half: slot / 2, artHalf: size / 2, growable: true,
    }));
    for (const maxScale of [1, 1.2, 2, 3.2]) for (const progress of [0, 0.25, 0.5, 1]) {
        let minWidth = Infinity, maxWidth = 0;
        for (let pointer = -radius; pointer <= states.at(-1).cx + radius; pointer += 0.5) {
            const frame = layout(states, pointer, progress, maxScale, radius);
            assert.ok(Number.isFinite(frame.total) && Number.isFinite(frame.shift));
            for (let i = 1; i < states.length; ++i) {
                const a = frame.entries[i - 1], b = frame.entries[i];
                const actualGap = pitch + b.dx - a.dx - a.half - b.half;
                assert.ok(actualGap >= gap - 1e-8, "rounded plates must retain their resting gap");
                assert.equal(frame.byItem.get(i), b);
            }
            if (pointer > radius + slot && pointer < states.at(-1).cx - radius - slot) {
                minWidth = Math.min(minWidth, frame.total);
                maxWidth = Math.max(maxWidth, frame.total);
            }
            if (progress === 0 || maxScale === 1) {
                assert.equal(frame.total, 0);
                assert.equal(frame.shift, 0);
            }
        }
        assert.ok(maxWidth - minWidth < 1e-8, "interior cross-icon motion must not pulse the width");
    }
    // A rigid information card moves with the same field without scaling.
    const mixed = states.slice();
    mixed[8] = { ...mixed[8], growable: false };
    const frame = layout(mixed, mixed[8].cx, 1, 2, radius);
    assert.equal(frame.entries[8].scale, 1);
    assert.equal(frame.entries[8].progress, 0);
}
assert.deepEqual(layout([], 0, 1, 2, 140).entries, []);
console.log("Shared hover field: active-plate gaps, constant interior width, lookup, rigid members and restoration passed");

const group = [
    {item: "tray", cx: -100, half: 40, growable: false},
    {item: "app", cx: 0, half: 29, artHalf: 22, growable: true},
    {item: "stack", cx: 150, half: 80, growable: false},
];
const rest = layout(group, 0, 0, 2, 88);
assert.equal(overApps(group, rest, -100), false);
assert.equal(overApps(group, rest, 150), false);
assert.equal(overApps(group, rest, 0), true);
const magnified = layout(group, 0, 1, 2, 88);
assert.equal(overApps(group, magnified, 150 + magnified.byItem.get("stack").dx), false);
const compact = magnified.total;
console.log(`Compact wave: app-only hover, rigid controls retain native input; spread=${compact.toFixed(1)}px`);
