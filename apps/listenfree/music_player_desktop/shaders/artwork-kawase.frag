#version 440
// Kawarp, Copyright (c) 2026 Better Lyrics, MIT (licenses/kawarp-MIT.txt).
// Source: 97bb3b012540cd3400128a5895bc9b8f618e9a87, KAWASE_BLUR_SHADER.
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix; float qt_Opacity; float sampleOffset;
};
layout(binding=1) uniform sampler2D source;
void main() {
    vec2 offset = vec2(sampleOffset / 128.0);
    vec4 color = texture(source, qt_TexCoord0 + vec2(-offset.x, -offset.y));
    color += texture(source, qt_TexCoord0 + vec2(offset.x, -offset.y));
    color += texture(source, qt_TexCoord0 + vec2(-offset.x, offset.y));
    color += texture(source, qt_TexCoord0 + offset);
    fragColor = color * (0.25 * qt_Opacity);
}
