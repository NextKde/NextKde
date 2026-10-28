#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 surfaceSize;
    float radius;
    vec4 tintColor;
    float tintStrength;
    float diffuseStrength;
};
float roundedDistance(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - halfSize + vec2(r);
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}
float grain(vec2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, vec2(.06711056, .00583715)))) - .5;
}
void main() {
    vec2 uv = qt_TexCoord0;
    vec2 halfSize = surfaceSize * .5;
    float distance = roundedDistance((uv - .5) * surfaceSize, halfSize, clamp(radius, 0.0, min(halfSize.x, halfSize.y)));
    float shape = 1.0 - smoothstep(-max(fwidth(distance), .0001), 0.0, distance);
    // Material pigmentation only: no source texture, desktop image or fake blur.
    // Broad continuous face light and static subpixel-scale grain never change alpha.
    float face = .010 * cos((uv.y - .18) * 3.14159) + .004 * sin(uv.x * 3.14159);
    float texture = .003 * grain(floor(gl_FragCoord.xy));
    vec3 rgb = tintColor.rgb / max(tintColor.a, .0001);
    rgb = clamp(rgb + vec3((face + texture) * clamp(diffuseStrength, 0.0, 1.0)), 0.0, 1.0);
    float alpha = tintColor.a * clamp(tintStrength, 0.0, 1.0) * shape * qt_Opacity;
    fragColor = vec4(rgb * alpha, alpha);
}
