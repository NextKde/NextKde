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

// A diagonal glass light sweep reveals the next still image. This stays a
// single texture sample per pixel; the effect is inactive between changes.
void main() {
    vec2 uv = qt_TexCoord0;
    float sweepAxis = uv.x + uv.y * 0.22;
    if (ubuf.direction < 0.0)
        sweepAxis = 1.0 - uv.x + uv.y * 0.22;
    float front = mix(-0.16, 1.22, ubuf.progress);
    float distanceToFront = sweepAxis - front;
    float coverage = 1.0 - smoothstep(-0.045, 0.045, distanceToFront);
    vec4 pixel = texture(source, uv);
    float halo = exp(-pow(distanceToFront / 0.095, 2.0));
    float glint = exp(-pow(distanceToFront / 0.022, 2.0));
    pixel.rgb += vec3(0.025, 0.085, 0.11) * halo * pixel.a;
    pixel.rgb += vec3(0.11, 0.42, 0.52) * glint * pixel.a;
    fragColor = pixel * coverage * ubuf.qt_Opacity;
}
