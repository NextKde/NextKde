#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D matte;

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
    vec3 color = texture(source, uv).rgb;
    float alpha = texture(matte, uv).r * ubuf.qt_Opacity;
    fragColor = vec4(color * alpha, alpha);
}
