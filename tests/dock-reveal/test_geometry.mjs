import assert from 'node:assert/strict';
import { test } from 'node:test';
import { revealHitRect } from '../../shell/desktop/modules/dock/DockRevealGeometry.mjs';

const bottom = {
    triggerMode: 'dockSpan', position: 'bottom', windowWidth: 1000, windowHeight: 800,
    dockX: 300, dockY: 720, dockWidth: 400, dockHeight: 60,
    active: true, expanded: false,
};
const empty = { x: 0, y: 0, width: 0, height: 0 };
const hit = (rect, x, y) => x >= rect.x && x < rect.x + rect.width
    && y >= rect.y && y < rect.y + rect.height;

const positions = [
    ['bottom', bottom, { x: 300, y: 798, width: 400, height: 2 },
        { x: 300, y: 778, width: 400, height: 22 }],
    ['left', { ...bottom, position: 'left', dockX: 20, dockY: 130,
        dockWidth: 60, dockHeight: 400 },
        { x: 0, y: 130, width: 2, height: 400 },
        { x: 0, y: 130, width: 22, height: 400 }],
    ['right', { ...bottom, position: 'right', dockX: 920, dockY: 230,
        dockWidth: 60, dockHeight: 400 },
        { x: 998, y: 230, width: 2, height: 400 },
        { x: 978, y: 230, width: 22, height: 400 }],
];

for (const [name, input, cold, expanded] of positions) {
    test(`${name}: cold input is only the Dock's projection onto a 2px edge`, () => {
        assert.deepEqual(revealHitRect(input), cold);
        const vertical = name !== 'bottom';
        const cx = cold.x + cold.width / 2;
        const cy = cold.y + cold.height / 2;
        assert.equal(hit(cold, cx, cy), true);
        assert.equal(hit(cold, vertical ? cx : cold.x - 0.01,
            vertical ? cold.y - 0.01 : cy), false);
        assert.equal(hit(cold, vertical ? cx : cold.x + cold.width,
            vertical ? cold.y + cold.height : cy), false);
        assert.equal(hit(cold, input.dockX + input.dockWidth / 2,
            input.dockY + input.dockHeight / 2), false);
    });
    test(`${name}: revealed input covers the gap and overlaps the static glass by 2px`, () => {
        assert.deepEqual(revealHitRect({ ...input, expanded: true }), expanded);
        // In particular the expanded rectangle does not swallow the entire
        // glass: that remains the Dock's own pointer/click region.
        assert.equal(hit(expanded, input.dockX + input.dockWidth / 2,
            input.dockY + input.dockHeight / 2), false);
        assert.equal(hit(expanded, cold.x + cold.width / 2,
            cold.y + cold.height / 2), true);
    });
    test(`${name}: always-visible mode has no edge input even when expanded`, () => {
        assert.deepEqual(revealHitRect({ ...input, active: false }), empty);
        assert.deepEqual(revealHitRect({ ...input, active: false, expanded: true }), empty);
    });
}

test('uses supplied non-centred Dock coordinates, including reserved side top bar', () => {
    assert.deepEqual(revealHitRect({ ...bottom, dockX: 83 }),
        { x: 83, y: 798, width: 400, height: 2 });
    assert.deepEqual(revealHitRect({ ...positions[1][1], dockY: 35,
        dockHeight: 765 }), { x: 0, y: 35, width: 2, height: 765 });
});

test('uses fractional logical coordinates without multiplying or rounding for scale', () => {
    const input = { ...bottom, windowWidth: 853.5, windowHeight: 640.25,
        dockX: 103.125, dockY: 579.75, dockWidth: 447.25, dockHeight: 55.5 };
    assert.deepEqual(revealHitRect(input),
        { x: 103.125, y: 638.25, width: 447.25, height: 2 });
    assert.deepEqual(revealHitRect({ ...input, expanded: true }),
        { x: 103.125, y: 633.25, width: 447.25, height: 7 });
});

test('follows changed Dock and surface dimensions without retaining a previous span', () => {
    assert.deepEqual(revealHitRect(bottom), positions[0][2]);
    assert.deepEqual(revealHitRect({ ...bottom, windowWidth: 1600,
        windowHeight: 900, dockX: 350, dockY: 810, dockWidth: 900 }),
        { x: 350, y: 898, width: 900, height: 2 });
    assert.deepEqual(revealHitRect({ ...bottom, dockX: 440, dockWidth: 120 }),
        { x: 440, y: 798, width: 120, height: 2 });
    assert.deepEqual(revealHitRect(bottom), positions[0][2]);
});

test('clips Dock spans at both ends and never extends outside its surface', () => {
    assert.deepEqual(revealHitRect({ ...bottom, dockX: -30, dockWidth: 1100 }),
        { x: 0, y: 798, width: 1000, height: 2 });
    assert.deepEqual(revealHitRect({ ...positions[1][1], dockY: -10, dockHeight: 900,
        expanded: true }), { x: 0, y: 0, width: 22, height: 800 });
    assert.deepEqual(revealHitRect({ ...bottom, dockY: 790, expanded: true }),
        { x: 300, y: 798, width: 400, height: 2 });
    assert.deepEqual(revealHitRect({ ...positions[1][1], dockX: -10,
        expanded: true }), { x: 0, y: 130, width: 2, height: 400 });
    assert.deepEqual(revealHitRect({ ...positions[2][1], dockX: 990,
        expanded: true }), { x: 998, y: 230, width: 2, height: 400 });
});

test('clips the 2px strip and expanded overlap on surfaces smaller than 2px', () => {
    assert.deepEqual(revealHitRect({ ...bottom, windowHeight: 1.5,
        dockY: 0, dockHeight: 1, expanded: true }),
        { x: 300, y: 0, width: 400, height: 1.5 });
    assert.deepEqual(revealHitRect({ ...positions[1][1], windowWidth: 1.5,
        dockX: 0.5, dockWidth: 1 }), { x: 0, y: 130, width: 1.5, height: 400 });
});

for (const key of ['windowWidth', 'windowHeight', 'dockWidth', 'dockHeight']) {
    test(`${key}: non-positive size cannot intercept input`, () => {
        for (const value of [0, -1])
            assert.deepEqual(revealHitRect({ ...bottom, [key]: value }), empty);
    });
}
for (const key of ['windowWidth', 'windowHeight', 'dockX', 'dockY', 'dockWidth', 'dockHeight']) {
    test(`${key}: missing or non-finite input cannot create an accidental edge`, () => {
        for (const value of [NaN, Infinity, -Infinity, undefined, null, '100'])
            assert.deepEqual(revealHitRect({ ...bottom, [key]: value }), empty);
    });
}

test('fully off-surface Docks and unsupported positions are inert', () => {
    for (const change of [{ dockX: 1000 }, { dockX: -400 },
        { dockY: 800 }, { dockY: -60 }, { position: 'top' }, { position: '' }]) {
        assert.deepEqual(revealHitRect({ ...bottom, ...change }), empty);
        assert.deepEqual(revealHitRect({ ...bottom, ...change, expanded: true }), empty);
    }
});


for (const [name, input] of positions) {
    test(`${name}: missing or invalid mode preserves the legacy 14px full edge`, () => {
        const expected = name === 'bottom'
            ? { x: 0, y: 786, width: 1000, height: 14 }
            : { x: name === 'left' ? 0 : 986, y: 0, width: 14, height: 800 };
        for (const triggerMode of [undefined, 'fullEdge', '', 'invalid', null]) {
            assert.deepEqual(revealHitRect({ ...input, triggerMode }), expected);
            assert.deepEqual(revealHitRect({ ...input, triggerMode, expanded: true }), expected);
        }
    });
    test(`${name}: legacy full edge does not depend on Dock layout readiness`, () => {
        const expected = revealHitRect({ ...input, triggerMode: 'fullEdge' });
        for (const layout of [{ dockWidth: 0, dockHeight: 0 },
            { dockX: NaN, dockY: undefined, dockWidth: 0, dockHeight: 0 },
            { dockX: -5000, dockY: -5000 }])
            assert.deepEqual(revealHitRect({ ...input, ...layout, triggerMode: 'fullEdge' }), expected);
        assert.deepEqual(revealHitRect({ ...input, triggerMode: 'fullEdge', active: false }), empty);
    });
}

test('switching modes replaces the span and does not retain expanded geometry', () => {
    assert.deepEqual(revealHitRect({ ...bottom, expanded: true }),
        { x: 300, y: 778, width: 400, height: 22 });
    assert.deepEqual(revealHitRect({ ...bottom, expanded: true, triggerMode: 'fullEdge' }),
        { x: 0, y: 786, width: 1000, height: 14 });
    assert.deepEqual(revealHitRect(bottom), { x: 300, y: 798, width: 400, height: 2 });
});

test('legacy full edge safely clips small surfaces and rejects invalid surfaces', () => {
    assert.deepEqual(revealHitRect({ ...bottom, triggerMode: 'fullEdge', windowHeight: 4 }),
        { x: 0, y: 0, width: 1000, height: 4 });
    assert.deepEqual(revealHitRect({ ...positions[1][1], triggerMode: 'fullEdge', windowWidth: 3 }),
        { x: 0, y: 0, width: 3, height: 800 });
    for (const change of [{ windowWidth: 0 }, { windowHeight: -1 },
        { windowWidth: NaN }, { windowHeight: Infinity }, { position: 'top' }])
        assert.deepEqual(revealHitRect({ ...bottom, ...change, triggerMode: 'fullEdge' }), empty);
});
