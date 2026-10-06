import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { advance } from "../../shell/desktop/modules/dock/DockMagnification.mjs";

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
