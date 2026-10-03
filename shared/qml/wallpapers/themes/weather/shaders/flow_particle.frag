#version 440
layout(location=0) in vec2 uv;
layout(location=1) in float alpha;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 viewport;
    float particleIndex;
    float count;
    float foreground;
    float theme;
} u;
void main() {
    float r=length(uv-0.5)*2.0;
    float a=(exp(-r*r*18.0)*0.42+exp(-r*r*5.0)*0.06)*smoothstep(1.0,0.75,r)*alpha*u.qt_Opacity;
    vec3 tint=u.theme>0.5 && u.theme<1.5 ? vec3(1.0,0.56,0.22) : vec3(0.50,0.75,1.0);
    fragColor=vec4(tint*a,a);
}
