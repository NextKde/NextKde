import assert from 'node:assert/strict';
import { metrics, reflowSlots, rowLayout, columnForSlot, slotForCell, densities } from '../../shell/desktop/modules/deskcenter/DesktopGridMetrics.mjs';

const width = 986.6, height = 947;
const capacity = m => Math.floor((width + m.gap) / (m.cellWidth + m.gap))
    * Math.floor((height + m.gap) / (m.cellHeight + m.gap));
const old = metrics(width / 8, 98, 52, 'comfortable', 16);
const compact = metrics(width / 8, 98, 52, 'compact', 16);
const dense = metrics(width / 8, 98, 52, 'dense', 16);
assert.equal(capacity(old), 56);
assert.equal(capacity(compact), 72);
assert.equal(capacity(dense), 81);
for (const size of [44, 52, 68, 84]) {
    for (const line of [13, 16, 21, 28]) {
        for (const density of densities) {
            const m = metrics(150, size + 46, size, density, line);
            assert.ok(m.cellWidth >= size + 8, 'icon stays inside the cell');
            assert.ok(m.cellHeight >= m.iconTop + size + m.labelGap + 2 * line + 6,
                'two complete label lines fit, even with larger fonts');
            assert.ok(m.gap >= 6, 'background remains available for rubber-band selection');
        }
    }
}
assert.deepEqual(metrics(123,98,52,'invalid',16),metrics(123,98,52,'comfortable',16));

// Extra Small is the 32 px tier: 44 px of artwork. It must add capacity in the
// reference area and never reduce it elsewhere.
const smallComfortable = metrics(40 + 72, 40 + 58, 52, 'comfortable', 16);
const extraSmallComfortable = metrics(32 + 72, 32 + 58, 44, 'comfortable', 16);
assert.ok(capacity(extraSmallComfortable) > capacity(smallComfortable),
    'extra-small icons fit more files in the reference area');
for (const density of densities) {
    const small = metrics(40 + 72, 40 + 58, 52, density, 16);
    const extraSmall = metrics(32 + 72, 32 + 58, 44, density, 16);
    assert.ok(capacity(extraSmall) >= capacity(small),
        `extra-small ${density} capacity must not shrink`);
}

// Extra Small leaves enough spare height for one more row at the reference
// height. The row uses that space instead of leaving a visible bottom gap,
// while keeping at least a 3 px gutter.
const extraRows = rowLayout(947, extraSmallComfortable.cellHeight,
    extraSmallComfortable.gap);
const smallRows = rowLayout(947, smallComfortable.cellHeight,
    smallComfortable.gap);
assert.equal(extraRows.count, 9);
assert.equal(smallRows.count, 9);
assert.ok(extraRows.gap >= 3, 'extra row keeps a usable gutter');
assert.ok(smallRows.gap >= 3);
const usedHeight = (rows, cellHeight) => (rows.count - 1) * rows.pitch + cellHeight;
assert.ok(usedHeight(extraRows, extraSmallComfortable.cellHeight) <= 947 + 1e-6);
assert.ok(usedHeight(smallRows, smallComfortable.cellHeight) <= 947 + 1e-6);
for (const density of densities) {
    const m = metrics(32 + 72, 32 + 58, 44, density, 16);
    const rows = rowLayout(947, m.cellHeight, m.gap);
    assert.ok(rows.gap >= 3);
    assert.ok(usedHeight(rows, m.cellHeight) <= 947 + 1e-6);
}

// The live desk grid excludes the Dock inset; 840 is the actual usable height
// for the current 960 px logical output (24 top + 96 bottom). Dense spacing
// can still use the spare height for a ninth row, even though its gap shrinks
// from 6 px to 3.75 px.
const extraSmallDense = metrics(32 + 72, 32 + 58, 44, 'dense', 16);
const denseRows = rowLayout(840, extraSmallDense.cellHeight,
    extraSmallDense.gap);
assert.equal(denseRows.count, 9);
assert.ok(denseRows.gap >= 3);
assert.ok(usedHeight(denseRows, extraSmallDense.cellHeight) <= 840 + 1e-6);

// Alignment is a pure column-order mirror: every slot must round-trip through
// the visual cell, and the first slot starts at the requested edge.
for (const rows of [1, 5, 9]) {
    for (const columns of [1, 4]) {
        for (const alignment of ["left", "right"]) {
            for (let slot = 0; slot < rows * columns; ++slot) {
                const column = columnForSlot(slot, rows, columns, alignment);
                assert.ok(column >= 0 && column < columns);
                assert.equal(slotForCell(column, slot % rows, rows, columns,
                    alignment), slot);
            }
        }
    }
}
assert.equal(columnForSlot(0, 9, 4, "left"), 0);
assert.equal(columnForSlot(0, 9, 4, "right"), 3);
assert.equal(slotForCell(0, 0, 9, 4, "left"), 0);
assert.equal(slotForCell(0, 0, 9, 4, "right"), 27);

const ids = Array.from({length: 90}, (_, i) => `file-${i}`);
let slots = reflowSlots(ids, {}, 56);
[slots['file-0'], slots['file-4']] = [slots['file-4'], slots['file-0']];
slots = reflowSlots(ids, slots, 72);
assert.equal(Object.keys(slots).length,72,'density increase reveals previously omitted files');
assert.equal(slots['file-0'],4,'manual placement remains when still valid');
slots = reflowSlots(ids, slots, 36);
assert.equal(Object.keys(slots).length,36);
assert.equal(new Set(Object.values(slots)).size,36);
assert.ok(Object.values(slots).every(n=>n>=0 && n<36),'smaller fields have no off-grid icons');
slots = reflowSlots(ids, slots, 90);
assert.equal(Object.keys(slots).length,90,'all entries return when space is restored');
console.log('Desktop density: capacity, label bounds, gutters, and reversible reflow passed');
