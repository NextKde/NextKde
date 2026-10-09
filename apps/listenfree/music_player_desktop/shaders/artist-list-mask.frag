#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float fadeTop;
    float fadeWidth;
};
layout(binding = 1) uniform sampler2D source;
void main() {
    float mask=smoothstep(fadeTop-fadeWidth,fadeTop+fadeWidth*.25,qt_TexCoord0.y);
    fragColor=texture(source,qt_TexCoord0)*mask*qt_Opacity;
}
