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
