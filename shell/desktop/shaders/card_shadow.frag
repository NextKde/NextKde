#version 440

// Position inside this item, interpolated from the vertex stage. It is not
// qt_TexCoord0: the vertex shader derives it from qt_Vertex, because a
// ShaderEffect without a source is not guaranteed texture coordinates.
layout(location = 0) in vec2 shadowCoord;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // Size of this shadow item and of the card it belongs to. The card is
    // centred inside the shadow item, so both fields are expressed around that
    // shared centre.
    float shadowWidth;
    float shadowHeight;
    float cardWidth;
    float cardHeight;
    float cornerRadius;
    float cornerExponent;
    // Cast direction and shape of the shadow.
    float offsetX;
    float offsetY;
    float softness;
    float spread;
    float falloff;
    vec4 shadowColor;
    // Appended last so the vertex stage's identical block keeps every earlier
    // offset: both stages share one buffer, and only this one needs the field.
    float debugMode;
};

// The same superelliptical field as Squircle.mjs / shaders/squircle.frag. Keep
// all three in sync: the shadow's outline is the card's outline, and the hole
// this shader cuts has to be the same curve the mask draws, or the two edges
// disagree around 45 degrees and a gap shows up between card and shadow.
float squircleNorm(vec2 q, float n)
{
    if (q.x <= 0.0)
        return q.y;
    if (q.y <= 0.0)
        return q.x;
    return pow(pow(q.x, n) + pow(q.y, n), 1.0 / n);
}

float squircleDistance(vec2 p, vec2 halfSize, float radius, float n)
{
    vec2 q = abs(p) - halfSize + vec2(radius);
    // n == 2 is a plain rounded rectangle: the p-norm collapses to length(),
    // so the whole field is the classic rounded-box SDF with no pow() at all.
    // n arrives as a uniform, which makes this a uniform branch -- every pixel
    // in the draw takes the same side, so the pow path below costs nothing
    // when the card has circular corners. That case has to be fast: it is the
    // fallback the shadow drops to when the squircle token is off, and the
    // fill-rate-bound GPUs are exactly the ones that cannot afford 3 pow()
    // per squircleDistance() call, twice per pixel.
    if (n == 2.0)
        return length(max(q, vec2(0.0)))
            + min(max(q.x, q.y), 0.0) - radius;
    return squircleNorm(max(q, vec2(0.0)), n) + min(max(q.x, q.y), 0.0) - radius;
}

void main()
{
    // Probe 3: flat green over the whole item, no field evaluation at all. If
    // this block stops at the card's outline, something outside this shader is
    // clipping the surface rather than mis-shaping the shadow.
    if (debugMode > 2.5) {
        fragColor = vec4(0.0, 1.0, 0.0, 1.0) * qt_Opacity;
        return;
    }

    vec2 halfSize = vec2(cardWidth, cardHeight) * 0.5;
    // Item coordinates in pixels, around the item centre -- which is also the
    // card centre.
    vec2 centered = (shadowCoord - 0.5) * vec2(shadowWidth, shadowHeight);

    float n = clamp(cornerExponent, 2.0, 8.0);
    float maxRadius = min(halfSize.x, halfSize.y);
    float radius = min(cornerRadius, maxRadius);

    // The card, where it actually is. The hole is grown a pixel past the card's
    // own outline on purpose: the compositor captures the *previous* frame inside
    // this rectangle as the glass backdrop (BlurEffect::drawWindow blurs before
    // it draws the window, and renderTarget keeps the frame before that), so a
    // single shadow pixel landing inside the card's silhouette gets blurred back
    // into the glass and greys the card out. One pixel of margin means rounding,
    // scaling and anti-aliasing cannot place one there.
    float card = squircleDistance(centered, halfSize + vec2(1.0), radius, n);

    // The card's own coverage: 1 inside the outline, 0 outside. A fixed
    // one-pixel band rather than the mask's f / fwidth(f) ratio -- the hole only
    // has to line up with the card to within a pixel, and a constant band cannot
    // collapse into a degenerate ratio, which would invert this value and paint
    // the shading inside the card instead of outside it. Subtraction of this is
    // what keeps the shadow out of the card: a translucent card must not be
    // tinted by its own shadow, so the shadow is an outer-only effect rather
    // than a texture underneath the glass.
    float inside = clamp(0.5 - card, 0.0, 1.0);

    // Probe 1: the card's coverage. White must sit exactly under the card and
    // black everywhere else; a white block that fills the whole item means the
    // coordinate or size uniforms are wrong.
    if (debugMode > 0.5 && debugMode < 1.5) {
        fragColor = vec4(vec3(inside), 1.0) * qt_Opacity;
        return;
    }

    // The cast shadow: the same outline, moved towards the light's opposite
    // (offsetX, offsetY) and optionally grown so it stays solid right up to the
    // card edge instead of thinning out there. "cast" alone is a reserved word
    // in GLSL, hence the name.
    float castField = squircleDistance(centered - vec2(offsetX, offsetY), halfSize,
                                       min(radius + spread, maxRadius), n);

    // Probe 2: the cast outline. Red must appear as the card's shape shifted
    // down-right by (offsetX, offsetY), blue outside it.
    if (debugMode > 1.5 && debugMode < 2.5) {
        float s = castField < 0.0 ? 1.0 : 0.0;
        fragColor = vec4(s, 0.0, 1.0 - s, 1.0) * qt_Opacity;
        return;
    }

    // Smooth, monotone falloff -- 1 at the shadow's own edge, 0 at `softness`
    // pixels out. Written out rather than using smoothstep() because GLSL leaves
    // smoothstep(edge0 > edge1) undefined and the ramp here runs backwards.
    float span = max(softness, 0.5);
    float t = clamp(castField / span, 0.0, 1.0);
    float alpha = 1.0 - t;
    alpha = alpha * alpha * (3.0 - 2.0 * alpha);

    // A fixed quadratic falloff stands in for pow(alpha, falloff): pow() is a
    // per-pixel exp2/log2 pair spent on a knob no caller tunes, while
    // alpha*alpha is two multiplies and keeps the same monotone pull-in
    // towards the card that falloff > 1 produced. `falloff` stays declared in
    // the block -- the vertex stage shares this buffer's layout -- but no
    // longer feeds the curve.
    alpha = alpha * alpha * (1.0 - inside);

    // Qt Quick layers composite premultiplied, so rgb is scaled by its own
    // alpha before the item opacity is applied.
    float a = alpha * shadowColor.a;
    fragColor = vec4(shadowColor.rgb * a, a) * qt_Opacity;
}
