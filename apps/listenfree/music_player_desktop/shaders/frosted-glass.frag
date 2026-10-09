#version 440
// Material postprocess adapted from VideoLAN VLC FrostedGlassEffect,
// cacc4b02aefda52c0cff1b0039399bbfd9c38e95, GPL-2.0-or-later.
// Copyright (C) 2025 VLC authors and VideoLAN.
// Qt adaptation: RGB-only static noise and an antialiased rounded mask.
// See licenses/VLC-GPL-2.0.txt and docs/research/qt-glass-miniplayer.md.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 tint;
    vec2 surfaceSize;
    float radius;
    float tintStrength;
    float exclusionStrength;
    float noiseStrength;
};
layout(binding = 1) uniform sampler2D source;
void main() {
    vec4 sampleColor = texture(source, qt_TexCoord0);
    vec3 color = sampleColor.rgb / max(sampleColor.a, 0.001);
    // Exclusion brings only the extremes inward, without desaturation.
    color = color + exclusionStrength - 2.0 * color * exclusionStrength;
    color = mix(color, tint.rgb / max(tint.a, 0.001), tintStrength);
    float noise = fract(sin(dot(qt_TexCoord0, vec2(12.9898,78.233))) * 43758.5453) - 0.5;
    color = clamp(color + noise * noiseStrength, 0.0, 1.0);
    vec2 q = abs((qt_TexCoord0 - 0.5) * surfaceSize) - surfaceSize * 0.5 + radius;
    float distance = length(max(q,0.0)) + min(max(q.x,q.y),0.0) - radius;
    float alpha = 1.0 - smoothstep(-fwidth(distance),0.0,distance);
    fragColor = vec4(color * alpha, alpha) * qt_Opacity;
}
