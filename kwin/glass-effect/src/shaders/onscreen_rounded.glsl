#include "sdf.glsl"

uniform sampler2D texUnit;
uniform mat4 colorMatrix;
uniform float offset;
uniform vec2 halfpixel;
// Output scale: shape boxes are device pixels, the sampled capture is logical.
uniform float viewportScale;
uniform vec4 box;
uniform vec4 cornerRadius;
uniform float opacity;
uniform int glassEnabled;
uniform int scrimMode;
uniform float scrimCap;
uniform float scrimDecay;
uniform sampler2D scrimLumaTex;
uniform int scrimLumaValid;

in vec2 uv;
in vec2 vertex;
#include "glass.glsl"
#include "oklab.glsl"

// Read a broad local neighbourhood from the independent 1/16-scale
// backdrop. A separable 1:2:1 kernel plus linear texture filtering removes
// texel boundaries and prevents high-frequency wallpaper detail steering tint.
float localScrimLuminance(vec2 coord)
{
    vec2 stepSize = 1.0 / vec2(textureSize(scrimLumaTex, 0));
    vec3 color = vec3(0.0);
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            float weight = (x == 0 ? 2.0 : 1.0) * (y == 0 ? 2.0 : 1.0);
            color += texture(scrimLumaTex, coord + vec2(x, y) * stepSize).rgb * weight;
        }
    }
    return clamp(dot(color / 16.0, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
}

vec3 adaptiveScrim(vec3 background, float lum, bool whiteScrim)
{
    float damage = whiteScrim ? 1.0 - lum : lum;
    float floorAlpha = 0.06 * scrimCap;
    float peakAlpha = min(0.9999, max(floorAlpha, min(scrimDecay, scrimCap)));
    // Rational compression keeps the resulting backdrop brightness monotonic,
    // even at strong caps. A widened smoothstep followed by opacity clipping
    // can still turn a smooth gradient into a dark ridge. Lower decay gently
    // slows the response in middle tones without adding threshold boundaries.
    float response = pow(damage, 2.0 - scrimDecay);
    float ratio = (1.0 - peakAlpha) / (1.0 - floorAlpha);
    float primaryAlpha = floorAlpha + (peakAlpha - floorAlpha)
        * response / (ratio + (1.0 - ratio) * response);
    // Blend the faint opposite tint out across the compressed brightness
    // range, with zero slope at both ends. Limit its lift on very strong
    // finishes and reserve room under cap, including during popup fades.
    float compressed = damage * (1.0 - primaryAlpha);
    float handoff = 1.0 - smoothstep(0.0, 1.0 - peakAlpha, compressed);
    float oppositeCap = min(min(0.10, scrimCap), 0.5 * (1.0 - peakAlpha));
    float oppositeAlpha = oppositeCap * handoff
        * (scrimCap - primaryAlpha) / max(scrimCap, 0.0001);
    vec3 primaryTint = whiteScrim ? vec3(1.0) : vec3(0.0);
    // Compose the two fills directly rather than mixing straight tint and
    // opacity separately, which creates an extra ridge during a handoff.
    return mix(mix(background, primaryTint, primaryAlpha),
               1.0 - primaryTint, oppositeAlpha);
}

void main(void)
{
    // Same field as the cut below, evaluated from the fragment's own position
    // relative to the box centre. It used to be reconstructed as
    // "uv * blurSize - blurSize * 0.5", which is a rounded rectangle centred on
    // the *texture* and mirrored in y; that only agreed with the box when the
    // box was the whole texture, so any other stage -- and every protocol shape
    // but the first -- would have gate and cut disagreeing.
    // KWin's vertex space and the sampled texture have opposite Y axes.
    // Keep the material field in texture orientation, so the deliberately
    // stronger top glint is actually painted at the visual top.
    vec2 position = vec2(vertex.x - box.x, box.y - vertex.y);
    float dist = roundedRectangleDist(position, box.zw, cornerRadius);

    // The eight taps below are only read by the paths that keep them: glass()
    // hands the fragment to the Snell sampler whenever refraction is on, and
    // that samples the texture itself. Fetching them there cost eight texture
    // reads plus the average per covered fragment for a value nobody read.
    // Not `const`: both terms are uniforms, and GLSL requires a constant
    // expression in a const initializer -- the driver rejects the whole shader
    // otherwise ("initializer of const variable must be a constant
    // expression"), which leaves the effect half-initialised and the glass
    // unrendered.
    bool needsDetail = glassEnabled != 1 || refractionStrength <= 0.0;
    vec4 sum = vec4(0);
    if (dist <= 0.0 && needsDetail) {
        sum = texture(texUnit, uv + vec2(-halfpixel.x * 2.0, 0.0) * offset);
        sum += texture(texUnit, uv + vec2(-halfpixel.x, halfpixel.y) * offset) * 2.0;
        sum += texture(texUnit, uv + vec2(0.0, halfpixel.y * 2.0) * offset);
        sum += texture(texUnit, uv + vec2(halfpixel.x, halfpixel.y) * offset) * 2.0;
        sum += texture(texUnit, uv + vec2(halfpixel.x * 2.0, 0.0) * offset);
        sum += texture(texUnit, uv + vec2(halfpixel.x, -halfpixel.y) * offset) * 2.0;
        sum += texture(texUnit, uv + vec2(0.0, -halfpixel.y * 2.0) * offset);
        sum += texture(texUnit, uv + vec2(-halfpixel.x, -halfpixel.y) * offset) * 2.0;
        sum /= 12.0;
    }

    if (glassEnabled == 1) {
        sum = glass(sum, cornerRadius, position, box.zw);
        // Fixed finishes keep their exact tone/opacity. Adaptive finishes
        // follow broad local luminance through continuous, gently sloped curves.
        if (scrimMode >= 3) {
            bool whiteScrim = scrimMode == 4 || scrimMode == 6;
            vec3 tint = scrimMode == 6 ? vec3(0.92, 0.915, 0.905)
                : scrimMode == 5 ? vec3(0.34, 0.335, 0.35)
                : (whiteScrim ? vec3(1.0) : vec3(0.0));
            sum.rgb = mix(sum.rgb, tint, scrimCap);
        } else if (scrimMode > 0) {
            float lum = scrimLumaValid == 1 ? localScrimLuminance(uv) : 0.5;
            sum.rgb = adaptiveScrim(sum.rgb, lum, scrimMode == 2);
        }
        float df = fwidth(dist);
        sum *= 1.0 - clamp(0.5 + dist / df, 0.0, 1.0);
    }

    if (glassEnabled == 1 && useOklabSaturation == 1) {
        sum.rgb = oklabSaturate(sum.rgb, saturation);
    }

    fragColor = glassEnabled == 1
        ? sum * colorMatrix * opacity
        : sum * opacity;
}
