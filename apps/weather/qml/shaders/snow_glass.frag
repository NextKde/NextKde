#version 440
layout(location=0) in vec2 uv;
layout(location=0) out vec4 fragColor;
layout(binding=1) uniform sampler2D source;
layout(binding=2) uniform sampler2D maskSource;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 surfaceSize;
    float clock;
    float wind;
    float density;
};
float hash(vec2 p) {
    return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);
}
float noise(vec2 p) {
    vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
float snowfall(vec2 px,float layer) {
    float cell=mix(32.0,154.0,layer);
    float speed=mix(15.0,66.0,layer);
    vec2 motion=vec2(wind*mix(.3,1.0,layer)*clock+sin(clock*.43+layer*8.0)*mix(3.0,18.0,layer),speed*clock);
    vec2 p=(px-motion)/cell;
    vec2 id=floor(p)+layer*91.0;
    float seed=hash(id);
    vec2 center=vec2(.22+.56*seed,.22+.56*hash(id+11.0));
    center.x+=.055*sin(clock*(.35+seed*.3)+seed*35.0);
    vec2 d=(fract(p)-center)*cell;
    // Airborne flakes have distinct focus planes, small clusters and short streaks.
    d.x+=d.y*wind/200.0;
    float radius=mix(.75,7.0,layer)*(.6+.8*hash(id+4.0));
    vec2 q=d/vec2(radius,radius*mix(1.65,1.1,layer));
    float soft=exp(-dot(q,q)*mix(2.0,.85,layer));
    vec2 lobe=q-vec2(.6,-.3);
    soft=max(soft,.5*exp(-dot(lobe,lobe)*2.0));
    float focus=mix(.32,.17,layer);
    return soft*focus*(.5+.5*seed)*step(seed,.4+.5*density);
}
void main() {
    vec3 plain=texture(source,uv).rgb;
    float mask=texture(maskSource,uv).r;
    if(mask<.01) { fragColor=vec4(plain,1)*qt_Opacity; return; }
    vec2 px=uv*surfaceSize;
    float airborne=snowfall(px,0.0)+snowfall(px,.48)+snowfall(px,1.0);
    vec3 scene=mix(plain,vec3(.86,.91,.96),clamp(airborne,0.0,.65));

    // Sparse wet clumps sit on the glass, soften, then melt into a small lens.
    // Their positions are stable; only melt and slow downward creep evolve.
    vec2 grid=px/112.0;
    vec2 id=floor(grid);
    float seed=hash(id+43.0);
    vec2 center=vec2(.24+.5*hash(id+19.0),.24+.48*hash(id+91.0));
    float phase=fract(clock/(28.0+seed*25.0)+hash(id+5.0));
    float life=smoothstep(0.0,.09,phase)*(1.0-smoothstep(.82,1.0,phase));
    float melt=smoothstep(.18,.75,phase);
    vec2 d=(fract(grid)-center)*112.0;
    d.y-=smoothstep(.65,1.0,phase)*9.0;
    float size=5.0+7.0*hash(id+8.0);
    vec2 q=d/vec2(size,size*(1.0+.3*melt));
    float n=noise(q*5.0+id*7.0);
    float boundary=length(q)+.22*(n-.5)+.09*sin(atan(q.y,q.x)*7.0+seed*20.0);
    float clump=(1.0-smoothstep(.58,1.05,boundary))*life*step(seed,.43);
    float water=(1.0-smoothstep(.7,1.08,length(q)))*life*step(seed,.43)*melt;
    if(clump+water>.005) {
        vec2 shift=q*(1.0-clamp(length(q),0.0,1.0))*3.5;
        vec2 refracted=uv+shift/surfaceSize;
        vec2 spread=vec2(1.8)/surfaceSize;
        vec3 refract=texture(source,refracted).rgb*.5
            +(texture(source,refracted+spread).rgb+texture(source,refracted-spread).rgb)*.25;
        scene=mix(scene,refract,water*.8);
        float ice=clump*(1.0-.78*melt)*(.12+.45*n);
        scene=mix(scene,vec3(.88,.93,.96),ice);
        // Broken crystalline detail and a restrained wet rim, without white discs.
        float crystals=smoothstep(.52,.82,noise(q*17.0+id*5.0))*clump*(1.0-melt);
        scene+=vec3(.09,.10,.11)*crystals;
        float rim=exp(-pow((length(q)-.83)*13.0,2.0));
        float top=max(0.0,dot(normalize(q+vec2(.001)),normalize(vec2(-.5,-1.0))));
        scene+=vec3(.13,.16,.18)*rim*top*water;
        scene*=1.0-water*.035*max(0.0,q.y);
    }
    fragColor=vec4(mix(plain,scene,mask),1.0)*qt_Opacity;
}
