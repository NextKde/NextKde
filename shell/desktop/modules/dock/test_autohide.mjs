// Test harness for DockAutoHideMath.mjs — run with: node test_autohide.mjs
import {
    visibleDockRect, avoidanceRect, releaseRect, intersects,
    windowEligible, hasConflict, shouldBeVisible, policyWantsHidden,
    handleSizes, dockOpacity, dockScale, handleOpacity
} from "./DockAutoHideMath.mjs";

let errors = 0;
const checks = [];
function ok(cond, label) {
    checks.push([cond, label]);
    if (!cond) errors++;
}
function nearly(a, b, eps = 1e-6) {
    return Math.abs(a - b) <= eps;
}

// ── Zoom: a 50%-scaled screen. Everything uses logical coords (1920 wide).
const S = { x: 0, y: 0, width: 1920, height: 1080, name: "DP-1" };
const DIM = 260; // dock width for side, height for bottom — any plausible value

// ── visibleDockRect: top / bottom / left / right ──
{
    const r = visibleDockRect(S, "top", 1920 - 30, 35, 15);
    ok(nearly(r.x, 15), "top x = edgeMargin");
    ok(nearly(r.y, 0), "top y = screen top");
    ok(nearly(r.width, 1920 - 30) && nearly(r.height, 35), "top size");
}
{
    const r = visibleDockRect(S, "bottom", DIM, 60, 5);
    ok(nearly(r.x, (1920 - DIM) / 2), "bottom centred x");
    ok(nearly(r.y, 1080 - 5 - 60), "bottom y above edgeMargin");
    ok(nearly(r.width, DIM) && nearly(r.height, 60), "bottom size");
}
{
    const r = visibleDockRect(S, "left", 260, 60, 5);
    ok(nearly(r.x, 5), "left x = edgeMargin");
    ok(nearly(r.y, (1080 - 60) / 2), "left centred y");
}
{
    const r = visibleDockRect(S, "right", 260, 60, 5);
    ok(nearly(r.x, 1920 - 5 - 260), "right x inset from edge");
    ok(nearly(r.y, (1080 - 60) / 2), "right centred y");
}

// ── Negative-coordinate screen (a display left/above the primary) ──
{
    const NEG = { x: -1280, y: -100, width: 1280, height: 720, name: "DP-2" };
    const r = visibleDockRect(NEG, "bottom", DIM, 60, 5);
    ok(nearly(r.x, NEG.x + (NEG.width - DIM) / 2), "negative-x bottom centred");
    ok(nearly(r.y, NEG.y + NEG.height - 5 - 60), "negative-y bottom y");
    const l = visibleDockRect(NEG, "left", DIM, 60, 5);
    ok(nearly(l.x, NEG.x + 5), "negative-x left inset");
}

// ── expand / avoidance / release rects ──
{
    const base = { x: 100, y: 100, width: 50, height: 30 };
    const av = avoidanceRect(base);
    ok(av.x === 92 && av.width === 66, "avoidance expands 8px each side");
    const rel = releaseRect(base);
    ok(rel.x === 84 && rel.width === 82, "release expands 16px each side");
    ok(rel.x < av.x && rel.x < base.x, "release is wider than avoidance");
}
{
    const a = { x: 0, y: 0, width: 10, height: 10 };
    const b = { x: 5, y: 5, width: 10, height: 10 };
    ok(intersects(a, b), "overlapping rects intersect");
    const c = { x: 11, y: 0, width: 10, height: 10 };
    ok(!intersects(a, c), "adjacent (1px gap) rects do not intersect");
    const d = { x: 9, y: 0, width: 10, height: 10 };
    ok(intersects(a, d), "1px overlap does intersect");
}

// ── windowEligible / hasConflict ──
function win(overrides) {
    return Object.assign({
        geometry: { x: 800, y: 700, width: 300, height: 200 },
        isMinimized: false,
        isFullscreen: false,
        onAllDesktops: false,
        desktopIds: ["d1"],
        screenName: "DP-1"
    }, overrides);
}

// A minimized window never participates.
ok(!windowEligible(win({ isMinimized: true }), S, "d1"), "minimized filtered");
// A window on another desktop is filtered.
ok(!windowEligible(win({ desktopIds: ["d2"] }), S, "d1"), "other-desktop filtered");
// onAllDesktops bypasses the desktop check.
ok(windowEligible(win({ onAllDesktops: true }), S, "d1"), "onAllDesktops eligible");
// A window on another screen name but overlapping the target screen stays.
ok(windowEligible(win({ screenName: "DP-2" }), S, "d1"), "overlap keeps window");
// Zero geometry is never eligible (provider geometry missing).
ok(!windowEligible(win({ geometry: null }), S, "d1"), "missing geometry filtered");
ok(!windowEligible(win({ geometry: { x: 0, y: 0, width: 0, height: 0 } }), S, "d1"), "zero geometry filtered");
// A window with neither a matching screen name nor overlapping geometry is
// filtered (foreign providers may have no output name, so overlap is the
// secondary keep).
ok(!windowEligible(win({ screenName: "DP-2", geometry: { x: 5000, y: 5000, width: 10, height: 10 } }), S, "d1"), "unrelated screen+geometry filtered");
// A same-name window with far geometry is still eligible (screen membership is
// the primary keep for KWin); the conflict pass ignores its far geometry.
ok(windowEligible(win({ geometry: { x: 5000, y: 5000, width: 10, height: 10 } }), S, "d1"), "same-screen-name window eligible");

const base = visibleDockRect(S, "bottom", DIM, 60, 5);
const av = avoidanceRect(base);
const rel = releaseRect(base);

// Window placed directly over the dock region triggers a conflict.
{
    const over = win({ geometry: { x: base.x + 5, y: base.y + 5, width: 50, height: 50 } });
    ok(hasConflict([over], S, av, rel, false, "d1"), "window over dock conflicts");
}
// Window 1px into the avoidance ring but not touching the visual dock also conflicts.
{
    const touch = win({ geometry: { x: base.x + 6, y: base.y - 9, width: 50, height: 50 } });
    ok(hasConflict([touch], S, av, rel, false, "d1"), "entry into 8px ring conflicts");
}
// Window parked in the 8–16px release ring: no fresh conflict, but an active
// conflict is retained (hysteresis). A 1px-tall window at y=1003 sits above the
// dock top (1015) between the avoidance (top 1007) and release (top 999) edges.
{
    const edge = win({ geometry: { x: base.x + 6, y: 1003, width: 50, height: 1 } });
    ok(!hasConflict([edge], S, av, rel, false, "d1"), "release-ring not a fresh conflict");
    ok(hasConflict([edge], S, av, rel, true, "d1"), "hysteresis keeps active conflict in release ring");
}
// Top avoidance and conflict test
{
    const topBase = visibleDockRect(S, "top", 1920 - 30, 35, 15);
    const topAv = avoidanceRect(topBase);
    const topRel = releaseRect(topBase);
    const winNearTop = win({ geometry: { x: 100, y: 10, width: 400, height: 300 } });
    ok(hasConflict([winNearTop], S, topAv, topRel, false, "d1"), "window near top conflicts with top bar");
    const winFarBottom = win({ geometry: { x: 100, y: 300, width: 400, height: 300 } });
    ok(!hasConflict([winFarBottom], S, topAv, topRel, false, "d1"), "window at bottom does not conflict with top bar");
}

// A far-away window never conflicts.
{
    const far = win({ geometry: { x: 100, y: 100, width: 300, height: 300 } });
    ok(!hasConflict([far], S, av, rel, false, "d1"), "distant window no conflict");
    ok(!hasConflict([far], S, av, rel, true, "d1"), "distant window clears conflict");
}
// Minimized window overlapping the dock does not conflict.
{
    const min = win({ geometry: { x: base.x, y: base.y, width: 50, height: 50 }, isMinimized: true });
    ok(!hasConflict([min], S, av, rel, false, "d1"), "minimized over dock ignored");
}
// Other-desktop window overlapping the dock does not conflict.
{
    const od = win({ geometry: { x: base.x, y: base.y, width: 50, height: 50 }, desktopIds: ["d9"] });
    ok(!hasConflict([od], S, av, rel, false, "d1"), "other-desktop over dock ignored");
}
// Other-screen window overlapping the dock's geometry participates (overlap is
// the eligibility keep), so it does conflict — verified through the far-window
// case above that its geometry is what matters. An unrelated-screen window far
// away does not.
{
    const os = win({ geometry: { x: base.x + 6, y: base.y + 6, width: 50, height: 50 }, screenName: "DP-9" });
    ok(hasConflict([os], S, av, rel, false, "d1"), "overlapping other-screen ignored for eligibility");
}
// A fullscreen window on this screen forces a conflict anywhere.
{
    const fs = win({ isFullscreen: true, geometry: { x: 0, y: 0, width: 1920, height: 1080 } });
    ok(hasConflict([fs], S, av, rel, false, "d1"), "fullscreen forces conflict");
}

// ── Policy: shouldBeVisible / policyWantsHidden ──
{
    // always ignores everything.
    ok(shouldBeVisible("always", true, false), "always visible with conflict");
    ok(!policyWantsHidden("always", true), "always no hide");
    // smart hides only on conflict (no inhibitor).
    ok(shouldBeVisible("smart", false, false), "smart visible without conflict");
    ok(!shouldBeVisible("smart", true, false), "smart hidden with conflict");
    ok(shouldBeVisible("smart", true, true), "smart stays with inhibitor");
    ok(policyWantsHidden("smart", true) && !policyWantsHidden("smart", false), "smart wants hidden on conflict only");
    // persistent hides regardless of conflict; inhibitor holds it.
    ok(!shouldBeVisible("persistent", false, false), "persistent hidden on empty desktop");
    ok(!shouldBeVisible("persistent", true, false), "persistent hidden with conflict");
    ok(shouldBeVisible("persistent", false, true), "persistent shown by inhibitor");
    ok(policyWantsHidden("persistent", false), "persistent always wants hidden");
}

// ── Handle sizes: 80% of the long edge, 4px thick ──
{
    const b = handleSizes(1920, 1080, "bottom");
    ok(b.width === Math.round(1920 * 0.8) && b.height === 4, "bottom handle = 80% wide x 4");
    const l = handleSizes(1920, 1080, "left");
    ok(l.width === 4 && l.height === Math.round(1080 * 0.8), "left handle = 4 x 80% tall");
    const r = handleSizes(1920, 720, "right");
    ok(r.width === 4 && r.height === Math.round(720 * 0.8), "right handle = 4 x 80% tall");
}

// ── Auxiliary visual values ──
{
    ok(nearly(handleOpacity(0.0), 1), "handle fully opaque when hidden (p=0)");
    ok(nearly(handleOpacity(0.42), 0), "handle gone by p>=0.42");
    ok(nearly(dockOpacity(1.0), 1.0) && nearly(dockOpacity(0.0), 0.30), "dock opacity band");
    ok(nearly(dockScale(0.0), 0.985) && nearly(dockScale(1.0), 1.0), "dock scale band");
}

// ── Report ──
for (const [cond, label] of checks) {
    console.log((cond ? "ok   " : "FAIL ") + label);
}
console.log("\n" + (errors === 0 ? "ALL PASS" : errors + " FAILURE(S)"));
process.exit(errors === 0 ? 0 : 1);