#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 bodySize;
    vec2 shadowOffset;
    float padding;
    float radius;
    float softness;
    float shadowOpacity;
    vec4 shadowColor;
};
float roundedDistance(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - halfSize + vec2(r);
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}
void main() {
    vec2 halfSize = bodySize * .5;
    vec2 p = qt_TexCoord0 * (bodySize + 2.0 * padding) - padding - halfSize;
    float r = clamp(radius, 0.0, min(halfSize.x, halfSize.y));
    float bodyDistance = roundedDistance(p, halfSize, r);
    // The interior contributes no colour or opacity: this is an outer shadow,
    // never an opaque shape below a translucent material.
    float outside = smoothstep(0.0, max(fwidth(bodyDistance), .001), bodyDistance);
    float distance = roundedDistance(p - shadowOffset, halfSize, r);
    float falloff = 1.0 / (1.0 + exp(clamp(distance / max(.1, softness * .4), -20.0, 20.0)));
    fragColor = shadowColor * (outside * falloff * shadowOpacity * qt_Opacity);
}
