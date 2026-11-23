// test_launcher_geometry.mjs — unit tests for LauncherGeometry.mjs
//
// Regressions covered (PR #425):
//  - after the Dock returned from a side edge the reveal clip froze at the
//    previous output size (1874x1080 instead of 960x540);
//  - the side-Dock card was sized from the Dock's whole edge length and
//    stretched to 85% of the output.
import assert from "node:assert/strict";
import {
    compactCardWidth,
    compactCardHeight,
    launcherSize,
    revealRect,
} from "./LauncherGeometry.mjs";

console.log("Running launcher geometry unit tests...");

const SCREEN = { screenWidth: 1920, screenHeight: 1080 };

// 1. Compact card at the bottom edge: half the output, 16:9.
assert.deepEqual(
    launcherSize({
        displayMode: "bottomWide", dockPosition: "bottom", dockWidth: 1575,
        ...SCREEN,
    }),
    { width: 960, height: 540 });

// 2. Side Dock: the compact card stands up (transposed), a touch wider than
//    half the output height, capped at two thirds of the output.
for (const dockPosition of ["left", "right"]) {
    assert.deepEqual(
        launcherSize({
            displayMode: "bottomWide", dockPosition, dockWidth: 1001,
            ...SCREEN,
        }),
        { width: 594, height: 720 });
}

// 3. Wide displays keep the same proportions.
assert.deepEqual(
    launcherSize({
        displayMode: "bottomWide", dockPosition: "left", dockWidth: 1400,
        screenWidth: 2560, screenHeight: 1440,
    }),
    { width: Math.max(720, 792), height: Math.min(1280, 960) },
    "side card on a 2560x1440 output");

// 4. Compact (non-wide) mode still follows the Dock width, with the 50%
//    minimum when the Dock is shorter than half the output.
assert.deepEqual(
    launcherSize({
        displayMode: "bottom", dockPosition: "bottom", dockWidth: 700,
        ...SCREEN,
    }),
    { width: 960, height: 500 },
    "short Dock falls back to the minimum card");
assert.deepEqual(
    launcherSize({
        displayMode: "bottom", dockPosition: "bottom", dockWidth: 1200,
        ...SCREEN,
    }),
    { width: 1200, height: 540 },
    "long Dock stretches the card width");

// 5. Center and fullscreen presentations are independent of Dock edges.
assert.deepEqual(
    launcherSize({ displayMode: "center", dockPosition: "left", dockWidth: 1001, ...SCREEN }),
    { width: 1040, height: 734 });
assert.deepEqual(
    launcherSize({ displayMode: "fullscreen", dockPosition: "right", dockWidth: 1001, ...SCREEN }),
    { width: 1920, height: 1080 });

// 6. Reveal placement: bottom card centered and flush with the bottom edge of
//    the Dock-cleared window.
assert.deepEqual(
    revealRect({
        isFullscreenMode: false, isCenterMode: false, dockPosition: "bottom",
        width: 960, height: 540, parentWidth: 1920, parentHeight: 1006,
    }),
    { x: 480, y: 466, width: 960, height: 540 });

// 7. Reveal placement: side cards hug their Dock edge, vertically centered.
assert.deepEqual(
    revealRect({
        isFullscreenMode: false, isCenterMode: false, dockPosition: "left",
        width: 594, height: 720, parentWidth: 1874, parentHeight: 1080,
    }),
    { x: 0, y: 180, width: 594, height: 720 });
assert.deepEqual(
    revealRect({
        isFullscreenMode: false, isCenterMode: false, dockPosition: "right",
        width: 594, height: 720, parentWidth: 1874, parentHeight: 1080,
    }),
    { x: 1280, y: 180, width: 594, height: 720 });

// 8. Center and fullscreen reveal placement.
assert.deepEqual(
    revealRect({
        isFullscreenMode: false, isCenterMode: true, dockPosition: "bottom",
        width: 1040, height: 734, parentWidth: 1920, parentHeight: 1006,
    }),
    { x: 440, y: 136, width: 1040, height: 734 });
assert.deepEqual(
    revealRect({
        isFullscreenMode: true, isCenterMode: false, dockPosition: "left",
        width: 1920, height: 1080, parentWidth: 1920, parentHeight: 1080,
    }),
    { x: 0, y: 0, width: 1920, height: 1080 });

// 9. Regression: a Dock edge round-trip (bottom -> side -> bottom) must not
//    leak the side state into the bottom geometry. The functions are pure, so
//    the only contract is that the answer for a given state never depends on
//    what came before.
const side = launcherSize({ displayMode: "bottomWide", dockPosition: "left", dockWidth: 1001, ...SCREEN });
const back = launcherSize({ displayMode: "bottomWide", dockPosition: "bottom", dockWidth: 1575, ...SCREEN });
const sideRect = revealRect({
    isFullscreenMode: false, isCenterMode: false, dockPosition: "left",
    width: side.width, height: side.height, parentWidth: 1874, parentHeight: 1080,
});
const backRect = revealRect({
    isFullscreenMode: false, isCenterMode: false, dockPosition: "bottom",
    width: back.width, height: back.height, parentWidth: 1920, parentHeight: 1006,
});
assert.deepEqual(back, { width: 960, height: 540 },
    "bottom size after a side round-trip");
assert.deepEqual(backRect, { x: 480, y: 466, width: 960, height: 540 },
    "bottom placement after a side round-trip");
assert.deepEqual(sideRect, { x: 0, y: 180, width: 594, height: 720 },
    "side placement");

// 10. Helpers keep their documented halves.
assert.equal(compactCardWidth({
    isBottomWideMode: true, screenWidth: 1920, dockWidth: 1575,
    minimumLauncherWidth: 960,
}), 960);
assert.equal(compactCardHeight({ usesMinimumSize: true, screenHeight: 1080 }), 500);
assert.equal(compactCardHeight({ usesMinimumSize: false, screenHeight: 1080 }), 540);

console.log("launcher geometry: all checks passed");
