#version 440
// AMLL media-time sweep, half-em soft edge.
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf { mat4 qt_Matrix;float qt_Opacity;float progress;float edgeWidth;float sungAlpha;float unsungAlpha; };
layout(binding=1) uniform sampler2D source;
void main() {
    float edge=max(.001,edgeWidth),head=mix(-edge,1.0+edge,progress);
    float mask=1.0-smoothstep(head-edge,head+edge,qt_TexCoord0.x);
    fragColor=texture(source,qt_TexCoord0)*mix(unsungAlpha,sungAlpha,mask)*qt_Opacity;
}
