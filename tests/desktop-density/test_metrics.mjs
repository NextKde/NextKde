import assert from 'node:assert/strict';
import { metrics, reflowSlots, densities } from '../../shell/desktop/modules/deskcenter/DesktopGridMetrics.mjs';

const width = 986.6, height = 947;
const capacity = m => Math.floor((width + m.gap) / (m.cellWidth + m.gap))
    * Math.floor((height + m.gap) / (m.cellHeight + m.gap));
const old = metrics(width / 8, 98, 52, 'comfortable', 16);
const compact = metrics(width / 8, 98, 52, 'compact', 16);
const dense = metrics(width / 8, 98, 52, 'dense', 16);
assert.equal(capacity(old), 56);
assert.equal(capacity(compact), 72);
assert.equal(capacity(dense), 81);
for (const size of [52, 68, 84]) {
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

const blocked = [0, 2, 6];
const withWidgets = reflowSlots(['a','b','c','d'], {a:5,b:2,c:4,d:0}, 8, blocked);
assert.equal(withWidgets.a,5,'valid manual position stays unchanged');
assert.equal(withWidgets.c,4,'uncovered manual position stays unchanged');
assert.ok(Object.values(withWidgets).every(slot => !blocked.includes(slot)), 'widgets exclude their actual slots');
assert.equal(new Set(Object.values(withWidgets)).size,4,'reflow avoids collisions');
const freed = reflowSlots(['a','b','c','d','e'],withWidgets,8,[]);
assert.equal(freed.a,5,'moving a widget does not reset an existing manual position');
assert.equal(Object.keys(freed).length,5,'new space is usable after a widget moves');
console.log('Desktop icon bounds: actual widget slots excluded; uncovered positions preserved');
