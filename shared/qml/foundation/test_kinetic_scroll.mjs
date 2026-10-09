// Test harness for KosKineticScrollPhysics.mjs -- run with: node test_kinetic_scroll.mjs
//
// The QML side (tests/interaction-controls/tst_kinetic_scroll.qml) proves the
// component is wired to a real Flickable; this file proves the numbers it feeds
// that view, which a running compositor can only show as "it felt wrong": how
// far one notch travels, how much the view lags the hand, how long the glide is
// after the hand stops, that a new operation stops it dead, and how far a fling
// may rebound past an end.
//
// Sign convention, the same one the QML component applies: a wheel turned away
// from the user reports a negative angleDelta and moves the content *towards its
// end* (contentY grows). NOTCH is that content-space step.
import { CONFIG, axis, advance, bounds, clamp, frameDt, push, release, reset, wheelStep }
    from "./KosKineticScrollPhysics.mjs";

const NOTCH = -wheelStep(-120, 0).delta;    // 72px, towards the end of the content
const OPEN = { min: 0, max: 1000000 };

let errors = 0;
function check(condition, description) {
    if (condition)
        console.log("OK:  ", description);
    else
        console.log("FAIL:", description), errors++;
}

// One wheel event the way the component delivers it: aim, then let the spring
// have the frames until the next event (real events are >= 30ms apart).
function wheel(ax, delta, range, dtSince = Infinity, frames = 2) {
    push(ax, delta, range, dtSince);
    for (let i = 0; i < frames; i++)
        advance(ax, 1 / 60, range);
}

// Run to a standstill and report the trip.
function settle(ax, range, dt = 1 / 60) {
    let frames = 0, moving = true, overshootLow = 0, overshootHigh = 0;
    while (moving && frames < 200000) {
        moving = advance(ax, dt, range);
        overshootLow = Math.min(overshootLow, ax.position - range.min);
        overshootHigh = Math.max(overshootHigh, ax.position - range.max);
        frames++;
    }
    return { frames: frames, seconds: frames * dt, position: ax.position,
             pastMin: -overshootLow, pastMax: overshootHigh };
}

// --- what one wheel event means ---------------------------------------------

check(wheelStep(-120, 0).delta === -72 && !wheelStep(-120, 0).continuous,
    "a 120-unit notch is 72px of notched-wheel travel (Qt's own 0.6px/unit)");
check(wheelStep(15, 0).delta === 9, "an angle delta scales linearly");
check(wheelStep(0, -7).delta === -7 && wheelStep(0, -7).continuous,
    "a pixel-only event is a continuous device and travels 1:1");
check(wheelStep(-120, -7).delta === -7 && wheelStep(-120, -7).continuous,
    "a device reporting both keeps the continuous pixel channel");
check(wheelStep(0, 0).delta === 0, "an empty event moves nothing");
check(NOTCH === 72, "and it scrolls towards the end of the content");

// --- the scrollable range ---------------------------------------------------

const inBounds = bounds(2000, 200, 0, 0);
check(inBounds.min === 0 && inBounds.max === 1800, "a plain view scrolls 0..content-viewport");
const withMargins = bounds(2000, 200, 40, 30);
check(withMargins.min === -40 && withMargins.max === 1830, "margins extend the range at both ends");

// --- one notch: weight, not a jump, and no overshoot -------------------------

const lone = axis(0);
push(lone, NOTCH, OPEN);
const loneTrip = settle(lone, OPEN);
check(Math.abs(loneTrip.position - 72) < 0.5,
    "a lone notch lands exactly on the platform's step (" + loneTrip.position.toFixed(2) + "px)");
check(loneTrip.seconds > 0.12 && loneTrip.seconds < 0.4,
    "eased home in " + Math.round(loneTrip.seconds * 1000) + "ms (weight, not a jump)");
check(loneTrip.pastMax <= 0.5, "without overshooting the target");
check(release(lone, OPEN) === false, "and releases no glide: there was no gesture speed");

// --- following the hand -----------------------------------------------------
//
// A wheel that arrives as a ramp of events (KWin, high-resolution wheels) is
// followed by a spring stiff enough that the hand never feels the view lag.

const ramp = axis(0);
let worstLag = 0;
for (let i = 0; i < 6; i++) {
    wheel(ramp, NOTCH, OPEN, i === 0 ? Infinity : 0.03);
    worstLag = Math.max(worstLag, ramp.target - ramp.position);
}
check(ramp.target === 6 * 72, "six notches ask for their exact sum (" + ramp.target + "px)");
check(worstLag < 90,
    "while the view stays on the hand (worst lag " + Math.round(worstLag) + "px)");
check(Math.abs(ramp.speed - 72 / 0.03) < 1,
    "its speed is measured from the event gap (" + Math.round(ramp.speed) + "px/s)");
check(settle(ramp, OPEN).position === 6 * 72, "and the follow ends exactly on the sum");

const slow = axis(0);
for (let i = 0; i < 6; i++)
    wheel(slow, NOTCH, OPEN, i === 0 ? Infinity : 0.4);
check(slow.speed === 0, "notches far apart are separate gestures, not one speed");
check(settle(slow, OPEN).position === 6 * 72, "and they still keep the platform's distance");

const instant = axis(0);
push(instant, NOTCH, OPEN, Infinity);
push(instant, NOTCH, OPEN, 0);
check(instant.speed === 72 / CONFIG.minEventGap,
    "two events in the same millisecond read as the floor, not infinite speed");
release(instant, OPEN);
check(Math.abs(instant.velocity) === CONFIG.maxCoastSpeed,
    "and a glide from it is capped at " + CONFIG.maxCoastSpeed + "px/s");

// --- the glide --------------------------------------------------------------

const burst = axis(0);
for (let i = 0; i < 6; i++)
    wheel(burst, NOTCH, OPEN, i === 0 ? Infinity : 0.03);
const handStopped = burst.target;
const released = release(burst, OPEN);
check(released === true && burst.released === true, "a fast gesture releases a glide");
const trip = settle(burst, OPEN);
const coast = trip.position - handStopped;
check(coast > 250, "which carries " + Math.round(coast) + "px past where the hand stopped");
check(coast < 1400, "without flinging the whole list (" + Math.round(coast) + "px)");
check(trip.seconds > 0.3 && trip.seconds < 2.0,
    "and takes " + Math.round(trip.seconds * 1000) + "ms to spend");

// The glide only ever slows down.
const decaying = axis(0);
for (let i = 0; i < 6; i++)
    wheel(decaying, NOTCH, OPEN, i === 0 ? Infinity : 0.03);
release(decaying, OPEN);
let previous = Math.abs(decaying.velocity), monotonic = true, frames = 0;
while (advance(decaying, 1 / 60, OPEN) && frames < 10000) {
    // While the glide owns the axis it only ever slows; once it hands the axis
    // back to the spring, the spring is allowed to brake it the rest of the way.
    if (decaying.released && Math.abs(decaying.velocity) > previous + 1e-9)
        monotonic = false;
    previous = Math.abs(decaying.velocity);
    frames++;
}
check(monotonic, "the glide only ever slows down (" + frames + " frames)");

// --- stopping on the newest operation ---------------------------------------

const interrupted = axis(0);
for (let i = 0; i < 6; i++)
    wheel(interrupted, NOTCH, OPEN, i === 0 ? Infinity : 0.03);
release(interrupted, OPEN);
for (let i = 0; i < 10; i++)
    advance(interrupted, 1 / 60, OPEN);
const whenInterrupted = interrupted.position;
push(interrupted, -NOTCH, OPEN, 0.03);
check(interrupted.released === false, "a new event cancels the glide outright");
check(interrupted.velocity === 0, "with no speed left over from the old direction");
check(interrupted.target === whenInterrupted - 72,
    "and the reversal bites from where the view actually is ("
    + whenInterrupted.toFixed(0) + " -> " + interrupted.target.toFixed(0) + ")");
advance(interrupted, 1 / 60, OPEN);
check(interrupted.position < whenInterrupted, "so the very next frame moves the new way");

const resumed = axis(0);
for (let i = 0; i < 6; i++)
    wheel(resumed, NOTCH, OPEN, i === 0 ? Infinity : 0.03);
release(resumed, OPEN);
advance(resumed, 1 / 60, OPEN);
const resumedAt = resumed.position;
push(resumed, NOTCH, OPEN, 0.3);
check(resumed.released === false && resumed.target === resumedAt + 72,
    "a fresh notch during a glide takes over from where the view is, not from the "
    + "old glide's destination");

// --- the soft end -----------------------------------------------------------

const bounded = bounds(500, 200, 0, 0);
const intoTheEnd = axis(0);
for (let i = 0; i < 6; i++)
    wheel(intoTheEnd, NOTCH, bounded, i === 0 ? Infinity : 0.03);
release(intoTheEnd, bounded);
const ended = settle(intoTheEnd, bounded);
check(ended.pastMax > 10, "a glide into an end rebounds " + Math.round(ended.pastMax) + "px past it");
check(ended.pastMax <= CONFIG.bounceMax + 5, "by no more than the soft end allows");
check(ended.position === bounded.max, "and comes all the way back to it");

const atTheStart = axis(0);
atTheStart.position = 40; atTheStart.target = 40;
for (let i = 0; i < 4; i++)
    wheel(atTheStart, -NOTCH, bounded, i === 0 ? Infinity : 0.03);
release(atTheStart, bounded);
check(settle(atTheStart, bounded).position === bounded.min,
    "and rebounds off the start when flung the other way");

const poking = axis(0);
poking.position = 40; poking.target = 40;
for (let i = 0; i < 4; i++)
    wheel(poking, -NOTCH, bounded, i === 0 ? Infinity : 0.03);
check(settle(poking, bounded).pastMin < CONFIG.bounceMax + 5,
    "with the same bound on how far it may poke out");

// --- content that shrinks ---------------------------------------------------

const shrinking = axis(0);
shrinking.position = 400; shrinking.target = 400;
const newRange = bounds(300, 200, 0, 0);
advance(shrinking, 1 / 60, newRange);
check(shrinking.position === 100, "content that shrinks leaves the view inside the range");

// --- tick timing ------------------------------------------------------------

check(frameDt(1000, 0) === 1 / 60, "the first tick of a gesture stands in for one frame");
check(Math.abs(frameDt(1016, 1000) - 0.016) < 1e-9, "an on-time tick measures 16ms");
check(frameDt(2000, 1000) === CONFIG.maxFrameTime,
    "a stalled ticker is capped, so the view cannot teleport");

// The motion integrates over measured time (in fixed sub-steps), so its shape
// does not depend on the tick rate.
function tripAt(dt) {
    const ax = axis(0);
    for (let i = 0; i < 6; i++) {
        push(ax, NOTCH, OPEN, i === 0 ? Infinity : 0.03);
        for (let k = 0; k < Math.round(0.033 / dt); k++)
            advance(ax, dt, OPEN);
    }
    release(ax, OPEN);
    return settle(ax, OPEN, dt).position;
}
const at60 = tripAt(1 / 60);
const at144 = tripAt(1 / 144);
check(Math.abs(at60 - at144) / Math.max(at60, at144) < 0.05,
    "the whole trip is the same at 60Hz (" + at60.toFixed(0) + "px) and 144Hz ("
    + at144.toFixed(0) + "px)");

// --- aiming -----------------------------------------------------------------

const aimed = axis(500);
push(aimed, NOTCH, { min: 0, max: 1800 });
push(aimed, NOTCH, { min: 0, max: 1800 });
check(aimed.position === 500 && aimed.target === 644, "wheel events move the target, not the view");
push(aimed, NOTCH * 10000, { min: 0, max: 1800 });
check(aimed.target === 1800, "a target past the end clamps to the end");
reset(aimed, 900);
check(aimed.target === 900 && aimed.velocity === 0 && aimed.released === false,
    "reset re-anchors the axis and drops any glide");

console.log(errors ? "\n" + errors + " FAILED" : "\nAll kinetic scroll cases passed");
process.exit(errors ? 1 : 0);
