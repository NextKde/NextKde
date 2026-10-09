#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float sidebarFraction;
};
layout(binding = 1) uniform sampler2D source;
void main() {
    float opacity = qt_TexCoord0.x < sidebarFraction ? 0.84 : 1.0;
    fragColor = texture(source, qt_TexCoord0) * qt_Opacity * opacity;
}
