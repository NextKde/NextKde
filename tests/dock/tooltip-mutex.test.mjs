import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

// Regression: the Dock showed two overlapping tooltips on styles without
// distance magnification (material / windows12). The fallback popup's active
// condition used `_usesSharedMagnification`, which is true only when distance
// magnification is on (macos by default, or any style once the user moves the
// hover-scale slider). The shared name label, however, exists in every style,
// so on material with a never-touched slider both surfaces appeared at once.
//
// The fix gates the popup on label ownership instead: the host that exposes
// `updateNameLabel()` owns the label, and the popup must then stay inactive —
// regardless of magnification. These tests pin both halves of that contract
// against the real source, so a future edit that re-couples the popup to
// magnification (or drops the ownership test) fails here instead of on a
// user's desktop.

const iconSource = readFileSync(
    new URL("../../shell/desktop/modules/dock/DockIcon.qml", import.meta.url), "utf8");

test("dock tooltip mutex", async () => {
    // ── ownership property exists and mirrors updateDockName()'s own test ──
    const ownership = iconSource.match(
        /readonly property bool _dockOwnsNameLabel:([\s\S]*?)\/\/ Non-Dock hosts/);
    assert.ok(ownership, "DockIcon.qml must declare _dockOwnsNameLabel");
    assert.match(ownership[1], /magnificationRoot !== null/,
        "ownership must test the magnification root itself");
    assert.match(ownership[1], /typeof magnificationRoot\.updateNameLabel === "function"/,
        "ownership must test for updateNameLabel, the exact capability the"
        + " shared-label path (updateDockName) depends on");

    // ── the fallback popup is gated on ownership, not magnification ──
    const loader = iconSource.match(/Loader \{\n\s*active: ([^\n]+)\n\s*&& !icon\._hasWindows/);
    assert.ok(loader, "DockNameTooltip Loader active condition moved; update this test");
    assert.match(loader[1], /!icon\._dockOwnsNameLabel/,
        "popup must be inactive whenever the host owns the shared label");
    assert.doesNotMatch(loader[1], /_usesSharedMagnification/,
        "popup must not depend on magnification: styles without distance"
        + " magnification still own a label (double-tooltip regression)");

    // ── the ownership test matches what updateDockName() actually checks ──
    const updater = iconSource.match(/function updateDockName\(\) \{[\s\S]*?\n    \}/);
    assert.ok(updater, "updateDockName() moved; update this test");
    assert.match(updater[0], /magnificationRoot && typeof magnificationRoot\.updateNameLabel === "function"/,
        "updateDockName() still uses the same ownership test; keep the popup"
        + " condition in lockstep with it");

    // ── the shared label really exists on the container for every style ──
    const containerSource = readFileSync(
        new URL("../../shell/desktop/modules/dock/DockContainer.qml", import.meta.url), "utf8");
    assert.match(containerSource, /readonly property alias nameLabel: sharedNameLabel/,
        "DockContainer must keep a style-independent shared name label");
    assert.doesNotMatch(containerSource,
        /nameLabelsEnabled:[^\n]*isMacos/,
        "shared label availability must not be tied to a shell style");
});
