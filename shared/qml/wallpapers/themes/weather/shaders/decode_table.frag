#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 tableSize;
    float channels;
} u;
layout(binding=1) uniform sampler2D encoded;
float decode(ivec2 p) {
    uvec3 lo=uvec3(round(texelFetch(encoded,p,0).rgb*255.0));
    uint hi=uint(round(texelFetch(encoded,p+ivec2(1,0),0).r*255.0));
    return uintBitsToFloat(lo.r | (lo.g<<8) | (lo.b<<16) | (hi<<24));
}
void main() {
    ivec2 p=ivec2(clamp(floor(qt_TexCoord0*u.tableSize),vec2(0),u.tableSize-1));
    p.x*=int(u.channels)*2;
    fragColor=vec4(decode(p),decode(p+ivec2(2,0)),u.channels>2.5 ? decode(p+ivec2(4,0)) : 0.0,1);
}
