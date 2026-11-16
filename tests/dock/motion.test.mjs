import assert from "node:assert/strict";
import { advance, launchBounce, layout, nameOwner, overApps, releaseLaunchFeedback, visualHeadroom } from "../../shell/desktop/modules/dock/DockMagnification.mjs";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { revealHitRect } from "../../shell/desktop/modules/dock/DockRevealGeometry.mjs";

test("launch bounce", async () => {
    assert.equal(launchBounce(0), 0);
    assert.equal(launchBounce(0.41), 1);
    assert.equal(launchBounce(0.82), 0);
    assert.equal(launchBounce(1), 0);
    for (let phase = 0; phase <= 1; phase += 0.001)
        assert.ok(launchBounce(phase) >= 0 && launchBounce(phase) <= 1);
    console.log('Launch flight stays bounded and returns to ground');
});

test("launch headroom", async () => {
    // Reconstruct physical surface and artwork bounds, rather than using an
    // oversized fixture window. The inputs include the exact no-hover case that
    // previously allocated only 4 px for a 0.65 * iconSize launch excursion.
    for (const edge of ['bottom', 'left', 'right']) {
        for (const size of [18, 44, 96]) {
            for (const gap of [0, 4]) {
                for (const maxScale of [1, 1.2, 2, 3]) {
                    const liftRatio = 0.2 * (maxScale - 1);
                    const slot = size + 2 * gap;
                    const thickness = slot + 8;
                    const headroom = visualHeadroom(size, gap, maxScale, liftRatio, thickness, 0.65);
                    const edgeMargin = 6;
                    const workspaceMargin = 6;
                    const nameBudget = 6 + (edge === "bottom" ? 28 : 220);
                    const surfaceThickness = thickness + edgeMargin + workspaceMargin + headroom + nameBudget;
                    const glassNear = edge === 'left' ? edgeMargin : workspaceMargin + headroom + nameBudget;
                    const slotCenter = glassNear + thickness / 2;
                    const inputNear = edge === 'left' ? glassNear : glassNear - headroom;
                    const inputFar = edge === 'left' ? glassNear + thickness + headroom : glassNear + thickness;
                    assert.ok(edge === 'left'
                        ? surfaceThickness - inputFar >= nameBudget
                        : inputNear >= nameBudget, 'label-only space must remain outside input mask');
                    for (const hover of [0, 0.5, 1]) {
                        const scale = 1 + hover * (maxScale - 1);
                        // This is DockIcon's actual center-origin scale compensation
                        // and continuous hover lift, composed with ballistic flight.
                        const hoverTranslation = -size * liftRatio * hover - slot / 2 * (scale - 1);
                        for (let phase = 0; phase <= 1; phase += 0.025) {
                            const launchTranslation = -size * 0.65 * launchBounce(phase);
                            const direction = edge === 'left' ? -1 : 1;
                            const center = slotCenter + direction * (hoverTranslation + launchTranslation);
                            const near = center - slot * scale / 2;
                            const far = center + slot * scale / 2;
                            const context = `${edge} size=${size} gap=${gap} scale=${maxScale} phase=${phase}`;
                            assert.ok(near >= 0 && far <= surfaceThickness, `surface clips: ${context}`);
                            assert.ok(near >= inputNear && far <= inputFar, `hover input clips: ${context}`);
                        }
                    }
                }
            }
        }
    }
    console.log('Real thin surface + input budgets contain combined hover/launch motion on all edges');
});

test("launch name owner", async () => {
    const states = Array.from({length: 6}, (_, i) => ({
        item: {index: i}, cx: 30 + i * 60, half: 26, artHalf: 22, growable: true,
    }));
    for (const scale of [1, 1.2, 2, 3]) {
        for (let x = states[0].cx; x <= states.at(-1).cx; x += 0.5) {
            const frame = layout(states, x, 1, scale, 220, 8);
            assert.ok(nameOwner(states, frame, x), `blank at ${x}, scale ${scale}`);
        }
    }
    const flat = layout(states, 120, 0, 1, 220, 8);
    assert.equal(nameOwner(states, flat, -1000), null);
    assert.equal(nameOwner(states, flat, 1000), null);
    assert.equal(nameOwner(states, flat, NaN), null);
    const divider = {item: {}, cx: 180, half: 3, growable: false};
    const separated = states.slice(0, 3).concat([divider], states.slice(3));
    const blocked = layout(separated, 180, 0, 1, 220, 8);
    assert.equal(nameOwner(separated, blocked, 180), null);
    // A rigid slot may never become an application's ownership region.
    const spacer = {...divider, half: 30, flexible: true};
    const spaced = states.slice(0, 3).concat([spacer], states.slice(4));
    assert.equal(nameOwner(spaced, layout(spaced, 180, 0, 1, 220, 8), 180), null);
    console.log('Continuous bounded name ownership: shared layouts, spacing and rigid barriers passed');
});

test("launch readiness", async () => {
    const started = 1000;
    const release = (elapsed, ready) => releaseLaunchFeedback(started, started + elapsed, ready, 500, 15000);

    // Even an immediately mapped window leaves enough frames for visible feedback.
    for (const elapsed of [0, 1, 16, 100, 499]) {
        assert.equal(release(elapsed, true), false, `ready window cleared feedback at ${elapsed}ms`);
    }
    assert.equal(release(500, true), true);
    assert.equal(release(900, true), true, 'slow readiness does not add another minimum delay');
    assert.equal(release(500, false), false, 'minimum is not a windowless launch deadline');
    assert.equal(release(14999, false), false);
    assert.equal(release(15000, false), true, 'windowless launches remain bounded');
    assert.equal(release(-1, true), false, 'a backwards clock must not clear feedback early');
    console.log('Fast window readiness preserves visible launch feedback without extending slow readiness or the timeout');
});

test("magnification response", async () => {
    // Read the production tuning rather than silently testing a different response.
    const animation = readFileSync(new URL(
        "../../shell/desktop/modules/dock/DockAnimation.qml", import.meta.url), "utf8");
    const response = Number(animation.match(/magnificationResponseSeconds:\s*([\d.]+)/)[1]);
    const epsilon = Number(animation.match(/magnificationEpsilon:\s*([\d.]+)/)[1]);
    assert.ok(response > 0 && response < 0.06);
    assert.ok(epsilon > 0 && epsilon <= 0.0001);

    for (const hz of [30, 60, 90, 120, 144, 165, 240]) {
        let value = 0;
        let t90 = 0;
        // While approaching the same target, every frame must advance: there is
        // no 16 ms spring tick that repeats values on high-refresh displays.
        for (let frame = 1; frame <= hz; frame++) {
            const next = advance(value, 1, 1 / hz, response, epsilon);
            assert.ok(next >= value && next <= 1);
            if (value < 1) assert.ok(next > value, `${hz} Hz stalled at frame ${frame}`);
            value = next;
            if (!t90 && value >= 0.9) t90 = frame / hz;
        }
        assert.equal(value, 1, "must settle exactly so the frame driver can sleep");
        const expectedT90 = response * Math.log(10);
        assert.ok(t90 >= expectedT90 && t90 <= expectedT90 + 1 / hz);
        for (let frame = 0; frame < hz; frame++) {
            const next = advance(value, 0, 1 / hz, response, epsilon);
            assert.ok(next >= 0 && next <= value);
            value = next;
        }
        assert.equal(value, 0);
        console.log(`Fisheye ${hz} Hz: monotonic entry/exit, t90=${(t90 * 1000).toFixed(1)} ms`);
    }

    // Equal elapsed time gives the same answer across different frame partitions,
    // including a long frame: this is not a per-frame lerp or Euler integrator.
    const reference = advance(0, 1, 0.12, response, epsilon);
    for (const frames of [1, 2, 8, 16, 32]) {
        let value = 0;
        for (let i = 0; i < frames; i++) value = advance(value, 1, 0.12 / frames, response, epsilon);
        assert.ok(Math.abs(reference - value) < 1e-12);
    }
    let value = advance(0, 1, 1 / 144, response, epsilon);
    const reversed = advance(value, 0, 1 / 144, response, epsilon);
    assert.ok(reversed < value && reversed > 0, "direction reversal must respond next frame");
    for (const dt of [0, -1, NaN, Infinity]) {
        assert.equal(advance(0.3, 1, dt, response, epsilon), 0.3);
    }
    assert.equal(advance(1 - epsilon / 2, 1, 0, response, epsilon), 1);
    assert.equal(advance(0, 1, 10, response, epsilon), 1);
    console.log("Fisheye response: frame-rate independence, reversal, stalls and exact settlement passed");
});

test("magnification layout", async () => {
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
});

const bottom = {
    position: 'bottom', windowWidth: 1000, windowHeight: 800,
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

test('expanding does not retain the cold 2px span', () => {
    assert.deepEqual(revealHitRect({ ...bottom, expanded: true }),
        { x: 300, y: 778, width: 400, height: 22 });
    assert.deepEqual(revealHitRect(bottom), { x: 300, y: 798, width: 400, height: 2 });
});
