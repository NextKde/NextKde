#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf { mat4 qt_Matrix;float qt_Opacity; };
layout(binding=1) uniform sampler2D source;
void main() {
    vec3 rgb=(texture(source,qt_TexCoord0).rgb-.5)*.4+.5;
    float luma=dot(rgb,vec3(.2126,.7152,.0722));
    rgb=mix(vec3(luma),rgb,3.0);rgb=((rgb-.5)*1.7+.5)*.75;
    fragColor=vec4(clamp(rgb,0.0,1.0),1.0)*qt_Opacity;
}
