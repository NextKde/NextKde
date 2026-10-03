#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 viewport;
    float time;
    vec4 pointer;
    vec4 clickPulse;
} u;
layout(binding=1) uniform sampler2D source;
layout(binding=2) uniform sampler2D flowNoise;
const float tau=6.283185307;

// DefaultDiscColor's angular rate u*sqrt(0.5*u), with its original time*8
// scale. Project the light transport onto the reference material, leaving
// the photograph's horizon and large-scale lighting as the geometry guide.
float orbitalRate(float radius) {
    float inverseRadius=1.0/(3.0*max(radius/0.34,1.0));
    return inverseRadius*sqrt(0.5*inverseRadius)*8.0;
}
vec2 transportedLight(vec2 plane,float radiusScale,float clock) {
    float radius=length(plane),angle=atan(plane.y,plane.x);
    float rate=orbitalRate(radius*radiusScale);
    float turn=(angle-rate*clock)/tau;
    // Integral azimuth frequencies make the polar seam continuous.
    float coarse=texture(flowNoise,fract(vec2(radius*19.0,turn*12.0))).r;
    float fine=texture(flowNoise,fract(vec2(radius*43.0+0.31,turn*28.0+0.17))).r;
    float thread=sin(radius*240.0+coarse*5.0+fine*2.0)*0.5+0.5;
    float density=coarse*0.58+fine*0.30+thread*0.12;
    // Moving luminous packets embedded in the filaments, not isolated rings.
    float packet=smoothstep(0.65,0.88,coarse)*smoothstep(0.35,0.8,fine);
    return vec2(density,packet);
}
void main() {
    float aspect=u.viewport.x/max(u.viewport.y,1.0);
    const float imageAspect=1.5;
    vec2 crop=aspect>imageAspect ? vec2(1.0,imageAspect/aspect) : vec2(aspect/imageAspect,1.0);
    vec2 uv=(qt_TexCoord0-0.5)*crop+0.5;
    vec2 hole=(uv-vec2(0.85,0.36))*vec2(imageAspect,1.0);
    float radius=length(hole);
    vec2 tangent=normalize(vec2(imageAspect,-0.43));
    vec2 normal=vec2(-tangent.y,tangent.x);
    float disk=exp(-pow((uv.y-(0.80-uv.x*0.43))/0.115,2.0));
    float arc=exp(-pow((radius-0.375)/0.085,2.0));
    float material=max(disk,arc)*smoothstep(0.30,0.34,radius);
    vec3 original=texture(source,uv).rgb;
    float luminance=dot(original,vec3(0.2126,0.7152,0.0722));
    float luminous=smoothstep(0.04,0.35,luminance);
    vec3 color=original;
    if(material*luminous>0.015) {
        vec2 discOffset=(uv-vec2(0.85,0.4345))*vec2(imageAspect,1.0);
        vec2 discPlane=vec2(dot(discOffset,tangent),dot(discOffset,normal)/0.22);
        vec2 relative=(qt_TexCoord0-u.pointer.xy)*vec2(aspect,1.0);
        float influence=exp(-dot(relative,relative)*40.0)*u.pointer.z;
        float age=u.time-u.clickPulse.z;
        vec2 burst=(qt_TexCoord0-u.clickPulse.xy)*vec2(aspect,1.0);
        float distance=length(burst);
        float pulse=exp(-pow((distance-age*0.22)*50.0,2.0))*exp(-max(age,0.0)*1.5)*step(0.0,age);
        // Mouse input bends the moving light field, rather than the horizon.
        vec2 bend=vec2(-relative.y,relative.x)*influence*0.06
            +burst/max(distance,0.001)*pulse*0.015;
        vec2 discLight=transportedLight(discPlane+bend,0.65,u.time);
        vec2 ringLight=transportedLight(hole+bend,1.0,u.time-0.32);
        float ringWeight=arc/(disk+arc+0.0001);
        vec2 light=mix(discLight,ringLight,ringWeight);
        // Original warm/white colour and silhouette remain; grain flows in
        // one direction, with brighter and faster inner orbits.
        float strength=material*luminous;
        float core=1.0-smoothstep(0.65,0.95,luminance);
        color*=1.0+(light.x-0.5)*0.85*strength*mix(0.35,1.0,core);
        color+=original*light.y*strength*0.28;
        vec2 displacement=(tangent*(light.x-0.5)*0.0018
            +normal*(light.y-0.12)*0.0007)*strength;
        vec3 detail=texture(source,clamp(uv+displacement,vec2(0.001),vec2(0.999))).rgb;
        color+=(detail-original)*0.45;
    }
    fragColor=vec4(color,1.0)*u.qt_Opacity;
}
