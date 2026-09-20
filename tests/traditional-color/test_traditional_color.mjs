import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
    buildScheme, buildSchemePair, roleColor, nearestNamed, contrastRatio,
    hexToHct, hctToHex, ROLE_NAMES, TABLES_AVAILABLE, _internals,
} from "../../shared/qml/colorize/TraditionalColorScheme.mjs";
import {
    ROLE_NAMES as MATERIAL_ROLE_NAMES, buildScheme as buildMaterialScheme,
    buildSchemePair as buildMaterialPair,
} from "../../shared/qml/colorize/MaterialColorScheme.mjs";
import { CHINESE_COLORS } from "../../shared/qml/colorize/ChineseColors.mjs";
import { JAPANESE_COLORS } from "../../shared/qml/colorize/JapaneseColors.mjs";

// Verifies the traditional-colour scheme generator (中国传统色 / 日本の伝統色).
//
// Runs with plain node — no Qt, no display, no external tools — so it works in
// headless CI. The three claims worth defending are:
//
//   1. FIDELITY: the accent keeps the wallpaper's tone. This is the whole
//      reason the scheme exists, and the numbers below pin it as a hard
//      multiple better than the Material scheme, not a vague "closer".
//   2. READABILITY: every foreground role clears WCAG AA against what it sits
//      on, including accents so pale or so dark that Material's fixed 100/20
//      foregrounds would fail.
//   3. FALLBACK: when the table cannot express the seed, the output is exactly
//      the Material scheme for that seed — byte for byte, variant included.

// ── tables ────────────────────────────────────────────────────────────────
{
    assert.ok(Array.isArray(CHINESE_COLORS) && CHINESE_COLORS.length > 400,
        "chinese table should be substantial, got " + CHINESE_COLORS.length);
    assert.ok(Array.isArray(JAPANESE_COLORS) && JAPANESE_COLORS.length > 150,
        "japanese table should be substantial, got " + JAPANESE_COLORS.length);
    assert.deepEqual(TABLES_AVAILABLE.sort(), ["chinese", "japanese"]);

    for (const [table, entries] of [["chinese", CHINESE_COLORS],
        ["japanese", JAPANESE_COLORS]]) {
        const seen = new Set();
        for (const entry of entries) {
            assert.equal(entry.length, 2, table + " entry must be [name, hex]");
            const [name, hex] = entry;
            assert.ok(typeof name === "string" && name.length > 0,
                table + " name must be non-empty, got " + JSON.stringify(name));
            assert.match(hex, /^#[0-9a-f]{6}$/,
                table + " hex must be lowercase #rrggbb, got " + hex);
            // Duplicate colours would let two different names match the same
            // seed, which makes the reported name depend on table order.
            assert.ok(!seen.has(hex), table + " duplicate hex " + hex);
            seen.add(hex);
        }
    }
    console.log("tables: ok (" + CHINESE_COLORS.length + " chinese, "
        + JAPANESE_COLORS.length + " japanese, no duplicate colours)");
}

// ── role contract ─────────────────────────────────────────────────────────
// The shell's ColorScheme singleton reshapes {light, dark} into
// palette[role][mode].color and every consumer reads that. A role name that
// only one of the two schemes produces would silently become undefined at the
// consumer, so the two must agree exactly.
{
    assert.deepEqual(ROLE_NAMES, MATERIAL_ROLE_NAMES,
        "role names must match MaterialColorScheme exactly, in order");
    assert.equal(ROLE_NAMES.length, 49);

    const pair = buildSchemePair("#64c4d4");
    for (const mode of ["light", "dark"]) {
        const keys = Object.keys(pair[mode]);
        assert.equal(keys.length, 50, mode + " should be 49 roles + source_color");
        assert.ok(keys.includes("source_color"));
        for (const role of ROLE_NAMES) {
            assert.match(pair[mode][role], /^#[0-9a-f]{6}$/,
                mode + " " + role + " must be a hex colour, got "
                + pair[mode][role]);
        }
    }
    console.log("role contract: ok (49 roles + source_color x 2 modes, "
        + "names identical to MaterialColorScheme)");
}

// ── accent fidelity ───────────────────────────────────────────────────────
// The user's requirement: generated colours must stay close to the wallpaper.
// Measured as the tone difference between the seed and the generated accent,
// against the Material scheme doing the same job on the same seed.
{
    const seeds = [
        "#e60012", "#7fecad", "#1a2847", "#f0c239", "#ffb7c5", "#64c4d4",
        "#0f7b6c", "#c3272b", "#2e4e7e", "#d94f70", "#3f7f5f", "#f4a01c",
        "#8c4356", "#5b6eae", "#b45309", "#2f6f4f",
    ];
    let ourTotal = 0, materialTotal = 0;
    for (const seed of seeds) {
        const seedTone = hexToHct(seed)[2];
        ourTotal += Math.abs(seedTone - hexToHct(buildSchemePair(seed).light.primary)[2]);
        materialTotal += Math.abs(seedTone
            - hexToHct(buildMaterialPair(seed, { variant: "vibrant" }).light.primary)[2]);
    }
    const ours = ourTotal / seeds.length, material = materialTotal / seeds.length;
    // Material lands ~25 tone steps away on average; this scheme must be at
    // least 4x closer. The bar is deliberately far below the measured value
    // (which is ~2) so the test reports a real regression, not noise.
    assert.ok(ours * 4 < material,
        "accent fidelity regressed: ours " + ours.toFixed(1)
        + " tone steps from the seed, Material " + material.toFixed(1));
    console.log("accent fidelity: ok (" + ours.toFixed(1)
        + " tone steps from the seed on average vs Material's "
        + material.toFixed(1) + ")");
}

// ── match accuracy ────────────────────────────────────────────────────────
// A seed with real chroma must land in the right part of the colour wheel.
// Seeds below the neutral cutoff have no meaningful hue and are excluded —
// that exclusion is the point of the cutoff, not a convenience.
{
    let state = 20260919;
    const random = function () {
        state = (state * 1103515245 + 12345) & 0x7fffffff;
        return state / 0x7fffffff;
    };
    const hueDelta = function (a, b) {
        const d = Math.abs(a - b) % 360;
        return d > 180 ? 360 - d : d;
    };

    const deltas = [];
    let fallbacks = 0;
    for (let i = 0; i < 500; i++) {
        const seed = hctToHex(random() * 360, 8 + random() * 40, 8 + random() * 84);
        const match = nearestNamed(seed);
        assert.ok(match, "every seed must resolve to a nearest colour");
        if (!match.accepted) {
            fallbacks++;
            continue;
        }
        const seedHct = hexToHct(seed);
        // Dithering to 8-bit sRGB perturbs the requested hue; re-read it.
        if (seedHct[1] < _internals.NEUTRAL_CUTOFF) continue;
        deltas.push(hueDelta(seedHct[0], hexToHct(match.hex)[0]));
    }
    deltas.sort(function (a, b) { return a - b; });
    const p50 = deltas[Math.floor(deltas.length * 0.5)];
    const p90 = deltas[Math.floor(deltas.length * 0.9)];
    assert.ok(p50 <= 10, "median hue error too large: " + p50.toFixed(1) + "°");
    assert.ok(p90 <= 22, "p90 hue error too large: " + p90.toFixed(1) + "°");
    // The shipped tables are dense enough that the fallback should be rare.
    assert.ok(fallbacks / 500 < 0.05,
        "fallback rate too high: " + fallbacks + "/500");
    console.log("match accuracy: ok (median hue error " + p50.toFixed(1)
        + "°, p90 " + p90.toFixed(1) + "°, fallback " + fallbacks + "/500)");
}

// ── readability ───────────────────────────────────────────────────────────
// Every foreground role against the surface it is actually painted on. This is
// the check Material's fixed tone table cannot make, because the accent here
// keeps whatever tone the wallpaper had.
{
    const seeds = [
        "#e60012", "#7fecad", "#1a2847", "#f0c239", "#ffb7c5", "#64c4d4",
        "#0f7b6c", "#ffffff", "#000000", "#808080", "#fffefa", "#1c0d1a",
    ];
    const pairs = [
        ["on_primary", "primary"], ["on_secondary", "secondary"],
        ["on_tertiary", "tertiary"], ["on_error", "error"],
        ["on_primary_container", "primary_container"],
        ["on_secondary_container", "secondary_container"],
        ["on_tertiary_container", "tertiary_container"],
        ["on_error_container", "error_container"],
        ["on_primary_fixed", "primary_fixed"],
        ["on_surface", "surface"], ["on_background", "background"],
    ];
    let worst = { ratio: Infinity, label: "" };
    for (const seed of seeds) {
        const pair = buildSchemePair(seed);
        for (const mode of ["light", "dark"]) {
            for (const [fg, bg] of pairs) {
                const ratio = contrastRatio(pair[mode][fg], pair[mode][bg]);
                if (ratio < worst.ratio) {
                    worst = { ratio: ratio, label: fg + " on " + bg
                        + " (" + mode + ", " + seed + ")" };
                }
                assert.ok(ratio >= _internals.MIN_CONTRAST,
                    "contrast " + ratio.toFixed(2) + " below "
                    + _internals.MIN_CONTRAST + " for " + fg + " on " + bg
                    + " (" + mode + ", seed " + seed + ")");
            }
        }
    }
    console.log("readability: ok (worst pair " + worst.ratio.toFixed(2)
        + ":1 — " + worst.label + ")");
}

// ── clean backdrop ────────────────────────────────────────────────────────
// The chosen behaviour: the accent carries the wallpaper, the backdrop stays
// neutral. Surfaces must therefore sit at low chroma, and the elevation ramp
// must actually ascend — a decorative table that ignores tone would scatter it.
{
    const seeds = ["#e60012", "#7fecad", "#1a2847", "#f0c239", "#64c4d4"];
    const ladder = ["surface_container_lowest", "surface_container_low",
        "surface_container", "surface_container_high",
        "surface_container_highest"];
    for (const seed of seeds) {
        const pair = buildSchemePair(seed);
        for (const mode of ["light", "dark"]) {
            for (const role of ["surface", "background", "surface_container_low",
                "surface_container", "surface_container_high",
                "surface_container_highest"]) {
                const chroma = hexToHct(pair[mode][role])[1];
                assert.ok(chroma <= _internals.NEUTRAL_MAX_CHROMA + 1,
                    role + " (" + mode + ", " + seed + ") is not neutral: chroma "
                    + chroma.toFixed(1));
            }
            const tones = ladder.map(function (role) {
                return hexToHct(pair[mode][role])[2];
            });
            // Light mode ascends in tone from lowest elevation to highest
            // (100 -> 90 is descending brightness, 90 -> 100 ascending); dark
            // mode is the mirror. Either way the ramp must be strictly
            // monotonic, so the direction is read from the ends rather than
            // assumed.
            const ascending = tones[tones.length - 1] > tones[0];
            for (let i = 1; i < tones.length; i++) {
                const step = tones[i] - tones[i - 1];
                assert.ok(ascending ? step > 0 : step < 0,
                    "surface ladder must be strictly monotonic in " + mode
                    + " for " + seed + ": "
                    + tones.map(function (t) { return t.toFixed(0); }).join(" -> "));
            }
        }
    }
    console.log("clean backdrop: ok (surfaces within chroma "
        + _internals.NEUTRAL_MAX_CHROMA + ", elevation ramp ascends)");
}

// ── accent is the table's colour ──────────────────────────────────────────
// Fidelity claim, stated positively: light and dark share one accent and that
// accent IS the matched swatch, not a tone of it.
{
    for (const seed of ["#e60012", "#64c4d4", "#f0c239", "#0f7b6c"]) {
        const match = nearestNamed(seed);
        const pair = buildSchemePair(seed);
        assert.ok(match.accepted, seed + " should match the table");
        assert.equal(pair.light.primary, match.hex,
            "light primary must be the matched swatch for " + seed);
        assert.equal(pair.dark.primary, match.hex,
            "dark primary must be the same swatch for " + seed);
    }
    console.log("accent identity: ok (both modes carry the matched swatch)");
}

// ── fallback ──────────────────────────────────────────────────────────────
// The user's rule: if the table cannot express the seed, use Material. Driven
// through an injected one-colour table, because the shipped tables are dense
// enough that this branch never fires on its own (measured: 0/500 seeds).
{
    const seed = "#e60012";
    const wrongHue = [["远色绿", "#00ff00"]];
    const result = buildScheme(seed, { table: wrongHue });
    const material = buildMaterialScheme(seed, { variant: "vibrant" });
    assert.deepEqual(result, material,
        "an unmatched seed must produce exactly the Material scheme");

    // Green table, green seed: accepted, so this is a genuine branch test and
    // not a test that passes because everything falls back.
    const green = buildScheme("#00ff00", { table: wrongHue });
    assert.equal(green.primary, "#00ff00");
    assert.notDeepEqual(green, buildMaterialScheme("#00ff00", { variant: "vibrant" }));

    // The fallback must honour the requested variant, not Material's default.
    // MaterialColorScheme defaults to "tonal-spot"; the shell runs "vibrant".
    const fallback = buildScheme(seed, { table: wrongHue, variant: "tonal-spot" });
    assert.deepEqual(fallback,
        buildMaterialScheme(seed, { variant: "tonal-spot" }));
    assert.notDeepEqual(fallback, material);

    // Directly on the rule, so a table change cannot quietly disarm it.
    const matched = _internals.matchDistance;
    assert.equal(typeof matched, "function");
    const hct = hexToHct(seed);
    assert.equal(_internals.acceptMatch({ h: hct[0], c: hct[1], t: hct[2] },
        { entry: { name: "远色绿", hex: "#00ff00", h: hexToHct("#00ff00")[0],
            c: hexToHct("#00ff00")[1], t: hexToHct("#00ff00")[2] } }), false);
    console.log("fallback: ok (unmatched seed returns Material byte for byte, "
        + "variant preserved)");
}

// ── determinism & both tables ─────────────────────────────────────────────
{
    const seeds = ["#64c4d4", "#e60012", "#1a2847"];
    for (const seed of seeds) {
        for (const table of ["chinese", "japanese"]) {
            const first = buildSchemePair(seed, { table: table });
            const second = buildSchemePair(seed, { table: table });
            assert.deepEqual(first, second,
                table + " must be deterministic for " + seed);
        }
    }
    // The two tables must be capable of different answers, or the setting is a
    // no-op that still costs the user a choice.
    const different = seeds.some(function (seed) {
        return buildSchemePair(seed, { table: "chinese" }).light.primary
            !== buildSchemePair(seed, { table: "japanese" }).light.primary;
    });
    assert.ok(different, "chinese and japanese tables must not agree on "
        + "every accent");
    console.log("determinism: ok (stable across calls, tables differ)");
}

// ── layer tint readability ────────────────────────────────────────────────
// Every Material surface is its role tinted with the accent, and the tonal
// plate then paints layer1 through panelOpacity 0.60 — so two fifths of any
// tint is replaced by the blurred backdrop. Raising the tint is what makes a
// colour-source switch visible at all; raising it too far makes label text
// unreadable.
//
// The ratios live in AppearanceTokens.qml and are read from the source here
// rather than duplicated, so editing the QML is editing what this test checks.
{
    const source = readFileSync(new URL(
        "../../shell/desktop/modules/common/AppearanceTokens.qml",
        import.meta.url), "utf8");
    const tints = {};
    const pattern =
        /_layerTint(\d):\s*tokens\.isDarkTheme\s*\?\s*([0-9.]+)\s*:\s*([0-9.]+)/g;
    let match;
    while ((match = pattern.exec(source)) !== null) {
        tints[match[1]] = { dark: Number(match[2]), light: Number(match[3]) };
    }
    assert.deepEqual(Object.keys(tints).sort(),
        ["0", "1", "2", "3", "4"],
        "AppearanceTokens must define a tint ratio for every layer");

    const toRgb = function (hex) {
        return [1, 3, 5].map(function (i) {
            return parseInt(hex.slice(i, i + 2), 16) / 255;
        });
    };
    const tinted = function (base, tint, amount) {
        return base.map(function (v, i) { return v + (tint[i] - v) * amount; });
    };
    const luminance = function (rgb) {
        const linear = rgb.map(function (v) {
            return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        });
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
    };
    const contrast = function (a, b) {
        const la = luminance(a), lb = luminance(b);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    };

    const roles = ["background", "surface_container_low", "surface_container",
        "surface_container_high", "surface_container_highest"];

    let state = 424242;
    const random = function () {
        state = (state * 1103515245 + 12345) & 0x7fffffff;
        return state / 0x7fffffff;
    };

    let worst = { ratio: Infinity, label: "" };
    for (let i = 0; i < 120; i++) {
        // Chroma stays in the range a wallpaper quantiser actually produces.
        const seed = hctToHex(random() * 360, 2 + random() * 26, 8 + random() * 84);
        for (const table of [null, "chinese"]) {
            const pair = table
                ? buildSchemePair(seed, { table: table })
                : buildMaterialPair(seed, { variant: "vibrant" });
            for (const mode of ["light", "dark"]) {
                const ink = toRgb(pair[mode].on_surface);
                const accent = toRgb(pair[mode].primary);
                for (let layer = 0; layer < roles.length; layer++) {
                    const ratio = contrast(ink, tinted(
                        toRgb(pair[mode][roles[layer]]), accent,
                        tints[String(layer)][mode]));
                    if (ratio < worst.ratio) {
                        worst = { ratio: ratio, label: "layer" + layer + "/"
                            + mode + "/" + (table ?? "monet") + "/" + seed };
                    }
                    assert.ok(ratio >= 4.5,
                        "layer" + layer + " tinted at "
                        + tints[String(layer)][mode] + " (" + mode + ", "
                        + (table ?? "monet") + ", seed " + seed
                        + ") leaves on_surface at " + ratio.toFixed(2)
                        + ":1, below 4.5:1");
                }
            }
        }
    }
    console.log("layer tint readability: ok (worst label contrast "
        + worst.ratio.toFixed(2) + ":1 — " + worst.label + ")");
}

// ── tint is actually visible ──────────────────────────────────────────────
// The failure this guards against is subtle: the tints were once 0.01 in light
// mode, which passed every contrast check and changed nothing anyone could see.
// A switch between colour sources has to move the Dock's own background by a
// perceptible amount, so that is asserted directly.
{
    const seeds = ["#1b3a42", "#3d5a80", "#4a4a6a", "#a33b3b", "#8b5a3c",
        "#2d4a3e", "#6b5b95", "#c96f4a"];
    const toRgb = function (hex) {
        return [1, 3, 5].map(function (i) {
            return parseInt(hex.slice(i, i + 2), 16) / 255;
        });
    };
    // Same 0.20 as AppearanceTokens' light-mode layer0; read from the file so
    // the two cannot drift apart.
    const source = readFileSync(new URL(
        "../../shell/desktop/modules/common/AppearanceTokens.qml",
        import.meta.url), "utf8");
    const amount = Number(source.match(
        /_layerTint0:\s*tokens\.isDarkTheme\s*\?\s*[0-9.]+\s*:\s*([0-9.]+)/)[1]);

    const deltas = seeds.map(function (seed) {
        const m = buildMaterialPair(seed, { variant: "vibrant" });
        const t = buildSchemePair(seed, { table: "chinese" });
        const bgOf = function (pair, scheme) {
            const base = toRgb(pair.light.background);
            const accent = toRgb(pair.light.primary);
            return base.map(function (v, i) {
                return v + (accent[i] - v) * amount;
            });
        };
        const a = bgOf(m), b = bgOf(t);
        return Math.round(Math.max(...a.map(function (v, i) {
            return Math.abs(v - b[i]);
        })) * 255);
    });
    deltas.sort(function (a, b) { return a - b; });
    const median = deltas[Math.floor(deltas.length / 2)];
    // 8/255 is roughly where a side-by-side difference becomes obvious on a
    // full-width bar; below that the switch reads as "nothing happened".
    assert.ok(median >= 8,
        "a colour-source switch must visibly move the Dock background: median "
        + median + "/255 across " + seeds.length + " seeds");
    console.log("tint visibility: ok (colour-source switch moves the Dock "
        + "background by a median of " + median + "/255)");
}

// ── one tonal plate, not one per host ─────────────────────────────────────
// The Dock's pill paints through LiquidGlassSurface while the standalone Bar
// paints a plain Rectangle, and the two used to carry their own numbers:
// layer1 at 0.60 against layer0 at 1.00. Same Material role, visibly different
// plate — so a Bar rendered the fused material only while it was fused into the
// Dock, and went solid the moment it was not. Both now read one pair of tokens,
// and this asserts the wiring rather than the numbers: a later edit may change
// the fill or the opacity, but it cannot fork them per host again.
{
    const read = function (relative) {
        return readFileSync(new URL(relative, import.meta.url), "utf8");
    };
    const tokens = read(
        "../../shell/desktop/modules/common/AppearanceTokens.qml");
    const glass = read(
        "../../shell/desktop/modules/common/LiquidGlassSurface.qml");
    const panel = read(
        "../../shell/desktop/modules/common/LiquidGlassPanel.qml");
    const floatPanel = read(
        "../../shell/desktop/modules/common/KosFloatPanel.qml");

    assert.match(tokens,
        /readonly property color panelFill:\s*tokens\.colors\.layer1/,
        "surface.panelFill must stay the tonal plate's single fill (layer1)");
    assert.match(tokens,
        /readonly property real panelOpacity:\s*tokens\.glass\.materialOpacity/,
        "surface.panelOpacity must stay the tonal plate's single opacity");
    assert.match(tokens,
        /readonly property color barFill:\s*usesTonalRoles\s*\n\s*\?\s*panelFill/,
        "the Bar must paint panelFill rather than a layer of its own");
    assert.match(tokens,
        /readonly property real barOpacity:\s*usesTonalRoles \? panelOpacity : 0\.0/,
        "the Bar must paint panelOpacity; a hardcoded 1.0 is opaque while the "
        + "Dock is not");
    assert.match(tokens,
        /readonly property color widgetFill:\s*usesTonalRoles\s*\n\s*\?\s*panelFill/,
        "widget cards must paint the same plate as the Bar and the Dock");
    assert.match(glass, /AppearanceTokens\.surface\.panelFill/,
        "LiquidGlassSurface's tonal branch must read the shared plate fill");
    assert.match(glass, /AppearanceTokens\.surface\.panelOpacity/,
        "LiquidGlassSurface's tonal branch must read the shared plate opacity");
    // A host may opt out of translucency, but only by asking: the override is
    // per-instance and defaults to the shared token, so every other surface
    // still renders through one pair.
    assert.match(glass, /property real tonalOpacity: -1/,
        "the tonal opacity override must default to the shared token");
    assert.match(glass,
        /readonly property real tonalPlateOpacity: tonalOpacity >= 0\s*\n\s*\?\s*Math\.min\(1\.0, tonalOpacity\) : AppearanceTokens\.surface\.panelOpacity/,
        "the override must be the only way to move the plate's alpha");
    assert.match(glass, /materialSurfaceColor\.b, tonalPlateOpacity\)/,
        "the tonal fill must read that alpha rather than a literal -- a "
        + "hardcoded number is what made every host's surfaceOpacity dead");
    assert.match(panel, /tonalOpacity: root\.tonalOpacity/,
        "LiquidGlassPanel must forward the override to the surface");
    // One family asked for it: a confirmation dialog's contrast must not
    // depend on the wallpaper behind it.
    assert.match(floatPanel, /tonalOpacity: 1\.0/,
        "KosFloatPanel must opt into a fully opaque plate");
    console.log("tonal plate: ok (Bar, Dock pill and widget cards share one "
        + "fill/opacity pair; dialogs opt out per surface)");
}

// ── swatch coverage ───────────────────────────────────────────────────────
// The palette should be the table's own colours wherever the table can supply
// them. The container roles are the newest members of that set — they used to
// be derived tones of the accent — so their coverage is pinned here, along with
// the promise that a container stays in its accent's colour family.
{
    const inTable = new Set(CHINESE_COLORS.map(function (pair) {
        return pair[1];
    }));
    const containerRoles = ["primary_container", "secondary_container",
        "tertiary_container", "error_container"];
    const hueDelta = function (a, b) {
        const d = Math.abs(a - b) % 360;
        return d > 180 ? 360 - d : d;
    };

    let state = 909090;
    const random = function () {
        state = (state * 1103515245 + 12345) & 0x7fffffff;
        return state / 0x7fffffff;
    };

    let hits = 0, total = 0, worstHue = 0;
    for (let i = 0; i < 60; i++) {
        const seed = hctToHex(random() * 360, 4 + random() * 24, 10 + random() * 80);
        const pair = buildSchemePair(seed);
        for (const mode of ["light", "dark"]) {
            for (const role of containerRoles) {
                total++;
                if (inTable.has(pair[mode][role])) hits++;
            }
            // A container must stay in its accent's family: resolving containers
            // to swatches instead of deriving them must not let the two drift.
            worstHue = Math.max(worstHue,
                hueDelta(hexToHct(pair[mode].primary_container)[0],
                    hexToHct(pair[mode].primary)[0]));
        }
    }
    assert.ok(hits / total >= 0.75,
        "container roles should mostly be table swatches, got "
        + hits + "/" + total);
    assert.ok(worstHue <= 30,
        "a container must stay in its accent's colour family, worst hue gap "
        + worstHue.toFixed(1) + "°");
    console.log("swatch coverage: ok (containers are table swatches " + hits
        + "/" + total + ", worst accent hue gap " + worstHue.toFixed(1) + "°)");
}

// ── helper ────────────────────────────────────────────────────────────────
{
    assert.equal(roleColor("#64c4d4", "primary"),
        buildScheme("#64c4d4").primary);
    assert.equal(roleColor("#64c4d4", "not_a_role"), undefined);
    // An unknown table name must not throw — it falls back to the default.
    assert.equal(buildSchemePair("#64c4d4", { table: "klingon" }).light.primary,
        buildSchemePair("#64c4d4", { table: "chinese" }).light.primary);
    console.log("helpers: ok");
}

console.log("\ntraditional colour scheme contracts: passed");
