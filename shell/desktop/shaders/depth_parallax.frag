// Qt Quick ShaderEffect inputs: source and depthMap are normalized 2D textures.
// The depth response is relative, not a metric camera translation. The shader
// applies PreserveAspectCrop itself because Image.fillMode is not passed to a
// ShaderEffect texture. A small extra crop reserves room for motion.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D depthMap;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 pointer;
    vec2 cropScale;
} ubuf;

void main()
{
    const float margin = 0.032;
    vec2 croppedUv = vec2(0.5) + (qt_TexCoord0 - vec2(0.5))
        * ubuf.cropScale * (1.0 - 2.0 * margin);
    float depth = texture(depthMap, croppedUv).r;
    // Most motion translates the whole image coherently. Only the small
    // centered component depends on depth, limiting disocclusion at edges.
    vec2 baseOffset = ubuf.pointer * (0.0275 * ubuf.cropScale);
    vec2 depthOffset = ubuf.pointer * ((depth - 0.5) * 0.005
                                      * ubuf.cropScale);
    vec2 movedUv = croppedUv + baseOffset + depthOffset;
    float movedDepth = texture(depthMap, movedUv).r;
    float continuity = 1.0 - smoothstep(0.04, 0.16,
                                       abs(movedDepth - depth));
    vec2 sampleUv = clamp(croppedUv + baseOffset
                          + depthOffset * continuity,
                          vec2(0.001), vec2(0.999));
    fragColor = texture(source, sampleUv) * ubuf.qt_Opacity;
}
