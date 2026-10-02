// The foreground stays registered with its matte. The reconstructed background
// moves across a shallow spherical patch around the image center. This keeps
// disocclusion small while making the far field respond to the viewing angle.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D background;
layout(binding = 3) uniform sampler2D matte;
layout(binding = 4) uniform sampler2D influence;
layout(binding = 5) uniform sampler2D depthMap;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 pointer;
    vec2 cropScale;
} ubuf;

void main()
{
    const float margin = 0.05;
    vec2 croppedUv = vec2(0.5) + (qt_TexCoord0 - vec2(0.5))
        * ubuf.cropScale * (1.0 - 2.0 * margin);
    vec2 pointer = clamp(ubuf.pointer, vec2(-1.0), vec2(1.0));
    vec2 screen = (qt_TexCoord0 - vec2(0.5)) * 2.0;
    vec2 sphereXY = screen * 0.42;
    float sphereZ = sqrt(max(0.01, 1.0 - dot(sphereXY, sphereXY)));

    // Rotate a shallow spherical backdrop around the image center. This
    // creates position-dependent motion and cross-axis parallax, rather than
    // translating the whole background as one flat card.
    float yaw = pointer.x * 0.075;
    float pitch = -pointer.y * 0.055;
    float cosineYaw = cos(yaw);
    float sineYaw = sin(yaw);
    float cosinePitch = cos(pitch);
    float sinePitch = sin(pitch);
    float turnedX = sphereXY.x * cosineYaw + sphereZ * sineYaw;
    float turnedZ = -sphereXY.x * sineYaw + sphereZ * cosineYaw;
    float turnedY = sphereXY.y * cosinePitch - turnedZ * sinePitch;
    vec2 orbit = (vec2(turnedX, turnedY) - sphereXY) * 0.27;

    float depth = texture(depthMap, croppedUv).r;
    float farWeight = 1.0 - smoothstep(0.30, 0.72, depth);
    // The original depth map sees the removed subject where the background
    // was reconstructed. Treat those pixels as the far surface underneath
    // the stationary foreground cutout.
    farWeight = max(farWeight, step(0.08, texture(matte, croppedUv).r));
    vec2 backgroundUv = clamp(croppedUv + orbit * farWeight
        * ubuf.cropScale,
        vec2(0.001), vec2(0.999));
    float opacity = texture(matte, croppedUv).r;
    vec3 backgroundColor = texture(background, backgroundUv).rgb;
    vec3 foregroundColor = texture(source, croppedUv).rgb;
    fragColor = vec4(mix(backgroundColor, foregroundColor, opacity), 1.0)
        * ubuf.qt_Opacity;
}
