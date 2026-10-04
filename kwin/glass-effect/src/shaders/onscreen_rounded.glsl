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
        // Contrast scrim: adaptive modes use a black or white fill whose opacity rises with the
        // backdrop's proximity to the opposite extreme, so light-on-light and
        // dark-on-dark content both stay legible. Once either configured tint
        // reaches its floor on a matching backdrop, it reverses to the opposite
        // tint at a restrained 10%. The reversed tint never ramps farther with
        // luminance, so an extreme backdrop cannot make the panel unexpectedly
        // heavy. Both handoffs are deliberately narrow and smooth. Fixed modes
        // bypass luminance and reversal and use scrimCap as exact opacity.
        if (scrimMode > 0) {
            // One value for the whole surface: the compositor reduces the
            // backdrop to a 1x1 average and feeds it here, so every fragment
            // of the surface shares the same scrim tone. Per-pixel backdrop
            // luminance made a variegated wallpaper band a panel into uneven
            // light/dark blocks; a single average keeps it uniform.
            float lum = 0.5;
            if (scrimLumaValid == 1)
                lum = dot(texture(scrimLumaTex, vec2(0.5)).rgb,
                          vec3(0.299, 0.587, 0.114));
            // A floor of a small fraction of cap keeps the scrim from
            // collapsing fully to invisible on a backdrop that already matches
            // the tint; scaling with cap means see-through levels still stay
            // nearly transparent while readable ones hold a faint presence.
            bool fixedScrim = scrimMode >= 3;
            bool whiteScrim = scrimMode == 2 || scrimMode == 4
                || scrimMode == 6;
            float floorAlpha = 0.06 * scrimCap;
            float damage = whiteScrim ? (1.0 - lum) : lum;
            float amount = smoothstep(0.40, 0.85, damage);
            float scrimAlpha = fixedScrim ? scrimCap
                : clamp(max(amount * scrimDecay, floorAlpha), 0.0, scrimCap);
            vec3 tint = scrimMode == 6 ? vec3(0.92, 0.915, 0.905)
                : scrimMode == 5 ? vec3(0.34, 0.335, 0.35)
                : (whiteScrim ? vec3(1.0) : vec3(0.0));

            if (!fixedScrim && whiteScrim) {
                // All shipped white curves have reached their minimum by about
                // 57% backdrop luminance. Reverse there, but hold the black
                // result at the lowest visual tier (10%) regardless of how much
                // brighter the backdrop gets. A lower custom cap still wins.
                float blackAlpha = min(0.10, scrimCap);
                float handoff = smoothstep(0.57, 0.63, lum);
                scrimAlpha = mix(scrimAlpha, blackAlpha, handoff);
                tint = mix(vec3(1.0), vec3(0.0), handoff);
            } else if (!fixedScrim) {
                // Mirror the white-to-black rule: all shipped black curves have
                // reached their floor by about 43% luminance. Below that point,
                // reverse to a fixed 10% white tint and never ramp it farther.
                float whiteAlpha = min(0.10, scrimCap);
                float handoff = 1.0 - smoothstep(0.37, 0.43, lum);
                scrimAlpha = mix(scrimAlpha, whiteAlpha, handoff);
                tint = mix(vec3(0.0), vec3(1.0), handoff);
            }
            sum.rgb = mix(sum.rgb, tint, scrimAlpha);
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
