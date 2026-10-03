#version 440
layout(location=0) in vec4 qt_Vertex;
layout(location=1) in vec2 qt_MultiTexCoord0;
layout(location=0) out vec2 uv;
layout(location=1) out float alpha;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 viewport;
    float particleIndex;
    float count;
    float foreground;
    float theme;
} u;
layout(binding=1) uniform sampler2D state;
void main() {
    vec4 p=texture(state,vec2((u.particleIndex+0.5)/u.count,0.5/16.0));
    vec2 projected=p.xy;
    vec2 tangent=normalize(vec2(1.0,0.20));
    if(u.theme>0.5 && u.theme<1.5) {
        projected=vec2(p.x,-p.z*0.22+p.y);
        projected.x*=u.viewport.y/max(u.viewport.x,1.0);
        tangent=normalize(vec2(-p.z,-p.x*0.22));
    }
    float sceneScale=u.theme>0.5 && u.theme<1.5 ? 0.22 : 0.45;
    vec2 center=(projected*sceneScale+0.5)*u.viewport;
    if(u.theme>0.5 && u.theme<1.5) center+=vec2(0.16,-0.03)*u.viewport.y;

    float nearSide=step(0.0,p.z);
    alpha=((u.theme>1.5 ? u.foreground<0.5 : abs(nearSide-u.foreground)<0.1) ? 1.0 : 0.0)*smoothstep(0.0,0.6,p.w);
    if(u.theme>0.5 && u.theme<1.5 && length(center-(vec2(0.5)*u.viewport+vec2(0.16,-0.03)*u.viewport.y))<u.viewport.y*0.064) alpha=0.0;
    float size=mix(3.0,6.0,clamp(p.z*0.5+0.5,0.0,1.0));
    uv=qt_MultiTexCoord0;
    vec2 local=(uv-0.5)*vec2(size*2.8,size);
    vec2 offset=tangent*local.x+vec2(-tangent.y,tangent.x)*local.y;
    gl_Position=u.qt_Matrix*vec4(center+offset,0,1);
}
