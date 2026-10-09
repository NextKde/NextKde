#version 440
layout(location=0) in vec2 bounds;
layout(location=1) in vec3 offset;
layout(location=2) in vec3 anchor;
layout(location=3) in vec2 style;
layout(location=0) out vec2 uv;
layout(location=1) out vec4 ink;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    mat4 camera;
    vec4 viewport; // width, height, focal length, playback seconds
    vec4 controls; // audio energy, motion enabled, focus distance, Qt opacity
    vec4 accent;
    vec4 focusRect; // projected reading plane and its half extents
} ub;
void main(){
    float time=ub.viewport.w*ub.controls.y;
    float energy=ub.controls.x*ub.controls.y;
    float angle=sin(time*.13+style.x)*.22*ub.controls.y;
    vec3 p=vec3(offset.x*cos(angle)+offset.z*sin(angle),offset.y,-offset.x*sin(angle)+offset.z*cos(angle));
    // One continuous displacement field per welded surface, not random
    // per-particle scatter. Geometry breathes; the camera stays independent.
    float ripple=sin(dot(offset,vec3(2.2,1.7,1.3))-time*1.7+style.x);
    p*=1.0+energy*(.10+.055*ripple);
    vec3 view=(ub.camera*vec4(anchor+p,1.0)).xyz;
    float z=max(.25,view.z);
    float fade=smoothstep(.9,2.8,view.z)*(1.0-smoothstep(23.0,35.0,view.z));
    vec2 center=ub.viewport.xy*vec2(.5,.47)+view.xy*ub.viewport.z/z;
    uv=bounds/ub.viewport.xy*2.0-1.0;
    float core=clamp(9.0/z,.48,1.65)*(ub.viewport.z/768.0);
    float haze=clamp(abs(z-ub.controls.z)*.025,0.0,.55);
    vec2 pixel=center+uv*core*(2.8+haze);
    gl_Position=ub.qt_Matrix*vec4(pixel,0.0,1.0);
    float tint=clamp(style.y*.65+.30+.25*sin(offset.y*1.8-time*.55+style.x),0.0,1.0);
    vec3 color=mix(vec3(.95,.94,.93),ub.accent.rgb,tint);
    float pulse=.68+.23*energy+.09*sin(offset.y*2.0-time*1.1+style.x);
    vec2 reading=abs(center-ub.focusRect.xy)/ub.focusRect.zw;
    float clearance=1.0-smoothstep(.85,1.3,max(reading.x,reading.y));
    ink=vec4(color,fade*pulse*(1.0-clearance*.90)*ub.controls.w);
}
