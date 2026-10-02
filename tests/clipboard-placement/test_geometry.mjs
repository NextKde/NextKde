import assert from 'node:assert/strict';
import { validAnchor, screenForAnchor, bounds, place } from '../../shell/desktop/modules/quicksearch/ClipboardPlacement.mjs';

const primary = { x: 0, y: 0, width: 1920, height: 1080 };
const left = { x: -1280, y: -200, width: 1280, height: 800 };
const caret = (x, y, extra = {}) => ({ available: true, source: 'caret', x, y, width: 0, height: 20, ...extra });
assert(validAnchor(caret(0, 0)), 'zero-width text caret is valid');
for (const anchor of [null, {}, caret(NaN, 0), caret(0, Infinity), caret(0, 0, {width: -1})])
    assert(!validAnchor(anchor));
assert.equal(screenForAnchor([primary, left], caret(-800, -150), primary), left);
assert.equal(screenForAnchor([primary, left], caret(0, 100), left), primary);
assert.equal(screenForAnchor([primary], caret(-800, 200), primary), primary, 'removed output falls back');
assert.deepEqual(place(primary, caret(400, 200), 580, 380), {x: 400, y: 228});
assert.deepEqual(place(primary, caret(1900, 1020), 580, 380), {x: 1320, y: 632});
assert.deepEqual(place(left, caret(-1200, -150), 580, 380), {x: 80, y: 78});
assert.deepEqual(place(primary, caret(1, 1), 580, 380), {x: 12, y: 29});
assert.deepEqual(place(primary, caret(400, 200, {source: 'pointer', height: 0}), 580, 380), {x: 400, y: 208});
const reserved = caret(1800, 1000, {areaX: 0, areaY: 40, areaWidth: 1920, areaHeight: 940});
assert.deepEqual(bounds(primary, reserved), {x: 0, y: 40, width: 1920, height: 940});
assert.deepEqual(place(primary, reserved, 580, 380), {x: 1220, y: 588});
assert.deepEqual(place(primary, null, 580, 380), {x: 670, y: 173});
// Fractional scaling is already represented by logical pixels; do not apply
// the device pixel ratio again. Check every edge and randomized screen origins.
for (const screen of [primary, left, {x: 1280.5, y: -300.25, width: 853.5, height: 600.5}]) {
    for (let i = 0; i < 200; i++) {
        const anchor = caret(screen.x + i * screen.width / 199,
            screen.y + ((i * 37) % 200) * screen.height / 200);
        const p = place(screen, anchor, 580, 380);
        assert(p.x >= 12 && p.y >= 12);
        assert(p.x + 580 <= screen.width - 12 && p.y + 380 <= screen.height - 12);
    }
}
console.log('PASS: caret, pointer, four edges, reserved panels, negative origins, removed outputs and fractional logical coordinates');
