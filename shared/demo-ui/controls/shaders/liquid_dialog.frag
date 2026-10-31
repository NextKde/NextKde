#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D source;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 surfaceSize;
    vec2 sampleOrigin;
    vec2 sampleAxisX;
    vec2 sampleAxisY;
    float radius;
    vec4 tintColor;
    float tintStrength;
    float blurRadius;
    float readability;
    float lightAppearance;
    float refractionStrength;
    float magnification;
    float edgeWidth;
    float diffuseStrength;
    float materialOpacity;
};

// Fourth-order superellipse corners meet each straight edge with zero
// curvature (G2), unlike a circular rounded rectangle. Divide the implicit
// distance by its gradient length for a consistent antialiased optical edge.
float roundedDistance(vec2 p, vec2 halfSize, float r)
{
    vec2 q = abs(p) - halfSize + vec2(r);
    vec2 c = max(q, vec2(0.0));
    float n = pow(dot(c * c, c * c), 0.25);
    if (n < 0.0001) return max(q.x, q.y) - r;
    vec2 gradient = c * c * c / (n * n * n);
    return (n - r) / max(length(gradient), 0.0001);
}

vec2 roundedNormal(vec2 p, vec2 halfSize, float r)
{
    vec2 q = abs(p) - halfSize + vec2(r);
    vec2 c = max(q, vec2(0.0));
    if (dot(c, c) > 0.0001) return normalize(c * c * c) * sign(p);
    return q.x > q.y ? vec2(sign(p.x), 0.0) : vec2(0.0, sign(p.y));
}

vec2 sourceUv(vec2 localUv)
{
    return sampleOrigin + sampleAxisX * localUv.x + sampleAxisY * localUv.y;
}

vec4 blur9(vec2 uv, vec2 dx, vec2 dy)
{
    vec4 color = texture(source, uv) * 0.25;
    color += (texture(source, uv + dx) + texture(source, uv - dx)
        + texture(source, uv + dy) + texture(source, uv - dy)) * 0.125;
    color += (texture(source, uv + dx + dy) + texture(source, uv - dx - dy)
        + texture(source, uv + dx - dy) + texture(source, uv - dx + dy)) * 0.0625;
    return color;
}

void main()
{
    vec2 halfSize = surfaceSize * 0.5;
    float r = clamp(radius, 0.0, min(halfSize.x, halfSize.y));
    vec2 p = (qt_TexCoord0 - 0.5) * surfaceSize;
    float distance = roundedDistance(p, halfSize, r);
    float shape = 1.0 - smoothstep(-max(fwidth(distance), 0.0001), 0.0, distance);
    float edge = 1.0 - clamp(-distance / max(1.0, edgeWidth), 0.0, 1.0);
    vec2 normal = roundedNormal(p, halfSize, r);

    // Warp the actual source coordinates, not a painted colour gradient.
    vec2 localUv = 0.5 + (qt_TexCoord0 - 0.5) / max(1.0, magnification);
    localUv -= normal * max(0.0, refractionStrength) * edge * edge / surfaceSize;
    vec2 dx = sampleAxisX * max(0.0, blurRadius) / surfaceSize.x;
    vec2 dy = sampleAxisY * max(0.0, blurRadius) / surfaceSize.y;
    vec4 sampled = blur9(sourceUv(localUv), dx, dy);

    // Both textures and QColor uniforms arrive premultiplied. Preserve alpha
    // when sampling sparse content such as the slider track.
    vec4 glass = mix(sampled, tintColor, clamp(tintStrength, 0.0, 1.0));
    vec3 rgb = glass.rgb / max(glass.a, 0.0001);
    float luminance = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
    float contrastRisk = mix(luminance, 1.0 - luminance, lightAppearance);
    float scrim = clamp(readability, 0.0, 0.85) * smoothstep(0.08, 0.92, contrastRisk);
    rgb = mix(rgb, vec3(lightAppearance), scrim);
    // A restrained directional glint, never an accent/focus outline.
    float glint = pow(edge, 6.0) * max(dot(normal, normalize(vec2(-0.6, -0.8))), 0.0);
    rgb = mix(rgb, vec3(1.0), glint * 0.08);
    // Composite the glass layer over the softened underlay, not the sharp page.
    // Opacity controls that layer; tintStrength controls its independent colour.
    vec4 underlay = blur9(sourceUv(qt_TexCoord0), dx, dy);
    vec4 composed = mix(underlay, vec4(rgb * glass.a, glass.a),
                        clamp(materialOpacity, 0.0, 1.0));
    fragColor = composed * shape * qt_Opacity;
}
