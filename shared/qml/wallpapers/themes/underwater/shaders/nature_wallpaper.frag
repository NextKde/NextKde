#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(binding=1) uniform sampler2D scenery;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 viewport;
    float imageAspect;
    float imageReady;
    float time;
    float scene;
    float front;
    float quality;
    vec4 pointer;
    vec4 clickPulse;
    float targetCount;
    vec4 target0; vec4 target1; vec4 target2; vec4 target3;
    vec4 target4; vec4 target5; vec4 target6; vec4 target7;
} u;
float hash(float p) { return fract(sin(p*127.1)*43758.5453); }
float noise(vec2 p) {
    vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    float n=i.x+i.y*57.0;
    return mix(mix(hash(n),hash(n+1.0),f.x),mix(hash(n+57.0),hash(n+58.0),f.x),f.y);
}
float mist(vec2 p) { return noise(p)*0.6+noise(p*2.03)*0.28+noise(p*4.01)*0.12; }
vec4 target(int i) {
    if(i==0)return u.target0; if(i==1)return u.target1;
    if(i==2)return u.target2; if(i==3)return u.target3;
    if(i==4)return u.target4; if(i==5)return u.target5;
    if(i==6)return u.target6; return u.target7;
}
float caustic(vec2 p) {
    // Intersecting warped wave crests, rather than a regular checkerboard.
    p+=vec2(sin(p.y*1.7+u.time*0.4),cos(p.x*1.4-u.time*0.3))*0.65;
    float a=sin(p.x+p.y*0.6+sin(p.y*1.3)+u.time*0.35);
    float b=cos(p.y-p.x*0.7+sin(p.x*1.6)-u.time*0.28);
    return pow(max(0.0,1.0-abs(a+b)*0.9),12.0);
}
void main() {
    vec2 uv=qt_TexCoord0; float aspect=u.viewport.x/max(u.viewport.y,1.0);
    vec3 color=vec3(0.0); float alpha=0.0;
    if(u.front<0.5) {
        // Cover crop preserves the asset proportions on every screen.
        vec2 crop=aspect>u.imageAspect ? vec2(1.0,u.imageAspect/aspect)
            : vec2(aspect/max(u.imageAspect,0.001),1.0);
        vec2 sampleUV=uv;
        if(u.scene<0.5) {
            float age=u.time-u.clickPulse.z;
            vec2 delta=(uv-u.clickPulse.xy)*vec2(aspect,1.0);
            float d=length(delta);
            float ripple=sin(d*75.0-age*9.0)*exp(-pow((d-age*0.14)*16.0,2.0))
                *exp(-max(age,0.0)*1.3)*step(0.0,age);
            sampleUV+=vec2(sin(uv.y*12.0+u.time*0.35),cos(uv.x*10.0-u.time*0.27))*0.0012;
            sampleUV+=delta/max(d,0.001)/vec2(aspect,1.0)*ripple*0.002;
        }
        color=u.imageReady>0.5 ? texture(scenery,clamp((sampleUV-0.5)*crop+0.5,0.0,1.0)).rgb
            : (u.scene<0.5?vec3(0.008,0.08,0.12):vec3(0.008,0.035,0.03));
        if(u.scene<0.5) {
            float light=caustic(uv*vec2(aspect,1.0)*22.0);
            color+=color*vec3(0.08,0.15,0.16)*light*smoothstep(0.4,1.0,uv.y);
        } else {
            float fog=mist(uv*vec2(aspect,1.0)*4.0-vec2(u.time*0.018,0.0));
            color+=vec3(0.012,0.024,0.022)*fog*exp(-pow((uv.y-0.65)*5.0,2.0));
        }
        alpha=1.0;
    }
    int count=u.quality>0.5?(u.scene<0.5?48:72):32;
    for(int i=0;i<72;i++) {
        if(i>=count)break;
        float seed=float(i)*13.71+4.0;
        float cycle=u.time*(u.scene<0.5?0.075:0.045)+hash(seed);
        float life=fract(cycle), depth=0.5+0.5*sin(cycle*6.28318+hash(seed+1.0)*6.28318);
        float nearWeight=smoothstep(0.44,0.56,depth);
        float pass=u.front>0.5?nearWeight:1.0-nearWeight;
        vec2 pos;
        if(u.scene<0.5) pos=vec2(hash(seed+2.0)+sin(u.time*0.6+seed)*0.018,1.12-life*1.28);
        else pos=vec2(hash(seed+2.0)+sin(u.time*0.28+seed)*0.075,
            0.18+hash(seed+3.0)*0.70+sin(u.time*0.41+seed)*0.045);
        // A subset traverses actual widgets, on the same path in both passes.
        if(i<24 && u.targetCount>0.0) {
            vec4 r=target(int(mod(float(i),u.targetCount)));
            if(u.scene<0.5) pos=vec2(r.x+r.z*(0.15+hash(seed)*0.70)+sin(u.time*0.6+seed)*0.012,
                r.y+r.w+0.08-life*(r.w+0.16));
            else pos=r.xy+r.zw*vec2(0.5+sin(u.time*0.35+seed)*0.60,0.5+cos(u.time*0.28+seed)*0.60);
        }
        vec2 mouse=(pos-u.pointer.xy)*vec2(aspect,1.0);
        float proximity=exp(-dot(mouse,mouse)*90.0)*u.pointer.z;
        if(u.scene<0.5) pos+=mouse/vec2(aspect,1.0)*proximity*0.6;
        else {
            // Some fireflies gather in a loose orbit, others gently flee.
            float gather=exp(-dot(mouse,mouse)*8.0)*u.pointer.z;
            float angle=u.time*(0.6+hash(seed)*0.4)+seed;
            vec2 orbit=u.pointer.xy+vec2(cos(angle)/aspect,sin(angle))*mix(0.035,0.09,hash(seed+8.0));
            pos=mix(pos,orbit,gather*(i<16?0.85:0.25));
        }
        float age=u.time-u.clickPulse.z;
        vec2 burst=(pos-u.clickPulse.xy)*vec2(aspect,1.0);
        float impulse=exp(-dot(burst,burst)*18.0)*exp(-max(age,0.0)*0.85)*step(0.0,age);
        pos+=normalize(burst+vec2(0.0001))/vec2(aspect,1.0)*impulse*0.15;
        vec2 delta=(uv-pos)*vec2(aspect,1.0);
        float d=length(delta), size=mix(0.002,0.0065,depth);
        float glow;
        float blink=1.0;
        vec3 tint;
        if(u.scene<0.5) {
            float rim=exp(-pow((d-size)/0.0008,2.0));
            float glint=exp(-dot(delta-vec2(-size*0.4,-size*0.6),delta-vec2(-size*0.4,-size*0.6))/0.000001);
            glow=rim*0.32+glint*0.8; tint=vec3(0.42,0.85,0.90);
        } else {
            blink=0.45+0.55*pow(0.5+0.5*sin(u.time*1.3+seed),3.0);
            glow=(exp(-d*d/(size*size))*1.15+exp(-d*d/(size*size*36.0))*0.16)*blink;
            // A short dim trail makes the direction of flight visible.
            vec2 tail=delta+vec2(cos(u.time*0.28+seed),sin(u.time*0.41+seed))*0.007;
            glow+=exp(-dot(tail,tail)/(size*size*2.0))*0.18*blink;
            glow*=1.0+impulse*1.4;
            tint=mix(vec3(0.52,0.84,0.22),vec3(1.0,0.72,0.22),hash(seed+7.0));
        }
        glow*=pass;
        color+=tint*glow;
        if(u.front>0.5)alpha+=glow;
        // Local light grazes a card edge as a near firefly passes it.
        if(u.front>0.5 && u.scene>0.5 && i<24 && u.targetCount>0.0) {
            vec4 r=target(int(mod(float(i),u.targetCount)));
            vec2 q=abs(uv-(r.xy+r.zw*0.5))-r.zw*0.5+0.008;
            float edge=length(max(q,0.0))+min(max(q.x,q.y),0.0)-0.008;
            float halo=exp(-abs(edge)*180.0)*exp(-dot(delta,delta)*100.0)*blink*pass*0.18;
            halo+=(1.0-smoothstep(-0.006,0.003,edge))*exp(-dot(delta,delta)*220.0)*blink*pass*0.025;
            color+=tint*halo; alpha+=halo;
        }
    }
    if(u.scene<0.5) {
        // A few individually shaded fish, with shared positions in both passes.
        for(int i=0;i<7;i++) {
            float seed=float(i)*27.13+2.0;
            float direction=hash(seed)>0.5?1.0:-1.0;
            float travel=fract(u.time*(0.012+hash(seed+1.0)*0.012)+hash(seed+2.0));
            vec2 pos=vec2(direction>0.0?travel*1.3-0.15:1.15-travel*1.3,
                0.30+hash(seed+3.0)*0.48+sin(u.time*0.4+seed)*0.025);
            float depth=0.5+0.5*sin(u.time*0.5+seed);
            if(i<3 && u.targetCount>0.0) {
                vec4 r=target(int(mod(float(i),u.targetCount)));
                float angle=u.time*0.5+seed;
                vec2 orbit=r.xy+r.zw*vec2(0.5+sin(angle-0.8)*0.68*direction,0.5+cos(angle)*0.32);
                pos=mix(pos,orbit,smoothstep(0.08,0.30,depth));
            }
            vec2 away=(pos-u.pointer.xy)*vec2(aspect,1.0);
            pos+=away/vec2(aspect,1.0)*exp(-dot(away,away)*35.0)*u.pointer.z*0.6;
            float age=u.time-u.clickPulse.z;
            vec2 burst=(pos-u.clickPulse.xy)*vec2(aspect,1.0);
            pos+=burst/vec2(aspect,1.0)*exp(-dot(burst,burst)*18.0)*exp(-max(age,0.0))*step(0.0,age)*0.5;
            float nearWeight=smoothstep(0.44,0.56,depth);
            float pass=u.front>0.5?nearWeight:1.0-nearWeight;
            vec2 q=(uv-pos)*vec2(aspect,1.0)/mix(0.006,0.024,depth);
            q.x*=direction;
            float wag=sin(u.time*5.0+seed);
            q.y+=wag*0.12*smoothstep(0.2,1.5,-q.x);
            float body=1.0-smoothstep(0.94,1.06,length(q/vec2(1.2,0.42)));
            float tail=(1.0-smoothstep(0.0,0.09,abs(q.y)-(-q.x-0.75)*0.6))
                *smoothstep(-1.85,-1.72,q.x)*(1.0-smoothstep(-0.9,-0.78,q.x));
            float fin=(1.0-smoothstep(0.0,0.08,abs(q.x+0.1)-0.45))
                *(1.0-smoothstep(0.32,0.67,abs(q.y)))*0.55;
            float mask=max(body,max(tail,fin))*pass*0.85;
            vec3 scales=mix(vec3(0.04,0.15,0.19),vec3(0.32,0.56,0.58),(1.0-smoothstep(-0.4,0.35,q.y)));
            scales*=0.86+0.14*sin(q.x*32.0+q.y*18.0);
            scales+=vec3(0.20,0.32,0.32)*exp(-pow((q.y+0.13)*10.0,2.0))*body;
            float eye=1.0-smoothstep(0.07,0.11,length(q-vec2(0.78,-0.09)));
            scales=mix(scales,vec3(0.008,0.02,0.024),eye);
            scales=mix(vec3(0.035,0.14,0.18),scales,0.35+depth*0.65);
            if(u.front<0.5) color=mix(color,scales,mask);
            else { color=color*(1.0-mask)+scales*mask; alpha=alpha*(1.0-mask)+mask; }
        }
    }
    if(u.front>0.5 && u.scene>0.5) {
        float age=u.time-u.clickPulse.z;
        float d=length((uv-u.clickPulse.xy)*vec2(aspect,1.0));
        float ring=exp(-pow((d-age*0.12)*160.0,2.0))*exp(-max(age,0.0)*1.8)*step(0.0,age)*0.10;
        color+=vec3(0.65,0.85,0.22)*ring; alpha+=ring;
    }
    if(u.front>0.5 && u.scene<0.5) {
        for(int i=0;i<8;i++) {
            if(float(i)>=u.targetCount)break;
            vec4 r=target(i);
            vec2 q=abs(uv-(r.xy+r.zw*0.5))-r.zw*0.5+0.012;
            float edge=length(max(q,0.0))+min(max(q.x,q.y),0.0)-0.012;
            float inside=1.0-smoothstep(-0.004,0.002,edge);
            float wave=caustic(uv*vec2(aspect,1.0)*22.0);
            float mouseLight=exp(-dot((uv-u.pointer.xy)*vec2(aspect,1.0),(uv-u.pointer.xy)*vec2(aspect,1.0))*40.0)*u.pointer.z;
            float glimmer=inside*wave*0.085+exp(-abs(edge)*220.0)*wave*0.22;
            glimmer+=exp(-abs(edge)*130.0)*mouseLight*0.12;
            color+=vec3(0.32,0.72,0.76)*glimmer; alpha+=glimmer;
        }
    }
    if(u.front>0.5) {
        alpha=clamp(max(alpha,max(color.r,max(color.g,color.b))),0.0,0.95);
        color=min(color,vec3(alpha));
    }
    fragColor=vec4(color,alpha)*u.qt_Opacity;
}
