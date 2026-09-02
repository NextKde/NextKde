#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float opacityMult;
    float sat;
    float iconTintEnabled;
    vec4 iconTintColor;
} ubuf;

void main() {
    vec4 sampleColor = texture(source, qt_TexCoord0);
    float sourceAlpha = sampleColor.a;

    // Qt Quick blends premultiplied-alpha colors. Convert to straight RGB while
    // styling so transparent pixels do not become artificially dark/gray.
    vec3 sourceColor = sourceAlpha > 0.001
        ? clamp(sampleColor.rgb / sourceAlpha, 0.0, 1.0)
        : vec3(0.0);

    // 1. Convert to grayscale first
    float lum = dot(sourceColor, vec3(0.299, 0.587, 0.114));
    vec3 gray = vec3(lum);
    vec3 desat = mix(sourceColor, gray, 1.0 - ubuf.sat);

    // 2. Tonal tint preserves the source luminance: true shadows remain dark,
    // midtones receive the selected hue, and highlights stay near white.
    vec3 tintColor = mix(ubuf.iconTintColor.rgb, vec3(1.0), lum) * lum;
    vec3 styledColor = mix(desat, tintColor, ubuf.iconTintEnabled);

    // 3. Apply opacity uniformly, then premultiply RGB again for Qt Quick.
    // This preserves antialiased edges without adding a gray veil.
    float finalAlpha = sourceAlpha * ubuf.opacityMult;
    vec3 premultipliedColor = styledColor * finalAlpha;

    fragColor = vec4(premultipliedColor, finalAlpha) * ubuf.qt_Opacity;
}
