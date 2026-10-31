import assert from "node:assert/strict";
import vm from "node:vm";
import { MIN_ICON_SIZE, activeBackgroundPadding, computeLayout } from "../../shell/desktop/modules/dock/AdaptiveMath.mjs";
import { avoidanceRect, dockOpacity, dockScale, handleOpacity, handleSizes, hasConflict, intentionalOverlapRect, intersects, policyWantsHidden, releaseRect, shouldBeVisible, visibleDockRect, windowEligible } from "../../shell/desktop/modules/dock/DockAutoHideMath.mjs";
import { readFileSync } from "node:fs";
import { test } from "node:test";

test("adaptive", async () => {
    const cases = [
        [60, 5, 3, false, 1920, 'few icons, no music'],
        [60, 5, 3, true,  1920, 'few icons, with music'],
        [60, 15, 18, false, 1920, 'medium icons, no music'],
        [60, 15, 18, true,  1920, 'medium icons, with music'],
        [60, 30, 30, false, 1920, 'many icons, no music'],
        [60, 30, 30, true,  1920, 'many icons, with music'],
        [60, 0, 0, false,   1920, 'empty dock'],
        [60, 0, 0, true,    1920, 'music only'],
    ];

    let errors = 0;
    for (const [bh, pc, wc, hasInfoSlot, sw, desc] of cases) {
        const r = computeLayout(bh, pc, wc, hasInfoSlot, sw);
        const issues = [];
        if (r.iconUnits > 0) {
            if (r.dockHeight > 100) issues.push('dockHeight exceeds max: ' + r.dockHeight);
            if (r.iconSize < MIN_ICON_SIZE && r.iconSize !== 0) issues.push('iconSize below min');
            if (r.dockWidth > sw * 0.98 + 2) issues.push('dockWidth > 98%');
            if (r.infoUnits !== (hasInfoSlot ? 4 : 0)) issues.push('wrong infoUnits');
            if (r.activeBackgroundGap <= 0) issues.push('missing active background gap');
        } else {
            if (r.dockHeight !== 0 || r.iconSize !== 0) issues.push('empty dock non-zero');
        }
        if (issues.length) {
            console.log('FAIL:', desc, issues.join(', ')); errors++;
        } else {
            console.log('OK:  ', desc.padEnd(25), 'H=' + r.dockHeight, 'icon=' + r.iconSize, 'W=' + r.dockWidth);
        }
    }

    // Spacing proportions must affect the calculation, while the width cap stays
    // fixed at 98% for every caller.
    const configured = computeLayout(60, 5, 3, false, 1920, {
        vpad: 0.2, hpad: 0.3, spacing: 0.1, divmargin: 0.25,
    });
    if (configured.dockWidth > 1920 * 0.98 + 2)
        errors++, console.log('FAIL: fixed 98% max width ignored');
    if (configured.vPadding !== Math.round(configured.iconSize * 0.2))
        errors++, console.log('FAIL: configured vpad ignored');
    if (configured.hPadding !== Math.round(configured.iconSize * 0.3))
        errors++, console.log('FAIL: configured hpad ignored');

    const normal = computeLayout(60, 1, 1, false, 1920);
    if (Math.abs(normal.activeBackgroundGap - activeBackgroundPadding(normal.iconSize)) > 0.001)
        errors++, console.log('FAIL: active background gap is not proportional');

    // Fully opaque square artwork is the worst case, regardless of the image's
    // transparent margins. Check actual distance to the corner arc at all styles.
    for (const size of [18, 44, 70]) {
        for (const radiusRatio of [0.18, 0.28, 0.30]) {
            const padding = activeBackgroundPadding(size, radiusRatio);
            const radius = size * radiusRatio;
            const clearance = radius - Math.SQRT2 * Math.max(0, radius - padding);
            if (clearance < size * 0.035 - 0.001)
                errors++, console.log('FAIL: rounded corner clearance', size, radiusRatio);
            const layout = computeLayout(60, 5, 3, false, 1920,
                { vpad: 0.12, activeRadiusRatio: radiusRatio });
            if (layout.dockHeight + 0.5 < layout.iconSize + 2 * layout.activeBackgroundGap)
                errors++, console.log('FAIL: active plate exceeds dock thickness');
        }
    }

    const sideInfo = computeLayout(60, 3, 2, true, 1080, {}, 0.95, 2);
    if (sideInfo.infoUnits !== 2)
        errors++, console.log('FAIL: side info slot did not reserve two units');

    const invalidInfo = computeLayout(60, 3, 2, true, 1080, {}, 0.95, NaN);
    if (invalidInfo.infoUnits !== 0)
        errors++, console.log('FAIL: invalid info unit override was not rejected');

    const crowded = computeLayout(60, 80, 80, true, 800);
    if (crowded.iconSize !== MIN_ICON_SIZE)
        errors++, console.log('FAIL: crowded layout did not clamp to icon floor');

    // Both built-in icons can be hidden, leaving only an information card or no
    // content at all. Neither state should reserve a separator or yield NaN gaps.
    const infoOnly = computeLayout(60, 0, 0, true, 1920);
    if (infoOnly.dividerCount !== 0)
        errors++, console.log('FAIL: information-only dock has a leading divider');
    const empty = computeLayout(60, 0, 0, false, 1920);
    if (empty.activeBackgroundGap !== 0)
        errors++, console.log('FAIL: empty dock has an invalid background gap');

    // With both built-ins hidden, an integrated tray must keep a usable height
    // even when no application or information card occupies the core row.
    const trayOnly = computeLayout(60, 0, 0, false, 1920, {}, 0.98, 4, true);
    if (trayOnly.dockHeight !== normal.dockHeight || trayOnly.iconSize !== normal.iconSize
            || trayOnly.iconUnits !== 0 || trayOnly.dividerCount !== 0)
        errors++, console.log('FAIL: accessory-only dock lost its usable height');
    if (trayOnly.dockWidth <= 0 || !Number.isFinite(trayOnly.dockWidth))
        errors++, console.log('FAIL: accessory-only dock has invalid edge padding');

    console.log(errors ? '\n' + errors + ' FAILED'
        : '\nAll ' + (cases.length + 3) + ' passed');
    assert.equal(errors, 0, "all checks in this scenario must pass");
});

test("autohide", async () => {
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
            isMaximized: false,
            isVisible: true,
            onAllDesktops: false,
            desktopIds: ["d1"],
            screenName: "DP-1"
        }, overrides);
    }

    // A minimized window never participates.
    ok(!windowEligible(win({ isMinimized: true }), S, "d1"), "minimized filtered");
    // A window on another desktop is filtered.
    ok(!windowEligible(win({ desktopIds: ["d2"] }), S, "d1"), "other-desktop filtered");
    // A missing membership list falls back to KWin visibility instead of being
    // interpreted as either every desktop or no desktop.
    ok(windowEligible(win({ desktopIds: [], isVisible: true }), S, "d1"),
        "empty desktop list keeps visible window");
    ok(!windowEligible(win({ desktopIds: [], isVisible: false }), S, "d1"),
        "empty desktop list filters invisible window");
    // Before the first desktop snapshot, KWin visibility is the safe fallback.
    ok(windowEligible(win({ desktopIds: ["d2"], isVisible: true }), S, ""),
        "unknown desktop keeps visible window");
    ok(!windowEligible(win({ desktopIds: ["d1"], isVisible: false }), S, ""),
        "unknown desktop filters invisible window");
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
    const intentional = intentionalOverlapRect(base, "bottom");

    ok(intentional.y === base.y + 12 && intentional.height === base.height - 12,
        "bottom smart hide requires 12px intentional overlap");
    ok(intentionalOverlapRect({ x: 5, y: 10, width: 60, height: 200 }, "left").width === 48,
        "left smart hide trims its inner approach edge");
    {
        const right = intentionalOverlapRect(
            { x: 1855, y: 100, width: 60, height: 200 }, "right");
        ok(right.x === 1867 && right.width === 48,
            "right smart hide trims its inner approach edge");
    }

    // Window placed directly over the dock region triggers a conflict.
    {
        const over = win({ geometry: { x: base.x + 5, y: base.y + 5, width: 50, height: 50 } });
        ok(hasConflict([over], S, av, rel, false, "d1"), "window over dock conflicts");
    }
    // The math helper can still support an expanded entry ring for Bar policy.
    {
        const touch = win({ geometry: { x: base.x + 6, y: base.y - 9, width: 50, height: 50 } });
        ok(hasConflict([touch], S, av, rel, false, "d1"), "entry into 8px ring conflicts");
    }
    // Dock policy passes the full-reveal rectangle itself as the entry boundary:
    // proximity and a shallow overlap are not conflicts until the overlap is
    // intentional. Once hidden, leaving the real rectangle clears the conflict.
    {
        const near = win({ geometry: { x: base.x + 6, y: base.y - 9, width: 50, height: 8 } });
        ok(!hasConflict([near], S, base, rel, false, "d1"),
            "dock proximity without overlap is not a conflict");
        const overlap = win({ geometry: { x: base.x + 6, y: base.y - 1, width: 50, height: 2 } });
        ok(hasConflict([overlap], S, base, rel, false, "d1"),
            "dock actual overlap starts conflict");
        ok(!hasConflict([overlap], S, intentional, base, false, "d1"),
            "shallow dock overlap stays visible");
        const deep = win({ geometry: {
            x: base.x + 6, y: base.y + 13, width: 50, height: 20
        } });
        ok(hasConflict([deep], S, intentional, base, false, "d1"),
            "intentional dock overlap starts conflict");
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
    // A maximized window is only unconditional for the top Bar policy. The Dock
    // still relies on actual overlap with its full-reveal rectangle.
    {
        const max = win({
            isMaximized: true,
            geometry: { x: 0, y: 100, width: 1920, height: 800 }
        });
        const topBase = visibleDockRect(S, "top", 1890, 35, 15);
        const topAv = avoidanceRect(topBase);
        const topRel = releaseRect(topBase);
        ok(!hasConflict([max], S, topAv, topRel, false, "d1"),
            "reserved maximized window does not geometrically overlap bar");
        ok(hasConflict([max], S, topAv, topRel, false, "d1", true),
            "bar treats maximized window as conflict");
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
    assert.equal(errors, 0, "all checks in this scenario must pass");
});

test("wallpaper color source", async () => {
    // The wallpaper colour source now lives in the shared Kos.Ui layer.
    const wallpaper = readFileSync(
        new URL("../../shared/qml/colorize/WallpaperColorSource.qml", import.meta.url), "utf8");
    // Half the file's parsing side, from the first helper to `refresh`.
    // `_readWallpaperText` delegates to two pure helpers, so slicing it alone
    // would evaluate a body whose callees are undefined. The trio stays adjacent
    // and in this order in the source; that adjacency is what this slice relies on.
    const parser = wallpaper.slice(wallpaper.indexOf("    function _parseWallpaperConfig("),
        wallpaper.indexOf("    function refresh()"));
    const resolved = [];
    const cleared = [];
    const context = vm.createContext({
        preferredScreen: 1, preferredWallpaperUrl: "",
        configuredWallpaperUrl: "", wallpaperUrl: "",
        _resolveWallpaperUrl: url => resolved.push(url),
        paletteCleared: () => cleared.push(true),
        console: { warn() {} },
    });
    vm.runInContext(parser, context);
    const config = "[Containments][1]\nlastScreen=0\n"
        + "[Containments][1][Wallpaper][org.kde.image][General]\nImage=file:///first.png\n"
        + "[Containments][2]\nlastScreen=1\n"
        + "[Containments][2][Wallpaper][org.kde.image][General]\nImage=file:///second.png\n";
    context._readWallpaperText(config);
    context._readWallpaperText(config);
    assert.deepEqual(resolved, ["file:///second.png"]);
    context.preferredWallpaperUrl = "file:///quickshell-owned.png";
    context._readWallpaperText(config.replace("second.png", "plasma-backdrop.png"));
    assert.deepEqual(resolved, ["file:///second.png"],
        "the Plasma backdrop must not replace Quickshell's original image");
    context.preferredWallpaperUrl = "";
    context._readWallpaperText(config.replace("second.png", "replacement.png"));
    assert.equal(resolved.at(-1), "file:///replacement.png");
    context.preferredScreen = 9;
    context._readWallpaperText(config);
    assert.equal(resolved.at(-1), "file:///first.png");
    context._readWallpaperText("");
    assert.equal(context.configuredWallpaperUrl, "");
    assert.equal(context.wallpaperUrl, "");
    assert.equal(cleared.length, 1, "clearing the wallpaper must notify the shell adapter");

    // Plasma keeps one `[Wallpaper][<plugin>][General]` block per plugin that has
    // ever been configured, and retired ones keep their keys. image comes first,
    // then the others:
    //
    //   [Containments][5][Wallpaper][org.kde.image][General]
    //   Image=file:///real.png
    //   [Containments][5][Wallpaper][org.kde.potd][General]
    //   [Containments][5][Wallpaper][org.kde.slideshow][General]
    //   Image=file:///stale.jpg
    //
    // A cursor that is not reset on the headers it does not recognise leaves the
    // image block's id in place, so that stray slideshow Image lands on it and
    // overwrites the real wallpaper. That shipped: the URL never moved, the seed
    // was never re-sampled, and all three colour sources froze after a wallpaper
    // change — the symptom a user reports as "the colours no longer follow my
    // wallpaper". Real configs carry the same shape.
    const noisy = "[Containments][5]\nlastScreen=1\nwallpaperplugin=org.kde.image\n"
        + "[Containments][5][Wallpaper][org.kde.image][General]\nImage=file:///real.png\n"
        + "SlidePaths=/usr/share/wallpapers/\n"
        + "[Containments][5][Wallpaper][org.kde.potd][General]\nFillMode=1\n"
        + "[Containments][5][Wallpaper][org.kde.slideshow][General]\nImage=file:///stale.jpg\n";
    context.preferredScreen = 1;
    context._readWallpaperText(noisy);
    assert.equal(resolved.at(-1), "file:///real.png",
        "a retired plugin block must not overwrite the active wallpaper");
    context._readWallpaperText(noisy.replace("real.png", "changed.png"));
    assert.equal(resolved.at(-1), "file:///changed.png",
        "changing the active wallpaper must change the resolved URL");
    // The active plugin decides, rather than the image plugin being hardcoded.
    context._readWallpaperText(noisy.replace("wallpaperplugin=org.kde.image",
        "wallpaperplugin=org.kde.slideshow"));
    assert.equal(resolved.at(-1), "file:///stale.jpg",
        "an active slideshow plugin must resolve to its own image");

    // The applets config Plasma writes is named after the shell package the session
    // runs: `plasmashellrc [Shell] ShellPackage` -> `plasma-<package>-appletsrc`.
    // KOS's lock-screen install points that key at its own package, so the desktop
    // wallpapers land in `plasma-org.kos.desktop-appletsrc` while a hardcoded KDE
    // filename reads a file Plasma has stopped writing. Same symptom as the parser
    // bug above and for the same reason: a wallpaper URL that never moves.
    const shellPackageSource = wallpaper.slice(
        wallpaper.indexOf("    function _parseShellPackage("),
        wallpaper.indexOf("    property FileView _shellConfigFile:"));
    const svcContext = vm.createContext({
        svc: {
            configDirectory: "/home/user/.config",
            defaultConfigPath: "/home/user/.config/plasma-org.kde.plasma.desktop-appletsrc",
            configCandidates: ["/home/user/.config/plasma-org.kde.plasma.desktop-appletsrc"],
            configCandidateIndex: 0,
            configPath: "/home/user/.config/plasma-org.kde.plasma.desktop-appletsrc",
        },
        console: { warn() {} },
    });
    vm.runInContext(shellPackageSource, svcContext);
    // QML resolves the helper names through the object's scope; evaluated as plain
    // script they are plain function declarations on the context global, so they are
    // called through the context while the state stays on `svc`.
    const svc = svcContext.svc;

    assert.equal(svcContext._parseShellPackage("[Shell]\nShellPackage=org.kos.desktop\n"),
        "org.kos.desktop");
    assert.equal(svcContext._parseShellPackage(
        "[KDE]\nShellPackage=org.kde.plasma.desktop\n"), "",
        "only the [Shell] group names the shell package");
    assert.equal(svcContext._parseShellPackage("[Shell]\nLockScreen=kscreenlocker\n"), "");
    assert.equal(svcContext._parseShellPackage(""), "");

    svcContext._applyShellPackage("org.kos.desktop");
    assert.equal(svc.configPath, "/home/user/.config/plasma-org.kos.desktop-appletsrc",
        "the session's shell package must win over the hardcoded KDE filename");
    // Spread into host arrays: the candidates are built inside the vm context, so
    // their prototype is that realm's Array and deepStrictEqual would reject them.
    assert.deepEqual([...svc.configCandidates], [
        "/home/user/.config/plasma-org.kos.desktop-appletsrc",
        "/home/user/.config/plasma-org.kde.plasma.desktop-appletsrc",
    ]);
    // A named file that Plasma has not written yet must fall through instead of
    // leaving the shell with no wallpaper at all.
    svcContext._fallBackToNextConfig("no such file");
    assert.equal(svc.configPath, "/home/user/.config/plasma-org.kde.plasma.desktop-appletsrc");
    assert.equal(svc.configCandidateIndex, 1);
    // Lock screen uninstalled: kosctl deletes the key and the KDE file takes over.
    svcContext._applyShellPackage("");
    assert.equal(svc.configPath, "/home/user/.config/plasma-org.kde.plasma.desktop-appletsrc");
    assert.deepEqual([...svc.configCandidates],
        ["/home/user/.config/plasma-org.kde.plasma.desktop-appletsrc"]);

    const refreshBody = wallpaper.slice(wallpaper.indexOf("    function refresh()"),
        wallpaper.indexOf("    function _parseShellPackage("));
    assert.match(refreshBody, /_shellConfigFile\.reload\(\)/,
        "the shell package is re-read on the same timer, or the config can move");
    assert.match(refreshBody, /_configFile\.reload\(\)/);

    // The shared layer must not reach back into shell modules.
    assert.doesNotMatch(wallpaper, /import qs\.desktop/);
    assert.doesNotMatch(wallpaper, /AppearanceConfigService/);
    assert.match(wallpaper, /interval: 3000/);
    assert.match(wallpaper, /shellConfigPath: configDirectory \+ "\/plasmashellrc"/);
    assert.doesNotMatch(wallpaper, /wallpaper-palette-read|_refreshProcess/);
    console.log("wallpaper contracts: passed");
});

test("launcher presentation", async () => {
    // The launcher re-solves its whole icon grid from this width. Publishing
    // the live hover spread made every tile reflow while the pointer slid
    // along the Dock, so only the resting length may cross the boundary.
    const container = readFileSync(
        new URL("../../shell/desktop/modules/dock/DockContainer.qml", import.meta.url), "utf8");
    assert.match(container, /setDockPresentation\(\s*restingComputedWidth,/,
        "the launcher must follow the resting Dock length, not the hover spread");
    console.log("launcher presentation contracts: passed");
});
