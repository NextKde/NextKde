#version 440
// Adapted from Kawarp DOMAIN_WARP_SHADER and OUTPUT_SHADER.
// Copyright (c) 2026 Better Lyrics. MIT; see licenses/kawarp-MIT.txt.
// https://github.com/better-lyrics/kawarp/blob/97bb3b012540cd3400128a5895bc9b8f618e9a87/packages/core/src/index.ts
// Qt adaptation: merge warp/output, retain existing background state, slow to
// 0.6x upstream speed and compress highlights for white foreground text.
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix; float qt_Opacity; float flowTime; float aspect; float viewWidth; float viewHeight;
};
layout(binding=1) uniform sampler2D source;
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
  vec2 mod289(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
  vec3 permute(vec3 x) { return mod289(((x*34.0)+1.0)*x); }

  float snoise(vec2 v) {
    const vec4 C = vec4(0.211324865405187, 0.366025403784439,
                        -0.577350269189626, 0.024390243902439);
    vec2 i  = floor(v + dot(v, C.yy));
    vec2 x0 = v - i + dot(i, C.xx);
    vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = mod289(i);
    vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
    vec3 m = max(0.5 - vec3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);
    m = m*m; m = m*m;
    vec3 x = 2.0 * fract(p * C.www) - 1.0;
    vec3 h = abs(x) - 0.5;
    vec3 ox = floor(x + 0.5);
    vec3 a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0*a0 + h*h);
    vec3 g;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0 * dot(m, g);
  }


float hash(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}
void main() {
    vec2 uv = qt_TexCoord0;
    float t = flowTime * 0.6;
    vec2 center = uv - 0.5;
    float centerWeight = 1.0 - smoothstep(0.0, 0.7, length(center));
    float n1 = snoise(uv * 0.35 + vec2(t, t * 0.7));
    float n2 = snoise(uv * 0.35 + vec2(-t * 0.8, t * 0.5) + vec2(50.0, 50.0));
    float n3 = snoise(uv * 0.9 + vec2(t * 1.2, -t) + vec2(100.0, 0.0));
    float n4 = snoise(uv * 0.9 + vec2(-t, t * 1.1) + vec2(0.0, 100.0));
    vec2 warp = vec2(n1 * 0.65 + n3 * 0.35, n2 * 0.65 + n4 * 0.35) * centerWeight;
    vec2 warpedUV = clamp(uv + warp, 0.0, 1.0);
    vec3 rgb = texture(source, warpedUV).rgb;
    rgb *= 1.0 - dot(center, center) * 0.3;
    float gray = dot(rgb, vec3(0.299, 0.587, 0.114));
    rgb = max(mix(vec3(gray), rgb, 1.5), vec3(0.0));
    // A smooth shoulder preserves shading instead of clipping bright regions.
    vec3 linear = pow(rgb, vec3(2.2));
    float luma = dot(linear, vec3(0.2126, 0.7152, 0.0722));
    rgb = pow(linear * (0.22 / (0.22 + luma)), vec3(1.0 / 2.2));
    // Keep fine dithering stationary; it must not shimmer when lyrics move.
    float noise = hash(vec3(floor(qt_TexCoord0 * vec2(viewWidth, viewHeight)), 0.0));
    rgb += (noise - 0.5) * 0.008;
    fragColor = vec4(clamp(rgb, 0.0, 1.0), 1.0) * qt_Opacity;
}
