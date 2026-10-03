#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix; float qt_Opacity;
    vec2 extent; vec2 light0; vec2 light1; vec2 light2; vec3 intensity;
} u;
void main() {
    vec2 p=qt_TexCoord0*u.extent;
    vec2 q=abs(p-u.extent*0.5)-(u.extent*0.5-vec2(22));
    float edge=length(max(q,0.0))+min(max(q.x,q.y),0.0)-14.0;
    vec2 a=(p-u.light0)/95.0,b=(p-u.light1)/95.0,c=(p-u.light2)/95.0;
    float light=exp(-dot(a,a))*u.intensity.x+exp(-dot(b,b))*u.intensity.y+exp(-dot(c,c))*u.intensity.z;
    float alpha=min(0.32,light*(exp(-abs(edge)/3.5)*0.14+(1.0-smoothstep(-2.0,0.0,edge))*0.018));
    fragColor=vec4(vec3(0.95,0.78,0.28)*alpha,alpha)*u.qt_Opacity;
}
