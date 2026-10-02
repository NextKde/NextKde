#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D source;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float direction;
    float effectMode;
    float angle;
    float waveWidth;
    float waveHeight;
    vec2 origin;
    float aspect;
    vec2 paintScale;
    float zoom;
} ubuf;

// One texture sample, active only while changing wallpapers.
void main() {
    vec2 uv = qt_TexCoord0;
    float p = clamp(ubuf.progress, 0.0, 1.0);
    float coverage = 1.0;
    int mode = int(ubuf.effectMode + 0.5);
    if (mode >= 1 && mode <= 4) {
        vec2 offset = mode == 1 ? vec2(1.0, 0.0) : mode == 2 ? vec2(-1.0, 0.0)
            : mode == 3 ? vec2(0.0, 1.0) : vec2(0.0, -1.0);
        uv += offset * (1.0 - p);
        coverage = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
    } else if (mode == 5 || mode == 6 || mode == 9) {
        vec2 axis = vec2(cos(ubuf.angle), sin(ubuf.angle));
        float extent = abs(axis.x) + abs(axis.y);
        float coordinate = dot(uv - 0.5, axis) / max(extent, 0.001) + 0.5;
        if (mode == 9) coordinate = (ubuf.direction < 0.0 ? 1.0 - uv.x : uv.x) * 0.82 + uv.y * 0.18;
        float margin = 0.03;
        if (mode == 6) {
            coordinate += sin(dot(uv, vec2(-axis.y, axis.x)) * 6.2831853 / max(ubuf.waveWidth, 0.02)) * ubuf.waveHeight;
            margin += ubuf.waveHeight;
        }
        coverage = 1.0 - smoothstep(-0.012, 0.012, coordinate - mix(-margin, 1.0 + margin, p));
    } else if (mode == 7 || mode == 8) {
        vec2 metric = vec2(ubuf.aspect, 1.0);
        vec2 reach = max(ubuf.origin, 1.0 - ubuf.origin) * metric;
        float maximum = length(reach);
        float distanceFromOrigin = length((uv - ubuf.origin) * metric);
        float radius = mix(-0.025, maximum + 0.025, mode == 8 ? 1.0 - p : p);
        coverage = 1.0 - smoothstep(radius - 0.015, radius + 0.015, distanceFromOrigin);
        if (mode == 8) coverage = 1.0 - coverage;
    }
    vec2 imageUv = (uv - 0.5) * ubuf.paintScale / max(ubuf.zoom, 0.001) + 0.5;
    float insideImage = step(0.0, imageUv.x) * step(imageUv.x, 1.0)
        * step(0.0, imageUv.y) * step(imageUv.y, 1.0);
    vec4 imageColor = mix(vec4(0.0666667, 0.0666667, 0.0666667, 1.0),
        texture(source, clamp(imageUv, 0.0, 1.0)), insideImage);
    fragColor = imageColor * coverage * ubuf.qt_Opacity;
}
