#version 440
// Kawarp, Copyright (c) 2026 Better Lyrics, MIT (licenses/kawarp-MIT.txt).
// Source: 97bb3b012540cd3400128a5895bc9b8f618e9a87, TINT_SHADER defaults.
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf { mat4 qt_Matrix; float qt_Opacity; };
layout(binding=1) uniform sampler2D source;
void main() {
    vec4 color = texture(source, qt_TexCoord0);
    float luma = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    float darkMask = 1.0 - smoothstep(0.0, 0.5, luma);
    color.rgb = mix(color.rgb, vec3(0.157, 0.157, 0.235), darkMask * 0.15);
    fragColor = color * qt_Opacity;
}
