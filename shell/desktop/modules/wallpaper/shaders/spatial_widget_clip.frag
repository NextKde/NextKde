#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D source;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 viewport;
    vec4 rect;
} u;
void main() {
    vec2 local = qt_TexCoord0 * u.rect.zw;
    vec2 uv = (u.rect.xy + local) / u.viewport;
    fragColor = texture(source, uv) * u.qt_Opacity;
}
