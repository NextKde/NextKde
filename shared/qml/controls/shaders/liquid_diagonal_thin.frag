#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 surfaceSize;
    float radius;
    float reflectionStrength;
    vec4 rimColor;
};
float roundedDistance(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - halfSize + vec2(r);
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}
vec2 roundedNormal(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - halfSize + vec2(r);
    vec2 corner = max(q, vec2(0.0));
    if (dot(corner, corner) > .0001) return normalize(corner) * sign(p);
    return q.x > q.y ? vec2(sign(p.x), 0.0) : vec2(0.0, sign(p.y));
}
void main() {
    vec2 uv = qt_TexCoord0;
    vec2 halfSize = surfaceSize * .5;
    float r = clamp(radius, 0.0, min(halfSize.x, halfSize.y));
    vec2 p = (uv - .5) * surfaceSize;
    float d = roundedDistance(p, halfSize, r);
    float aa = max(fwidth(d), .0001);
    float coverage = 1.0 - smoothstep(-aa, 0.0, d);
    float depth = max(0.0, -d);
    vec2 normal = roundedNormal(p, halfSize, r);
    // Match the plugin's narrow contour glints, in Qt's downward Y axis.
    // Opposing corner envelopes fade continuously through rounded corners.
    float diagonal = clamp(2.0 * abs(normal.x * normal.y), 0.0, 1.0);
    float sigma = mix(max(aa * .22, .24), max(aa * .28, .30),
                      smoothstep(.08, .72, diagonal));
    float contour = exp(-.5 * pow((depth - .55) / sigma, 2.0));
    float x = clamp(uv.x + .04, 0.0, 1.0);
    float left = 1.0 - smoothstep(0.0, 1.0, x);
    float right = 1.0 - smoothstep(0.0, 1.0, 1.0 - x);
    float top = 1.0 - smoothstep(0.0, 1.0, uv.y);
    float bottom = 1.0 - smoothstep(0.0, 1.0, 1.0 - uv.y);
    float primary = min(1.0,
        pow(max(-normal.y, 0.0), .78) * left
        + pow(max(-normal.x, 0.0), .78) * top);
    float secondary = min(1.0,
        pow(max(normal.y, 0.0), .78) * right
        + pow(max(normal.x, 0.0), .78) * bottom);
    float strength = clamp(reflectionStrength, 0.0, 2.0);
    float keyAlpha = clamp(contour * primary * .60 * strength, 0.0, .60);
    float counterAlpha = clamp(contour * secondary * .50 * strength, 0.0, .50);
    float alpha = (1.0 - (1.0 - keyAlpha) * (1.0 - counterAlpha))
        * coverage * qt_Opacity;
    // Positive white reflection only; no dark bevel or broad soft-glass glow.
    fragColor = vec4(vec3(alpha), alpha);
}
