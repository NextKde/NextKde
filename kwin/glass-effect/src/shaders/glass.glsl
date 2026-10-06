uniform float edgeSizePixels;
uniform float refractionStrength;
uniform float refractionNormalPow;
uniform float refractionRGBFringing;
uniform float refractionOffsetStrength;
uniform float materialSoftness;
uniform float materialReflectionStrength;
uniform float cornerExponent;

float squircleNorm(vec2 q)
{
    float exponent = clamp(cornerExponent, 2.0, 8.0);
    if (exponent <= 2.0001)
        return length(q);
    if (q.x <= 0.0)
        return q.y;
    if (q.y <= 0.0)
        return q.x;
    return pow(pow(q.x, exponent) + pow(q.y, exponent), 1.0 / exponent);
}

float roundedRectangleDist(vec2 p, vec2 b, vec4 cornerRadius)
{
    float r = p.x > 0.0
        ? (p.y > 0.0 ? cornerRadius.y : cornerRadius.w)
        : (p.y > 0.0 ? cornerRadius.x : cornerRadius.z);
    vec2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + squircleNorm(max(q, 0.0)) - r;
}

// Only the sampled colour leaves this stage. The distance, edge and normal
// fields it used to carry had no reader left once the outline paths were
// removed, and passing them around made them look like live outputs.
struct GlassFragment {
    vec4 color;
};

#include "snells-glass.glsl"

// Analytic gradient of the rounded-box SDF (Kyant0 gradSdRoundedRect). One
// exact normal sample replaces the finite-difference pair, and the gradient
// radius is widened so the normal field stays continuous across the corner
// transition instead of picking up the per-corner radius discontinuity.
vec2 gradSdRoundedBox(vec2 p, vec2 b, float r)
{
    vec2 q = abs(p) - b + r;
    vec2 sgn = sign(p);
    float exponent = clamp(cornerExponent, 2.0, 8.0);
    if (q.x > 0.0 && q.y > 0.0) {
        float norm = squircleNorm(q);
        if (norm > 1e-5) {
            return sgn * vec2(pow(q.x, exponent - 1.0),
                pow(q.y, exponent - 1.0))
                * pow(norm, 1.0 - exponent);
        }
    }
    if (q.x > 0.0)
        return vec2(sgn.x, 0.0);
    if (q.y > 0.0)
        return vec2(0.0, sgn.y);
    return (q.x > q.y) ? vec2(sgn.x, 0.0) : vec2(0.0, sgn.y);
}

// Rim highlight colour from the iOS render shader: on a dark backdrop the
// rim is white for contrast; on a bright or colourful backdrop it keeps the
// backdrop's own hue, brightened — the "vibrancy at the edge" that makes the
// rim read as glass catching light instead of a painted white stripe.
vec3 getHighlightColor(vec3 backgroundColor, float targetBrightness)
{
    const vec3 grayscaleWeights = vec3(0.299, 0.587, 0.114);
    float luminance = dot(backgroundColor, grayscaleWeights);
    float maxComponent = max(max(backgroundColor.r, backgroundColor.g), backgroundColor.b);
    float lumFactor = (luminance * 2.5) / (1.0 + luminance * 2.5);
    float satFactor = (maxComponent * 2.5) / (1.0 + maxComponent * 2.5);
    float colorInfluence = lumFactor * satFactor;
    vec3 hueLifted = (backgroundColor / max(luminance, 0.001)) * targetBrightness;
    return mix(vec3(targetBrightness), hueLifted, colorInfluence);
}

// The liquid rim's light colour. Over a dark backdrop the edge normally reads
// as white light; over a bright one white light would vanish into the backdrop,
// so it warms toward a dark gold -- "black gold", the tinted colour of light --
// keeping the edge visible in both cases from the glass itself, without a
// separate QString outline drawn by the client.
vec3 rimLight(vec3 backdrop)
{
    const vec3 luma = vec3(0.299, 0.587, 0.114);
    // Nearly black with only a restrained warm-gold bias. This is the dark
    // reflected edge of liquid glass, not a bright metallic gold stroke.
    const vec3 darkGold = vec3(0.14, 0.11, 0.055);
    float lum = dot(backdrop, luma);
    float brightT = smoothstep(0.45, 0.80, lum);
    return mix(vec3(1.0), darkGold, brightT);
}

// ── Edge-confined liquid reflection ───────────────────────────────────
// Keep the material body untouched. This retains main's narrow Gaussian edge
// streaks and changes only which pair of edges receives the primary light.
// There is deliberately no full dark contour or broad halo here.
vec3 applyLiquidGlints(vec3 rgb, vec2 position, vec2 halfBlurSize,
    vec4 cornerRadius, float dist, float edgeAntialiasWidth)
{
    // Main's narrow Gaussian cross-section, now evaluated against the one SDF
    // contour shared by straight edges and rounded corners. Four independent
    // x/y lines leave the real contour at a corner and caused the visible gap.
    float minRadius = min(min(cornerRadius.x, cornerRadius.y),
        min(cornerRadius.z, cornerRadius.w));
    vec2 gradient = gradSdRoundedBox(position, halfBlurSize,
        max(minRadius, 1.0));
    vec2 outward = length(gradient) > 1e-5 ? normalize(gradient)
        : vec2(0.0, 1.0);

    // Liquid keeps its tight rim. Soft glass uses the same rim, but lets its
    // high light diffuse *inward* over the authored highlight width instead
    // of adding a separate directional reflection layer.
    float softness = clamp(materialSoftness, 0.0, 1.0);
    float softSpread = smoothstep(0.05, 0.65, softness);
    const float liquidHighlightWidthPx = 3.0;
    float widthScale = clamp(liquidHighlightWidthPx / 3.0, 0.80, 1.20);
    float straightSigma = max(edgeAntialiasWidth * 0.52,
        0.62 * widthScale);
    // A sub-pixel Gaussian is stable on an axis-aligned edge but aliases when
    // a curved contour crosses the pixel grid diagonally. Widen only those
    // diagonal arc samples to main's 0.72 px end-cap coverage; straight runs
    // retain the original hairline. The normal makes this transition
    // continuous through both tangents instead of introducing another join.
    float arcDiagonal = clamp(2.0 * abs(outward.x * outward.y), 0.0, 1.0);
    float arcCoverage = smoothstep(0.08, 0.72, arcDiagonal);
    float arcSigma = max(0.72, edgeAntialiasWidth * 0.72);
    float sigma = mix(straightSigma, max(straightSigma, arcSigma),
        arcCoverage);
    float edgeDistance = max(-dist, 0.0);
    float contourLine = exp(-0.5 * pow((edgeDistance - 1.0) / sigma, 2.0));
    // Soft glass is a longer inward scatter, not a wider solid stroke. An
    // exponential falloff loses energy continuously as it travels inward;
    // the smooth tail reaches zero at 26 px without leaving a hard inner ring.
    // The longer decay keeps the scatter visible over near-black backdrops.
    const float softGlowReachPx = 26.0;
    const float softGlowDecayPx = 9.5;
    // Start at zero on the contour so soft glass has no extra hard highlight;
    // energy blooms just inside the edge, then scatters and fades inward.
    float softGlow = (1.0 - exp(-edgeDistance / 1.8))
        * exp(-edgeDistance / softGlowDecayPx)
        * (1.0 - smoothstep(softGlowReachPx * 0.68,
            softGlowReachPx, edgeDistance));

    // Keep the selected diagonal from the previous design. At 45 degrees the
    // primary corner is top-left and the secondary corner is bottom-right.
    // Each envelope is blended by the continuous SDF normal through the corner
    // and decays over the full side length, so there is no tangent discontinuity.
    // The authored light direction is fixed at 45 degrees (top-left).
    // The material light is authored at 45 degrees (top-left). It is not a
    // user preference, so keep it as part of the shader design.
    const vec2 primarySign = vec2(-1.0, 1.0);

    float xProgress = clamp((position.x + halfBlurSize.x)
        / max(halfBlurSize.x * 2.0, 1.0), 0.0, 1.0);
    float yProgress = clamp((halfBlurSize.y - position.y)
        / max(halfBlurSize.y * 2.0, 1.0), 0.0, 1.0);
    float fromLeft = 1.0 - smoothstep(0.0, 1.0, xProgress);
    float fromRight = 1.0 - smoothstep(0.0, 1.0, 1.0 - xProgress);
    float fromTop = 1.0 - smoothstep(0.0, 1.0, yProgress);
    float fromBottom = 1.0 - smoothstep(0.0, 1.0, 1.0 - yProgress);

    float primaryHorizontalFade = primarySign.x < 0.0 ? fromLeft : fromRight;
    float primaryVerticalFade = primarySign.y > 0.0 ? fromTop : fromBottom;
    float secondaryHorizontalFade = primarySign.x < 0.0 ? fromRight : fromLeft;
    float secondaryVerticalFade = primarySign.y > 0.0 ? fromBottom : fromTop;

    float primaryHorizontalFacing = pow(max(outward.y * primarySign.y, 0.0), 0.78);
    float primaryVerticalFacing = pow(max(outward.x * primarySign.x, 0.0), 0.78);
    float secondaryHorizontalFacing = pow(max(-outward.y * primarySign.y, 0.0), 0.78);
    float secondaryVerticalFacing = pow(max(-outward.x * primarySign.x, 0.0), 0.78);

    float primaryEnvelope = min(1.0,
        primaryHorizontalFacing * primaryHorizontalFade
        + primaryVerticalFacing * primaryVerticalFade);
    float secondaryEnvelope = min(1.0,
        secondaryHorizontalFacing * secondaryHorizontalFade
        + secondaryVerticalFacing * secondaryVerticalFade);
    // Liquid's narrow glints fade out as the soft material takes over. The
    // soft scatter is applied independently below; it must not inherit the
    // liquid highlight's refraction response.
    float primaryGlint = contourLine * primaryEnvelope
        * (1.0 - softSpread);
    float secondaryGlint = contourLine * secondaryEnvelope
        * (1.0 - softSpread);

    float refractionResponse = smoothstep(0.05, 0.75,
        clamp(refractionStrength, 0.0, 1.0));
    float liquidResponse = refractionResponse;
    // Liquid uses the authored white/black-gold rim. Soft glass uses only a
    // neutral lift of the backdrop itself, so its scatter cannot turn gold.
    vec3 rim = rimLight(rgb);
    rgb = mix(rgb, rim,
        clamp(primaryGlint * 0.60 * liquidResponse, 0.0, 0.60));
    rgb = mix(rgb, rim,
        clamp(secondaryGlint * 0.50 * liquidResponse, 0.0, 0.50));

    // Soft scatter is a separate material contribution: no hard contour and
    // no dependency on refraction. It begins at zero on the edge, blooms just
    // inside it, then loses brightness continuously over the 26 px reach.
    // A stronger neutral lift is intentional here: unlike the liquid rim it
    // must remain readable when both the glass and the backdrop are dark.
    vec3 softLight = mix(rgb, vec3(1.0), 0.52);
    const float softScatterStrength = 0.48;
    rgb = mix(rgb, softLight,
        clamp(softGlow * softSpread * softScatterStrength, 0.0, 0.48));
    return rgb;
}

// One shared material stage for both presets. Soft glass does not select a
// second shader: it increases low-frequency diffusion and a broad directional
// reflection on top of the same edge-lens refraction used by liquid glass.
vec3 applySoftMaterial(vec3 rgb, vec2 position, vec2 halfBlurSize,
    vec4 cornerRadius, float dist, float edgeFactor)
{
    float softness = clamp(materialSoftness, 0.0, 1.0);
    float reflection = clamp(materialReflectionStrength, 0.0, 1.0);
    // Liquid glass ships with both at zero, so every term below would be
    // computed and then mixed away at weight zero. Skip the whole stage.
    if (softness <= 0.0 && reflection <= 0.0)
        return rgb;

    const vec3 lumaWeights = vec3(0.299, 0.587, 0.114);
    float luma = dot(rgb, lumaWeights);
    vec3 diffused = mix(rgb, vec3(luma), 0.22);
    diffused = mix(diffused, smoothstep(vec3(0.0), vec3(1.0), diffused), 0.18);
    rgb = mix(rgb, diffused, softness);

    float minRadius = min(min(cornerRadius.x, cornerRadius.y),
        min(cornerRadius.z, cornerRadius.w));
    vec2 gradient = gradSdRoundedBox(position, halfBlurSize,
        max(minRadius, 1.0));
    vec2 outward = length(gradient) > 1e-5 ? normalize(gradient)
        : vec2(0.0, 1.0);
    // One key lobe alone made the broad reflection a top-only highlight: its
    // weight is smoothstep(-0.15, 0.85, dot(outward, lightDirection)), which
    // bottoms out at zero for every normal facing away from a light coming from
    // the upper left. The bottom edge sits exactly at zero and the right edge
    // under a third, so the rim below never lit. A soft material catches a
    // grazing sheen on every side it is seen from, so a counter lobe from the
    // opposite side keeps the far rim at `counterShare` of the key's peak --
    // all four edges stay lit while the upper left still leads.
    vec2 lightDirection = normalize(vec2(-0.55, 0.84));
    float keyLobe = smoothstep(-0.15, 0.85, dot(outward, lightDirection));
    float counterLobe = smoothstep(-0.15, 0.85, -dot(outward, lightDirection));
    const float counterShare = 0.45;
    float directional = max(keyLobe, counterLobe * counterShare);
    float broadBand = pow(clamp(edgeFactor, 0.0, 1.0), 1.6);
    float reflected = broadBand * directional * reflection;
    vec3 reflectionColor = getHighlightColor(rgb, mix(0.82, 1.0, directional));
    return mix(rgb, reflectionColor, clamp(reflected * 0.34, 0.0, 0.32));
}

vec4 glass(vec4 sum, vec4 cornerRadius, vec2 position, vec2 halfBlurSize)
{
    float minHalfSize = min(halfBlurSize.x, halfBlurSize.y);
    float dist = roundedRectangleDist(position, halfBlurSize, cornerRadius);
    // Evaluate derivatives before the early return: doing so only in the
    // inside branch is undefined along the exact contour on some GPUs.
    float edgeAntialiasWidth = max(fwidth(dist), 0.75);

    if (dist >= 0.0) {
        return sum;
    }

    float minEsp = clamp(edgeSizePixels, 0.1, minHalfSize * 0.9);
    float edgeFactor = 1.0 - clamp(abs(dist) / minEsp, 0.0, 1.0);
    float concaveFactor = 1.0 - sqrt(1.0 - pow(smoothstep(0.0, 1.0, edgeFactor), refractionNormalPow));

    GlassFragment s;
    if (refractionStrength > 0.0) {
        vec4 r = clamp(cornerRadius * 2.0, min(64.0, minHalfSize), min(128.0, minHalfSize));
        s = snellsRefraction(position, halfBlurSize, r, minHalfSize, dist,
            concaveFactor);
    } else {
        s = GlassFragment(sum);
    }

    vec3 rgb = s.color.rgb;
    rgb = applySoftMaterial(rgb, position, halfBlurSize, cornerRadius, dist,
        edgeFactor);
    rgb = applyLiquidGlints(rgb, position, halfBlurSize, cornerRadius, dist,
        edgeAntialiasWidth);

    // Opaque material only. The silhouette is cut once, by the caller, from the
    // same box/radius/exponent -- so a stage that has its own box (one protocol
    // shape among several) gets its own edge instead of this one's. Applying a
    // second mask here is what the removed roundedRectangle() did, and it
    // assumed a single window-wide box.
    return vec4(rgb, 1.0);
}
