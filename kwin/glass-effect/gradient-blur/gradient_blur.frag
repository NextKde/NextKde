#version 440

// Directional gradient-feathered Gaussian blur -- prototype for roadmap #3.
//
// Effect model (see /home/purn/pr2/GRADIENT-BLUR-PROPOSAL.md):
//   * the *backdrop* is blurred; whatever the host draws on top stays crisp;
//   * the blur radius ramps continuously between two points given in the
//     rectangle's local frame (start = no blur, end = maxRadius); the ramp is a
//     RADIUS ramp only -- never an opacity cross-fade, which would draw a
//     ghost second copy in the middle of the ramp;
//   * the "band" profile adds a second falloff toward the far edge so a
//     floating element gets a halo instead of a blur strip;
//   * an optional tint rides the same ramp, either composited over the blurred
//     result or mixed into every tap so the tint itself is blurred.
//
// This file is the tuning vehicle: the ramp math here is what gets ported into
// kwin/glass-effect/src/ later, where it will pick between existing pyramid
// levels instead of taking taps.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;   // level 0: the sharp backdrop
layout(binding = 2) uniform sampler2D level1;
layout(binding = 3) uniform sampler2D level2;
layout(binding = 4) uniform sampler2D level3;
layout(binding = 5) uniform sampler2D level4;
layout(binding = 6) uniform sampler2D level5;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float globalStrength;
    // Blur-pyramid radii, in pixels: x..w = r1..r4, levelRadiiB.x = r5.
    vec4 levelRadii;
    vec4 levelRadiiB;
    // xy = canvas size in pixels, zw = 1 / size. Passed in rather than read
    // with textureSize(): the --qt6 target also bakes an ESSL 100 variant for
    // Qt's built-in vertex shader, where textureSize does not exist.
    vec4 canvasAndTexel;
    // Per zone: rectangle in canvas pixels, then the ramp as two local points
    // (start = 0 blur, end = full blur), the blur shape, the tint, and flags. Kept as explicit members rather than arrays: this
    // is the layout Qt's shader reflection reports back, and arrays inside a
    // std140 block are the one thing worth not risking in a prototype.
    vec4 z0Rect;   // x, y, width, height   (pixels)
    vec4 z0Ramp;   // startX, startY, endX, endY  (local, centre = 0,0)
    vec4 z0Shape;  // maxRadiusPx, cornerRadiusPx, featherCurve, sideFeather
    vec4 z0Tint;   // rgb, alpha
    vec4 z0Flags;  // enabled, bandProfile, tintPerTap, featherOut
    vec4 z0Amount; // blur fraction at the start point / at the end point
    vec4 z1Rect;
    vec4 z1Ramp;
    vec4 z1Shape;
    vec4 z1Tint;
    vec4 z1Flags;
    vec4 z1Amount;
    vec4 z2Rect;
    vec4 z2Ramp;
    vec4 z2Shape;
    vec4 z2Tint;
    vec4 z2Flags;
    vec4 z2Amount;
    vec4 z3Rect;
    vec4 z3Ramp;
    vec4 z3Shape;
    vec4 z3Tint;
    vec4 z3Flags;
    vec4 z3Amount;
};

float sat01(float x)
{
    return clamp(x, 0.0, 1.0);
}

// Variable-radius blur by interpolating two pre-blurred pyramid levels.
//
// The first version sampled a 48-tap disc directly: on a high-contrast edge a
// sparse tap cloud lands on a handful of discrete positions, and the sum reads
// as a ghost / multi-image. The levels are dense blurs, so interpolating a
// bracketing pair stays smooth at every radius. This is also exactly what the
// KWin-side port will do -- it already owns a blur pyramid.
vec3 levelSample(int index, vec2 uv)
{
    if (index <= 1)
        return texture(level1, uv).rgb;
    if (index == 2)
        return texture(level2, uv).rgb;
    if (index == 3)
        return texture(level3, uv).rgb;
    if (index == 4)
        return texture(level4, uv).rgb;
    return texture(level5, uv).rgb;
}

vec3 blurredAt(vec2 uv, float radiusPx)
{
    if (radiusPx <= 0.5)
        return texture(source, uv).rgb;
    float r1 = levelRadii.x;
    float r2 = levelRadii.y;
    float r3 = levelRadii.z;
    float r4 = levelRadii.w;
    float r5 = levelRadiiB.x;
    if (radiusPx < r1)
        return mix(texture(source, uv).rgb, levelSample(1, uv), radiusPx / max(r1, 1e-3));
    if (radiusPx < r2)
        return mix(levelSample(1, uv), levelSample(2, uv), (radiusPx - r1) / max(r2 - r1, 1e-3));
    if (radiusPx < r3)
        return mix(levelSample(2, uv), levelSample(3, uv), (radiusPx - r2) / max(r3 - r2, 1e-3));
    if (radiusPx < r4)
        return mix(levelSample(3, uv), levelSample(4, uv), (radiusPx - r3) / max(r4 - r3, 1e-3));
    if (radiusPx < r5)
        return mix(levelSample(4, uv), levelSample(5, uv), (radiusPx - r4) / max(r5 - r4, 1e-3));
    return levelSample(5, uv);
}

vec3 applyZone(vec3 color, vec2 uv, vec2 texel, vec2 canvasSize,
               vec4 rect, vec4 ramp, vec4 shape, vec4 tint, vec4 flags,
               vec4 amount, float strength, float unusedTapLimit)
{
    if (flags.x < 0.5 || strength <= 0.0)
        return color;

    vec2 size = max(rect.zw, vec2(1.0));
    vec2 centered = uv * canvasSize - rect.xy - size * 0.5;

    // Rounded-rect coverage, one pixel wide.
    float cornerRadius = min(shape.y, min(size.x, size.y) * 0.5);
    vec2 q = abs(centered) - size * 0.5 + vec2(cornerRadius);
    float dist = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - cornerRadius;
    float cover = 1.0 - smoothstep(-1.0, 1.0, dist);
    if (cover <= 0.0)
        return color;

    // Ramp parameter: start and end are POINTS in the rectangle's own frame
    // (centre = 0,0; +-0.5 = the edges), and both may sit outside it. Blur is 0
    // at the start point and maxRadius at the end point; the segment between
    // them is the whole ramp.
    vec2 local = centered / size;
    vec2 seg = ramp.zw - ramp.xy;
    float segLen = length(seg);
    vec2 dir = segLen > 1e-5 ? seg / segLen : vec2(0.0, 1.0);
    vec2 perp = vec2(-dir.y, dir.x);
    float along = dot(local - ramp.xy, dir);
    // Eased ramp from the start point (0 blur) to the end point (full).
    float rampT = segLen > 1e-5 ? sat01(along / segLen) : 0.0;
    float feathered = rampT * rampT * (3.0 - 2.0 * rampT);
    rampT = mix(rampT, feathered, sat01(shape.z));
    // Perpendicular falloff: softens the zone's side edges for blur AND tint.
    float sideT = 1.0;
    if (shape.w > 0.0) {
        float edgeDistance = 0.5 * (abs(perp.x) + abs(perp.y))
            - abs(dot(local, perp));
        sideT = sat01(edgeDistance / shape.w);
    }
    // The blur fades back out past the end point in band mode. The tint must
    // NOT: tying it to the same falloff made it read as "the tint only exists
    // between the two points", while the reference status bar keeps its tint
    // across the whole band and only the blur fades.
    float fallT = 1.0;
    if (flags.y > 0.5 && flags.w > 0.0)
        fallT = sat01(1.0 - (along - segLen) / flags.w);
    // Blur amount here: the ramp is scaled between the fractions asked for at
    // the start point (default 0) and at the end point (default 100%), so a
    // ramp can start at 20% and top out at 80%.
    float blurAmount = mix(amount.x, amount.y, rampT);
    float t = blurAmount * sideT * fallT;      // radius profile
    float tintT = blurAmount * sideT;          // tint inherits the same amounts

    // The radius carries the whole ramp: at the start point it is 0, so those
    // pixels are the untouched backdrop and the zone leaves no seam. The
    // composite must NOT also fade between sharp and blurred -- doing both is
    // exactly what draws a semi-transparent second copy in the middle of the
    // ramp (the ghosting this prototype showed).
    float coverage = sat01(cover * strength);
    if (coverage <= 0.001)
        return color;

    vec3 blurred = blurredAt(uv, shape.x * t);
    if (flags.z > 0.5)
        blurred = mix(blurred, tint.rgb, tint.a);
    vec3 mixed = mix(color, blurred, coverage);
    if (flags.z < 0.5 && tint.a > 0.0)         // tint rides the same ramp
        mixed = mix(mixed, tint.rgb, sat01(tint.a * tintT * coverage));
    return mixed;
}

void main()
{
    vec2 uv = qt_TexCoord0;
    vec2 canvasSize = canvasAndTexel.xy;
    vec2 texel = canvasAndTexel.zw;
    vec3 color = texture(source, uv).rgb;
    color = applyZone(color, uv, texel, canvasSize,
                      z0Rect, z0Ramp, z0Shape, z0Tint, z0Flags, z0Amount,
                      globalStrength, 0.0);
    color = applyZone(color, uv, texel, canvasSize,
                      z1Rect, z1Ramp, z1Shape, z1Tint, z1Flags, z1Amount,
                      globalStrength, 0.0);
    color = applyZone(color, uv, texel, canvasSize,
                      z2Rect, z2Ramp, z2Shape, z2Tint, z2Flags, z2Amount,
                      globalStrength, 0.0);
    color = applyZone(color, uv, texel, canvasSize,
                      z3Rect, z3Ramp, z3Shape, z3Tint, z3Flags, z3Amount,
                      globalStrength, 0.0);

    fragColor = vec4(color, 1.0) * qt_Opacity;
}
