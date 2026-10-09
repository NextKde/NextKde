// The arithmetic behind KosKineticScroll.qml.
//
// Why this is a plain ES module and not inline QML: the *feel* of a scroll is a
// numeric policy -- how far one notch travels, how much weight the follow has,
// how long the glide is, how far it may bounce past an end -- and a wrong number
// is invisible in a diff and impossible to argue about from a screenshot.
// Keeping it here lets the whole curve be replayed and asserted in node
// (test_kinetic_scroll.mjs).
//
// The model is a damped spring pulled towards what the wheel asked for:
//
//   * FOLLOW -- the target is the input (0.6px per angle unit, the platform's
//     own), and the view eases onto it. Slightly underdamped, so a notch has
//     visible weight instead of arriving as a step; stiff enough that a hand
//     turning the wheel never feels the view lag behind it. (A pure 1:1 follow
//     is what "feels linear and dumb"; a soft spring is what "feels sticky" --
//     followStiffness/followDamping is that dial.)
//   * GLIDE -- when the events stop, the speed the gesture was carrying is
//     released and decays at coastDeceleration. A wheel that arrives as a ramp
//     of events (KWin, high-resolution wheels) is the whole reason this exists.
//   * REBOUND -- the ends of the content are soft: a glide that runs into one
//     pushes past it against resistance (bounceMax) and is sprung back by
//     bounceStiffness, which is the "rebound" a scroll with physics has.
//   * STOP -- any new input cancels the glide, and a reversal kills the
//     velocity outright, so the newest operation bites on its own event.

export const CONFIG = {
    // Pixels per wheel angle unit. Qt's own Flickable moves 0.6px per unit
    // (120 units per notch -> 72px).
    angleStep: 0.6,
    // The follow's weight, as a range rather than one number, because a wheel
    // makes two different gestures with the same device. A single slow notch is
    // a flick of the hand and wants a visible, weighty easing; a fast spin is a
    // stream of events and wants the view *on* the hand, lagging it by as close
    // to nothing as a spring can manage. One stiffness cannot do both: soft
    // enough for the notch lags a spin by ~a hundred pixels, stiff enough for
    // the spin turns the notch into a jump.
    //
    // So the stiffness follows the gesture: sqrt() is the angular frequency in
    // rad/s, and the speed at which the follow is at full stiffness is
    // followFullSpeed px/s.
    followStiffnessSlow: 1150,
    followStiffnessFast: 9000,
    followFullSpeed: 2200,
    // 1 is critically damped (no overshoot). Just under gives a notch a little
    // weight at the end without looking like a spring toy.
    followDamping: 1.0,
    // A gesture's speed is the gap between its events; events closer together
    // than this belong to the same gesture.
    momentumWindow: 0.2,
    // Floor on the gap between two events, so "arrived in the same millisecond"
    // is the fastest a gesture can be rather than an infinite speed.
    minEventGap: 0.008,
    // Quiet for this long after the last event means the hand has stopped.
    releaseDelay: 0.055,
    // How much of the gesture's speed the glide inherits.
    releaseGain: 0.72,
    // Ceiling on the released speed.
    maxCoastSpeed: 4200,
    // px/s^2 the glide decays at. Smaller means a longer, lighter glide.
    coastDeceleration: 4800,
    // Below this the glide is over and the spring takes the view the rest of
    // the way.
    stopSpeed: 14,
    // Settled: what counts as arrived.
    settleDistance: 0.35,
    settleSpeed: 8,
    // The soft end. bounceMax is how far past a bound a glide may travel before
    // the resistance has eaten it; bounceStiffness pulls it home (sqrt = rad/s,
    // so 300 is ~17 rad/s, a little over 1/4 second) and bounceDamping below 1
    // lets the rebound settle without ringing.
    bounceMax: 60,
    bounceStiffness: 520,
    bounceDamping: 0.9,
    // A frame longer than this is a stall, not a frame: the view must not
    // teleport by however long the ticker was away.
    maxFrameTime: 0.05,
    // Integration step. The follow is a stiff spring by design (a fast spin asks
    // for an angular frequency near 100 rad/s), and stepping one Euler step per
    // frame at that frequency diverges -- the view oscillates instead of
    // settling. Nailing each frame to this step keeps the integrator accurate
    // and the feel identical at 60Hz and 144Hz.
    integrationStep: 1 / 240,
};

export function clamp(value, min, max) {
    if (min > max)
        return min;
    return value < min ? min : (value > max ? max : value);
}

// One scroll event, in pixels, plus which profile it belongs to.
//
// Pixel deltas identify continuous input even when an angle is also present.
// The QML companion hands these events to native scrolling without a glide.
export function wheelStep(angleDelta, pixelDelta, config = CONFIG) {
    const pixels = pixelDelta || 0;
    if (pixels !== 0)
        return { delta: pixels, continuous: true };
    const angle = angleDelta || 0;
    if (angle !== 0)
        return { delta: angle * config.angleStep, continuous: false };
    return { delta: 0, continuous: false };
}

// The scrollable range of a Flickable-shaped view. Mirrors what Qt itself
// allows: contentY runs from the top margin to the content's end plus the
// bottom margin.
export function bounds(contentSize, viewportSize, topMargin, bottomMargin) {
    const min = -(topMargin || 0);
    return { min: min, max: Math.max(min, contentSize + (bottomMargin || 0) - viewportSize) };
}

// One axis of motion. `position` is where the view is drawn, `target` the sum
// of what the wheel has asked for, `velocity` the spring's speed, and `speed`
// how fast the gesture itself is moving.
export function axis(position = 0) {
    return { position: position, target: position, velocity: 0, speed: 0, released: false };
}

export function reset(ax, position) {
    ax.position = position;
    ax.target = position;
    ax.velocity = 0;
    ax.speed = 0;
    ax.released = false;
}

// A wheel event. The target moves by exactly the platform's step; how the view
// gets there is advance()'s job.
//
// `dtSince` is the time since the previous event of this gesture (Infinity for
// the first), which is the only speed signal a wheel gives.
export function push(ax, delta, range, dtSince = Infinity, config = CONFIG) {
    // The newest operation owns the view: whatever glide was running ends here,
    // and it ends *where the view is*, not where the old glide was aiming. (A
    // glide has already pushed the target out to its coasting destination, so
    // adding to that target would let a reversal keep gliding the old way.)
    if (ax.released) {
        ax.target = clamp(ax.position, range.min, range.max);
        ax.released = false;
    }
    // A reversal kills the old direction's velocity outright, so the new
    // direction bites on this very event instead of a few hundred pixels later.
    if (delta !== 0 && ax.velocity !== 0 && Math.sign(delta) !== Math.sign(ax.velocity))
        ax.velocity = 0;
    ax.target = clamp(ax.target + delta, range.min, range.max);
    if (delta !== 0 && dtSince >= 0 && dtSince <= config.momentumWindow)
        ax.speed = delta / Math.max(dtSince, config.minEventGap);
    else
        ax.speed = 0;
    return ax.target;
}

// The hand has stopped. The gesture had a speed, so the view has somewhere to
// coast to: the target is pushed on by exactly the distance that speed can be
// braked away in (v^2 / 2a), and the spring carries the view there with the
// speed already in hand. One number does the whole glide -- there is no second
// phase to keep in sync with the first, and a new event cancels it simply by
// aiming somewhere else.
export function release(ax, range, config = CONFIG) {
    const speed = clamp(ax.speed * config.releaseGain, -config.maxCoastSpeed, config.maxCoastSpeed);
    if (Math.abs(speed) < config.stopSpeed)
        return false;
    // Where the glide is going: the distance this speed brakes away in. The
    // glide itself is friction (below), not a spring, so it keeps the even,
    // decaying character of a coast instead of easing like a hand.
    const carry = speed * Math.abs(speed) / (2 * config.coastDeceleration);
    ax.target = clamp(ax.target + carry, range.min, range.max);
    ax.velocity = speed;
    ax.released = true;
    // The gesture is over: the follow goes back to its slow, weighty setting,
    // which is what the view eases home with once the coast is spent.
    ax.speed = 0;
    return true;
}

// Advance one frame. Returns true while there is still motion to show.
export function advance(ax, dt, range, config = CONFIG) {
    // Content can shrink under the view (a filtered list, a removed row): come
    // back inside the bounds rather than rest out of them.
    if (ax.position < range.min || ax.position > range.max) {
        const bound = ax.position < range.min ? range.min : range.max;
        const outside = Math.abs(ax.position - bound);
        if (!ax.released && outside > config.bounceMax) {
            ax.position = clamp(ax.position, range.min, range.max);
            ax.target = clamp(ax.target, range.min, range.max);
            ax.velocity = 0;
            return true;
        }
    }

    let remaining = dt;
    while (remaining > 0) {
        const step = Math.min(remaining, config.integrationStep);
        remaining -= step;

        let accel;
        const past = ax.position < range.min ? range.min
            : (ax.position > range.max ? range.max : null);
        if (past !== null) {
            // Past an end: a damped spring pulls the view home. This is the
            // rebound, and it is what lets a glide overshoot an end without
            // leaving the content.
            const stiffness = config.bounceStiffness;
            accel = stiffness * (past - ax.position)
                - 2 * Math.sqrt(stiffness) * config.bounceDamping * ax.velocity;
        } else if (ax.released) {
            // The glide: friction opposite to the motion, in a straight line to
            // the target the release aimed at. Once it is spent the spring takes
            // over, so the last few pixels are eased home rather than drifted
            // into.
            if (Math.abs(ax.velocity) <= config.stopSpeed)
                ax.released = false;
            accel = -Math.sign(ax.velocity) * config.coastDeceleration;
        } else {
            // The follow: a spring onto what the wheel asked for, stiffened by
            // how fast the gesture is going.
            const blend = Math.min(1, Math.abs(ax.speed) / config.followFullSpeed);
            const stiffness = config.followStiffnessSlow
                + (config.followStiffnessFast - config.followStiffnessSlow) * blend;
            accel = stiffness * (ax.target - ax.position)
                - 2 * Math.sqrt(stiffness) * config.followDamping * ax.velocity;
        }

        ax.velocity += accel * step;
        ax.position += ax.velocity * step;
    }

    const atTarget = Math.abs(ax.target - ax.position) <= config.settleDistance;
    const slow = Math.abs(ax.velocity) <= config.settleSpeed;
    const inside = ax.position >= range.min && ax.position <= range.max;
    if (atTarget && slow && inside) {
        // Arrived. Snap, so a crawl cannot park a fraction of a pixel short.
        ax.position = ax.target;
        ax.velocity = 0;
        return false;
    }
    return true;
}

// How much time one tick represents. The ticker is a sampling device, not a
// frame clock, so the motion is integrated over measured elapsed time; a gap
// long enough to be a stall is capped.
export function frameDt(nowMs, lastMs, config = CONFIG) {
    if (!lastMs)
        return 1 / 60;
    return Math.min((nowMs - lastMs) / 1000, config.maxFrameTime);
}
