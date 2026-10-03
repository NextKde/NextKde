#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(binding=1) uniform sampler2D source;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix; float qt_Opacity;
    vec2 viewport; float count; float blockedCount; vec4 dock;
    vec4 area0;
    vec4 area1;
    vec4 area2;
    vec4 area3;
    vec4 area4;
    vec4 area5;
    vec4 area6;
    vec4 area7;
    vec4 block0;
    vec4 block1;
    vec4 block2;
    vec4 block3;
    vec4 block4;
    vec4 block5;
    vec4 block6;
    vec4 block7;
    vec4 block8;
    vec4 block9;
    vec4 block10;
    vec4 block11;
    vec4 block12;
    vec4 block13;
    vec4 block14;
    vec4 block15;
} u;
float inside(vec2 p,vec4 r) { return step(r.x,p.x)*step(r.y,p.y)*step(p.x,r.x+r.z)*step(p.y,r.y+r.w); }
void main() {
    vec2 p=qt_TexCoord0*u.viewport;
    float allowed=0.0,blocked=0.0;
    if(u.count>0.0) allowed=max(allowed,inside(p,u.area0));
    if(u.count>1.0) allowed=max(allowed,inside(p,u.area1));
    if(u.count>2.0) allowed=max(allowed,inside(p,u.area2));
    if(u.count>3.0) allowed=max(allowed,inside(p,u.area3));
    if(u.count>4.0) allowed=max(allowed,inside(p,u.area4));
    if(u.count>5.0) allowed=max(allowed,inside(p,u.area5));
    if(u.count>6.0) allowed=max(allowed,inside(p,u.area6));
    if(u.count>7.0) allowed=max(allowed,inside(p,u.area7));
    if(u.blockedCount>0.0) blocked=max(blocked,inside(p,u.block0));
    if(u.blockedCount>1.0) blocked=max(blocked,inside(p,u.block1));
    if(u.blockedCount>2.0) blocked=max(blocked,inside(p,u.block2));
    if(u.blockedCount>3.0) blocked=max(blocked,inside(p,u.block3));
    if(u.blockedCount>4.0) blocked=max(blocked,inside(p,u.block4));
    if(u.blockedCount>5.0) blocked=max(blocked,inside(p,u.block5));
    if(u.blockedCount>6.0) blocked=max(blocked,inside(p,u.block6));
    if(u.blockedCount>7.0) blocked=max(blocked,inside(p,u.block7));
    if(u.blockedCount>8.0) blocked=max(blocked,inside(p,u.block8));
    if(u.blockedCount>9.0) blocked=max(blocked,inside(p,u.block9));
    if(u.blockedCount>10.0) blocked=max(blocked,inside(p,u.block10));
    if(u.blockedCount>11.0) blocked=max(blocked,inside(p,u.block11));
    if(u.blockedCount>12.0) blocked=max(blocked,inside(p,u.block12));
    if(u.blockedCount>13.0) blocked=max(blocked,inside(p,u.block13));
    if(u.blockedCount>14.0) blocked=max(blocked,inside(p,u.block14));
    if(u.blockedCount>15.0) blocked=max(blocked,inside(p,u.block15));
    float mask=max(inside(p,u.dock),allowed)*(1.0-blocked);
    if(mask<0.5) { fragColor=vec4(0); return; }
    fragColor=texture(source,qt_TexCoord0)*mask*u.qt_Opacity;
}
