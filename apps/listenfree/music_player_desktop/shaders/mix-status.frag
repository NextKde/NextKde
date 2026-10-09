#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf { mat4 qt_Matrix; float qt_Opacity; float phase; };
layout(binding=1) uniform sampler2D source;
void main() {
    vec4 text = texture(source, qt_TexCoord0);
    float center = mix(-.35, 1.35, phase);
    float highlight = 1.0 - smoothstep(0.0, .32, abs(qt_TexCoord0.x - center));
    fragColor = vec4(mix(text.rgb, vec3(text.a), highlight * .9), text.a) * qt_Opacity;
}
