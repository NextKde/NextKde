#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 panelSize;
    float revealProgress;
    vec4 plateColor;
};

float roundedRectSDF(vec2 p, vec2 halfSize, float radius)
{
    vec2 q = abs(p) - halfSize + vec2(radius);
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void main()
{
    float t = clamp(revealProgress, 0.0, 1.0);
    vec2 size = mix(vec2(160.0, 64.0), panelSize, t);
    vec2 center = vec2(panelSize.x * 0.5, panelSize.y - size.y * 0.5);
    float radius = min(mix(32.0, 36.0, t), min(size.x, size.y) * 0.5);
    float d = roundedRectSDF(qt_TexCoord0 * panelSize - center, size * 0.5, radius);
    float aa = max(fwidth(d), 0.5);
    float coverage = 1.0 - smoothstep(-aa, aa, d);
    // Close all the way to transparent instead of leaving the start capsule.
    float alpha = plateColor.a * coverage * smoothstep(0.0, 0.08, t) * qt_Opacity;
    fragColor = vec4(plateColor.rgb * alpha, alpha);
}
