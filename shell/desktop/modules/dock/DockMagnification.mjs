// Exact first-order response for a target held during this frame. Unlike a
// fixed per-frame lerp (or SpringAnimation's 16 ms integration), elapsed time
// determines the response, so 60/120/144 Hz follow the same curve. A changing
// target is chased immediately without retaining an obsolete spring velocity.
export function advance(current, target, deltaSeconds, responseSeconds, epsilon) {
    const distance = target - current;
    if (Math.abs(distance) <= epsilon)
        return target;
    if (!Number.isFinite(deltaSeconds) || deltaSeconds <= 0)
        return current;
    const next = target - distance * Math.exp(-deltaSeconds / responseSeconds);
    return Math.abs(target - next) <= epsilon ? target : next;
}

// Critical landing: the same first-order response, but the time constant
// shrinks with the remaining error once it drops below `knee`. While the
// error is large the smoothing is exactly `advance`'s (a moving target is
// damped at the full response), so mid-motion behaviour -- tremor rejection,
// slot-handover rounding -- is unchanged. The asymptotic tail, which read as
// the row still sliding for ~0.7 s after the pointer stopped, collapses
// instead: each halving of the error also halves the time constant, so the
// last pixels land in a couple of frames. Monotone, no overshoot.
export function advanceCritical(current, target, deltaSeconds, responseSeconds,
                                knee, epsilon) {
    const distance = target - current;
    const error = Math.abs(distance);
    if (error <= epsilon)
        return target;
    if (!Number.isFinite(deltaSeconds) || deltaSeconds <= 0)
        return current;
    const response = responseSeconds * Math.min(1, error / knee);
    const next = target - distance
        * Math.exp(-deltaSeconds / Math.max(response, deltaSeconds * 0.25));
    return Math.abs(target - next) <= epsilon ? target : next;
}
