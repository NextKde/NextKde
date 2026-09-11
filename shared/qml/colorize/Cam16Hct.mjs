// CAM16 colour appearance model + the HCT colour space, pure JavaScript.
//
// HCT is Material Color Utilities' colour space: hue and chroma come from
// CAM16, tone is CIE Lab L*. It exists because CAM16's hue is far more
// perceptually uniform than Lab's, which is what makes the Material 3 tonal
// palettes come out even.
//
// This is a faithful port of the reference implementation in
// material-color-utilities (Apache-2.0, Copyright 2021 Google LLC):
//   hct/cam16.ts, hct/viewing_conditions.ts, hct/hct.ts, utils/color_utils.ts
// The numeric constants are copied verbatim so results match to the last digit.
//
// ---------------------------------------------------------------------------
// Why the previous Lab-only implementation could not work
// ---------------------------------------------------------------------------
// The Lab port modelled each family as "one hue + one (tone -> chroma) table",
// calibrated against a single seed. Three things break that model:
//
//   1. Lab hue is not CAM16 hue. Within one family the Lab hue drifts 6-17
//      degrees from tone 40 to the tones near 5 and 95, because the two spaces
//      disagree about where the hue axis lies. A single-hue model cannot
//      represent that.
//   2. The chroma a family reaches is bounded by the sRGB gamut, and where that
//      boundary sits depends on the hue. Measured at tone 40 the primary family
//      ranges from ~26 (cyan) to ~123 (blue-violet) in Lab terms. A constant
//      table encodes whichever hue it was calibrated at.
//   3. Lab chroma and CAM16 chroma are different quantities. The same colour
//      reads roughly 1.6x higher in Lab, so Material's published constants
//      (primary chroma 200, secondary 16, tertiary 40, neutral 4) are not
//      comparable to Lab numbers at all.
//
// Working in HCT removes all three problems at once: the hue is stable within a
// family, the chroma is the quantity Material actually specifies, and gamut
// clipping becomes a well-defined search for the largest in-gamut chroma.
//
// Cost: one 3x3 matrix chain, a few transfer functions, and a bisection per
// out-of-gamut colour. Wallpaper-driven recolouring is a low-frequency event.

// ---------------------------------------------------------------------------
// Scalar helpers
// ---------------------------------------------------------------------------

const PI = Math.PI;

function signum(v) {
    return v < 0 ? -1 : v > 0 ? 1 : 0;
}

function lerp(start, stop, amount) {
    return start + (stop - start) * amount;
}

function sanitizeDegrees360(deg) {
    let d = deg % 360;
    if (d < 0) d += 360;
    return d;
}

// ---------------------------------------------------------------------------
// sRGB <-> linear <-> XYZ (D65)
// ---------------------------------------------------------------------------

function linearized(rgb8) {
    const normalized = rgb8 / 255.0;
    return normalized <= 0.040449936
        ? normalized / 12.92
        : Math.pow((normalized + 0.055) / 1.055, 2.4);
}

function delinearized(rgb) {
    const v = Math.max(0, Math.min(1, rgb));
    return v <= 0.0031308
        ? v * 12.92
        : 1.055 * Math.pow(v, 1.0 / 2.4) - 0.055;
}

function whitePointD65() {
    return [95.047, 100.0, 108.883];
}

// ---------------------------------------------------------------------------
// The scale convention, which is the one thing that has to be got exactly right
// ---------------------------------------------------------------------------
// MCU mixes two scales on purpose, and the mixing is load-bearing:
//
//   * A COLOUR's XYZ is 0-1. `Cam16.fromInt` builds it from `linearized(0..255)`
//     products with no scaling, and `argbFromXyz` feeds it straight back into
//     the sRGB matrix. Everything below follows that.
//   * The WHITE POINT is 0-100 (`[95.047, 100, 108.883]`). `ViewingConditions`
//     derives rW/gW/bW from it on that scale, and `rgbD = d*(100/rW) + 1 - d`
//     is only sensible because of it.
//   * `colorUtils.yFromLstar` also returns 0-100 (it is a luminance, not a
//     colour channel), so `lstarFromY` divides by 100 before the Lab transfer.
//
// The two scales meet in the `fl * |rD| / 100` term: for a 0-1 colour the
// cone response rD comes out around 0-1, so dividing by 100 would collapse it
// to noise -- except that rgbD carries the 100/rW factor and cancels it. Get
// this wrong by 100x and the hue survives (it is a ratio) while chroma and tone
// skew, which is exactly the failure the Lab port had. Do not "simplify" it.

// XYZ (0-1) -> sRGB triple (0-255). MCU's argbFromXyz.
function xyzToRgb255(x, y, z) {
    const rL = 3.2413774792388685 * x + -1.5376652402851851 * y + -0.49885366846268053 * z;
    const gL = -0.9691452513005321 * x + 1.8758853451067872 * y + 0.04156585616912061 * z;
    const bL = 0.05562093689691305 * x + -0.20395524564742123 * y + 1.0571799111220335 * z;
    return [
        Math.round(delinearized(rL) * 255),
        Math.round(delinearized(gL) * 255),
        Math.round(delinearized(bL) * 255),
    ];
}

// XYZ (0-1) -> linear sRGB (0-1).
function xyzToRgbLinear(x, y, z) {
    return [
        3.2413774792388685 * x + -1.5376652402851851 * y + -0.49885366846268053 * z,
        -0.9691452513005321 * x + 1.8758853451067872 * y + 0.04156585616912061 * z,
        0.05562093689691305 * x + -0.20395524564742123 * y + 1.0571799111220335 * z,
    ];
}

// Linear sRGB (0-1) -> XYZ (0-1). MCU's xyzFromArgb / the D65 sRGB matrix.
function rgbLinearToXyz(r, g, b) {
    return [
        0.41233895 * r + 0.35762064 * g + 0.18051042 * b,
        0.2126 * r + 0.7152 * g + 0.0722 * b,
        0.01932141 * r + 0.11916382 * g + 0.95034478 * b,
    ];
}

// ---------------------------------------------------------------------------
// L* <-> Y
// ---------------------------------------------------------------------------
// MCU's yFromLstar returns a 0-100 value (a luminance percentage, matching the
// 0-100 white point) and lstarFromY takes a 0-100 value. Both go through
// labF/labInvf with the CIE epsilon and kappa.

const LAB_E = 216 / 24389;
const LAB_K = 24389 / 27;

function labF(t) {
    return t > LAB_E ? Math.cbrt(t) : (LAB_K * t + 16) / 116;
}

function labInvf(ft) {
    const ft3 = ft * ft * ft;
    return ft3 > LAB_E ? ft3 : (116 * ft - 16) / LAB_K;
}

// 0-100 in, 0-100 out (MCU ColorUtils.yFromLstar).
function yFromLstar(lstar) {
    return 100.0 * labInvf((lstar + 16.0) / 116.0);
}

// 0-100 in, 0-100 out (MCU ColorUtils.lstarFromY).
function lstarFromY(y) {
    return labF(y / 100.0) * 116.0 - 16.0;
}

// ---------------------------------------------------------------------------
// Hex <-> ARGB int <-> RGB triples
// ---------------------------------------------------------------------------

export function hexToArgb(hex) {
    let h = String(hex).trim().replace(/^#/, "");
    if (h.length === 3) h = h.split("").map(c => c + c).join("");
    if (h.length === 6) h = "ff" + h;
    if (h.length !== 8) throw new Error("invalid hex colour: " + hex);
    return parseInt(h, 16) >>> 0;
}

export function argbToHex(argb) {
    const v = argb >>> 0;
    return "#" + [(v >>> 16) & 0xff, (v >>> 8) & 0xff, v & 0xff]
        .map(c => c.toString(16).padStart(2, "0")).join("");
}

function argbChannels(argb) {
    return [(argb >>> 16) & 0xff, (argb >>> 8) & 0xff, argb & 0xff];
}

function argbFromRgb(r, g, b) {
    return ((0xff << 24) | ((r & 0xff) << 16) | ((g & 0xff) << 8) | (b & 0xff)) >>> 0;
}

// ---------------------------------------------------------------------------
// CAM16 viewing conditions
// ---------------------------------------------------------------------------
// Verbatim from viewing_conditions.ts: ViewingConditions.make(), with MCU's
// defaults (D65 white, adapting luminance from L* 50, background L* 50,
// surround 2.0, illuminant not discounted).

function makeViewingConditions(
    whitePoint = whitePointD65(),
    adaptingLuminance = (200.0 / PI) * (yFromLstar(50.0) / 100.0),
    backgroundLstar = 50.0,
    surround = 2.0,
    discountingIlluminant = false,
) {
    const xyz = whitePoint;
    const rW = xyz[0] * 0.401288 + xyz[1] * 0.650173 + xyz[2] * -0.051461;
    const gW = xyz[0] * -0.250268 + xyz[1] * 1.204414 + xyz[2] * 0.045854;
    const bW = xyz[0] * -0.002079 + xyz[1] * 0.048952 + xyz[2] * 0.953127;

    const f = 0.8 + surround / 10.0;
    const c = f >= 0.9
        ? lerp(0.59, 0.69, (f - 0.9) * 10.0)
        : lerp(0.525, 0.59, (f - 0.8) * 10.0);

    let d;
    if (discountingIlluminant) {
        d = 1.0;
    } else {
        d = f * (1.0 - (1.0 / 3.6) * Math.exp((-adaptingLuminance - 42.0) / 92.0));
    }
    d = d > 1.0 ? 1.0 : d < 0.0 ? 0.0 : d;

    const nc = f;

    const rgbD = [
        d * (100.0 / rW) + 1.0 - d,
        d * (100.0 / gW) + 1.0 - d,
        d * (100.0 / bW) + 1.0 - d,
    ];

    const k = 1.0 / (5.0 * adaptingLuminance + 1.0);
    const k4 = k * k * k * k;
    const k4F = 1.0 - k4;
    const fl = k4 * adaptingLuminance
        + 0.1 * k4F * k4F * Math.cbrt(5.0 * adaptingLuminance);

    const n = yFromLstar(backgroundLstar) / whitePoint[1];
    const z = 1.48 + Math.sqrt(n);
    const nbb = 0.725 / Math.pow(n, 0.2);
    const ncb = nbb;

    const rgbAFactors = [
        Math.pow((fl * rgbD[0] * rW) / 100.0, 0.42),
        Math.pow((fl * rgbD[1] * gW) / 100.0, 0.42),
        Math.pow((fl * rgbD[2] * bW) / 100.0, 0.42),
    ];
    const rgbA = [
        (400.0 * rgbAFactors[0]) / (rgbAFactors[0] + 27.13),
        (400.0 * rgbAFactors[1]) / (rgbAFactors[1] + 27.13),
        (400.0 * rgbAFactors[2]) / (rgbAFactors[2] + 27.13),
    ];

    const aw = (2.0 * rgbA[0] + rgbA[1] + 0.05 * rgbA[2]) * nbb;

    return { n, aw, nbb, ncb, c, nc, rgbD, fl, fLRoot: Math.pow(fl, 0.25), z };
}

const DEFAULT_VIEWING = makeViewingConditions();

// ---------------------------------------------------------------------------
// CAM16
// ---------------------------------------------------------------------------

// XYZ (0-1) -> CAM16, in the given viewing conditions.
// MCU's Cam16.fromXyzInViewingConditions.
function cam16FromXyz(x, y, z, vc) {
    const rC = 0.401288 * x + 0.650173 * y - 0.051461 * z;
    const gC = -0.250268 * x + 1.204414 * y + 0.045854 * z;
    const bC = -0.002079 * x + 0.048952 * y + 0.953127 * z;

    const rD = vc.rgbD[0] * rC;
    const gD = vc.rgbD[1] * gC;
    const bD = vc.rgbD[2] * bC;

    const rAF = Math.pow((vc.fl * Math.abs(rD)) / 100.0, 0.42);
    const gAF = Math.pow((vc.fl * Math.abs(gD)) / 100.0, 0.42);
    const bAF = Math.pow((vc.fl * Math.abs(bD)) / 100.0, 0.42);

    const rA = (signum(rD) * 400.0 * rAF) / (rAF + 27.13);
    const gA = (signum(gD) * 400.0 * gAF) / (gAF + 27.13);
    const bA = (signum(bD) * 400.0 * bAF) / (bAF + 27.13);

    const a = (11.0 * rA + -12.0 * gA + bA) / 11.0;
    const b = (rA + gA - 2.0 * bA) / 9.0;
    const u = (20.0 * rA + 20.0 * gA + 21.0 * bA) / 20.0;
    const p2 = (40.0 * rA + 20.0 * gA + bA) / 20.0;

    const atan2 = Math.atan2(b, a);
    const atanDegrees = (atan2 * 180.0) / PI;
    const hue = sanitizeDegrees360(atanDegrees);

    const ac = p2 * vc.nbb;
    const j = 100.0 * Math.pow(ac / vc.aw, vc.c * vc.z);

    const huePrime = hue < 20.14 ? hue + 360 : hue;
    const eHue = 0.25 * (Math.cos((huePrime * PI) / 180.0 + 2.0) + 3.8);
    const p1 = (50000.0 / 13.0) * eHue * vc.nc * vc.ncb;
    const t = (p1 * Math.sqrt(a * a + b * b)) / (u + 0.305);
    const alpha = Math.pow(t, 0.9)
        * Math.pow(1.64 - Math.pow(0.29, vc.n), 0.73);
    const chroma = alpha * Math.sqrt(j / 100.0);
    const m = chroma * vc.fLRoot;

    return { hue, chroma, j, m };
}

// CAM16 (J, C, h) -> XYZ (0-1), in the given viewing conditions.
// MCU's Cam16.xyzInViewingConditions.
function xyzFromCam16Jch(j, chroma, hue, vc) {
    const alpha = (chroma === 0.0 || j === 0.0)
        ? 0.0
        : chroma / Math.sqrt(j / 100.0);

    const t = Math.pow(
        alpha / Math.pow(1.64 - Math.pow(0.29, vc.n), 0.73),
        1.0 / 0.9);
    const hRad = (hue * PI) / 180.0;

    const eHue = 0.25 * (Math.cos(hRad + 2.0) + 3.8);
    const ac = vc.aw * Math.pow(j / 100.0, 1.0 / vc.c / vc.z);
    const p1 = eHue * (50000.0 / 13.0) * vc.nc * vc.ncb;
    const p2 = ac / vc.nbb;

    const hSin = Math.sin(hRad);
    const hCos = Math.cos(hRad);

    const gamma = (23.0 * (p2 + 0.305) * t)
        / (23.0 * p1 + 11.0 * t * hCos + 108.0 * t * hSin);
    const a = gamma * hCos;
    const b = gamma * hSin;

    const rA = (460.0 * p2 + 451.0 * a + 288.0 * b) / 1403.0;
    const gA = (460.0 * p2 - 891.0 * a - 261.0 * b) / 1403.0;
    const bA = (460.0 * p2 - 220.0 * a - 6300.0 * b) / 1403.0;

    const rCBase = Math.max(0, (27.13 * Math.abs(rA)) / (400.0 - Math.abs(rA)));
    const rC = signum(rA) * (100.0 / vc.fl) * Math.pow(rCBase, 1.0 / 0.42);
    const gCBase = Math.max(0, (27.13 * Math.abs(gA)) / (400.0 - Math.abs(gA)));
    const gC = signum(gA) * (100.0 / vc.fl) * Math.pow(gCBase, 1.0 / 0.42);
    const bCBase = Math.max(0, (27.13 * Math.abs(bA)) / (400.0 - Math.abs(bA)));
    const bC = signum(bA) * (100.0 / vc.fl) * Math.pow(bCBase, 1.0 / 0.42);

    const rF = rC / vc.rgbD[0];
    const gF = gC / vc.rgbD[1];
    const bF = bC / vc.rgbD[2];

    const x = 1.86206786 * rF - 1.01125463 * gF + 0.14918677 * bF;
    const y = 0.38752654 * rF + 0.62144744 * gF - 0.00897398 * bF;
    const z = -0.01584150 * rF - 0.03412294 * gF + 1.04996444 * bF;

    // The (100 / fl) factor in the cone-response step is what brings this back
    // onto the 0-1 colour scale that cam16FromXyz consumes. No further scaling.
    return [x, y, z];
}

// ---------------------------------------------------------------------------
// HCT — hue and chroma from CAM16, tone from Lab L*
// ---------------------------------------------------------------------------

// ARGB -> [hue, chroma, tone]. MCU's Hct.fromInt.
export function argbToHct(argb) {
    const [r, g, b] = argbChannels(argb);
    const [x, y, z] = rgbLinearToXyz(linearized(r), linearized(g), linearized(b));
    const cam = cam16FromXyz(x, y, z, DEFAULT_VIEWING);
    // CAM16's J is not L*; HCT takes tone straight from Lab's L*. y is a 0-1
    // colour channel here, while lstarFromY works on the 0-100 luminance scale.
    const tone = lstarFromY(y * 100.0);
    return [cam.hue, cam.chroma, tone];
}

export function hexToHct(hex) {
    return argbToHct(hexToArgb(hex));
}

// HCT pins the *tone* (a Lab L*) while CAM16's lightness coordinate is J. A
// tone therefore fixes Y = yFromLstar(tone), but the J that goes with a given
// (hue, chroma) still has to be found.
//
// MCU does this with Newton iteration in findResultByJ, seeded by
// `j = 11 * sqrt(y)`. That seed only works because MCU's J is on the 0-100
// scale it inlines; with the viewing conditions we get from
// ViewingConditions.make a mid-tone colour lands at J around 5, so the MCU seed
// overshoots several-fold and Newton oscillates instead of converging.
//
// J -> Y is monotonically increasing in J, so bisect instead: slower per step
// but unconditionally stable, and still only a few dozen scalar operations.
// `y` is a 0-1 colour channel.
function solveJForY(hue, chroma, y) {
    let lo = 0.0;
    let hi = 100.0;
    for (let i = 0; i < 60; ++i) {
        const mid = (lo + hi) / 2.0;
        const yNow = xyzFromCam16Jch(mid, chroma, hue, DEFAULT_VIEWING)[1];
        if (yNow < y) lo = mid; else hi = mid;
    }
    return (lo + hi) / 2.0;
}

function inGamutXyz(x, y, z) {
    // XYZ here is 0-1, so linear sRGB must land inside 0-1 too.
    const lin = xyzToRgbLinear(x, y, z);
    return lin.every(v => v >= -1e-6 && v <= 1 + 1e-6);
}

// HCT -> ARGB. MCU's HctSolver.solveToInt.
export function hctToArgb(hue, chroma, tone) {
    if (tone <= 0.0) return argbFromRgb(0, 0, 0);
    if (tone >= 100.0) return argbFromRgb(255, 255, 255);
    if (chroma < 0.0001) {
        // MCU: argbFromLstar(tone) — a neutral grey at exactly this L*.
        const grey = lstarToSrgb8(tone);
        return argbFromRgb(grey, grey, grey);
    }

    // yFromLstar is 0-100; the CAM16 helpers work on the 0-1 colour scale.
    const yTarget = yFromLstar(tone) / 100.0;

    // J and the in-gamut chroma depend on each other: J is defined at the
    // chroma we end up using, and which chroma fits depends on where J puts the
    // colour. Resolve both by bisecting on chroma, with J re-solved at each
    // probe so the tone stays pinned to `yTarget` throughout.
    let lo = 0.0;
    let hi = chroma;
    for (let i = 0; i < 40; ++i) {
        const mid = (lo + hi) / 2.0;
        const j = solveJForY(hue, mid, yTarget);
        const xyz = xyzFromCam16Jch(j, mid, hue, DEFAULT_VIEWING);
        if (inGamutXyz(xyz[0], xyz[1], xyz[2])) lo = mid; else hi = mid;
    }

    const safeChroma = lo;
    const j = solveJForY(hue, safeChroma, yTarget);
    const xyz = xyzFromCam16Jch(j, safeChroma, hue, DEFAULT_VIEWING);
    const [r, g, b] = xyzToRgb255(xyz[0], xyz[1], xyz[2]);
    return argbFromRgb(r, g, b);
}

// MCU's argbFromLstar: the sRGB grey whose Lab L* equals `lstar`.
function lstarToSrgb8(lstar) {
    // yFromLstar is 0-100; delinearized wants 0-1.
    const y = yFromLstar(lstar) / 100.0;
    return Math.round(delinearized(y) * 255);
}

export function hctToHex(hue, chroma, tone) {
    return argbToHex(hctToArgb(hue, chroma, tone));
}

// ---------------------------------------------------------------------------
// Convenience exports used by the scheme builder and the tests
// ---------------------------------------------------------------------------

export { yFromLstar, lstarFromY };

export function hexToLab(hex) {
    const argb = hexToArgb(hex);
    const [r, g, b] = argbChannels(argb);
    const [x, y, z] = rgbLinearToXyz(linearized(r), linearized(g), linearized(b));
    // The Lab white point is the normalized 0-1 one, matching the 0-1 XYZ that
    // rgbLinearToXyz returns. (Y is the ratio to Yn = 1, which is exactly the
    // Lab definition, so no 0-100 rescale belongs here.)
    const xn = x / 0.95047, yn = y / 1.0, zn = z / 1.08883;
    const fx = labF(xn), fy = labF(yn), fz = labF(zn);
    return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
}

export function hexToLch(hex) {
    const [L, a, b] = hexToLab(hex);
    return [L, Math.hypot(a, b), sanitizeDegrees360((Math.atan2(b, a) * 180) / PI)];
}

export function deltaE(left, right) {
    const a = hexToLab(left), b = hexToLab(right);
    return Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
}

export { sanitizeDegrees360, signum };
export const _internals = { makeViewingConditions, cam16FromXyz, xyzFromCam16Jch };
