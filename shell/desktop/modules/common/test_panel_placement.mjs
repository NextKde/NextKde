// test_panel_placement.mjs — unit tests for PanelPlacement.mjs
//
// Regressions covered (PR #424):
//  - a status panel on a secondary output was pinned to that screen's far
//    edge: panelCenter reached PersistentPanelWindow in virtual-desktop
//    coordinates, the screen-local clamp ate it, and the panel parked at the
//    right/bottom edge instead of following its anchor cell;
//  - with the Dock on a side edge the panel tucked low (near the dock cell)
//    ran off the bottom of the screen — the vertical branch had no upper
//    clamp, so it looked "sunken and truncated".
import assert from "node:assert/strict";
import { panelPlacement, clampedCenterOffset } from "./PanelPlacement.mjs";

console.log("Running status panel placement unit tests...");

// 1. Primary output, standalone Bar: four pixels below the cell.
assert.deepEqual(
    panelPlacement({
        edge: "top",
        screenX: 0, screenY: 0, screenWidth: 1920, screenHeight: 1080,
        hostOrigin: { x: 0, y: 0 },
        hasAnchor: true, anchorX: 1000, anchorY: 6, anchorWidth: 24, anchorHeight: 24,
        gap: 4,
    }),
    { edge: "top", offset: 34, center: 1012 });

// 2. Bottom dock: offset measured from the dock artwork, not the cell.
assert.deepEqual(
    panelPlacement({
        edge: "bottom",
        screenX: 0, screenY: 0, screenWidth: 1920, screenHeight: 1080,
        hostOrigin: { x: 0, y: 1021 },
        hasAnchor: true, anchorX: 900, anchorY: 20, anchorWidth: 24, anchorHeight: 24,
        dockRect: { x: 172, y: 1005, width: 1575, height: 59 },
        gap: 8,
    }),
    { edge: "bottom", offset: 83, center: 912 });

// 3. Side dock: offset from the glass edge, centre along the vertical axis.
assert.deepEqual(
    panelPlacement({
        edge: "left",
        screenX: 0, screenY: 0, screenWidth: 1920, screenHeight: 1080,
        hostOrigin: { x: 0, y: 0 },
        hasAnchor: true, anchorX: 20, anchorY: 900, anchorWidth: 24, anchorHeight: 24,
        dockRect: { x: 5, y: 40, width: 59, height: 1000 },
        gap: 8,
    }),
    { edge: "left", offset: 72, center: 912 });
assert.deepEqual(
    panelPlacement({
        edge: "right",
        screenX: 0, screenY: 0, screenWidth: 1920, screenHeight: 1080,
        hostOrigin: { x: 1861, y: 0 },
        hasAnchor: true, anchorX: 20, anchorY: 900, anchorWidth: 24, anchorHeight: 24,
        dockRect: { x: 1856, y: 40, width: 59, height: 1000 },
        gap: 8,
    }),
    { edge: "right", offset: 72, center: 912 },
    "right dock: offset measured inward from the output's right edge");

// 4. Regression: secondary output. Every value must come out screen-local so
//    the consumer's clamp cannot send the panel to the far edge.
const secondary = panelPlacement({
    edge: "bottom",
    screenX: 1920, screenY: 0, screenWidth: 1920, screenHeight: 1080,
    hostOrigin: { x: 1920, y: 1021 },
    hasAnchor: true, anchorX: 900, anchorY: 20, anchorWidth: 24, anchorHeight: 24,
    dockRect: { x: 2092, y: 1005, width: 1575, height: 59 },
    gap: 8,
});
assert.deepEqual(secondary, { edge: "bottom", offset: 83, center: 912 },
    "secondary output anchors to its cell, not the screen's right edge");
assert.ok(secondary.center < 1920, "centre stays inside the output");

// 5. Null anchor still opens sanely: centred on the dock artwork.
assert.deepEqual(
    panelPlacement({
        edge: "bottom",
        screenX: 0, screenY: 0, screenWidth: 1920, screenHeight: 1080,
        hostOrigin: { x: 0, y: 1021 },
        hasAnchor: false,
        dockRect: { x: 172, y: 1005, width: 1575, height: 59 },
        gap: 8,
    }),
    { edge: "bottom", offset: 83, center: 959.5 });

// 6. Center clamp: a panel that fits stays exactly on its anchor.
assert.equal(clampedCenterOffset({
    center: 500, size: 400, screenSize: 1080, edgeMargin: 4,
}), 300);

// 7. Center clamp: both ends. A panel taller than the space between the
//    margins collapses onto the start margin instead of hanging off the end.
assert.equal(clampedCenterOffset({
    center: 1025, size: 970, screenSize: 1080, edgeMargin: 4,
}), 106);
assert.equal(clampedCenterOffset({
    center: 30, size: 970, screenSize: 1080, edgeMargin: 4,
}), 4);

// 8. Regression: the side-dock panel's bottom stays on screen after clamping.
const sideTop = clampedCenterOffset({
    center: 1025, size: 970, screenSize: 1080, edgeMargin: 4,
});
assert.ok(sideTop + 970 <= 1080, "panel bottom stays inside the output");

// 9. Regression: a secondary-output anchor near that screen's left edge
//    (virtual x ~2000) must not be clamped to the right edge of the output.
assert.equal(clampedCenterOffset({
    center: 80, size: 400, screenSize: 1920, edgeMargin: 4,
}), 4);
assert.equal(clampedCenterOffset({
    center: 900, size: 400, screenSize: 1920, edgeMargin: 4,
}), 700);

console.log("status panel placement: all checks passed");
