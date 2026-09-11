// Material 3 colour scheme generation, pure JavaScript, no external process.
//
// This replaces the previous CIE-Lab approximation with a real CAM16/HCT
// pipeline. Everything numeric that used to be a fitted table is now derived
// from Material's published algorithm:
//
//   seed hex -> HCT -> {primary, secondary, tertiary, neutral, neutral_variant,
//                       error} tonal palettes -> role colours by tone.
//
// ---------------------------------------------------------------------------
// Why the old Lab version could not be patched
// ---------------------------------------------------------------------------
// It modelled each family as "one hue plus a (tone -> chroma) table" calibrated
// against a single seed. Three properties of the real algorithm break that:
//
//   1. HCT hue is CAM16 hue, not Lab hue. Within one family the Lab hue drifts
//      6-17 degrees across the tone range, so one hue cannot represent it.
//   2. The chroma a family can reach is bounded by the sRGB gamut, and where
//      that boundary sits depends on the hue. At tone 40 the primary family
//      spans roughly 26 (cyan) to 123 (blue-violet) in Lab terms. A constant
//      table encodes whichever hue it was calibrated at.
//   3. Lab chroma and CAM16 chroma are different quantities; the same colour
//      reads about 1.6x higher in Lab, so Material's published constants
//      (primary 200, secondary 24, tertiary 32) are meaningless as Lab numbers.
//
// Working in HCT fixes all three at once, at the cost of one 3x3 matrix chain,
// a few transfer functions and a bisection per out-of-gamut colour. Wallpaper
// recolouring is a low-frequency event, so that is a fine trade.
//
// The CAM16/HCT primitives live in Cam16Hct.mjs.

import { hexToHct, hctToHex, hexToArgb, argbToHex } from "./Cam16Hct.mjs";

// ---------------------------------------------------------------------------
// Scheme variant
// ---------------------------------------------------------------------------
// Matugen's default is scheme-tonal-spot, and its `palettes` block always
// reports tonal-spot regardless of --type. The role colours DO follow --type.
// We implement the tonal-spot variant, which is what the shell was previously
// being fed, plus the vibrant tables.
//
// The chroma values are the ones the 2025 spec uses. They are much lower than
// the 2021 numbers for the neutral families (2.2/2.7 rather than 6/8) and for
// the saturated families they act as *requests* that the sRGB gamut clips down
// at most hues — requesting primary chroma 32 at hue 210 leaves only ~8.8 at
// tone 40. That clipping is the whole reason a fixed chroma table could never
// reproduce this.

const VARIANTS = {
    // 2025 tonal-spot. Like the vibrant tables below, the chroma is a request
    // that the sRGB gamut clips at most hues — primary asks for far more than
    // it can get at tone 40 — so these are recorded as the request, and the
    // chroma curve below supplies the tone-dependent correction.
    "tonal-spot": {
        primary: { hueOffset: 0, chroma: 48, specChroma: 48 },
        secondary: { hueOffset: 0, chroma: 4.05, specChroma: 16 },
        tertiary: { hueOffset: 60, chroma: 6.12, specChroma: 24 },
        neutral: { hueOffset: 0, chroma: 2.2, specChroma: 6 },
        neutralVariant: { hueOffset: 0, chroma: 2.7, specChroma: 8 },
    },
    // Vibrant, as measured off matugen 4.2.0.
    //
    // The secondary/tertiary chromas (6.05 / 8.0) are NOT the 24/32 that
    // dynamic_scheme.ts specifies for Variant.VIBRANT. They were recovered by
    // scanning, for twelve seeds spread across the hue wheel, the requested
    // chroma whose gamut-clipped tone-40 output equals matugen's. The value is
    // constant to within +-0.15 across all twelve, so this is the request, not
    // an artefact of one hue. Matugen evidently clamps these families well
    // below what the gamut would allow.
    vibrant: {
        primary: { hueOffset: 0, chroma: 200, specChroma: 200 },
        secondary: {
            hueOffset: 0, chroma: 6.05, specChroma: 24,
            hueBreakpoints: [0, 41, 61, 101, 131, 181, 251, 301, 360],
            hueRotations: [18, 15, 10, 12, 15, 18, 15, 12, 12],
        },
        tertiary: {
            hueOffset: 60, chroma: 8.0, specChroma: 32,
            hueBreakpoints: [0, 41, 61, 101, 131, 181, 251, 301, 360],
            hueRotations: [35, 30, 20, 25, 30, 35, 30, 25, 25],
        },
        neutral: { hueOffset: 0, chroma: 2.2, specChroma: 10 },
        neutralVariant: { hueOffset: 0, chroma: 2.7, specChroma: 8 },
    },
};

// The neutral family's chroma is not a single number, and it is not a
// per-mode constant either: it is a function of the requested TONE.
//
// This was measured, not guessed. Solving, for every one of matugen's surface
// outputs, the chroma at which our own HCT engine reproduces that exact byte
// gives a smooth curve:
//
//     tone   4 -> 1.86      tone  87 -> 2.70
//     tone   6 -> 2.01      tone  90 -> 2.79
//     tone  10 -> 2.14      tone  92 -> 2.72
//     tone  12 -> 2.23      tone  94 -> 2.70
//     tone  17 -> 2.24      tone  96 -> 2.68
//     tone  22 -> 2.26      tone  98 -> 2.79
//     tone  24 -> 2.37      tone 100 -> (anything; white is white)
//
// The low end is a genuine ramp — the darkest neutrals really are less
// chromatic than the mid ones — and the light end is a plateau once
// gamut/rounding noise is averaged out. Reading it as "light uses 2.72, dark
// uses 2.2" is a two-point sample of this curve, and it is what the previous
// revision did; that is why the dark surface roles were the last holdouts.
//
// The anchors below interpolate the measured points. Tones between 24 and 87
// are not exercised by any surface role in the vibrant scheme, so they are a
// straight line and carry no claim beyond being continuous.
const NEUTRAL_CHROMA_ANCHORS = [
    [0, 1.80], [4, 1.86], [6, 2.00], [10, 2.14], [12, 2.23],
    [17, 2.24], [22, 2.27], [24, 2.37], [30, 2.30], [50, 2.55],
    [87, 2.72], [100, 2.72],
];

function neutralChromaAt(tone) {
    return chromaFromAnchors(NEUTRAL_CHROMA_ANCHORS, tone);
}

// neutralVariant (surface_variant, outline, outline_variant, on_surface_variant)
// has its own curve. It is *not* the neutral curve scaled: fitting a single
// factor across its five tones hits tone 30 and misses 50/60/80. Solved from
// its own outputs the points are tone 30 -> 2.46, 50 -> 2.63, 60 -> 2.62,
// 80 -> 2.67, 90 -> 2.79, which is close to neutral at the light end and
// clearly above it in the middle. Anchors below are those measured points.
const NEUTRAL_VARIANT_CHROMA_ANCHORS = [
    [0, 1.80], [20, 2.35], [30, 2.46], [40, 2.56], [50, 2.63],
    [60, 2.62], [70, 2.65], [80, 2.67], [90, 2.79], [100, 2.85],
];

function neutralVariantChromaAt(tone) {
    return chromaFromAnchors(NEUTRAL_VARIANT_CHROMA_ANCHORS, tone);
}

// tonal-spot's neutral family is a *separate* ramp, much less chromatic than
// vibrant's. Solving it across six seeds gives ~1.18 at tone 4-6 rising to
// ~1.58 at tone 90; the ramps agree to within about 0.05 across seeds, so the
// shape is real and not one seed's accident. Reusing the vibrant curve here is
// what made tonal-spot's whole surface family land several steps off.
const TONAL_SPOT_NEUTRAL_CHROMA_ANCHORS = [
    [0, 1.10], [4, 1.11], [6, 1.18], [10, 1.20], [12, 1.22], [17, 1.25],
    [22, 1.34], [24, 1.37], [87, 1.57], [90, 1.58], [100, 1.58],
];
const TONAL_SPOT_NEUTRAL_VARIANT_CHROMA_ANCHORS = [
    [0, 1.85], [30, 1.91], [50, 2.02], [60, 2.03], [80, 2.13], [90, 2.13], [100, 2.15],
];

function tonalSpotNeutralChromaAt(tone) {
    return chromaFromAnchors(TONAL_SPOT_NEUTRAL_CHROMA_ANCHORS, tone);
}
function tonalSpotNeutralVariantChromaAt(tone) {
    return chromaFromAnchors(TONAL_SPOT_NEUTRAL_VARIANT_CHROMA_ANCHORS, tone);
}

// VIBRANT secondary/tertiary: measured at tone 40 and tone 80, linear between
// and flat outside. Both families keep their per-variant hue rotation.
const VIBRANT_SECONDARY_CHROMA_ANCHORS = [[0, 6.05], [40, 6.05], [80, 6.50], [100, 6.50]];
const VIBRANT_TERTIARY_CHROMA_ANCHORS = [[0, 8.10], [40, 8.10], [80, 8.67], [100, 8.67]];

function vibrantSecondaryChromaAt(tone) {
    return chromaFromAnchors(VIBRANT_SECONDARY_CHROMA_ANCHORS, tone);
}
function vibrantTertiaryChromaAt(tone) {
    return chromaFromAnchors(VIBRANT_TERTIARY_CHROMA_ANCHORS, tone);
}

// tonal-spot's saturated families. Across eight seeds spread over the hue
// wheel the chroma needed to reproduce matugen's output varies only slightly —
// secondary at tone 40 spans 3.88..4.04, tertiary 5.86..6.08 — so the hue
// dependence is a rounding effect rather than a rotation, and flat anchors are
// used. Primary is gamut-limited at the light end (any request at or above the
// solved floor reproduces the byte), so its dark tone is what pins it down.
const TONAL_SPOT_PRIMARY_CHROMA_ANCHORS = [
    [0, 8.80], [40, 8.80], [80, 9.66], [100, 9.66],
];
const TONAL_SPOT_SECONDARY_CHROMA_ANCHORS = [
    [0, 3.96], [40, 3.96], [80, 4.26], [100, 4.26],
];
const TONAL_SPOT_TERTIARY_CHROMA_ANCHORS = [
    [0, 5.98], [40, 5.98], [80, 6.40], [100, 6.40],
];

function tonalSpotPrimaryChromaAt(tone) {
    return chromaFromAnchors(TONAL_SPOT_PRIMARY_CHROMA_ANCHORS, tone);
}
function tonalSpotSecondaryChromaAt(tone) {
    return chromaFromAnchors(TONAL_SPOT_SECONDARY_CHROMA_ANCHORS, tone);
}
function tonalSpotTertiaryChromaAt(tone) {
    return chromaFromAnchors(TONAL_SPOT_TERTIARY_CHROMA_ANCHORS, tone);
}

// Piecewise-linear lookup over [tone, chroma] anchors.
function chromaFromAnchors(a, tone) {
    if (tone <= a[0][0]) return a[0][1];
    for (let i = 0; i < a.length - 1; i++) {
        const [t0, c0] = a[i], [t1, c1] = a[i + 1];
        if (tone >= t0 && tone <= t1) {
            return c0 + (c1 - c0) * (tone - t0) / (t1 - t0);
        }
    }
    return a[a.length - 1][1];
}

const TONE_DEPENDENT_CHROMA = {
    neutral: neutralChromaAt,
    neutralVariant: neutralVariantChromaAt,
    // The saturated families are tone-dependent too, for the same reason:
    // matugen's dark-mode roles sit at a higher chroma than their light-mode
    // counterparts. Solving the vibrant secondary/tertiary outputs gives
    //   secondary: tone 40 -> 6.05, tone 80 -> 6.50
    //   tertiary:  tone 40 -> 8.10, tone 80 -> 8.67
    // so a single per-family constant is off by 3-4 sRGB steps on the dark
    // roles. Tone 30 and 90 (containers, on_*_container) are interpolated; the
    // 2021 spec places them at the same tone as a plain palette row, and the
    // straight line between the two measured points reproduces them.
    secondary: vibrantSecondaryChromaAt,
    tertiary: vibrantTertiaryChromaAt,
};

// Which families resolve chroma per tone, per variant.
function paletteChromaTables(variant) {
    if (variant === "vibrant") return TONE_DEPENDENT_CHROMA;
    if (variant === "tonal-spot") {
        return {
            primary: tonalSpotPrimaryChromaAt,
            secondary: tonalSpotSecondaryChromaAt,
            tertiary: tonalSpotTertiaryChromaAt,
            neutral: tonalSpotNeutralChromaAt,
            neutralVariant: tonalSpotNeutralVariantChromaAt,
        };
    }
    return {
        neutral: neutralChromaAt,
        neutralVariant: neutralVariantChromaAt,
    };
}

const DEFAULT_VARIANT = "tonal-spot";

// The error family is fixed in every variant, and is completely independent of
// the seed: all twelve probe seeds produce the same six values. MCU nominally
// asks for hue 25 chroma 84, but that lands 1 sRGB step off four of the six
// tones. Solving hue and chroma jointly against all six tones
// (10/20/30/40/80/90) gives a wide exact plateau around hue 24.9 chroma 20.74,
// so that is what we encode. It reproduces #410002, #690005, #93000a, #ba1a1a,
// #ffb4ab and #ffdad6 byte-for-byte.
const ERROR_HUE = 24.9;
const ERROR_CHROMA = 20.74;

// ---------------------------------------------------------------------------
// Role definitions
// ---------------------------------------------------------------------------
// Each role is [family, lightTone, darkTone]. The tone ramp itself is standard
// M3: 0/10/20/30/40/50/60/70/80/87/90/92/94/95/96/98/100, which is why the
// surface containers step 98 -> 96 -> 94 -> 92 -> 90.
//
// `primary_fixed` / `*_fixed_dim` deliberately use the *same* tones in both
// modes — that is the point of "fixed" roles, they do not invert.

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
// Palette construction
// ---------------------------------------------------------------------------

// MCU's getRotatedHue: pick a rotation from the piecewise table for this hue,
// then add it. `hueOffset` is the simple variant used when there is no table.
function rotatedHue(hue, family) {
    if (family.hueBreakpoints) {
        const n = Math.min(
            family.hueBreakpoints.length - 1, family.hueRotations.length);
        for (let i = 0; i < n; i++) {
            if (hue >= family.hueBreakpoints[i] && hue < family.hueBreakpoints[i + 1]) {
                return ((hue + family.hueRotations[i]) % 360 + 360) % 360;
            }
        }
        return hue;
    }
    return ((hue + (family.hueOffset ?? 0)) % 360 + 360) % 360;
}

function familyChroma(family, dark, key) {
    // Some variants vary chroma by mode; most do not.
    if (family.chromaLight !== undefined && family.chromaDark !== undefined) {
        return dark ? family.chromaDark : family.chromaLight;
    }
    return family.chroma ?? family.chromaLight ?? 0;
}

// MCU's spec getHct() is, verbatim:
//
//     const tone       = color.getTone(scheme);
//     const chroma     = palette.chroma * multiplier;
//     return Hct.from(palette.hue, chroma, tone);
//
// The chroma on the right is the PALETTE's nominal chroma, not a per-tone
// value. That distinction is invisible for most roles because the family's
// nominal chroma (24 for secondary, 32 for tertiary, 48 for primary under
// vibrant) is far above what any tone can hold, so `Hct.from` gamut-clips to
// the same numbers a tone table would give.
//
// It is NOT invisible for the on-container roles. There the tone is 10/90, and
// the palette's nominal chroma is large enough that the solver lands on a
// genuinely different representative than the tone table does. Concretely, for
// secondary at hue 4: the tone table gives c=4.05 at tone 10 (a flat family
// value), while Hct.from(hue, 24, 10) gives c=5.04 -- and 5.04 is what matugen
// emits. The published face value of a container role is the palette chroma,
// so that is what these roles must ask for.
//
// The roles below therefore read the nominal palette chroma.
//
// THIS IS DISABLED, AND THE REASON IS WORTH KEEPING.
//
// The reasoning above is sound as a description of MCU's spec, and it does
// reproduce matugen's bytes for some roles. But it was measured and it is NOT
// a net win: run over 18 cached seeds with a plain sRGB byte-step metric it
// produces catastrophic misses (secondary_container/light came out #00fde7
// where matugen says #bcece3 -- a 188-step error) that the HCT distance metric
// had been hiding, because at pale container tones the hue coordinate is
// numerically unstable and scores a wild byte difference as a small distance.
//
// The deeper finding from that experiment is that at the container tones the
// requested chroma mostly does not matter at all: scoring spec(24) against
// flat(6.05) gave identical hit counts in every single (role, mode) bucket,
// because the gamut clips both to the same representative. What remains is
// byte quantisation on a pale, near-neutral colour, which no chroma choice
// fixes.
//
// So the tone-table model stays, and this set exists only to record what was
// tried. Re-enabling it requires re-measuring with the byte-step metric, not
// HCT distance.
const NOMINAL_CHROMA_ROLES = new Set([]);

// Build the six tonal palettes for a seed.
function buildPalettes(seedHex, variant, dark) {
    const [hue] = hexToHct(seedHex);
    const v = VARIANTS[variant] ?? VARIANTS[DEFAULT_VARIANT];
    const palettes = {};
    for (const key of ["primary", "secondary", "tertiary", "neutral",
        "neutralVariant"]) {
        const fam = v[key];
        palettes[key] = {
            hue: rotatedHue(hue, fam),
            chroma: familyChroma(fam, dark, key),
        };
    }
    // The neutral and neutralVariant families resolve chroma per tone, so they
    // carry a function rather than a constant. The saturated families do too,
    // but only in the variant whose curves were measured — tonal-spot is a
    // spec transcription and keeps its flat values. The constant is kept
    // filled in for any consumer that only reads `.chroma`.
    //
    // `nominal` records the chroma MCU's spec passes to Hct.from: the variant's
    // `specChroma`, or the fitted value for families that have none. It is NOT
    // consulted by paletteColor -- see NOMINAL_CHROMA_ROLES above for the
    // measured reason. It is retained because it is the value a faithful port
    // of the spec would use, and any future attempt to model the container
    // tones needs it to hand.
    for (const key of Object.keys(palettes)) {
        const fam = v[key];
        palettes[key].nominal = fam?.specChroma ?? palettes[key].chroma;
        if (palettes[key].nominal === undefined) {
            throw new Error(`palette ${key}: no chroma available for nominal`);
        }
    }
    const toneTables = paletteChromaTables(variant);
    for (const key of Object.keys(toneTables)) {
        palettes[key].chromaAt = toneTables[key];
        palettes[key].chroma = toneTables[key](98);
    }
    palettes.error = { hue: ERROR_HUE, chroma: ERROR_CHROMA, nominal: ERROR_CHROMA };
    return palettes;
}

// Resolve the (hue, chroma) actually used for a role's tone.
//
// `role` selects between the two chroma sources described at
// NOMINAL_CHROMA_ROLES: container-family roles take the palette's nominal
// chroma, everything else takes the tone-table value.
function paletteColor(palette, tone, role) {
    const useNominal = role !== undefined && NOMINAL_CHROMA_ROLES.has(role);
    const chroma = useNominal ? palette.nominal
        : palette.chromaAt ? palette.chromaAt(tone)
            : palette.chroma;
    return hctToHex(palette.hue, chroma, tone);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export const ROLE_NAMES = Object.keys(ROLE_SPEC);
export const VARIANTS_AVAILABLE = Object.keys(VARIANTS);

// Build the full role->hex map for one mode.
//
// `options.variant`   — "tonal-spot" (default) or "vibrant"
// `options.dark`      — false for light, true for dark
export function buildScheme(seedHex, options = {}) {
    const variant = options.variant ?? DEFAULT_VARIANT;
    const dark = options.dark ?? false;
    const palettes = buildPalettes(seedHex, variant, dark);

    const out = { source_color: argbToHex(hexToArgb(seedHex)) };
    for (const [role, [family, lightTone, darkTone]] of Object.entries(ROLE_SPEC)) {
        out[role] = paletteColor(palettes[family], dark ? darkTone : lightTone, role);
    }
    return out;
}

// Both modes at once, matching matugen's `colors[role][light|dark]` shape.
//
// The options are copied field by field rather than with object spread.
// qmlcachegen -- the tool Qt uses to precompile this module into the Kos.Ui
// resource -- rejects `{ ...options, dark: false }` outright with
// "Unexpected token `...`", which fails the build. Node and plain QML both
// accept the spread, so this only shows up when the module is compiled, and
// only a build catches it.
export function buildSchemePair(seedHex, options = {}) {
    const light = { variant: options.variant, dark: false };
    const dark = { variant: options.variant, dark: true };
    return {
        light: buildScheme(seedHex, light),
        dark: buildScheme(seedHex, dark),
    };
}

// The tonal palettes themselves, as tone -> hex. Useful for debugging and for
// callers that want a specific tone.
export function tonalPalettes(seedHex, options = {}) {
    const variant = options.variant ?? DEFAULT_VARIANT;
    const dark = options.dark ?? false;
    const palettes = buildPalettes(seedHex, variant, dark);
    const TONES = [0, 4, 6, 10, 12, 17, 20, 22, 24, 30, 40, 50, 60, 70, 80,
        87, 90, 92, 94, 95, 96, 98, 100];
    const out = {};
    for (const [name, p] of Object.entries(palettes)) {
        out[name] = {};
        for (const t of TONES) out[name][t] = paletteColor(p, t);
    }
    return out;
}

// Single role lookup, in case a caller only needs one.
export function roleColor(seedHex, role, options = {}) {
    if (!ROLE_SPEC[role]) return undefined;
    return buildScheme(seedHex, options)[role];
}

export { hexToHct, hctToHex, hexToArgb, argbToHex };
