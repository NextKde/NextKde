#version 440
// Sylvakru vivid background: separable Gaussian, sigma = 3% of each axis.
// Sample at a bounded texture size; the radius remains in normalized units.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 axis;
    float sigma;
};
layout(binding = 1) uniform sampler2D source;
void main() {
    vec4 sum = vec4(0.0);
    float weightSum = 0.0;
    for (int i = -24; i <= 24; ++i) {
        float distance = float(i) / 8.0;
        float weight = exp(-0.5 * distance * distance);
        sum += texture(source, clamp(qt_TexCoord0 + axis * sigma * distance, vec2(0.0), vec2(1.0))) * weight;
        weightSum += weight;
    }
    fragColor = sum / weightSum * qt_Opacity;
}
