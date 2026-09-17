// Superelliptical corner geometry -- one implicit function, several consumers.
//
// A shell surface's outline is drawn by more than one layer: the QML material
// mask (SquircleMask.qml), the compositor blur region (RoundedBlurRegion.qml,
// rectangular primitives only) and, from the KWin side of the work, the glass
// mask in vendor/kwin-effects-glass. Each is written in a different language,
// so the field lives here once and every other copy is a mirror of it:
//
//   Squircle.mjs                                 reference -- this file
//   SquircleMask.qml + shaders/squircle.frag     GPU mirror (QML side)
//   glass.glsl / onscreen_rounded.glsl           GPU mirror (compositor side)
//
// Keep them in sync. If the mask and the compositor mask stop evaluating the
// same family the content edge and the glass edge split apart around 45
// degrees, which is far more visible than either edge on its own.
//
// EXPONENT
//   2.0  a circular arc. Reproduces Rectangle.radius and today's glass mask
//        exactly, so 2.0 is always the safe value.
//   3-4  the continuous-curvature profile iOS uses.
//   >5   increasingly square; the corner stops reading as rounded.
//
// WHY THE P-NORM AND NOT |x/a|^n + |y/b|^n = 1
// The corner is the only place geometry changes, so the field keeps the
// rounded-box construction and swaps `length(max(q, 0))` for `pnorm(max(q, 0))`:
//
//   q = abs(p) - halfSize + radius
//   d = pnorm(max(q, 0), n) + min(max(q.x, q.y), 0) - radius
//
// Two properties fall out of that choice and both matter:
//
//   1. At n = 2 the p-norm IS length(), so the function is a strict
//      generalisation and nothing regresses.
//   2. The gradient of a p-norm is unit length on the axes and
//      2^(1/n - 1/2) on the diagonal -- 0.841 at n = 4, i.e. within 16% of a
//      true distance field. The anti-aliasing uses f / fwidth(f), a ratio that
//      cancels the gradient length entirely, so it is unaffected; only the
//      refraction band, which is measured in absolute pixels, drifts by that
//      16% and only near the corner diagonal.
//
// The corner radius keeps its current meaning: it is still the tangent length
// where the straight edge ends, at |x| = halfWidth - radius. What changes is
// that the corner bulges OUTSIDE the circular one -- it reaches
// radius * 2^(1/2 - 1/exponent) diagonally instead of radius, which is 18.9%
// further at exponent 4. It stays inside the bounding box (the corner's
// diagonal point sits 0.159 * radius in from the box corner), so no item has to
// grow -- but the compositor's circular blur region no longer covers it.
// halfExtentAt() is the hook that rebuilds that region.
//
// Numbers in this file are mirrored in shaders/squircle.frag, which is the
// authority for what the GPU actually evaluates; test_squircle.mjs pins the
// behaviour of the functions below.

export const MIN_EXPONENT = 2
export const MAX_EXPONENT = 8

// Anything unusable falls back to the circular case rather than throwing: this
// runs inside QML property bindings, where a thrown error would blank a
// surface.
export function normalizeExponent(value) {
    if (value === undefined || value === null || !Number.isFinite(value))
        return MIN_EXPONENT
    return Math.min(MAX_EXPONENT, Math.max(MIN_EXPONENT, value))
}

// The mask clamps the radius to the shorter half-extent, otherwise a pill
// (radius === halfHeight) produces overlapping corner regions.
export function clampCornerRadius(radius, halfWidth, halfHeight) {
    const limit = Math.min(halfWidth, halfHeight)
    if (radius === undefined || radius === null || !Number.isFinite(radius))
        return 0
    return Math.min(Math.max(radius, 0), limit)
}

// p-norm of a non-negative 2-vector. exponent 2 collapses to the Euclidean
// length so the circular case is reproduced exactly rather than approximately.
export function squircleNorm(x, y, exponent) {
    const n = normalizeExponent(exponent)
    if (n === 2)
        return Math.sqrt(x * x + y * y)
    if (x <= 0)
        return y
    if (y <= 0)
        return x
    return Math.pow(Math.pow(x, n) + Math.pow(y, n), 1 / n)
}

// Signed field, negative inside. Mirrors squircleDistance() in
// shaders/squircle.frag.
export function squircleDistance(x, y, halfWidth, halfHeight, radius, exponent) {
    const n = normalizeExponent(exponent)
    const r = clampCornerRadius(radius, halfWidth, halfHeight)
    const qx = Math.abs(x) - halfWidth + r
    const qy = Math.abs(y) - halfHeight + r
    return squircleNorm(Math.max(qx, 0), Math.max(qy, 0), n)
        + Math.min(Math.max(qx, qy), 0) - r
}

// Analytic gradient. { x, y } rather than a tuple so call sites read the same
// way the GLSL does.
//
// Outside the box the gradient of a p-norm has unit length on the axes and
// 2^(1/n - 1/2) on the diagonal; along a straight edge it is exactly unit, and
// in the interior it is unit along whichever axis the min/max term picks.
export function squircleGradient(x, y, halfWidth, halfHeight, radius, exponent) {
    const n = normalizeExponent(exponent)
    const r = clampCornerRadius(radius, halfWidth, halfHeight)
    const sx = x < 0 ? -1 : 1
    const sy = y < 0 ? -1 : 1
    const qx = Math.abs(x) - halfWidth + r
    const qy = Math.abs(y) - halfHeight + r

    if (qx > 0 && qy > 0) {
        const rho = squircleNorm(qx, qy, n)
        if (rho > 0) {
            const scale = Math.pow(rho, 1 - n)
            return { x: sx * Math.pow(qx, n - 1) * scale,
                y: sy * Math.pow(qy, n - 1) * scale }
        }
        // Degenerate: pnorm only reaches 0 when both components do, which is
        // the box centre. Direction is arbitrary there.
        return { x: sx, y: sy }
    }
    if (qx > 0)
        return { x: sx, y: 0 }
    if (qy > 0)
        return { x: 0, y: sy }
    return qx > qy ? { x: sx, y: 0 } : { x: 0, y: sy }
}

// Coverage of the shape at one pixel centre, using the compositor's own
// first-order footprint (vendor/kwin-effects-glass:
// src/shaders/onscreen_rounded.glsl -- sum *= 1 - clamp(0.5 + f / fwidth(f))).
//
// On the GPU fwidth() comes from screen-space derivatives; for a smooth field
// that is pixelSize * (|df/dx| + |df/dy|). Two consequences worth stating,
// because they are the entire reason to shape a surface with an SDF instead of
// tessellating a path:
//
//   - The expression is a ratio, so it scales itself to the field. The
//     anti-aliased band stays one pixel wide for every exponent in the family;
//     raising the exponent costs nothing in edge quality.
//   - The band widens to at most sqrt(2) pixels on a 45-degree edge, because
//     fwidth sums the two axis derivatives. That is inherent to the technique
//     and identical for a circle and a superellipse.
export function squircleCoverage(x, y, halfWidth, halfHeight, radius, exponent,
    pixelSize) {
    const distance = squircleDistance(x, y, halfWidth, halfHeight, radius,
        exponent)
    const gradient = squircleGradient(x, y, halfWidth, halfHeight, radius,
        exponent)
    const band = pixelSize * (Math.abs(gradient.x) + Math.abs(gradient.y))
    if (!(band > 0))
        return distance <= 0 ? 1 : 0
    return 1 - Math.min(1, Math.max(0, 0.5 + distance / band))
}

// Horizontal half-extent of the shape at |y| = offset, i.e. the row width a
// rectangular region builder needs. Wayland regions have no curved primitive,
// and RoundedBlurRegion's four ellipses under-cover a superelliptical corner,
// so the region side of the work feeds rows of this into square Regions.
export function halfExtentAt(offset, halfWidth, halfHeight, radius, exponent) {
    const n = normalizeExponent(exponent)
    const r = clampCornerRadius(radius, halfWidth, halfHeight)
    const ay = Math.abs(offset)
    if (ay <= halfHeight - r)
        return halfWidth
    const qy = ay - halfHeight + r
    if (qy >= r)
        return halfWidth - r
    const inner = Math.pow(r, n) - Math.pow(qy, n)
    if (!(inner > 0))
        return halfWidth - r
    return halfWidth - r + Math.pow(inner, 1 / n)
}
