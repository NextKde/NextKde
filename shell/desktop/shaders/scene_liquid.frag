#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

// G10 — in-scene backdrop sampling for the QML glass fallback. `source` is a
// ShaderEffectSource pointed at the host's hidden backdrop copy. Qt Quick
// binds a sampler by QML property name, so this must stay `source`.
layout(binding = 1) uniform sampler2D source;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float radius;
    vec2 surfaceSize;
    vec4 tintColor;
    float tintStrength;
    float scrimEnabled;
    float scrimCap;
    float scrimDecay;
    float scrimTint;
    float surfaceOpacity;
    float blurScale;
};

float sdRoundBox(vec2 p, vec2 halfSize, float r)
{
    vec2 q = abs(p) - halfSize + vec2(r);
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

// 3x3 taps on the 1/6-downsampled capture. Same kernel as scene_glass.frag.
vec3 blur9(vec2 uv, vec2 step)
{
    vec3 c = texture(source, uv).rgb * 0.25;
    c += texture(source, uv + vec2(step.x, 0.0)).rgb * 0.125;
    c += texture(source, uv - vec2(step.x, 0.0)).rgb * 0.125;
    c += texture(source, uv + vec2(0.0, step.y)).rgb * 0.125;
    c += texture(source, uv - vec2(0.0, step.y)).rgb * 0.125;
    c += texture(source, uv + step).rgb * 0.0625;
    c += texture(source, uv - step).rgb * 0.0625;
    c += texture(source, uv + vec2(step.x, -step.y)).rgb * 0.0625;
    c += texture(source, uv + vec2(-step.x, step.y)).rgb * 0.0625;
    return c;
}

// KWin's adaptiveScrim, ported from
// kwin/glass-effect/src/generated/onscreen_rounded_core.frag. Keep the curves
// identical: the QML fallback and the compositor must agree on how strongly a
// backdrop is compressed. `scrimTint > 0.5` selects the white tint.
vec3 adaptiveScrim(vec3 color, float lum, bool whiteScrim)
{
    float damage = whiteScrim ? 1.0 - lum : lum;
    float floorAlpha = 0.06 * scrimCap;
    float peakAlpha = min(0.9999, max(floorAlpha, min(scrimDecay, scrimCap)));
    float response = pow(damage, 2.0 - scrimDecay);
    float ratio = (1.0 - peakAlpha) / (1.0 - floorAlpha);
    float primaryAlpha = floorAlpha + (peakAlpha - floorAlpha)
        * response / (ratio + (1.0 - ratio) * response);
    float compressed = damage * (1.0 - primaryAlpha);
    float handoff = 1.0 - smoothstep(0.0, 1.0 - peakAlpha, compressed);
    float oppositeCap = min(min(0.10, scrimCap), 0.5 * (1.0 - peakAlpha));
    float oppositeAlpha = oppositeCap * handoff
        * (scrimCap - primaryAlpha) / max(scrimCap, 0.0001);
    vec3 primaryTint = whiteScrim ? vec3(1.0) : vec3(0.0);
    return mix(mix(color, primaryTint, primaryAlpha),
               1.0 - primaryTint, oppositeAlpha);
}

void main()
{
    vec2 halfSize = surfaceSize * 0.5;
    float r = min(radius, min(halfSize.x, halfSize.y));
    vec2 p = (qt_TexCoord0 - 0.5) * surfaceSize;
    float dist = sdRoundBox(p, halfSize, r);
    float band = max(fwidth(dist), 1e-6);
    float shape = 1.0 - clamp(0.5 + dist / band, 0.0, 1.0);

    // The capture is 1/6 scale; the 9 taps finish the blur. blurScale lets the
    // host widen the kernel without changing the texture size.
    vec2 step = 1.25 * 6.0 / surfaceSize * max(0.5, blurScale);
    vec3 sampled = blur9(qt_TexCoord0, step);

    vec3 color = mix(sampled, tintColor.rgb, clamp(tintStrength, 0.0, 1.0));

    if (scrimEnabled > 0.5) {
        float lum = clamp(dot(sampled, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
        color = adaptiveScrim(color, lum, scrimTint > 0.5);
    }

    float alpha = clamp(surfaceOpacity, 0.0, 1.0) * shape * qt_Opacity;
    fragColor = vec4(color * alpha, alpha);
}
