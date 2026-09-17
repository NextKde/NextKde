// Node harness for the superelliptical corner field. Run directly:
//
//   node shell/desktop/modules/common/test_squircle.mjs
//
// Two things are pinned here that a screenshot cannot pin:
//
//   1. Exponent 2 reproduces the circular rounded box bit for bit, so the
//      feature can never regress the surfaces that keep the default.
//   2. Raising the exponent does not cost anti-aliasing quality. The compositor
//      already anti-aliases with 1 - clamp(0.5 + f / fwidth(f)) and this module
//      mirrors that expression; the measurements below are what justify reusing
//      it for a superellipse instead of tessellating a path.
//
// The last block reads shaders/squircle.frag and checks it against this module
// numerically / structurally, so the two hand-written mirrors cannot drift
// apart unnoticed.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
    MAX_EXPONENT,
    MIN_EXPONENT,
    clampCornerRadius,
    halfExtentAt,
    normalizeExponent,
    squircleCoverage,
    squircleDistance,
    squircleGradient,
    squircleNorm,
} from "./Squircle.mjs";

// ---------------------------------------------------------------------------
// Reference: the classic rounded box, exactly as Qt and the compositor write it
// ---------------------------------------------------------------------------

function roundedBoxReference(x, y, halfWidth, halfHeight, radius) {
    const qx = Math.abs(x) - halfWidth + radius;
    const qy = Math.abs(y) - halfHeight + radius;
    return Math.min(Math.max(qx, qy), 0)
        + Math.sqrt(Math.max(qx, 0) * Math.max(qx, 0)
            + Math.max(qy, 0) * Math.max(qy, 0))
        - radius;
}

let checks = 0;
function check(condition, message) {
    checks += 1;
    assert.ok(condition, message);
}

// ---------------------------------------------------------------------------
// 1. Exponent handling
// ---------------------------------------------------------------------------

assert.equal(normalizeExponent(undefined), MIN_EXPONENT);
assert.equal(normalizeExponent(null), MIN_EXPONENT);
assert.equal(normalizeExponent(Number.NaN), MIN_EXPONENT);
assert.equal(normalizeExponent(1), MIN_EXPONENT);
assert.equal(normalizeExponent(-4), MIN_EXPONENT);
assert.equal(normalizeExponent(99), MAX_EXPONENT);
assert.equal(normalizeExponent(3.5), 3.5);
checks += 7;

// A radius larger than the shorter half-extent must clamp, or a pill produces
// overlapping corner regions.
assert.equal(clampCornerRadius(200, 196, 60), 60);
assert.equal(clampCornerRadius(-5, 196, 60), 0);
assert.equal(clampCornerRadius(28, 196, 60), 28);
checks += 3;

// ---------------------------------------------------------------------------
// 2. Exponent 2 is the circular rounded box, exactly
// ---------------------------------------------------------------------------

{
    const halfWidth = 196;
    const halfHeight = 60;
    const radius = 28;
    for (let x = -220; x <= 220; x += 7.5) {
        for (let y = -80; y <= 80; y += 3.25) {
            const mine = squircleDistance(x, y, halfWidth, halfHeight, radius, 2);
            const reference = roundedBoxReference(x, y, halfWidth, halfHeight,
                radius);
            assert.ok(Object.is(mine, reference),
                "exponent 2 must be bit-identical to the rounded box at "
                + x + "," + y + ": " + mine + " vs " + reference);
            checks += 1;
        }
    }
}

// ---------------------------------------------------------------------------
// 3. The corner gets fuller but never leaves the bounding box
//
// This is the property that lets the exponent change without resizing any
// item: the superelliptical corner bulges outside the circular arc, yet the
// bounding box still contains it.
// ---------------------------------------------------------------------------

{
    const halfWidth = 196;
    const halfHeight = 60;
    const radius = 28;
    const exponents = [2, 2.5, 3, 4, 5, 6, 8];
    const diagonalExtents = [];

    for (const exponent of exponents) {
        // Walk the outline near the top-right corner and find the boundary.
        // The corner centre is where the straight edges would have met.
        const centreX = halfWidth - radius;
        const centreY = halfHeight - radius;

        let maxX = 0;
        let maxY = 0;
        let diagonal = 0;

        for (let step = 0; step <= 2000; step += 1) {
            const angle = Math.PI * 0.5 * step / 2000;
            const directionX = Math.cos(angle);
            const directionY = Math.sin(angle);

            // Bisect outward from the corner centre for the zero crossing.
            let low = 0;
            let high = radius * 4;
            for (let iteration = 0; iteration < 60; iteration += 1) {
                const mid = (low + high) / 2;
                const d = squircleDistance(centreX + directionX * mid,
                    centreY + directionY * mid, halfWidth, halfHeight, radius,
                    exponent);
                if (d < 0)
                    low = mid;
                else
                    high = mid;
            }

            const boundaryX = centreX + directionX * low;
            const boundaryY = centreY + directionY * low;
            maxX = Math.max(maxX, boundaryX);
            maxY = Math.max(maxY, boundaryY);
            if (step === 1000)
                diagonal = low;
        }

        check(maxX <= halfWidth + 1e-9,
            "exponent " + exponent + " must stay inside the box in x, got "
            + maxX + " > " + halfWidth);
        check(maxY <= halfHeight + 1e-9,
            "exponent " + exponent + " must stay inside the box in y, got "
            + maxY + " > " + halfHeight);
        // And it must actually be fuller than the circle, or the whole feature
        // is a no-op.
        check(diagonal >= radius - 1e-9,
            "exponent " + exponent + " must reach at least the circular extent");

        diagonalExtents.push(diagonal);
    }

    // Monotone: each step up in exponent reaches further along the diagonal.
    for (let i = 1; i < diagonalExtents.length; i += 1)
        check(diagonalExtents[i] > diagonalExtents[i - 1],
            "corner fullness must increase with the exponent");

    // The closed form the module documents: radius * 2^(1/2 - 1/n).
    for (let i = 0; i < exponents.length; i += 1) {
        const expected = radius * Math.pow(2, 0.5 - 1 / exponents[i]);
        check(Math.abs(diagonalExtents[i] - expected) < 1e-6,
            "diagonal extent for exponent " + exponents[i] + " should be "
            + expected + ", got " + diagonalExtents[i]);
    }
}

// ---------------------------------------------------------------------------
// 4. Row extents (the hook a rectangular blur region needs)
// ---------------------------------------------------------------------------

{
    const halfWidth = 196;
    const halfHeight = 60;
    const radius = 28;

    // Straight part: full width.
    check(halfExtentAt(0, halfWidth, halfHeight, radius, 4) === halfWidth,
        "the straight edge spans the full width");
    checks += 1;

    // Exponent 2 must reproduce the exact circle: sqrt(r^2 - qy^2).
    for (let qy = 0.5; qy < radius; qy += 0.5) {
        const mine = halfExtentAt(halfHeight - radius + qy, halfWidth,
            halfHeight, radius, 2);
        const reference = halfWidth - radius
            + Math.sqrt(radius * radius - qy * qy);
        check(Math.abs(mine - reference) < 1e-9,
            "row extent at qy=" + qy + " should be " + reference + ", got "
            + mine);
    }

    // Higher exponents must cover at least the circular row (that is exactly
    // why an ellipse-based region under-covers a squircle).
    for (let qy = 0.5; qy < radius; qy += 0.5) {
        const circular = halfExtentAt(halfHeight - radius + qy, halfWidth,
            halfHeight, radius, 2);
        const squircle = halfExtentAt(halfHeight - radius + qy, halfWidth,
            halfHeight, radius, 4);
        check(squircle >= circular - 1e-9,
            "a squircle row must not be narrower than the circular one");
    }
}

// ---------------------------------------------------------------------------
// 5. Anti-aliasing quality does not depend on the exponent
//
// The mask uses the compositor's own footprint: coverage = 1 - clamp(0.5 +
// f / fwidth(f)). fwidth is an L1 screen-space measure, so the ramp works out
// to one pixel across an axis-aligned edge and sqrt(2) pixels at 45 degrees --
// both inherited from the compositor shader, unchanged.
//
// The measurement below marches across the corner diagonal, where a
// superellipse differs most from a circle, and recovers the band from the
// coverage slope: the ramp is linear in the field over one full band width, so
// the width is the reciprocal of the slope. Measuring between two fixed
// thresholds instead (say 0.98 and 0.02) would report only 96% of the band and
// invite a tolerance that hides a real regression.
//
// This is the number that decides the family, so it is measured rather than
// argued: had a formulation been chosen where |grad f| drifts with the
// exponent, this width would move with it.
// ---------------------------------------------------------------------------

function bandFromSlope(centreX, centreY, directionX, directionY, halfWidth,
    halfHeight, radius, exponent, pixelSize) {
    // Bisect for the zero crossing along the sampled line.
    let low = 0;
    let high = Math.max(halfWidth, halfHeight) * 2;
    for (let iteration = 0; iteration < 80; iteration += 1) {
        const mid = (low + high) / 2;
        if (squircleDistance(centreX + directionX * mid,
            centreY + directionY * mid, halfWidth, halfHeight, radius,
            exponent) < 0)
            low = mid;
        else
            high = mid;
    }
    const boundary = low;
    // 0.3px stays inside the linear part of the ramp for a band of at least
    // 0.6px, i.e. for every pixel size and every member of the family.
    const span = pixelSize * 0.3;
    const inside = squircleCoverage(centreX + directionX * (boundary - span),
        centreY + directionY * (boundary - span), halfWidth, halfHeight, radius,
        exponent, pixelSize);
    const outside = squircleCoverage(centreX + directionX * (boundary + span),
        centreY + directionY * (boundary + span), halfWidth, halfHeight, radius,
        exponent, pixelSize);
    assert.ok(inside > outside,
        "coverage must fall across the boundary for exponent " + exponent);
    assert.ok(inside < 1 && outside > 0,
        "both samples must sit on the ramp, not in the clamped region");
    return 2 * span / (inside - outside);
}

{
    const pixelSize = 1.0;
    const halfWidth = 120;
    const halfHeight = 120;
    const radius = 30;
    const expectedDiagonal = Math.SQRT2 * pixelSize;

    const widths = [];
    for (const exponent of [2, 2.5, 3, 4, 5, 6, 8]) {
        const width = bandFromSlope(halfWidth - radius, halfHeight - radius,
            Math.SQRT1_2, Math.SQRT1_2, halfWidth, halfHeight, radius, exponent,
            pixelSize);
        widths.push({ exponent, width });
        check(Math.abs(width - expectedDiagonal) < 1e-3,
            "the anti-aliased band on the corner diagonal should stay "
            + expectedDiagonal + "px at exponent " + exponent + ", measured "
            + width);
    }
    const spread = Math.max(...widths.map((entry) => entry.width))
        - Math.min(...widths.map((entry) => entry.width));
    check(spread < 1e-3,
        "the ramp width must not drift with the exponent, spread was "
        + spread);

    // Axis-aligned edges keep the one-pixel ramp. Sampled on the straight edge,
    // perpendicular to it.
    let flatWidth = 0;
    for (const exponent of [2, 4, 8]) {
        const width = bandFromSlope(halfWidth - 0.5, 0, 1, 0, halfWidth,
            halfHeight, radius, exponent, pixelSize);
        if (exponent === 2)
            flatWidth = width;
        check(Math.abs(width - pixelSize) < 1e-3,
            "the straight-edge ramp should stay one pixel wide at exponent "
            + exponent + ", measured " + width);
    }

    console.log("  AA band: flat edge " + flatWidth.toFixed(4)
        + "px (1px), corner diagonal "
        + widths[0].width.toFixed(4) + "px (sqrt(2)px), spread across"
        + " exponents 2..8 " + spread.toExponential(1));
}

// ---------------------------------------------------------------------------
// 6. Gradient sanity (documents the 16% band-width caveat)
// ---------------------------------------------------------------------------

{
    const halfWidth = 120;
    const halfHeight = 120;
    const radius = 30;

    for (const exponent of [2, 3, 4, 6, 8]) {
        // On the axis, i.e. the middle of a straight edge.
        const axis = squircleGradient(halfWidth - 0.001, 0, halfWidth,
            halfHeight, radius, exponent);
        check(Math.abs(axis.x - 1) < 1e-6 && Math.abs(axis.y) < 1e-6,
            "the gradient is unit length across a straight edge");
        checks += 1;

        // On the corner diagonal the p-norm gradient is shorter than the
        // Euclidean one by 2^(1/n - 1/2).
        const offset = radius * 0.5;
        const diagonal = squircleGradient(halfWidth - radius + offset,
            halfHeight - radius + offset, halfWidth, halfHeight, radius,
            exponent);
        const length = Math.sqrt(diagonal.x * diagonal.x
            + diagonal.y * diagonal.y);
        const expected = Math.pow(2, 1 / exponent - 0.5);
        check(Math.abs(length - expected) < 1e-6,
            "diagonal gradient length at exponent " + exponent + " should be "
            + expected + ", got " + length);
        checks += 1;
    }
}

// ---------------------------------------------------------------------------
// 7. The shader mirror
// ---------------------------------------------------------------------------

{
    const source = readFileSync(
        new URL("../../shaders/squircle.frag", import.meta.url), "utf8");
    const flat = source.replace(/\s+/g, " ");

    // --- Numeric: transpile the shader's squircleNorm() and compare. -------
    function extractBody(name) {
        const start = source.indexOf("float " + name + "(");
        assert.ok(start >= 0,
            "squircle.frag no longer declares " + name + "()");
        const open = source.indexOf("{", start);
        let depth = 0;
        for (let index = open; index < source.length; index += 1) {
            if (source[index] === "{")
                depth += 1;
            else if (source[index] === "}") {
                depth -= 1;
                if (depth === 0)
                    return source.slice(open + 1, index);
            }
        }
        assert.fail("unbalanced braces in " + name);
    }

    const normBody = extractBody("squircleNorm");
    const normJs = normBody
        .replace(/length\(q\)/g, "Math.sqrt(qx * qx + qy * qy)")
        .replace(/\bq\.x\b/g, "qx")
        .replace(/\bq\.y\b/g, "qy")
        .replace(/(?<!\bMath\.)\bpow\(/g, "Math.pow(")
        .replace(/\bn == 2\.0\b/g, "n === 2")
        .replace(/(\d)\.0\b/g, "$1");
    assert.doesNotMatch(normJs, /vec2|halfSize|radius|q\./,
        "the squircleNorm mirror needs updating: " + normJs);
    // eslint-disable-next-line no-new-func
    const shaderNorm = new Function("qx", "qy", "n", normJs);

    let normComparisons = 0;
    for (const exponent of [2, 2.5, 3, 4, 6, 8]) {
        for (let qx = 0; qx <= 40; qx += 1.7) {
            for (let qy = 0; qy <= 40; qy += 2.3) {
                const mine = squircleNorm(qx, qy, exponent);
                const theirs = shaderNorm(qx, qy, exponent);
                assert.equal(theirs, mine, "shader and JS p-norm disagree at "
                    + qx + "," + qy + " n=" + exponent);
                normComparisons += 1;
            }
        }
    }
    checks += normComparisons;

    // --- Structural: the construction and the footprint must stay put. -----
    check(flat.includes(
        "squircleNorm(max(q, vec2(0.0)), n) + min(max(q.x, q.y), 0.0) - radius"),
        "squircle.frag must keep the rounded-box construction");
    check(flat.includes("clamp(cornerExponent, 2.0, 8.0)"),
        "squircle.frag must clamp the exponent to the same range as "
        + "Squircle.mjs");
    check(flat.includes("fwidth(dist)"),
        "squircle.frag must anti-alias from the derivative, not a fixed width");
    check(flat.includes("1.0 - clamp(0.5 + dist / band, 0.0, 1.0)"),
        "squircle.frag must use the compressed compositor footprint");
    check(MIN_EXPONENT === 2 && MAX_EXPONENT === 8,
        "MIN_EXPONENT / MAX_EXPONENT must match the shader clamp");

    // --- Cross-check against the compositor's own mask, when the vendored
    //     effect is present. The whole point of matching the family is that
    //     both edges describe one outline.
    const compositor = new URL(
        "../../../../vendor/kwin-effects-glass/src/shaders/onscreen_rounded.glsl",
        import.meta.url);
    try {
        const compositorSource = readFileSync(compositor, "utf8")
            .replace(/\s+/g, " ");
        check(compositorSource.includes("clamp(0.5 + f / df, 0.0, 1.0)"),
            "the vendored compositor mask changed its footprint; "
            + "squircle.frag must follow it");
    } catch {
        console.log("note: vendored kwin-effects-glass not found, "
            + "skipping the compositor footprint cross-check");
    }
}

console.log("squircle: " + checks + " checks passed");
