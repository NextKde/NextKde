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

// Quintic smootherstep gives a broad centre and zero first/second derivatives
// at both ends. Neighbours join the wave gradually instead of a narrow peak.
export function influenceAt(distance, radius) {
    const t = Math.min(1, Math.abs(distance) / Math.max(1, radius));
    return 1 - t * t * t * (10 + t * (-15 + 6 * t));
}

// Artwork and translation use the same kernel and its analytic integral.
export function layout(states, pointer, progress, maxScale, radius, spacing = 0, bounds = null) {
    // 100% disables the entire wave, including plate-gap tightening.
    if (maxScale <= 1) progress = 0;
    const amplitude = Math.max(0, maxScale - 1) * progress;
    let slot = 0, artwork = 0;
    for (const state of states) {
        if (!state.growable) continue;
        slot = Math.max(slot, state.half * 2);
        artwork = Math.max(artwork, (state.artHalf ?? state.half) * 2);
    }
    const pitch = Math.max(1, slot + spacing);
    // Only artwork grows. Reserved padding and Row spacing must not be
    // multiplied along with it; that was adding empty room between icons.
    const density = artwork / pitch;
    const shoulder = pitch / 2;
    const support = Math.max(1, radius);
    let baseLeft = Infinity, baseRight = -Infinity;
    const entries = states.map(state => {
        const d = state.cx - pointer;
        const kernel = influenceAt(d, support);
        const influence = state.growable ? progress * kernel : 0;
        const scale = 1 + Math.max(0, maxScale - 1) * influence;
        const distance = Math.abs(d);
        const u = Math.min(1, Math.max(0, distance - shoulder) / support);
        // Integral of 1 - 10*u^3 + 15*u^4 - 6*u^5. The half-pitch envelope reserves enough
        // space between adjacent growing artwork, including a wave flank.
        const integral = u - u * u * u * u * (2.5 + u * (-3 + u));
        const dx = Math.sign(d) * density * (Math.min(distance, shoulder)
            + support * integral) * amplitude;
        const half = state.half + (state.artHalf ?? state.half) * (scale - 1)
            - (state.growable ? (state.hoverGapReduction ?? 0) * influence : 0);
        return { item: state.item, progress: influence, dx: dx, scale: scale, half: half };
    });
    const flexibleIndex = states.findIndex(state => state.flexible);
    let prefixOffset = 0, prefixRight = bounds?.y ?? Infinity;
    if (flexibleIndex > 0) {
        // Relaxed layouts already fill the output. Grow the application group
        // into their empty middle slot, keeping the trailing controls fixed.
        // This changes paint translations only, never the Row's layout width.
        const first = entries[0];
        prefixOffset = Math.max(0, first.half - states[0].half - first.dx);
        if (flexibleIndex + 1 < states.length) {
            const trailing = states[flexibleIndex + 1];
            prefixRight = Math.min(prefixRight, trailing.cx - trailing.half - spacing);
        }
    }
    let fraction = 1;
    for (let i = 0; i < entries.length; ++i) {
        const entry = entries[i], state = states[i];
        if (flexibleIndex >= 0) {
            entry.dx = i < flexibleIndex ? entry.dx + prefixOffset : 0;
        }
        if (state.flexible) continue;
        baseLeft = Math.min(baseLeft, state.cx - state.half);
        baseRight = Math.max(baseRight, state.cx + state.half);
        // All deltas are linear in progress. Limit the whole wave together;
        // clamping just the glass would still clip or overlap the artwork.
        if (bounds) {
            const leftDelta = entry.dx - (entry.half - state.half);
            const rightDelta = entry.dx + (entry.half - state.half);
            const rightBound = flexibleIndex >= 0 && i < flexibleIndex
                ? prefixRight : bounds.y;
            if (leftDelta < 0)
                fraction = Math.min(fraction,
                    Math.max(0, (state.cx - state.half - bounds.x) / -leftDelta));
            if (rightDelta > 0)
                fraction = Math.min(fraction,
                    Math.max(0, (rightBound - state.cx - state.half) / rightDelta));
        }
    }
    let left = Infinity, right = -Infinity;
    const byItem = new Map();
    for (let i = 0; i < entries.length; ++i) {
        const entry = entries[i], state = states[i];
        entry.progress *= fraction;
        entry.dx *= fraction;
        entry.scale = 1 + (entry.scale - 1) * fraction;
        entry.half = state.half + (entry.half - state.half) * fraction;
        // Build lookup in this existing pass, without N temporary pair arrays.
        byItem.set(entry.item, entry);
        if (state.flexible) continue;
        left = Math.min(left, state.cx + entry.dx - entry.half);
        right = Math.max(right, state.cx + entry.dx + entry.half);
    }
    const hasExtent = Number.isFinite(baseLeft) && amplitude > 0;
    return { entries: entries, byItem: byItem,
        total: hasExtent ? Math.max(0, right - left - (baseRight - baseLeft)) : 0,
        shift: hasExtent ? (right + left - baseRight - baseLeft) / 2 : 0 };
}

// The wave belongs to the application group. Rigid cards/tray accessories
// keep their own hover interactions, even next to a magnified edge icon.
export function overApps(states, frame, pointer) {
    let left = Infinity, right = -Infinity;
    for (const state of states) {
        const entry = frame.byItem.get(state.item);
        const cx = state.cx + (entry?.dx ?? 0);
        const half = entry?.half ?? state.half;
        if (!state.growable) {
            if (state.blocksMagnification !== false
                && pointer >= cx - half && pointer <= cx + half) return false;
            continue;
        }
        left = Math.min(left, state.cx - state.half, cx - half);
        right = Math.max(right, state.cx + state.half, cx + half);
    }
    return pointer >= left && pointer <= right;
}
