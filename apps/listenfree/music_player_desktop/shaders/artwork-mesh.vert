#version 440
// Bicubic Hermite patches; AMLL mesh renderer adaptation (research report).
layout(location=0) in vec4 qt_Vertex;
layout(location=1) in vec2 qt_MultiTexCoord0;
layout(location=0) out vec2 qt_TexCoord0;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;float qt_Opacity;float flowTime;float aspect;float viewWidth;float viewHeight;
};
vec2 point(vec2 p) {
    vec2 pos=p/3.0;
    if(p.x>0.0&&p.x<3.0&&p.y>0.0&&p.y<3.0)pos+=vec2(sin(p.x*7.1+p.y*3.2),cos(p.x*2.4+p.y*5.8))*.06;
    return pos;
}
vec2 tangent(vec2 p,bool vertical) {
    float angle=sin(p.x*5.1+p.y*2.7)*.4;
    if(p.x==0.0||p.x==3.0||p.y==0.0||p.y==3.0)angle=0.0;
    return (vertical?vec2(-sin(angle),cos(angle)):vec2(cos(angle),sin(angle)))/3.0;
}
vec4 basis(float t) {return vec4(2*t*t*t-3*t*t+1,-2*t*t*t+3*t*t,t*t*t-2*t*t+t,t*t*t-t*t);}
void main() {
    vec2 uv=qt_MultiTexCoord0,cell=min(floor(uv*3.0),vec2(2.0)),f=uv*3.0-cell;
    vec4 u=basis(f.x),v=basis(f.y);vec2 pos=vec2(0);
    for(int y=0;y<2;++y)for(int x=0;x<2;++x){vec2 p=cell+vec2(x,y);
        pos+=point(p)*u[x]*v[y]+tangent(p,false)*u[x+2]*v[y]+tangent(p,true)*u[x]*v[y+2];}
    qt_TexCoord0=uv;gl_Position=qt_Matrix*vec4(pos*vec2(viewWidth,viewHeight),0,1);
}
