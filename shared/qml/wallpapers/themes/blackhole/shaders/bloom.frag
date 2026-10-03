#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(binding=1) uniform sampler2D source;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 pixel;
    float strength;
    vec4 horizon;
} u;
vec3 bright(vec2 p) {
    vec3 c=texture(source,p).rgb;
    return c*max(0.0,max(c.r,max(c.g,c.b))-0.60)*2.0;
}
void main() {
    vec3 base=texture(source,qt_TexCoord0).rgb;
    vec3 halo=bright(qt_TexCoord0)*0.16;
    for(int i=0;i<12;i++) {
        float a=float(i)*0.5235987756;
        vec2 d=vec2(cos(a),sin(a))*u.pixel;
        halo+=bright(qt_TexCoord0+d*9.0)*0.025;
        halo+=bright(qt_TexCoord0+d*27.0)*0.020;
        halo+=bright(qt_TexCoord0+d*65.0)*0.012;
    }
    if(u.horizon.w>0.5) {
        vec2 aspect=vec2(u.pixel.y/u.pixel.x,1.0);
        vec2 relative=(qt_TexCoord0-u.horizon.xy)*aspect;
        float radius=length(relative);
        vec2 normal=relative/max(radius,0.00001);
        float edge=radius-u.horizon.z;
        // Expand only light already present in the traced inner image. No
        // independent white circle; the dark interior remains unobscured.
        float lower=smoothstep(-0.10,0.18,normal.y);
        float width=mix(0.0012,0.0085,lower);
        if(edge>-0.002 && edge<0.05) {
            vec3 expanded=vec3(0);
            for(int j=1;j<=16;j++) {
                float distance=float(j)*u.pixel.y;
                vec2 at=qt_TexCoord0-normal*distance/aspect;
                vec3 emission=texture(source,at).rgb;
                float radiant=max(emission.r,max(emission.g,emission.b));
                vec3 inside=texture(source,at-normal*0.003/aspect).rgb;
                vec3 outside=texture(source,at+normal*0.003/aspect).rgb;
                float background=max(max(inside.r,max(inside.g,inside.b)),max(outside.r,max(outside.g,outside.b)));
                // A thin radial peak is the inner ring; broad disc emission
                // should not be dragged across the joining area by this filter.
                float peak=smoothstep(0.035,0.20,radiant-background);
                float energy=smoothstep(0.10,0.35,radiant)*peak;
                float profile=exp(-distance*distance/(width*width))*0.85
                    +exp(-distance*distance/0.0004)*0.08;
                float filaments=0.88+0.12*sin(distance*2600.0);
                expanded=max(expanded,emission*energy*profile*filaments);
            }
            base+=expanded*lower*smoothstep(-0.0006,0.001,edge)*(1.0-smoothstep(0.035,0.05,edge));
        }
    }
    float alpha=texture(source,qt_TexCoord0).a;
    // Preserve transparency when this is the traced near-disc overlay.
    float glowAlpha=max(halo.r,max(halo.g,halo.b))*u.strength;
    fragColor=vec4(base+halo*u.strength,min(1.0,alpha+glowAlpha))*u.qt_Opacity;
}
