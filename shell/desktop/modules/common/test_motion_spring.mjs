import assert from "node:assert/strict";
import { step } from "./MotionSpring.mjs";

const settleEpsilon = 0.25;

function run(from, to, omega, zeta, seconds, dt) {
    let value = from;
    let velocity = 0;
    let steps = Math.ceil(seconds / dt);
    let peak = from;
    const trajectory = [];
    for (let i = 0; i < steps; i++) {
        const next = step(value, velocity, to, dt, omega, zeta, settleEpsilon);
        value = next.value;
        velocity = next.velocity;
        peak = Math.max(peak, value);
        trajectory.push(value);
    }
    return { value, velocity, peak, trajectory };
}

// ── the fitted pairs converge to the target and stop exactly on it ──
for (const [omega, zeta] of [[18.25, 0.71], [30.0, 1.33]]) {
    const result = run(0, 300, omega, zeta, 2, 1 / 240);
    assert.equal(result.value, 300, `spring ${omega}/${zeta} lands exactly on target`);
    assert.equal(result.velocity, 0, `spring ${omega}/${zeta} stops with no velocity`);
}

// The macOS pair keeps the reviewed 5 % overshoot; the critical pair must not
// pass the target at all (a long drop would carry the card off screen).
const bounce = run(0, 300, 18.25, 0.71, 1, 1 / 240);
assert.ok(bounce.peak > 301, "resize spring still has its overshoot");
assert.ok(bounce.peak < 300 * 1.07, "resize spring does not overshoot far past the reviewed curve");
const damped = run(0, 300, 30.0, 1.33, 1, 1 / 240);
assert.ok(damped.peak <= 300 + settleEpsilon, "move spring never passes its target");

// ── frame-rate independence: 60 Hz and 240 Hz must trace the same curve ──
{
    const slow = run(0, 300, 18.25, 0.71, 0.25, 1 / 60);
    const fast = run(0, 300, 18.25, 0.71, 0.25, 1 / 240);
    assert.ok(Math.abs(slow.value - fast.value) < 3,
        `60 Hz and 240 Hz agree at 250 ms (${slow.value.toFixed(2)} vs ${fast.value.toFixed(2)})`);
}
{
    // A display that drops to 30 Hz must still settle in the same wall time.
    const slow = run(0, 300, 30.0, 1.33, 0.5, 1 / 30);
    const fast = run(0, 300, 30.0, 1.33, 0.5, 1 / 240);
    assert.ok(Math.abs(slow.value - fast.value) < 4,
        `30 Hz and 240 Hz agree at 500 ms (${slow.value.toFixed(2)} vs ${fast.value.toFixed(2)})`);
}

// ── retargeting keeps the current velocity: a release hands its momentum in ──
{
    let value = 0;
    let velocity = 0;
    for (let i = 0; i < 24; i++) {
        const next = step(value, velocity, 300, 1 / 240, 30.0, 1.33, settleEpsilon);
        value = next.value;
        velocity = next.velocity;
    }
    const before = { value, velocity };
    const after = step(before.value, before.velocity, -300, 1 / 240, 30.0, 1.33, settleEpsilon);
    assert.ok(after.value >= before.value, "retarget does not teleport the value");
    assert.ok(after.velocity < 0 || after.value >= before.value,
        "retarget reverses the spring instead of restarting it from rest");
    assert.ok(Math.abs(after.value - before.value) < 5, "retarget keeps a continuous trajectory");
}

// ── degenerate inputs ──
assert.deepEqual(step(5, 0, 5, 0, 18.25, 0.71, 0.25), { value: 5, velocity: 0 },
    "a non-positive delta leaves the state alone");
assert.deepEqual(step(5, 0, 5, 1 / 240, 0, 0.71, 0.25), { value: 5, velocity: 0 },
    "a zero frequency spring is a no-op instead of NaN");
{
    // A freeze (suspend) must not explode the spring: the step is clamped.
    const next = step(0, 0, 300, 5, 30.0, 1.33, settleEpsilon);
    assert.ok(Number.isFinite(next.value) && Number.isFinite(next.velocity),
        "a long gap produces a finite clamped step");
    assert.ok(Math.abs(next.value) <= 300, "the clamped step cannot overshoot a full second of travel");
}

console.log("Motion spring: frame-time integration, overshoot and retarget tests passed");
