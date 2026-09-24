// Qt Quick ShaderEffect inputs: source and depthMap are normalized 2D textures.
// The depth-only fallback keeps nearby pixels almost fixed and gives distant
// pixels a restrained curved response. The layered renderer can reveal more
// background because it has a reconstructed image behind the foreground.
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
    float farWeight = 1.0 - smoothstep(0.30, 0.70, depth);
    vec2 pointer = clamp(ubuf.pointer, vec2(-1.0), vec2(1.0));
    vec2 sphereXY = (qt_TexCoord0 - vec2(0.5)) * 1.1;
    float sphereZ = sqrt(max(0.01, 1.0 - dot(sphereXY, sphereXY)));
    vec2 orbit = vec2(
        sphereXY.x * (cos(pointer.x * 0.065) - 1.0)
            + sphereZ * sin(pointer.x * 0.065),
        sphereXY.y * (cos(pointer.y * 0.065) - 1.0)
            + sphereZ * sin(pointer.y * 0.065)) * 0.055;
    vec2 sampleUv = clamp(croppedUv - orbit * farWeight * ubuf.cropScale,
                          vec2(0.001), vec2(0.999));
    fragColor = texture(source, sampleUv) * ubuf.qt_Opacity;
}
