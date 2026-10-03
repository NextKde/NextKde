// Derived from David Li Flow, MIT; see ../vendor/flow/LICENSE.
#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float delta;
    float initialize;
    float count;
    float theme;
    vec4 pointer;
    vec4 clickPulse;
    vec4 obstacle0;
    vec4 obstacle1;
    vec4 obstacle2;
    vec4 obstacle3;
    vec4 obstacle4;
    vec4 obstacle5;
    vec4 obstacle6;
    vec4 obstacle7;

} u;
layout(binding=1) uniform sampler2D previous;
vec4 mod289(vec4 x) {
return x - floor(x * (1.0 / 289.0)) * 289.0;
}
float mod289(float x) {
return x - floor(x * (1.0 / 289.0)) * 289.0;
}
vec4 permute(vec4 x) {
return mod289(((x*34.0)+1.0)*x);
}
float permute(float x) {
return mod289(((x*34.0)+1.0)*x);
}
vec4 taylorInvSqrt(vec4 r) {
return 1.79284291400159 - 0.85373472095314 * r;
}
float taylorInvSqrt(float r) {
return 1.79284291400159 - 0.85373472095314 * r;
}
vec4 grad4(float j, vec4 ip) {
const vec4 ones = vec4(1.0, 1.0, 1.0, -1.0);
vec4 p,s;
p.xyz = floor( fract (vec3(j) * ip.xyz) * 7.0) * ip.z - 1.0;
p.w = 1.5 - dot(abs(p.xyz), ones.xyz);
s = vec4(lessThan(p, vec4(0.0)));
p.xyz = p.xyz + (s.xyz*2.0 - 1.0) * s.www;
return p;
}
#define F4 0.309016994374947451
vec4 simplexNoiseDerivatives (vec4 v) {
const vec4  C = vec4( 0.138196601125011,0.276393202250021,0.414589803375032,-0.447213595499958);
vec4 i  = floor(v + dot(v, vec4(F4)) );
vec4 x0 = v -   i + dot(i, C.xxxx);
vec4 i0;
vec3 isX = step( x0.yzw, x0.xxx );
vec3 isYZ = step( x0.zww, x0.yyz );
i0.x = isX.x + isX.y + isX.z;
i0.yzw = 1.0 - isX;
i0.y += isYZ.x + isYZ.y;
i0.zw += 1.0 - isYZ.xy;
i0.z += isYZ.z;
i0.w += 1.0 - isYZ.z;
vec4 i3 = clamp( i0, 0.0, 1.0 );
vec4 i2 = clamp( i0-1.0, 0.0, 1.0 );
vec4 i1 = clamp( i0-2.0, 0.0, 1.0 );
vec4 x1 = x0 - i1 + C.xxxx;
vec4 x2 = x0 - i2 + C.yyyy;
vec4 x3 = x0 - i3 + C.zzzz;
vec4 x4 = x0 + C.wwww;
i = mod289(i);
float j0 = permute( permute( permute( permute(i.w) + i.z) + i.y) + i.x);
vec4 j1 = permute( permute( permute( permute (
i.w + vec4(i1.w, i2.w, i3.w, 1.0 ))
+ i.z + vec4(i1.z, i2.z, i3.z, 1.0 ))
+ i.y + vec4(i1.y, i2.y, i3.y, 1.0 ))
+ i.x + vec4(i1.x, i2.x, i3.x, 1.0 ));
vec4 ip = vec4(1.0/294.0, 1.0/49.0, 1.0/7.0, 0.0) ;
vec4 p0 = grad4(j0,   ip);
vec4 p1 = grad4(j1.x, ip);
vec4 p2 = grad4(j1.y, ip);
vec4 p3 = grad4(j1.z, ip);
vec4 p4 = grad4(j1.w, ip);
vec4 norm = taylorInvSqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2, p2), dot(p3,p3)));
p0 *= norm.x;
p1 *= norm.y;
p2 *= norm.z;
p3 *= norm.w;
p4 *= taylorInvSqrt(dot(p4,p4));
vec3 values0 = vec3(dot(p0, x0), dot(p1, x1), dot(p2, x2));
vec2 values1 = vec2(dot(p3, x3), dot(p4, x4));
vec3 m0 = max(0.5 - vec3(dot(x0,x0), dot(x1,x1), dot(x2,x2)), 0.0);
vec2 m1 = max(0.5 - vec2(dot(x3,x3), dot(x4,x4)), 0.0);
vec3 temp0 = -6.0 * m0 * m0 * values0;
vec2 temp1 = -6.0 * m1 * m1 * values1;
vec3 mmm0 = m0 * m0 * m0;
vec2 mmm1 = m1 * m1 * m1;
float dx = temp0[0] * x0.x + temp0[1] * x1.x + temp0[2] * x2.x + temp1[0] * x3.x + temp1[1] * x4.x + mmm0[0] * p0.x + mmm0[1] * p1.x + mmm0[2] * p2.x + mmm1[0] * p3.x + mmm1[1] * p4.x;
float dy = temp0[0] * x0.y + temp0[1] * x1.y + temp0[2] * x2.y + temp1[0] * x3.y + temp1[1] * x4.y + mmm0[0] * p0.y + mmm0[1] * p1.y + mmm0[2] * p2.y + mmm1[0] * p3.y + mmm1[1] * p4.y;
float dz = temp0[0] * x0.z + temp0[1] * x1.z + temp0[2] * x2.z + temp1[0] * x3.z + temp1[1] * x4.z + mmm0[0] * p0.z + mmm0[1] * p1.z + mmm0[2] * p2.z + mmm1[0] * p3.z + mmm1[1] * p4.z;
float dw = temp0[0] * x0.w + temp0[1] * x1.w + temp0[2] * x2.w + temp1[0] * x3.w + temp1[1] * x4.w + mmm0[0] * p0.w + mmm0[1] * p1.w + mmm0[2] * p2.w + mmm1[0] * p3.w + mmm1[1] * p4.w;
return vec4(dx, dy, dz, dw) * 49.0;
}
float seed(float n) { return fract(sin(n*127.1+311.7)*43758.5453); }
void main() {
    if(qt_TexCoord0.y>1.0/16.0) { fragColor=vec4(0); return; }
    float id=floor(qt_TexCoord0.x*u.count);
    vec3 spawn=vec3(seed(id+1.0)*2.0-1.0,seed(id+41.0)*2.0-1.0,seed(id+83.0)*2.0-1.0);
    if(u.theme>0.5 && u.theme<1.5) {
        float angle=seed(id+1.0)*6.2831853;
        float radius=0.55+seed(id+41.0)*0.50;
        spawn=vec3(cos(angle)*radius,(seed(id+83.0)-0.5)*0.035,sin(angle)*radius);
    }
    vec4 data=texture(previous,vec2((id+0.5)/u.count,0.5/16.0));
    if(u.initialize>0.5) { fragColor=vec4(spawn,5.0+seed(id+9.0)*10.0); return; }
    vec3 p=data.xyz;
    vec3 q=p*1.5;
    vec4 dx=vec4(0),dy=vec4(0),dz=vec4(0);
    // David Li Flow's analytic simplex potential derivatives and curl.
    for(int i=0;i<3;i++) {
        float frequency=exp2(float(i));
        float amplitude=pow(0.5,float(i))*0.5*frequency;
        dx+=simplexNoiseDerivatives(vec4(q*frequency,u.time*0.25))*amplitude;
        dy+=simplexNoiseDerivatives(vec4((q+vec3(123.4,129845.6,-1239.1))*frequency,u.time*0.25))*amplitude;
        dz+=simplexNoiseDerivatives(vec4((q+vec3(-9519.0,9051.0,-123.0))*frequency,u.time*0.25))*amplitude;
    }
    vec3 velocity=vec3(dz.y-dy.z,dx.z-dz.x,dy.x-dx.y)*0.075+vec3(0.04,0,0);
    if(u.theme>0.5 && u.theme<1.5) {
        float r=max(length(p.xz),0.2);
        velocity=velocity*0.16+vec3(-p.z,-p.y*0.8,p.x)*0.22/r-p*0.006;
    }
    if(u.theme>1.5) velocity+=vec3(0.015,0.12,0);
    vec2 cursor=(u.pointer.xy-0.5)/0.45;
    vec2 away=p.xy-cursor;
    float influence=exp(-dot(away,away)*14.0)*u.pointer.z;
    velocity.xy+=(away*1.8+vec2(-away.y,away.x)*3.0)*influence;
    float age=u.time-u.clickPulse.z;
    vec2 burst=p.xy-(u.clickPulse.xy-0.5)/0.45;
    float radius=length(burst);
    float wave=exp(-pow((radius-age*0.65)*12.0,2.0))*exp(-max(age,0.0))*step(0.0,age);
    velocity.xy+=burst/max(radius,0.02)*wave*0.8;
    vec4 obstacles[8]=vec4[8](u.obstacle0,u.obstacle1,u.obstacle2,u.obstacle3,u.obstacle4,u.obstacle5,u.obstacle6,u.obstacle7);
    for(int i=0;i<8;i++) {
        vec4 card=obstacles[i];
        if(card.z<=0.0) continue;
        vec2 relative=p.xy-(card.xy+card.zw*0.5-0.5)/0.45;
        vec2 outside=abs(relative)-card.zw*0.5/0.45;
        float distance=length(max(outside,vec2(0)));
        vec2 normal=normalize(sign(relative)*max(outside,vec2(0))+vec2(0.00001));
        if(max(outside.x,outside.y)<0.0)
            normal=outside.x>outside.y ? vec2(sign(relative.x),0) : vec2(0,sign(relative.y));
        velocity.xy+=normal*exp(-distance*distance*180.0)*0.85;
    }
    p+=velocity*min(u.delta,0.2);
    float lifetime=data.w-u.delta;
    if(lifetime<=0.0 || any(greaterThan(abs(p),vec3(1.2)))) {p=spawn; lifetime=10.0+seed(id+9.0)*5.0;}
    fragColor=vec4(p,lifetime);
}
