// Traditional-colour scheme generation (中国传统色 / 日本の伝統色), pure
// JavaScript, no external process.
//
// ---------------------------------------------------------------------------
// What this is for
// ---------------------------------------------------------------------------
// The Material scheme in MaterialColorScheme.mjs is faithful to Monet, and that
// is exactly the problem for a wallpaper-derived theme: Monet rewrites tone.
// Measured on this repository's own implementation, light-mode primary is
// forced to tone 40 (23-46 tone steps darker than the seed) and dark-mode
// primary to tone 80 (32-64 steps lighter), while the neutral surfaces are
// de-chromatised to chroma ~2 regardless of the seed. A dark navy wallpaper
// turns into a pale periwinkle; every wallpaper ends up with the same grey
// cards. The hue is preserved (worst case under 1 degree), so what the user
// perceives as "nothing like my wallpaper" is entirely tone and chroma.
//
// This module keeps the hue *and* the tone the wallpaper actually has, by
// snapping the seed to the nearest colour in a table of named traditional
// colours and using that colour as-is. The table is what makes the result
// legible to a person: the accent is not an anonymous tone-40 of some hue, it
// is 朱砂 or 一斤染 — a colour someone chose and named.
//
// ---------------------------------------------------------------------------
// Contract
// ---------------------------------------------------------------------------
// The output shape is identical to MaterialColorScheme.buildSchemePair, because
// Kos.Ui's ColorScheme singleton reshapes both into matugen's
// colors[role][light|dark].color and every shell consumer reads that. Same 49
// role names, same {light, dark} split, plus `source_color`.
//
//   seed hex -> HCT -> nearest named colour -> role colours
//
// Two deliberate departures from the Material algorithm:
//
//   1. The accent roles are the table's own colour, not a tone of it. Light and
//      dark mode therefore share one accent, which is the point: the accent is
//      the wallpaper's colour in both branches. The *foreground* roles adapt
//      instead — `on_primary` picks its tone from the accent's real tone, not
//      from a fixed 100/20 assumption.
//   2. The neutral roles are taken from the table's low-chroma colours, so a
//      light theme is 月白/象牙白 and a dark theme is 玄/墨 rather than a
//      mathematical grey. Chroma stays low on purpose: the shell asked for a
//      clean backdrop, and coloured surfaces fight the accent.
//
// FALLBACK: if the table has no colour close enough to the seed (see
// FALLBACK_TONE / FALLBACK_HUE below) the whole scheme falls back to the
// Material result for that seed, which is what the user asked for. Sparse
// tables degrade to Monet, they never produce a wrong-looking accent.

import { hexToHct, hctToHex } from "./Cam16Hct.mjs";
import { buildScheme as buildMaterialScheme } from "./MaterialColorScheme.mjs";
import { CHINESE_COLORS } from "./ChineseColors.mjs";
import { JAPANESE_COLORS } from "./JapaneseColors.mjs";

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

const TABLES = {
    chinese: CHINESE_COLORS,
    japanese: JAPANESE_COLORS,
};

// "chinese" matches the shell's own default and has the denser table (526 vs
// 228 entries), so it degrades to the fallback less often.
const DEFAULT_TABLE = "chinese";

// Variant used when a seed falls through to the Material scheme. The shell runs
// MaterialColorScheme with "vibrant" (see ColorScheme.qml), so the fallback has
// to ask for the same thing or a fallback seed would visibly use a different
// palette from every other seed.
const MATERIAL_FALLBACK_VARIANT = "vibrant";

// ---------------------------------------------------------------------------
// Role table
// ---------------------------------------------------------------------------
// Copied from MaterialColorScheme.mjs on purpose rather than imported: the two
// schemes must keep the same 49 role names, and a shared table would invite
// edits that only make sense for one of them. Each role is
// [family, lightTone, darkTone]. The tones are still used — but only as a
// *request* for derived roles, never applied to the accent itself.

const ROLE_SPEC = {
    primary: ["primary", 40, 80],
    on_primary: ["primary", 100, 20],
    primary_container: ["primary", 90, 30],
    on_primary_container: ["primary", 10, 90],
    primary_fixed: ["primary", 90, 90],
    primary_fixed_dim: ["primary", 80, 80],
    on_primary_fixed: ["primary", 10, 10],
    on_primary_fixed_variant: ["primary", 30, 30],

    secondary: ["secondary", 40, 80],
    on_secondary: ["secondary", 100, 20],
    secondary_container: ["secondary", 90, 30],
    on_secondary_container: ["secondary", 10, 90],
    secondary_fixed: ["secondary", 90, 90],
    secondary_fixed_dim: ["secondary", 80, 80],
    on_secondary_fixed: ["secondary", 10, 10],
    on_secondary_fixed_variant: ["secondary", 30, 30],

    tertiary: ["tertiary", 40, 80],
    on_tertiary: ["tertiary", 100, 20],
    tertiary_container: ["tertiary", 90, 30],
    on_tertiary_container: ["tertiary", 10, 90],
    tertiary_fixed: ["tertiary", 90, 90],
    tertiary_fixed_dim: ["tertiary", 80, 80],
    on_tertiary_fixed: ["tertiary", 10, 10],
    on_tertiary_fixed_variant: ["tertiary", 30, 30],

    error: ["error", 40, 80],
    on_error: ["error", 100, 20],
    error_container: ["error", 90, 30],
    on_error_container: ["error", 10, 90],

    surface_dim: ["neutral", 87, 6],
    surface: ["neutral", 98, 6],
    surface_bright: ["neutral", 98, 24],
    surface_container_lowest: ["neutral", 100, 4],
    surface_container_low: ["neutral", 96, 10],
    surface_container: ["neutral", 94, 12],
    surface_container_high: ["neutral", 92, 17],
    surface_container_highest: ["neutral", 90, 22],
    on_surface: ["neutral", 10, 90],
    surface_variant: ["neutralVariant", 90, 30],
    outline: ["neutralVariant", 50, 60],
    outline_variant: ["neutralVariant", 80, 30],
    on_surface_variant: ["neutralVariant", 30, 80],

    background: ["neutral", 98, 6],
    on_background: ["neutral", 10, 90],

    inverse_surface: ["neutral", 20, 90],
    inverse_on_surface: ["neutral", 95, 20],
    inverse_primary: ["primary", 80, 40],

    shadow: ["neutral", 0, 0],
    scrim: ["neutral", 0, 0],
    surface_tint: ["primary", 40, 80],
};

// ---------------------------------------------------------------------------
// Match thresholds
// ---------------------------------------------------------------------------
// These decide when the table is considered "close enough". They were set from
// the measured distribution of nearest-neighbour distances over both tables
// (see tests/traditional-color/test_traditional_color.mjs, which re-measures and
// asserts the fallback rate stays low).

// A hue this far from the seed means the table has no colour of that family at
// all, so the accent would not read as the wallpaper's colour.
const FALLBACK_HUE = 42;
// Tone difference the derived roles are allowed to carry. Kept generous: the
// table is sparse in the dark end, and a role being a few tone steps off is
// invisible, while refusing to derive would push us back to Monet for no gain.
const FALLBACK_TONE = 22;
// Chroma gap above which the match is rejected even if the hue lines up: a
// vivid wallpaper matched to a muted swatch looks like a different colour.
//
// Measured caveat: sRGB cannot express chroma above roughly 27 in HCT at
// tone 50 (24.8 at hue 0, 10.7 at hue 180), and the shipped tables span 0-27
// too, so with these tables this guard effectively never fires. It is kept
// because it is the correct rule the moment either table or colour space
// widens; tests drive the fallback through an injected table instead.
const FALLBACK_CHROMA = 34;

// Below this chroma a colour reads as neutral, and its hue coordinate becomes
// numerically unstable — 1 sRGB step can swing it tens of degrees (the same
// trap documented in docs/AppearanceArchitecture.md section 10.4). Matching
// near-neutral seeds on hue would pick a random family, so hue is dropped from
// the distance and from the rejection test.
//
// The threshold is measured, not guessed, and it has to be *low*. Measured
// against this table, a value of 8 silently discarded the hue of anything up to
// chroma 8 — which is most pastels — and the nearest neighbour of #ffb7c5
// (a pale pink) became 嘉陵水绿, a green 138 degrees away, because only tone and
// chroma were left to compare. The documented instability starts around chroma
// 1.2, so the cut sits just above it and only true greys lose their hue.
const NEUTRAL_CUTOFF = 2.5;

// Neutrals used for surfaces. The ceiling is deliberately low — the shell wants
// a clean backdrop, not a tinted one. At 12 the ladder reached 荸荠紫 and dark
// reds for its dark steps, which is not a neutral by any reading.
const NEUTRAL_MAX_CHROMA = 6;

// Foreground roles must clear this against the surface they sit on. 4.5:1 is
// WCAG AA for body text; the roles below carry labels, not decoration.
const MIN_CONTRAST = 4.5;

// ---------------------------------------------------------------------------
// Colour maths
// ---------------------------------------------------------------------------

function hueDistance(a, b) {
    const d = Math.abs(a - b) % 360;
    return d > 180 ? 360 - d : d;
}

function relativeLuminance(hex) {
    const value = parseInt(hex.slice(1), 16);
    const channels = [(value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff];
    let out = 0;
    const weights = [0.2126, 0.7152, 0.0722];
    for (let i = 0; i < 3; i++) {
        const c = channels[i] / 255;
        const linear = c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
        out += linear * weights[i];
    }
    return out;
}

function contrastRatio(a, b) {
    const la = relativeLuminance(a), lb = relativeLuminance(b);
    const hi = Math.max(la, lb), lo = Math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
}

// ---------------------------------------------------------------------------
// Table access
// ---------------------------------------------------------------------------

// [name, hex] pairs are converted to HCT once per table and cached. The table
// files stay pure data and the conversion never repeats.
//
// `name` may be a table name or a raw [name, hex] array. The array form is what
// lets a test drive the fallback branch with a deliberately impoverished table;
// it is not cached, since a fresh array has no stable identity to key on.
const catalogueCache = new Map();

function toEntries(table) {
    return table.map(function (pair) {
        const hct = hexToHct(pair[1]);
        return { name: pair[0], hex: pair[1], h: hct[0], c: hct[1], t: hct[2] };
    });
}

function catalogue(name) {
    if (Array.isArray(name)) return toEntries(name);
    if (catalogueCache.has(name)) return catalogueCache.get(name);
    const entries = toEntries(TABLES[name] ?? TABLES[DEFAULT_TABLE]);
    catalogueCache.set(name, entries);
    return entries;
}

// Distance in HCT space. Hue is weighted highest because it is what a person
// names ("this is the red one"), tone next because it is what they notice as
// "lighter or darker than my wallpaper", chroma last.
//
// Whether hue counts is decided by the SEED ALONE, and that asymmetry matters.
// An earlier version dropped the hue term whenever either colour was
// near-neutral, which handed a free pass to the grey end of the table: for the
// dark navy #1a2847 (chroma 5.9) the winner was 苍蝇灰 at chroma 2.0, distance
// 0.084, while the correct 钢青 (hue 254 against the seed's 269) scored 0.141.
// The grey won because it was excused from the hue comparison the coloured
// candidates had to pay for. Comparing hue whenever the seed itself has a hue
// punishes that properly — a low-chroma swatch now still has to sit in the right
// part of the wheel.
//
// When the seed is genuinely neutral its own hue reading is meaningless, so no
// candidate is charged for it and the match falls to tone and chroma.
function matchDistance(seed, entry) {
    let distance = 0;
    if (seed.c >= NEUTRAL_CUTOFF) {
        // Weighted 4.0 against chroma's 1.0: hue answers "is this the same
        // colour", which is the question being asked. At a lower weight the
        // term is swamped — for the mint #7fecad (hue 160, chroma 13.8) the
        // 16-degree 嘉陵水绿 beat the 6-degree 竹篁绿 purely on a 2.5-point
        // chroma gap, which is the wrong trade.
        const dh = hueDistance(seed.h, entry.h) / 180;
        distance += dh * dh * 4.0;
    }
    const dc = (seed.c - entry.c) / 50;
    const dt = (seed.t - entry.t) / 50;
    distance += dc * dc * 1.0 + dt * dt * 1.4;
    return Math.sqrt(distance);
}

// Nearest named colour, optionally restricted by a predicate (used to ask for
// "the closest low-chroma swatch" and similar).
function nearest(seed, entries, predicate) {
    let best = null, bestDistance = Infinity;
    for (let i = 0; i < entries.length; i++) {
        const entry = entries[i];
        if (predicate && !predicate(entry)) continue;
        const distance = matchDistance(seed, entry);
        if (distance < bestDistance) {
            bestDistance = distance;
            best = entry;
        }
    }
    return best ? { entry: best, distance: bestDistance } : null;
}

// ---------------------------------------------------------------------------
// Match rejection
// ---------------------------------------------------------------------------
// The user's rule: if the table cannot express this wallpaper, use Monet
// instead. That is tested per family, so a wallpaper whose accent matches but
// whose tertiary hue has no swatch still gets a traditional accent.
//
// As in matchDistance, the hue test keys off the seed: a seed with no chroma of
// its own has no hue to be wrong about.
function acceptMatch(seed, match) {
    if (!match) return false;
    const entry = match.entry;
    if (Math.abs(seed.t - entry.t) > FALLBACK_TONE) return false;
    if (Math.abs(seed.c - entry.c) > FALLBACK_CHROMA && entry.c < seed.c) return false;
    if (seed.c >= NEUTRAL_CUTOFF && hueDistance(seed.h, entry.h) > FALLBACK_HUE)
        return false;
    return true;
}

// ---------------------------------------------------------------------------
// Derived roles
// ---------------------------------------------------------------------------
// Only the accent *base* is taken from the table. Everything around it is
// derived from that base's hue and chroma so the family stays coherent and the
// contrast rules below have something predictable to work with.

function derived(hue, chroma, tone) {
    return hctToHex(hue, Math.max(0, chroma), tone);
}

// ---------------------------------------------------------------------------
// Foreground selection
// ---------------------------------------------------------------------------
// The role table's fixed 100/20 tones assume the accent sits at tone 40/80, the
// way Monet forces it to. A traditional accent keeps the wallpaper's real tone,
// which can be anything from 8 (墨) to 95 (月白), so a fixed foreground is
// simply wrong: white text on a pale 缃色 accent is unreadable. The foreground
// is therefore chosen from the accent's actual tone and then darkened or
// lightened until the contrast check passes.

function foregroundFor(accentHex, accentHct, baseChroma) {
    const chroma = baseChroma * 0.12;
    // Try both directions and keep the better one. A single direction chosen
    // from the accent's tone is not enough: at mid tone (瓦灰, T=52) neither
    // "#ffffff on it" nor a light step reaches 4.5:1, while a dark step clears
    // it comfortably. Picking by tone alone returned the failing white.
    const deep = walkTone(accentHex, accentHct.h, chroma, 18, -4);
    const pale = walkTone(accentHex, accentHct.h, chroma, 96, 4);
    if (deep && pale) {
        return contrastRatio(pale, accentHex) >= contrastRatio(deep, accentHex)
            ? pale : deep;
    }
    if (deep) return deep;
    if (pale) return pale;
    // Neither direction reaches the target — the accent sits in the dead zone
    // around mid grey. Fall back to near-black or near-white, whichever is
    // further from the accent, with chroma stripped so the label stays legible.
    const neutralDark = hctToHex(accentHct.h, 0, 0);
    const neutralLight = hctToHex(accentHct.h, 0, 100);
    return contrastRatio(neutralDark, accentHex) >= contrastRatio(neutralLight, accentHex)
        ? neutralDark : neutralLight;
}

// Steps the tone in `step` increments until the candidate clears MIN_CONTRAST.
// Returns null when the ramp runs off the end of the scale.
function walkTone(accentHex, hue, chroma, start, step) {
    let tone = start;
    for (let i = 0; i < 26; i++) {
        const candidate = derived(hue, chroma, tone);
        if (contrastRatio(candidate, accentHex) >= MIN_CONTRAST) return candidate;
        tone += step;
        if (tone < 0 || tone > 100) return null;
    }
    return null;
}

// ---------------------------------------------------------------------------
// Neutral ladder
// ---------------------------------------------------------------------------
// Surfaces come from the table's own low-chroma swatches so a light theme lands
// on 月白/象牙白 and a dark theme on 玄/墨 — real colours with real names,
// rather than a grey ramp. Each requested tone takes the closest unused swatch;
// once the table runs out the remainder is derived from the seed's hue at a
// very low chroma, so the ladder always has a value for every step.
function buildNeutralLadder(seed, entries) {
    const neutrals = entries.filter(function (e) {
        return e.c < NEUTRAL_MAX_CHROMA;
    });
    const used = new Set();
    // Same tone in, same colour out: surface and background are both tone 98 in
    // light mode and must not diverge just because one asked first.
    const byTone = new Map();
    return function tone(toneValue) {
        if (byTone.has(toneValue)) return byTone.get(toneValue);
        let best = null, bestScore = Infinity;
        for (let i = 0; i < neutrals.length; i++) {
            const entry = neutrals[i];
            if (used.has(entry.hex)) continue;
            // Tone decides, hue only breaks ties. That keeps the ladder
            // monotonic while letting a red wallpaper get the warm dark steps
            // and a blue one the cool ones, instead of whichever swatch
            // happened to sit at that tone.
            const score = Math.abs(entry.t - toneValue)
                + hueDistance(seed.h, entry.h) / 180 * 2.5;
            if (score < bestScore) {
                bestScore = score;
                best = entry;
            }
        }
        // Only claim a swatch when it really is at this step; otherwise the
        // ladder would jitter as unrelated swatches get consumed.
        let value;
        if (best && Math.abs(best.t - toneValue) <= 6) {
            used.add(best.hex);
            value = best.hex;
        } else {
            const chroma = Math.min(seed.c, NEUTRAL_MAX_CHROMA) * 0.35;
            value = hctToHex(seed.h, chroma, toneValue);
        }
        byTone.set(toneValue, value);
        return value;
    };
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export const ROLE_NAMES = Object.keys(ROLE_SPEC);
export const TABLES_AVAILABLE = Object.keys(TABLES);

// Build the full role->hex map for one mode.
//
//   options.table  — "chinese" (default) or "japanese"
//   options.dark   — false for light, true for dark
//
// The options are copied field by field rather than with object spread:
// qmlcachegen rejects `{ ...options }` outright and the failure only shows up
// at build time. MaterialColorScheme.mjs documents the same trap.
//
// Results are memoized on (seed, table, variant, dark) — the full set of
// inputs that can change the output. Each build costs 4+ nearest-neighbour
// scans over the whole table plus a tone-walk per foreground, and the same
// (seed, scheme) pair is requested repeatedly: once for the active palette
// and again for the settings preview on every palette revision. An injected
// array table (the tests' fallback driver) bypasses the cache: a fresh array
// has no name to key on and each one must be re-evaluated. A different seed,
// table, variant or mode is a different key, so a palette change always
// rebuilds and is never served the previous scheme.
const SCHEME_CACHE_LIMIT = 32;
const schemeCache = new Map();

export function buildScheme(seedHex, options = {}) {
    const table = options.table ?? DEFAULT_TABLE;
    const dark = options.dark ?? false;
    const cacheable = !Array.isArray(table);
    const key = cacheable
        ? String(seedHex).toLowerCase() + "|" + table + "|"
            + (options.variant ?? MATERIAL_FALLBACK_VARIANT)
            + "|" + (dark ? "1" : "0")
        : "";
    if (cacheable) {
        const cached = schemeCache.get(key);
        if (cached) return Object.assign({}, cached);
    }
    const entries = catalogue(table);
    const seed = { h: 0, c: 0, t: 0 };
    const seedHct = hexToHct(seedHex);
    seed.h = seedHct[0];
    seed.c = seedHct[1];
    seed.t = seedHct[2];

    const out = { source_color: seedHex };

    // The accent is the wallpaper's colour, matched directly.
    const accentMatch = nearest(seed, entries);
    if (!acceptMatch(seed, accentMatch)) {
        // Table cannot express this seed: hand the whole scheme to Monet.
        //
        // The variant is forwarded explicitly. MaterialColorScheme defaults to
        const fallback = buildMaterialScheme(seedHex, {
            variant: options.variant ?? MATERIAL_FALLBACK_VARIANT,
            dark: dark,
        });
        // The Monet result is still this scheme's answer for the seed, so it
        // is cached under the same key; repeat preview calls stay cheap.
        if (cacheable) {
            if (schemeCache.size >= SCHEME_CACHE_LIMIT)
                schemeCache.delete(schemeCache.keys().next().value);
            schemeCache.set(key, fallback);
        }
        return Object.assign({}, fallback);
    }

    const accent = accentMatch.entry;

    // secondary and tertiary follow Material's hue relationships (secondary is
    // the same family, tertiary sits a step around the wheel) but each is
    // resolved to a real swatch, so they are traditional colours too rather
    // than derived tones of the accent.
    const secondarySeed = { h: seed.h, c: Math.min(seed.c * 0.5, 18), t: seed.t };
    const tertiarySeed = {
        h: (seed.h + 60) % 360,
        c: Math.min(seed.c, 40),
        t: seed.t,
    };
    // Chroma 25, not Material's 60 for the error family. sRGB tops out at about
    // chroma 27 in HCT at mid tone, so a request of 60 is beyond anything the
    // table can hold: acceptMatch rejected every candidate on the chroma gap
    // and the error roles silently fell back to a derived red. Measured on the
    // same seed, 60 yields a computed #730005 while 25 yields 殷红 (#82111f) and
    // 丽春红 (#eb261a) — real traditional reds with names.
    const errorSeed = { h: 25, c: 25, t: Math.min(seed.t, 55) };

    const secondaryMatch = nearest(secondarySeed, entries);
    const tertiaryMatch = nearest(tertiarySeed, entries);
    const errorMatch = nearest(errorSeed, entries);

    const secondary = acceptMatch(secondarySeed, secondaryMatch)
        ? secondaryMatch.entry : seedToBase(secondarySeed);
    const tertiary = acceptMatch(tertiarySeed, tertiaryMatch)
        ? tertiaryMatch.entry : seedToBase(tertiarySeed);
    const error = acceptMatch(errorSeed, errorMatch)
        ? errorMatch.entry : seedToBase(errorSeed);

    // Each family resolves to its own swatches plus the foregrounds measured
    // against them, so no role can borrow a foreground that was computed for a
    // different surface.
    const families = {
        primary: resolveFamily("primary", accent, dark, entries),
        secondary: resolveFamily("secondary", secondary, dark, entries),
        tertiary: resolveFamily("tertiary", tertiary, dark, entries),
        error: resolveFamily("error", error, dark, entries),
    };

    const neutral = buildNeutralLadder(seed, entries);

    for (const role of ROLE_NAMES) {
        const spec = ROLE_SPEC[role];
        const family = spec[0];
        const tone = dark ? spec[2] : spec[1];

        if (family === "neutral" || family === "neutralVariant") {
            out[role] = neutralRole(role, tone, neutral, dark);
            continue;
        }
        out[role] = familyRole(families[family], tone, role);
    }

    if (cacheable) {
        if (schemeCache.size >= SCHEME_CACHE_LIMIT)
            schemeCache.delete(schemeCache.keys().next().value);
        schemeCache.set(key, out);
    }
    return Object.assign({}, out);
}

// A base colour synthesised from a seed when no swatch was acceptable, so the
// derived roles still have a hue and chroma to work from.
function seedToBase(seed) {
    return { name: "", hex: hctToHex(seed.h, Math.min(seed.c, 40), seed.t),
        h: seed.h, c: Math.min(seed.c, 40), t: seed.t };
}

// Roles whose family is not the accent. These follow the accent's rule — the
// family's own swatch carries both modes, and only the surrounding roles are
// derived — because secondary and tertiary are accents too.
//
// An earlier version derived `secondary` from the Material tone while computing
// `on_secondary` against the swatch's own tone. The two disagreed and the label
// landed at 1.70:1 on its own background (caught by the readability block in
// tests/traditional-color/test_traditional_color.mjs). The swatch and its
// foreground have to describe the same colour.
function familyRole(family, tone, role) {
    const name = family.name;
    const base = family.base;
    if (role === name) return family.hex;
    if (role === "on_" + name) return family.foreground;
    if (role === name + "_fixed") return family.hex;
    if (role === "on_" + name + "_fixed") return family.foreground;
    if (role === "on_" + name + "_fixed_variant") {
        return derived(base.h, base.c * 0.45,
            base.t > 55 ? Math.max(10, base.t - 30) : Math.min(90, base.t + 30));
    }
    if (role === name + "_fixed_dim") {
        return derived(base.h, base.c * 0.8, Math.max(8, base.t - 12));
    }
    if (role === name + "_container") return family.container.hex;
    if (role === "on_" + name + "_container") return family.onContainer;
    return derived(base.h, base.c * 0.9, tone);
}

// Containers are swatches too. A container's job is to be the same family at a
// different elevation, so the search is led by tone — a container that misses
// its step breaks the layer ordering — then by hue, with chroma only breaking
// ties. When nothing in the table sits close enough to the requested step the
// role falls back to a derived tone, which is what the whole family used to do.
const CONTAINER_TONE_TOLERANCE = 7;

function containerColour(baseHue, tone, baseChroma, entries) {
    const chromaHint = Math.max(4, baseChroma * 0.34);
    let best = null, bestScore = Infinity;
    for (let i = 0; i < entries.length; i++) {
        const entry = entries[i];
        const dt = (entry.t - tone) / 100;
        const dh = hueDistance(baseHue, entry.h) / 180;
        const dc = (entry.c - chromaHint) / 50;
        const score = dt * dt * 6.0 + dh * dh * 4.0 + dc * dc * 1.0;
        if (score < bestScore) {
            bestScore = score;
            best = entry;
        }
    }
    if (best && Math.abs(best.t - tone) <= CONTAINER_TONE_TOLERANCE) return best;
    return {
        name: "",
        hex: derived(baseHue, chromaHint, tone),
        h: baseHue,
        c: chromaHint,
        t: tone,
    };
}

// One accent family, resolved to swatches wherever the table can supply them.
// Both modes share the same base swatch — that is the point of the scheme — so
// only the container step is computed per mode.
//
// The two foregrounds are computed against the colour they will actually sit
// on. That is not decoration: keeping them together here is what stops a role
// from being paired with a foreground measured against a different surface,
// which is exactly how on_secondary once ended up at 1.70:1 on its own
// background.
function resolveFamily(name, base, dark, entries) {
    const container = containerColour(base.h, dark ? 30 : 90, base.c, entries);
    return {
        name: name,
        base: base,
        hex: base.hex,
        foreground: foregroundFor(base.hex, base, base.c),
        container: container,
        onContainer: foregroundFor(container.hex, container, container.c),
    };
}

// Surface roles. Everything neutral resolves through the ladder, which keeps
// the backdrop clean and the elevation steps ordered.
function neutralRole(role, tone, neutral, dark) {
    if (role === "shadow" || role === "scrim") return "#000000";
    // on_surface_variant is the weaker of the two label steps; giving it the
    // same value as on_surface would flatten Material's text hierarchy.
    if (role === "on_surface_variant") return neutral(dark ? 76 : 32);
    if (role.startsWith("on_")) {
        // on_surface / on_background are text on the ladder's surface step, so
        // the ladder's opposite end is the readable choice.
        return neutral(dark ? 90 : 10);
    }
    return neutral(tone);
}

// Both modes at once, matching matugen's colors[role][light|dark] shape.
export function buildSchemePair(seedHex, options = {}) {
    const light = { table: options.table, variant: options.variant, dark: false };
    const dark = { table: options.table, variant: options.variant, dark: true };
    return {
        light: buildScheme(seedHex, light),
        dark: buildScheme(seedHex, dark),
    };
}

// Single role lookup, in case a caller only needs one.
export function roleColor(seedHex, role, options = {}) {
    if (!ROLE_SPEC[role]) return undefined;
    return buildScheme(seedHex, options)[role];
}

// The named colour a seed resolves to, for diagnostics and for the settings UI.
export function nearestNamed(seedHex, options = {}) {
    const table = options.table ?? DEFAULT_TABLE;
    const hct = hexToHct(seedHex);
    const seed = { h: hct[0], c: hct[1], t: hct[2] };
    const match = nearest(seed, catalogue(table));
    if (!match) return null;
    return {
        name: match.entry.name,
        hex: match.entry.hex,
        accepted: acceptMatch(seed, match),
        distance: match.distance,
    };
}

export { hexToHct, hctToHex, contrastRatio };

// Exposed for the test suite: the acceptance rules are pure functions, and
// exercising them directly is the only way to cover the fallback path when the
// shipped tables are dense enough that it never triggers on its own.
export const _internals = {
    acceptMatch, matchDistance, hueDistance, catalogue, ROLE_SPEC,
    NEUTRAL_CUTOFF, NEUTRAL_MAX_CHROMA, FALLBACK_HUE, FALLBACK_TONE,
    FALLBACK_CHROMA, MIN_CONTRAST,
};
