#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D source;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float direction;
} ubuf;

// A short, soft reveal grows across the actual desktop. No noise, blur loop
// or continuously running effect: the layer is discarded after the transition.
void main() {
    vec2 uv = qt_TexCoord0;
    vec2 focus = vec2(ubuf.direction < 0.0 ? 0.76 : 0.24, 0.52);
    float edge = length((uv - focus) * vec2(1.0, 1.12));
    float front = mix(-0.12, 1.16, ubuf.progress);
    float coverage = 1.0 - smoothstep(front - 0.07, front + 0.07, edge);
    vec4 pixel = texture(source, uv);
    float glint = exp(-pow((edge - front) / 0.065, 2.0));
    pixel.rgb += vec3(0.055, 0.075, 0.085) * glint * pixel.a;
    fragColor = pixel * coverage * ubuf.qt_Opacity;
}
