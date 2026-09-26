#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D matte;
layout(binding = 3) uniform sampler2D backgroundReference;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 cropScale;
    float imageZoom;
} ubuf;

void main()
{
    vec2 uv = vec2(0.5) + (qt_TexCoord0 - vec2(0.5))
        * ubuf.cropScale / ubuf.imageZoom;
    vec3 captured = texture(source, uv).rgb;
    float alpha = texture(matte, uv).r;
    vec3 premultiplied = captured * alpha;

    // A soft source pixel already contains some of the original background.
    // Estimate its foreground contribution before it is composited over the
    // moving background; bound the correction because the matte and inpainted
    // background are only estimates, especially around hair and glow.
    if (alpha > 0.08 && alpha < 0.98) {
        vec3 oldBackground = texture(backgroundReference, uv).rgb;
        vec3 recovered = clamp(captured - oldBackground * (1.0 - alpha),
                               vec3(0.0), vec3(alpha));
        float maximumChange = 0.18 * alpha;
        recovered = clamp(recovered,
                          premultiplied - vec3(maximumChange),
                          premultiplied + vec3(maximumChange));
        float edgeWeight = smoothstep(0.08, 0.30, alpha)
                         * (1.0 - smoothstep(0.82, 0.98, alpha));
        premultiplied = mix(premultiplied, recovered, 0.75 * edgeWeight);
    }
    fragColor = vec4(premultiplied, alpha) * ubuf.qt_Opacity;
}
