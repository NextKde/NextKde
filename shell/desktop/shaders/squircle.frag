#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float cornerRadius;
    float cornerExponent;
    float maskWidth;
    float maskHeight;
    float borderWidth;
    vec4 borderColor;
};

// GPU mirror of squircleDistance() / squircleGradient() in
// ../../modules/common/Squircle.mjs. Keep both in sync: this mask and the
// compositor's glass mask (vendor/kwin-effects-glass) have to evaluate the same
// family, otherwise the content edge and the glass edge split around 45
// degrees -- far more visible than either edge alone.
//
// The rounded-box construction is kept and only the corner metric is swapped,
// so exponent 2 reproduces length(max(q, 0.0)) exactly and this shader is a
// strict generalisation of the circular mask it replaces.

float squircleNorm(vec2 q, float n)
{
    if (n == 2.0)
        return length(q);
    if (q.x <= 0.0)
        return q.y;
    if (q.y <= 0.0)
        return q.x;
    return pow(pow(q.x, n) + pow(q.y, n), 1.0 / n);
}

float squircleDistance(vec2 p, vec2 halfSize, float radius, float n)
{
    vec2 q = abs(p) - halfSize + vec2(radius);
    return squircleNorm(max(q, vec2(0.0)), n) + min(max(q.x, q.y), 0.0) - radius;
}

void main()
{
    vec2 halfSize = vec2(maskWidth, maskHeight) * 0.5;
    vec2 centered = (qt_TexCoord0 - 0.5) * vec2(maskWidth, maskHeight);

    float n = clamp(cornerExponent, 2.0, 8.0);
    float radius = min(cornerRadius, min(halfSize.x, halfSize.y));

    float dist = squircleDistance(centered, halfSize, radius, n);

    // First-order pixel distance, the same expression the compositor already
    // uses for its own mask (onscreen_rounded.glsl). f / fwidth(f) is a ratio,
    // so it normalises away the field's gradient length: the anti-aliased band
    // stays one pixel wide at every exponent, which is why shaping with an SDF
    // costs nothing in edge quality compared with a circular radius.
    float band = max(fwidth(dist), 1e-6);
    float shape = 1.0 - clamp(0.5 + dist / band, 0.0, 1.0);

    vec4 material = texture(source, qt_TexCoord0);

    // Optional outline, painted by this shader rather than left to the layered
    // item. A host that wants a squircle-shaped border cannot use
    // Rectangle.border: a straight border would be cut off wherever the mask's
    // corner arc departs from the rectangle edge. The ring is the [ -w, 0 ]
    // band of the same field, so it follows the corner exactly.
    float outline = 0.0;
    if (borderWidth > 0.0)
        outline = clamp(shape - (1.0 - clamp(0.5 + (dist + borderWidth) / band,
            0.0, 1.0)), 0.0, 1.0) * borderColor.a;

    // Qt Quick layers are premultiplied, and so is borderColor's straight rgb
    // after this composite.
    vec3 rgb = borderColor.rgb * outline + material.rgb * (1.0 - outline);
    float alpha = outline + material.a * (1.0 - outline);

    fragColor = vec4(rgb, alpha) * shape * qt_Opacity;
}
