#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 pointer;
    vec4 clickPulse;
    vec4 blackHoleFrame;
    vec2 viewport;
    float time;
    float front;
    float theme;
    float quality;
    float rain;
    float snow;
    float thunder;
    vec2 wind;
    float targetCount;
    vec4 target0;
    vec4 target1;
    vec4 target2;
    vec4 target3;
    vec4 target4;
    vec4 target5;
    vec4 target6;
    vec4 target7;

} u;
float hash(float x) { return fract(sin(x*127.1+311.7)*43758.5453); }
float segment(vec2 p,vec2 a,vec2 b) {
    vec2 d=b-a;
    return length(p-a-d*clamp(dot(p-a,d)/max(dot(d,d),1e-6),0.0,1.0));
}
vec2 infall(vec2 a,vec2 b,float t) {
    // End tangent follows the same tilted disc as the background camera.
    vec2 tangent=u.blackHoleFrame.zw;
    vec2 c1=a+vec2(0.16,0.18);
    vec2 c2=b-tangent*0.34;
    float v=1.0-t;
    return v*v*v*a+3.0*v*v*t*c1+3.0*v*t*t*c2+t*t*t*b;
}
void main() {
    vec2 aspect=vec2(u.viewport.x/max(u.viewport.y,1.0),1.0);
    vec2 p=qt_TexCoord0*aspect;
    vec2 cursor=u.pointer.xy*aspect;
    vec3 light=vec3(0);
    float opacity=0.0;
    vec4 targets[8]=vec4[8](u.target0,u.target1,u.target2,u.target3,u.target4,u.target5,u.target6,u.target7);
    if(u.theme<0.5) {
        for(int i=0;i<4;i++) {
            if(u.quality<0.5 && i>1) break;
            float id=float(i);
            bool targeted=u.targetCount>0.5 && i<3;
            // Three offset flights cross actual cards. At the default half-speed
            // they enter the card cluster about once every 2.2 wall-clock seconds.
            float clock=targeted ? (u.time+id*1.1)/3.3 : (u.time+id*2.3)/8.5;
            float cycle=floor(clock);
            float progress=fract(clock)*(targeted ? 2.0 : 3.2);
            if(progress>=1.0) continue;
            float seed=cycle*19.0+id*73.0;
            vec2 origin=vec2(hash(seed+2.0)*aspect.x*0.9-0.2,hash(seed+5.0)*0.35-0.1);
            vec2 direction=normalize(vec2(0.85,0.45+hash(seed+7.0)*0.3));
            float travel=1.35;
            if(targeted) {
                int selected=min(7,int(floor(hash(seed+13.0)*u.targetCount)));
                vec4 card=targets[selected];
                vec2 crossing=(card.xy+card.zw*(vec2(0.5)+vec2(hash(seed+17.0)-0.5,hash(seed+23.0)-0.5)*0.3))*aspect;
                travel=clamp(length(card.zw*aspect)*2.0,0.55,1.15);
                origin=crossing-direction*travel*0.46;
            }
            vec2 head=origin+direction*progress*travel;
            vec2 away=head-cursor;
            float pull=exp(-dot(away,away)*25.0)*u.pointer.z;
            head+=vec2(-away.y,away.x)*pull*0.32;
            direction=normalize(direction+vec2(-away.y,away.x)*pull*1.5);
            float near=targeted ? smoothstep(0.04,0.18,progress)*(1.0-smoothstep(0.78,0.98,progress)) : smoothstep(0.25,0.7,progress);
            float depth=u.front>0.5 ? near : 1.0-near;
            float envelope=smoothstep(0.0,0.12,progress)*(1.0-smoothstep(0.78,1.0,progress));
            vec2 d=p-head;
            float along=dot(d,direction);
            float crossDistance=abs(dot(d,vec2(-direction.y,direction.x)));
            float tail=smoothstep(-0.28,-0.015,along)*(1.0-smoothstep(0.0,0.007,along));
            float width=mix(0.0010,0.0028,near);
            float streak=exp(-crossDistance*crossDistance/(width*width))*tail;
            float halo=exp(-crossDistance*crossDistance/(width*width*18.0))*tail*0.12;
            float spark=exp(-dot(d,d)/0.000018)*0.9;
            float a=(streak*0.85+halo+spark)*envelope*depth;
            light+=mix(vec3(0.35,0.65,1.0),vec3(1.0,0.93,0.79),streak)*(a);
            opacity+=a;
        }
    } else if(u.theme>1.5) {
        vec2 hole=u.blackHoleFrame.xy*aspect;
        vec2 discDirection=u.blackHoleFrame.zw;
        vec2 discNormal=vec2(-discDirection.y,discDirection.x);
        for(int i=0;i<12;i++) {
            if(u.quality<0.5 && i>=6) break;
            float id=float(i);
            float clock=u.time*0.24+id*0.137;
            float cycle=floor(clock);
            float life=fract(clock);
            float seed=id*79.0+cycle*23.0;
            vec4 card=vec4(0.03,0.06,0.35,0.32);
            if(u.targetCount>0.5) card=targets[min(7,int(hash(seed+3.0)*u.targetCount))];
            vec2 source=(card.xy+card.zw*vec2(-0.16,0.15+hash(seed+7.0)*0.65))*aspect;
            vec2 destination=hole-discDirection*(0.62+hash(seed+13.0)*0.38)
                +discNormal*(hash(seed+17.0)-0.5)*0.025;
            float progress=life*life*0.85+life*0.15;
            vec2 head=infall(source,destination,progress);
            float previous=max(0.0,life-0.065);
            vec2 tail=infall(source,destination,previous*previous*0.85+previous*0.15);
            vec2 relative=head-cursor;
            float wake=exp(-dot(relative,relative)*28.0)*u.pointer.z;
            vec2 offset=vec2(-relative.y,relative.x)*wake*0.17;
            float age=u.time-u.clickPulse.z;
            vec2 impulse=head-u.clickPulse.xy*aspect;
            float pulse=exp(-dot(impulse,impulse)*36.0)*exp(-max(age,0.0)*2.0)*step(0.0,age);
            offset+=discNormal*pulse*0.035;
            head+=offset; tail+=offset*0.7;
            float near=smoothstep(0.02,0.15,life)*(1.0-smoothstep(0.70,0.93,life));
            float depth=u.front>0.5 ? near : 1.0-near;
            float envelope=smoothstep(0.0,0.08,life)*(1.0-smoothstep(0.86,1.0,life));
            vec2 line=head-tail;
            float along=clamp(dot(p-tail,line)/max(dot(line,line),1e-7),0.0,1.0);
            float distance=segment(p,tail,head);
            float width=mix(0.0011,0.0020,life);
            float streak=exp(-distance*distance/(width*width))*(0.2+0.8*along);
            float glow=exp(-distance*distance/(width*width*24.0))*0.09;
            float a=(streak*0.70+glow)*depth*envelope;
            light+=mix(vec3(1.0,0.40,0.12),vec3(1.0,0.90,0.70),along)*a;
            opacity+=a;
            // A moving light grazes the real rounded card boundary; no full
            // rectangle tint and no permanent halo when the stream has left.
            if(u.front>0.5 && u.targetCount>0.5) {
                vec2 center=(card.xy+card.zw*0.5)*aspect;
                vec2 halfSize=card.zw*aspect*0.5;
                float corner=min(0.018,min(halfSize.x,halfSize.y)*0.3);
                vec2 d=abs(p-center)-halfSize+corner;
                float edge=length(max(d,vec2(0)))+min(max(d.x,d.y),0.0)-corner;
                float rim=exp(-edge*edge/0.000016);
                float proximity=exp(-dot(p-head,p-head)*48.0);
                vec2 normal=normalize((p-center)/max(halfSize,vec2(0.001)));
                float facing=0.25+0.75*max(0.0,dot(normal,normalize(head-center+vec2(0.0001))));
                float illumination=rim*proximity*facing*envelope*near*0.18;
                light+=vec3(1.0,0.59,0.25)*illumination;
                opacity+=illumination;
            }
        }
    } else {
        // Rain and snow both use the same cells on the two depth passes.
        for(int i=0;i<2;i++) {
            float layer=float(i);
            float depth=u.front>0.5 ? (i==1 ? 1.0 : 0.0) : (i==0 ? 1.0 : 0.0);
            float scale=mix(28.0,16.0,layer);
            float drift=u.wind.x*0.26+sin(u.time*0.5)*u.wind.y*0.08;
            vec2 relative=p-cursor;
            float gust=exp(-dot(relative,relative)*30.0)*u.pointer.z;
            vec2 displacement=vec2(drift*u.time+gust*relative.x*0.18,0);
            vec2 q=(p-displacement)*scale;
            q.y-=u.time*(u.snow>0.5 ? 0.7 : 5.0+layer*3.0);
            vec2 cell=floor(q);
            vec2 local=fract(q);
            float random=hash(dot(cell,vec2(17,131))+layer*97.0);
            vec2 center=vec2(0.2+random*0.6,hash(random*71.0)*0.8);
            vec2 v=local-center;
            float slant=drift*2.0+gust*relative.x;
            float rainLine=exp(-pow((v.x-v.y*slant)*100.0,2.0))*smoothstep(-0.35,-0.15,v.y)*(1.0-smoothstep(0.06,0.18,v.y));
            float flake=exp(-dot(v,v)*1200.0);
            float a=(rainLine*u.rain*0.22+flake*u.snow*0.5)*depth*step(0.18,random);
            light+=vec3(0.65,0.82,1.0)*a;
            opacity+=a;
        }
        if(u.front>0.5) {
            // Short wind filaments respond locally to cursor motion.
            float gust=exp(-dot(p-cursor,p-cursor)*22.0)*u.pointer.z;
            float ribbon=sin(p.y*70.0+sin(p.x*6.0-u.time)*2.0-u.time*3.0);
            float windLight=pow(max(0.0,ribbon),32.0)*(u.wind.y*0.03+gust*0.06);
            light+=vec3(0.65,0.85,1.0)*windLight;
            opacity+=windLight;
            // Thunder only for WMO thunderstorm codes. No repeated flash at
            // time zero: static/reduced-motion wallpaper starts with no bolt.
            float stormClock=u.time+3.0;
            float age=mod(stormClock,11.0);
            float strike=floor(stormClock/11.0);
            float flash=(exp(-age*24.0)+0.6*exp(-pow((age-0.18)*35.0,2.0)))*u.thunder;
            if(flash>0.002) {
                float x=(0.15+hash(strike+7.0)*0.65)*aspect.x;
                if(u.targetCount>0.5) {
                    int selected=min(7,int(floor(hash(strike+11.0)*u.targetCount)));
                    vec4 card=targets[selected];
                    x=(card.x+card.z*(0.25+hash(strike+17.0)*0.5))*aspect.x;
                }
                vec2 start=vec2(x,-0.02);
                float distance=10.0;
                for(int j=1;j<=12;j++) {
                    float n=float(j);
                    vec2 end=vec2(x+(hash(strike*31.0+n*5.0)-0.5)*0.17,n*0.063);
                    distance=min(distance,segment(p,start,end));
                    if(j==5 || j==8) distance=min(distance,segment(p,end,end+vec2(0.08,0.10)));
                    start=end;
                }
                float bolt=exp(-distance*distance/0.000004)+0.16*exp(-distance*distance/0.0003);
                float a=flash*(bolt*0.7+0.035);
                light+=vec3(0.78,0.83,1.0)*a;
                opacity+=a;
            }
        }
    }
    // Keep premultiplied output valid when two bright streaks overlap.
    float alpha=clamp(opacity,0.0,0.88);
    fragColor=vec4(min(light,vec3(alpha)),alpha)*u.qt_Opacity;
}
