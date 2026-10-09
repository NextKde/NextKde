#version 440
// Sample the decoded Image directly. No intermediate crop or mask render target.
// Center-crop rounding follows Qt Quick's QQuickImage::PreserveAspectCrop.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 surfaceSize;
    float radius;
};
layout(binding = 1) uniform sampler2D source;
void main() {
    vec2 pixels = vec2(textureSize(source, 0));
    vec2 scale = surfaceSize / pixels;
    vec2 cropSize = pixels;
    if (scale.x > scale.y)
        cropSize.y = max(1.0, floor(scale.y / scale.x * pixels.y));
    else
        cropSize.x = max(1.0, floor(scale.x / scale.y * pixels.x));
    vec2 cropOrigin = ceil((pixels - cropSize) * 0.5);
    vec2 uv = (cropOrigin + qt_TexCoord0 * cropSize) / pixels;
    vec4 color = texture(source, uv);

    // Same antialiased rounded boundary as the existing frosted-glass shader.
    float r = clamp(radius, 0.0, min(surfaceSize.x, surfaceSize.y) * 0.5);
    vec2 q = abs((qt_TexCoord0 - 0.5) * surfaceSize) - surfaceSize * 0.5 + r;
    float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
    float mask = 1.0 - smoothstep(-max(fwidth(distance), 0.0001), 0.0, distance);
    fragColor = color * (mask * qt_Opacity);
}
