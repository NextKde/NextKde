import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

// Regression for #214: the wallpaper preview panels animate `scale` on entry
// (scale: 0.94 + 0.06 * opacity), and SurfaceShape computes its compositor
// geometry through mapRectToScene — which folds transforms in. But the sync
// triggers only listened to x/y/width/height/visible/opacity, so during a
// scale animation the rounded-corner shape stayed at the pre-animation
// geometry and the window edge grew fuzzy fringes until the animation ended.
//
// The fix listens to scaleChanged on both the target and every ancestor. This
// test pins that contract against the real source: any future connect list
// that drops scaleChanged (or a rewire that forgets the ancestors) fails here.

const source = readFileSync(
    new URL("../../shell/native/surface-shape/surfaceshape.cpp", import.meta.url), "utf8");

// Slice the two connect sites apart. setTarget() runs from `if (m_target) {`
// to the closing `} else {` of its rewire branch; rewireAncestors() starts at
// its own signature.
function sliceBetween(startMarker, endMarker) {
    const start = source.indexOf(startMarker);
    assert.ok(start > 0, `start marker ${JSON.stringify(startMarker)} moved; update test`);
    const end = source.indexOf(endMarker, start);
    assert.ok(end > start, `end marker ${JSON.stringify(endMarker)} moved; update test`);
    return source.slice(start, end);
}

test("surfaceshape listens to scale", async () => {
    // ── setTarget(): the target's own scale must re-run the sync ──
    const setTarget = sliceBetween("void SurfaceShape::setTarget", "} else {");
    assert.match(setTarget, /connect\(m_target, &QQuickItem::scaleChanged,\s*\n?\s*this, &SurfaceShape::scheduleSync\)/,
        "setTarget must connect QQuickItem::scaleChanged to scheduleSync:"
        + " scale feeds mapRectToScene but emits no geometry signal"
        + " (issue #214 wallpaper preview fringes)");

    // ── rewireAncestors(): an ancestor's scale moves the target too ──
    const rewire = sliceBetween("void SurfaceShape::rewireAncestors",
        "void SurfaceShape::disconnectAncestors");
    assert.match(rewire, /connect\(item, &QQuickItem::scaleChanged,\s*\n?\s*this, &SurfaceShape::scheduleSync\)/,
        "rewireAncestors must connect scaleChanged on every ancestor");

    // ── the sync really derives geometry from mapRectToScene ──
    // (If this changes, the transform sensitivity contract changes with it.)
    const sync = sliceBetween("void SurfaceShape::sync", "kos_surface_shape_v1_set_geometry");
    assert.match(sync, /mapRectToScene\(/,
        "sync still reads geometry through mapRectToScene; if this changed,"
        + " re-evaluate which signals matter");

    // ── both scale connects use the same scheduleSync as geometry does ──
    const connects = source.match(/&QQuickItem::scaleChanged/g) || [];
    assert.ok(connects.length >= 2,
        "expected scaleChanged connects on target and ancestors, found "
        + connects.length);
});
