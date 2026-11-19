// Per-shape composite of the blurred backdrop.
//
// Vertex positions and `box` are capture-local device pixels; the capture
// texture is logical resolution, so `uv` is normalised capture coordinates.
// The material field (SDF, normals, glints) lives in the same flipped-Y space
// as the old compositor material: +y is the visual top, which is what makes
// the stronger top glint appear on top.
uniform sampler2D texUnit;
uniform vec4 box;          // centre.xy, half size.zw (device px)
uniform vec4 cornerRadius; // per-corner radii (device px)
uniform float cornerExponent;
uniform vec4 tint;         // non-premultiplied rgb, opacity
uniform float opacity;

// Adaptive scrim. mode 0 off, 1 darkens bright backdrops, 2 lightens dark
// ones. cap/decay are the theme's readable/balanced/transparent presets.
uniform int scrimMode;
uniform float scrimCap;
uniform float scrimDecay;
// 1 when the sampled texture is the unblurred capture (the shape asked for no
// blur): the scrim strength then has to read a broad neighbourhood, otherwise
// wallpaper detail would show through as mottling.
uniform int scrimLumaSmooth;

// Liquid optics. All radii/box values are device pixels; the refraction shift
// is expressed in texels of the half-resolution capture, so one unit is
// `2 * viewportScale` device pixels.
uniform float viewportScale;
uniform int liquidEnabled;
uniform float edgeSizePixels;
uniform float refractionStrength;   // 0..1, already scaled by the material
uniform float refractionNormalPow;
uniform float refractionRGBFringing;
uniform float refractionOffsetStrength;
uniform float materialSoftness;
uniform float materialReflectionStrength;

// Pointer light. pointerLocal is the cursor in the same flipped-Y,
// capture-local device pixel space as `position`. hoverAmount is the settled
// 0..1 fade; parallaxStrength biases the lens toward the pointer. hoverRadius
// is the light's reach in device pixels; zero keeps the adaptive default.
uniform vec2 pointerLocal;
uniform float hoverAmount;
uniform float hoverStrength;
uniform float hoverRadius;
uniform float parallaxStrength;

// Click ripple. clickLocal is the press position, clickRadius the current
// expanding ring radius and clickAmount its 0..1 envelope, all in the same
// device pixel space as `position`.
uniform vec2 clickLocal;
uniform float clickRadius;
uniform float clickAmount;

in vec2 uv;
in vec2 vertex;

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

// Analytic gradient of the rounded-box SDF. One exact normal replaces a pair of
// finite differences; the radius is widened so the normal field stays
// continuous across a corner join instead of stepping at the radius edge.
vec2 roundedBoxGradient(vec2 p, vec2 b, float r)
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

// Rim colour: white on a dark backdrop for contrast; on a bright or saturated
// backdrop it keeps the backdrop's own hue, lifted, so the rim reads as glass
// catching light rather than a painted white stripe.
vec3 highlightColor(vec3 backdrop, float targetBrightness)
{
    const vec3 lumaWeights = vec3(0.299, 0.587, 0.114);
    float luminance = dot(backdrop, lumaWeights);
    float maxComponent = max(max(backdrop.r, backdrop.g), backdrop.b);
    float luminanceWeight = (luminance * 2.5) / (1.0 + luminance * 2.5);
    float saturationWeight = (maxComponent * 2.5) / (1.0 + maxComponent * 2.5);
    float colorInfluence = luminanceWeight * saturationWeight;
    vec3 hueLifted = (backdrop / max(luminance, 0.001)) * targetBrightness;
    return mix(vec3(targetBrightness), hueLifted, colorInfluence);
}

// White glint over a dark backdrop, warm deep gold over a bright one.
vec3 rimLight(vec3 backdrop)
{
    const vec3 lumaWeights = vec3(0.299, 0.587, 0.114);
    float luminance = dot(backdrop, lumaWeights);
    float bright = smoothstep(0.45, 0.80, luminance);
    vec3 whiteRim = mix(vec3(1.0),
                        clamp(highlightColor(backdrop, 1.0), 0.0, 1.0), 0.06);
    const vec3 deepGold = vec3(0.46, 0.32, 0.12);
    vec3 darkRim = mix(deepGold, deepGold * clamp(backdrop, 0.0, 1.0), 0.08);
    return mix(whiteRim, darkRim, bright);
}

// Edge-confined liquid reflection. The body keeps the blurred backdrop; only a
// narrow Gaussian band on the contour is replaced by the rim colour, strongest
// on a light pair of edges that fades continuously through the corners.
// Soft glass replaces the narrow band by a broad inward scatter.
vec3 applyEdgeLight(vec3 rgb, vec2 position, vec2 halfSize, vec4 radii,
                    float dist, float antialiasWidth)
{
    float minRadius = min(min(radii.x, radii.y), min(radii.z, radii.w));
    vec2 gradient = roundedBoxGradient(position, halfSize, max(minRadius, 1.0));
    vec2 outward = length(gradient) > 1e-5 ? normalize(gradient)
                                           : vec2(0.0, 1.0);

    float softness = clamp(materialSoftness, 0.0, 1.0);
    float softSpread = smoothstep(0.05, 0.65, softness);
    float edgeBand = clamp(edgeSizePixels, 0.1,
                           min(halfSize.x, halfSize.y) * 0.9);
    float widthScale = clamp(edgeBand / 50.0, 0.90, 1.12);
    float straightSigma = max(antialiasWidth * 0.52, 0.62 * widthScale);
    // A sub-pixel line is stable on an axis-aligned edge but aliases where the
    // contour crosses the pixel grid diagonally; widen only those arc samples.
    float arcDiagonal = clamp(2.0 * abs(outward.x * outward.y), 0.0, 1.0);
    float arcCoverage = smoothstep(0.08, 0.72, arcDiagonal);
    float arcSigma = max(0.72, antialiasWidth * 0.72);
    float sigma = mix(straightSigma, max(straightSigma, arcSigma), arcCoverage);
    // Dark reflections make sub-pixel steps far more visible: spread their
    // coverage and lower the peak, keeping the line's energy.
    float darkRimWeight = smoothstep(0.45, 0.80,
        dot(rgb, vec3(0.299, 0.587, 0.114)));
    float filteredSigma = mix(sigma,
        sqrt(sigma * sigma + antialiasWidth * antialiasWidth / 12.0),
        darkRimWeight);
    float edgeDistance = max(-dist, 0.0);
    float contourLine = (sigma / filteredSigma)
        * exp(-0.5 * pow((edgeDistance - 1.0) / filteredSigma, 2.0));

    // Soft glass is a long inward scatter, not a wider solid stroke; an
    // exponential tail loses energy continuously and reaches zero without a
    // hard inner ring.
    const float softGlowReachPx = 26.0;
    const float softGlowDecayPx = 9.5;
    float softGlow = (1.0 - exp(-edgeDistance / 1.8))
        * exp(-edgeDistance / softGlowDecayPx)
        * (1.0 - smoothstep(softGlowReachPx * 0.68, softGlowReachPx,
                            edgeDistance));

    // Primary light pair: top-left / bottom-right, with the envelope shifted
    // slightly so the two lights meet continuously at the corners.
    const vec2 primarySign = vec2(-1.0, 1.0);

    float xProgress = clamp((position.x + halfSize.x)
                            / max(halfSize.x * 2.0, 1.0), 0.0, 1.0) + 0.04;
    xProgress = clamp(xProgress, 0.0, 1.0);
    float yProgress = clamp((halfSize.y - position.y)
                            / max(halfSize.y * 2.0, 1.0), 0.0, 1.0);
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
    float primaryGlint = contourLine * primaryEnvelope * (1.0 - softSpread);
    float secondaryGlint = contourLine * secondaryEnvelope * (1.0 - softSpread);

    float liquidResponse = smoothstep(0.05, 0.75,
                                      clamp(refractionStrength, 0.0, 1.0));
    vec3 rim = rimLight(rgb);
    rgb = mix(rgb, rim,
              clamp(primaryGlint * 0.60 * liquidResponse, 0.0, 0.60));
    rgb = mix(rgb, rim,
              clamp(secondaryGlint * 0.50 * liquidResponse, 0.0, 0.50));

    // The soft scatter is independent of refraction and must stay readable
    // over a dark backdrop as well as over a dark glass body.
    vec3 softLight = mix(rgb, vec3(1.0), 0.52);
    const float softScatterStrength = 0.48;
    rgb = mix(rgb, softLight,
              clamp(softGlow * softSpread * softScatterStrength, 0.0, 0.48));
    return rgb;
}

// Soft glass: low-frequency diffusion plus a broad directional sheen. Liquid
// ships with both at zero, in which case the whole stage is skipped.
vec3 applySoftMaterial(vec3 rgb, vec2 position, vec2 halfSize, vec4 radii,
                       float edgeFactor)
{
    float softness = clamp(materialSoftness, 0.0, 1.0);
    float reflection = clamp(materialReflectionStrength, 0.0, 1.0);
    if (softness <= 0.0 && reflection <= 0.0)
        return rgb;

    float luma = dot(rgb, vec3(0.299, 0.587, 0.114));
    vec3 diffused = mix(rgb, vec3(luma), 0.22);
    diffused = mix(diffused, smoothstep(vec3(0.0), vec3(1.0), diffused), 0.18);
    rgb = mix(rgb, diffused, softness);

    if (reflection <= 0.0)
        return rgb;

    float minRadius = min(min(radii.x, radii.y), min(radii.z, radii.w));
    vec2 gradient = roundedBoxGradient(position, halfSize, max(minRadius, 1.0));
    vec2 outward = length(gradient) > 1e-5 ? normalize(gradient)
                                           : vec2(0.0, 1.0);
    // One key lobe would leave the far rim unlit; a weaker counter lobe keeps
    // every edge catching light while the upper left still leads.
    vec2 lightDirection = normalize(vec2(-0.55, 0.84));
    float keyLobe = smoothstep(-0.15, 0.85, dot(outward, lightDirection));
    float counterLobe = smoothstep(-0.15, 0.85, -dot(outward, lightDirection));
    const float counterShare = 0.45;
    float directional = max(keyLobe, counterLobe * counterShare);
    float broadBand = pow(clamp(edgeFactor, 0.0, 1.0), 1.6);
    float reflected = broadBand * directional * reflection;
    vec3 reflectionColor = highlightColor(rgb, mix(0.82, 1.0, directional));
    return mix(rgb, reflectionColor, clamp(reflected * 0.34, 0.0, 0.32));
}

// Pointer specular lobe plus the edge transmission that travels with it. The
// body lobe sits where the pointer is; the rim lobe is the same light reaching
// the contour, so only the part inside the edge band lights up.
vec3 applyHoverLight(vec3 rgb, vec2 position, vec2 halfSize, float edgeFactor)
{
    float amount = clamp(hoverAmount * hoverStrength, 0.0, 1.0);
    if (amount <= 0.0)
        return rgb;
    // Configured radius wins; zero keeps the adaptive body/rim default.
    float radius = hoverRadius > 0.0
        ? hoverRadius
        : max(48.0, min(halfSize.x, halfSize.y) * 0.75);
    vec2 delta = position - pointerLocal;
    float d2 = dot(delta, delta);
    float bodyLobe = exp(-0.5 * d2 / (radius * radius));
    float rimLobe = exp(-0.5 * d2 / (radius * radius * 0.45)) * edgeFactor;
    rgb = mix(rgb, vec3(1.0), clamp(bodyLobe * amount * 0.30, 0.0, 0.30));
    rgb = mix(rgb, vec3(1.0), clamp(rimLobe * amount * 0.38, 0.0, 0.38));
    return rgb;
}

// One click pulse: an expanding rim with a soft interior halo. The envelope
// lives on the effect side, so the shader only places the light.
vec3 applyClickLight(vec3 rgb, vec2 position)
{
    if (clickAmount <= 0.0 || clickRadius <= 0.0)
        return rgb;
    float d = distance(position, clickLocal);
    float width = max(10.0, clickRadius * 0.18);
    float ring = exp(-0.5 * pow((d - clickRadius) / width, 2.0));
    float halo = exp(-0.5 * pow(d / (clickRadius * 0.65 + 1.0), 2.0)) * 0.45;
    float light = clamp((ring + halo) * clickAmount, 0.0, 0.85);
    return mix(rgb, vec3(1.0), light * 0.45);
}

// One refracted backdrop sample. The lens shift is clamped to a fixed pixel
// budget so a wide panel can never drag wallpaper-sized smears into itself.
vec4 refractBackdrop(vec2 baseUv, vec3 glassNormal, float ior,
                     float dispersion, float magnitude, vec2 pixelUv,
                     vec2 lensShift)
{
    const float maxLensShiftPx = 48.0;
    vec2 maxShift = pixelUv * maxLensShiftPx;

    vec3 viewRay = vec3(0.0, 0.0, -1.0);
    vec3 refracted = refract(viewRay, glassNormal, 1.0 / ior);
    vec2 direction = length(refracted.xy) > 0.001
        ? normalize(refracted.xy) : vec2(0.0);

    vec2 shift = clamp(direction * magnitude * pixelUv + lensShift,
                       -maxShift, maxShift);
    vec4 sampleG = texture(texUnit, clamp(baseUv + shift, 0.0, 1.0));

    if (dispersion > 0.001) {
        float fringe = clamp(dispersion, 0.0, 1.0) * 0.3;
        vec2 shiftR = clamp(direction * (magnitude * (1.0 + fringe)) * pixelUv
                            + lensShift, -maxShift, maxShift);
        vec2 shiftB = clamp(direction * (magnitude * (1.0 - fringe)) * pixelUv
                            + lensShift, -maxShift, maxShift);
        float red = texture(texUnit, clamp(baseUv + shiftR, 0.0, 1.0)).r;
        float blue = texture(texUnit, clamp(baseUv + shiftB, 0.0, 1.0)).b;
        return vec4(red, sampleG.g, blue, sampleG.a);
    }
    return sampleG;
}

// Edge lens plus volume body lens. The edge tilt is part of the liquid
// material, not a tuning knob; soft glass has no raised edge.
vec4 liquidBackdrop(vec2 position, vec2 halfSize, vec4 radii, float minHalfSize,
                    float dist, float concaveFactor, float edgeFactor)
{
    float bandWidth = clamp(edgeSizePixels, 0.1, minHalfSize * 0.9);
    const float bodyReachPx = 40.0;
    const float bodyMaxPx = 40.0;
    float ior = 1.0 + refractionStrength;

    float minRadius = min(min(radii.x, radii.y), min(radii.z, radii.w));
    float epsilon = min(bandWidth * 0.75, minRadius * 0.6);
    // Finite differences here, not the analytic gradient: the small smoothing
    // radius keeps the normal field of the lens continuous through the corner
    // joins, where the analytic form steps.
    float dxp = roundedRectangleDist(position + vec2(epsilon, 0.0),
                                     halfSize, radii);
    float dxn = roundedRectangleDist(position - vec2(epsilon, 0.0),
                                     halfSize, radii);
    float dyp = roundedRectangleDist(position + vec2(0.0, epsilon),
                                     halfSize, radii);
    float dyn = roundedRectangleDist(position - vec2(0.0, epsilon),
                                     halfSize, radii);
    vec2 smoothGradient = vec2(dxp - dxn, dyp - dyn);
    float gradientLength = length(smoothGradient);

    float fixedBevelIntensity = materialSoftness > 0.001 ? 0.0 : 1.4;
    float normalHeight = concaveFactor * fixedBevelIntensity;
    vec2 normalXY = gradientLength > 0.001
        ? (smoothGradient / gradientLength) * normalHeight : vec2(0.0);
    vec3 glassNormal = normalize(vec3(normalXY, 1.0));

    float lensMagnitude = min(concaveFactor * fixedBevelIntensity * 6.0, 10.0);
    vec2 outwardDir = gradientLength > 0.001
        ? smoothGradient / gradientLength : vec2(0.0);

    // One displacement unit is a texel of the half-resolution capture: two
    // logical pixels of the backdrop.
    vec2 pixelUv = 1.0 / vec2(textureSize(texUnit, 0));
    vec2 lensShift = -outwardDir * lensMagnitude * pixelUv;
    // Pointer parallax: bias the lens toward the cursor by at most two capture
    // texels (four logical pixels). Weighted by the edge factor so only the
    // refractive rim band moves; the panel's interior backdrop stays put, or
    // the whole material reads as a sliding picture when the pointer moves.
    if (parallaxStrength > 0.0) {
        vec2 pointerVec = clamp(pointerLocal / max(halfSize, vec2(1.0)),
                                vec2(-1.0), vec2(1.0));
        lensShift += pointerVec * parallaxStrength * 2.0 * pixelUv
            * smoothstep(0.0, 1.0, edgeFactor);
    }

    // Volume lens: the body bends the backdrop perpendicular to each edge,
    // with full strength at the rim easing to zero 40 px inward. Measured in
    // absolute pixels, not as a fraction of the surface, so a wide launcher
    // and a small Dock bend by the same amount.
    float interiorDist = max(-dist, 0.0);
    float bodyT = 1.0 - clamp(interiorDist / bodyReachPx, 0.0, 1.0);
    float bodyProfile = 1.0 - sqrt(max(1.0 - bodyT * bodyT, 0.0));
    float bodyMagnitude = min(clamp(refractionOffsetStrength, 0.0, 12.0)
                              * refractionStrength * 6.0, bodyMaxPx);
    // Never let the shift run past the captured backdrop: the sample would
    // clamp one edge texel and read as a repeated smear.
    vec2 sampleDir = -outwardDir;
    vec2 dirAbs = max(abs(sampleDir), vec2(1e-3));
    vec2 roomToEdge = (halfSize - sign(sampleDir) * position) / dirAbs;
    float available = min(roomToEdge.x, roomToEdge.y);
    float roomInShiftUnits = available / max(viewportScale * 2.0, 0.0001);
    bodyMagnitude = min(bodyMagnitude, roomInShiftUnits * 0.85);
    lensShift -= outwardDir * bodyMagnitude * bodyProfile * pixelUv;

    float refractionMagnitude = lensMagnitude * refractionStrength;
    return refractBackdrop(uv, glassNormal, ior, refractionRGBFringing,
                           refractionMagnitude, pixelUv, lensShift);
}

// Same curve as the previous implementation and the QML fallback: a rational
// compression that stays monotonic in the backdrop luminance, plus a faint
// opposite tint that dissolves near the compressed end. Applying it after the
// tint means the glass tone is preserved and only the backdrop's brightness
// decides how much the surface closes up.
vec3 adaptiveScrim(vec3 background, float lum, bool whiteScrim)
{
    float damage = whiteScrim ? 1.0 - lum : lum;
    float floorAlpha = 0.06 * scrimCap;
    float peakAlpha = min(0.9999, max(floorAlpha, min(scrimDecay, scrimCap)));
    float response = pow(damage, 2.0 - scrimDecay);
    float ratio = (1.0 - peakAlpha) / (1.0 - floorAlpha);
    float primaryAlpha = floorAlpha + (peakAlpha - floorAlpha)
        * response / (ratio + (1.0 - ratio) * response);
    float compressed = damage * (1.0 - primaryAlpha);
    float handoff = 1.0 - smoothstep(0.0, 1.0 - peakAlpha, compressed);
    float oppositeCap = min(min(0.10, scrimCap), 0.5 * (1.0 - peakAlpha));
    float oppositeAlpha = oppositeCap * handoff
        * (scrimCap - primaryAlpha) / max(scrimCap, 0.0001);
    vec3 primaryTint = whiteScrim ? vec3(1.0) : vec3(0.0);
    return mix(mix(background, primaryTint, primaryAlpha),
               1.0 - primaryTint, oppositeAlpha);
}

void main(void)
{
    // Material field in flipped-Y texture orientation; see the header comment.
    vec2 position = vec2(vertex.x - box.x, box.y - vertex.y);
    float dist = roundedRectangleDist(position, box.zw, cornerRadius);
    // Derivatives must be evaluated once, before any branch: undefined along
    // the exact contour on some drivers otherwise.
    float antialiasWidth = max(fwidth(dist), 0.75);
    float coverageWidth = max(fwidth(dist), 0.0001);
    float coverage = 1.0 - clamp(0.5 + dist / coverageWidth, 0.0, 1.0);

    float minHalfSize = min(box.z, box.w);
    float edgeBand = clamp(edgeSizePixels, 0.1, minHalfSize * 0.9);
    float edgeFactor = 1.0 - clamp(abs(dist) / edgeBand, 0.0, 1.0);
    float concaveFactor = 1.0 - sqrt(1.0 - pow(smoothstep(0.0, 1.0, edgeFactor),
                                               refractionNormalPow));

    // The whole optical stage belongs to the liquid profile. Frosted shapes
    // only receive the blurred backdrop and the tint. Strength lives in the
    // downsample chain, not in the composite: one fetch per covered fragment.
    vec3 color = texture(texUnit, uv).rgb;
    // Scrim strength follows the backdrop's own brightness, not the shaded
    // glass: pick the luma up before the optics and tint are applied.
    float backdropLuma =
        dot(color, vec3(0.299, 0.587, 0.114));
    if (scrimMode > 0 && scrimLumaSmooth == 1) {
        // The blurred chains are already a low pass; only the raw capture needs
        // the equivalent of the previous implementation's 1/16-scale luma map.
        vec2 step = 16.0 / vec2(textureSize(texUnit, 0));
        const vec3 lumaWeights = vec3(0.299, 0.587, 0.114);
        float sum = backdropLuma * 2.0;
        sum += dot(texture(texUnit, uv + vec2(step.x, 0.0)).rgb, lumaWeights);
        sum += dot(texture(texUnit, uv - vec2(step.x, 0.0)).rgb, lumaWeights);
        sum += dot(texture(texUnit, uv + vec2(0.0, step.y)).rgb, lumaWeights);
        sum += dot(texture(texUnit, uv - vec2(0.0, step.y)).rgb, lumaWeights);
        backdropLuma = sum / 6.0;
    }
    if (liquidEnabled == 1 && dist < 0.0) {
        if (refractionStrength > 0.0) {
            vec4 lensRadii = clamp(cornerRadius * 2.0, min(64.0, minHalfSize),
                                   min(128.0, minHalfSize));
            color = liquidBackdrop(position, box.zw, lensRadii, minHalfSize,
                                   dist, concaveFactor, edgeFactor).rgb;
        }
        color = applySoftMaterial(color, position, box.zw, cornerRadius,
                                  edgeFactor);
        color = applyEdgeLight(color, position, box.zw, cornerRadius, dist,
                               antialiasWidth);
        if (hoverAmount > 0.0) {
            color = applyHoverLight(color, position, box.zw, edgeFactor);
        }
        color = applyClickLight(color, position);
    }
    color = mix(color, tint.rgb, tint.a);
    if (scrimMode > 0) {
        color = adaptiveScrim(color, backdropLuma, scrimMode == 2);
    }

    float alpha = coverage * opacity;
    fragColor = vec4(color * alpha, alpha);
}
