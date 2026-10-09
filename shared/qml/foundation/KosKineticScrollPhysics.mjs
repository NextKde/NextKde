// Mouse-wheel smoothing policy for KosKineticScroll.qml.
// Recent input determines a short bounded coast. A critically damped follow
// settles without overshooting; all motion stops at content boundaries.
// Design reference: KDE Kirigami src/wheelhandler.cpp (windowed velocity and
// bounded inertia endpoints). These conservative constants are KOS tuning,
// not Kirigami defaults. Continuous streams use native Qt animation.
export const CONFIG = {
    angleStep: 0.6, // Preserve the existing 72px/notch distance.
    followStiffnessSlow: 2200, // About 200ms to settle a single notch.
    followStiffnessFast: 9000,
    followFullSpeed: 2200,
    followDamping: 1.0,
    momentumWindow: 0.08, // Average the most recent 80ms of input.
    minEventGap: 0.008,
    releaseDelay: 0.055,
    releaseGain: 0.25,
    maxCoastSpeed: 900,
    maxCoastDistance: 72, // No more than one extra notch.
    coastDeceleration: 6000, // At most 150ms of free coast.
    stopSpeed: 14,
    settleDistance: 0.35,
    settleSpeed: 8,
    maxFrameTime: 0.05,
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
// The QML companion gives pixel streams direct motion without an extra glide.
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
export function bounds(contentSize, viewportSize, topMargin, bottomMargin, origin = 0) {
    const min = origin - (topMargin || 0);
    return { min: min, max: Math.max(min, origin + contentSize + (bottomMargin || 0) - viewportSize) };
}

// One axis of motion. `position` is where the view is drawn, `target` the sum
// of what the wheel has asked for, `velocity` the spring's speed, and `speed`
// how fast the gesture itself is moving.
export function axis(position = 0) {
    return { position: position, target: position, velocity: 0, speed: 0, released: false, samples: [] };
}

export function reset(ax, position) {
    ax.position = position;
    ax.target = position;
    ax.velocity = 0;
    ax.speed = 0;
    ax.released = false;
    ax.samples = [];
}

// A wheel event. The target moves by exactly the platform's step; how the view
// gets there is advance()'s job.
//
// `dtSince` is the time since the previous event of this gesture (Infinity for
// the first), which is the only speed signal a wheel gives.
export function push(ax, delta, range, dtSince = Infinity, config = CONFIG) {
    const pending = ax.target - ax.position;
    const reversing = delta !== 0 && ((pending !== 0 && Math.sign(delta) !== Math.sign(pending))
        || (ax.velocity !== 0 && Math.sign(delta) !== Math.sign(ax.velocity)));
    if (ax.released || reversing) {
        ax.target = clamp(ax.position, range.min, range.max);
        ax.released = false;
        ax.samples = [];
    }
    if (reversing)
        ax.velocity = 0;
    ax.target = clamp(ax.target + delta, range.min, range.max);
    if (delta !== 0 && dtSince >= 0 && dtSince <= config.momentumWindow) {
        const dt = Math.max(dtSince, config.minEventGap);
        ax.samples.push({ delta, dt });
        let elapsed = 0;
        let displacement = 0;
        let first = ax.samples.length - 1;
        for (let i = ax.samples.length - 1; i >= 0; --i) {
            if (elapsed + ax.samples[i].dt > config.momentumWindow && elapsed > 0)
                break;
            elapsed += ax.samples[i].dt;
            displacement += ax.samples[i].delta;
            first = i;
        }
        ax.samples = ax.samples.slice(first);
        ax.speed = displacement / elapsed;
    } else {
        ax.samples = [];
        ax.speed = 0;
    }
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
    const carry = clamp(speed * Math.abs(speed) / (2 * config.coastDeceleration),
        -config.maxCoastDistance, config.maxCoastDistance);
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
    // Dynamic content changes and inertia both obey hard bounds.
    ax.position = clamp(ax.position, range.min, range.max);
    ax.target = clamp(ax.target, range.min, range.max);
    let remaining = Math.max(0, Math.min(dt, config.maxFrameTime));
    while (remaining > 0) {
        const step = Math.min(remaining, config.integrationStep);
        remaining -= step;
        const previous = ax.position;
        if (ax.released) {
            // Brake without changing velocity sign or adding a rebound phase.
            const magnitude = Math.max(0, Math.abs(ax.velocity) - config.coastDeceleration * step);
            ax.velocity = Math.sign(ax.velocity) * magnitude;
            ax.position += ax.velocity * step;
            if (magnitude <= config.stopSpeed)
                ax.released = false;
        } else {
            const blend = Math.min(1, Math.abs(ax.speed) / config.followFullSpeed);
            const stiffness = config.followStiffnessSlow
                + (config.followStiffnessFast - config.followStiffnessSlow) * blend;
            const accel = stiffness * (ax.target - ax.position)
                - 2 * Math.sqrt(stiffness) * config.followDamping * ax.velocity;
            ax.velocity += accel * step;
            ax.position += ax.velocity * step;
        }
        // Every substep stays between its starting point and requested endpoint.
        ax.position = clamp(ax.position, Math.min(previous, ax.target), Math.max(previous, ax.target));
        if (ax.position === ax.target) {
            ax.velocity = 0;
            ax.released = false;
        }
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

// Kirigami prefers angle deltas when available on Wayland: the pixel channel
// can be much slower. Preserve KOS's 72px/notch convention for that channel.
export function continuousStep(angleDelta, pixelDelta, config = CONFIG) {
    return angleDelta !== 0 ? angleDelta * config.angleStep : pixelDelta;
}

// Like Kirigami's OutCubic scroll animation: duration scales with remaining
// distance, with a short floor for visible motion. Values are KOS defaults.
export function continuousDuration(distance, config = CONFIG) {
    const pixels = Math.abs(distance);
    if (pixels <= 2)
        return 0;
    return Math.max(50, Math.min(200, Math.round(pixels * 200 / (120 * config.angleStep))));
}
