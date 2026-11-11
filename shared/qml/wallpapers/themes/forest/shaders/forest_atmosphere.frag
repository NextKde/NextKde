#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 viewport;
    float time;
    float quality;
};
float hash(float p) { return fract(sin(p*127.1)*43758.5453); }
float noise(vec2 p) {
    vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    float n=i.x+i.y*57.0;
    return mix(mix(hash(n),hash(n+1.0),f.x),mix(hash(n+57.0),hash(n+58.0),f.x),f.y);
}
float mist(vec2 p) {
    return noise(p)*0.57+noise(p*2.03+7.1)*0.28+noise(p*4.11+19.3)*0.15;
}
float trees(vec2 p,float layer) {
    float scale=12.0-layer*2.0;
    float cell=floor(p.x*scale), local=fract(p.x*scale)-0.5;
    float seed=hash(cell+layer*73.0);
    float center=(cell+0.5)/scale;
    // A stepped clearing exposes the moon; tall foreground firs frame its sides.
    float clearing=exp(-pow((center-0.25)*2.8,2.0));
    float top=0.08+seed*0.23-layer*0.09+clearing*(0.22+layer*0.10);
    float down=clamp((p.y-top)/max(0.73-top,0.08),0.0,1.0);
    float trunk=0.008+down*0.020;
    float branch=pow(down,0.75)*(0.31+seed*0.17);
    branch*=0.48+0.52*pow(0.5+0.5*sin(down*(38.0+seed*17.0)+seed*8.0),0.7);
    branch*=0.83+0.17*noise(vec2(p.y*110.0,cell));
    float sway=sin(time*0.17+seed*6.0)*0.009*(1.0-down);
    float edge=max(trunk,branch)-abs(local+sway+sin(p.y*7.0+seed*6.0)*down*0.025);
    float aa=max(fwidth(local),0.001);
    return smoothstep(-aa,aa,edge)*smoothstep(top-0.005,top+0.01,p.y);
}
vec3 woodland(vec2 p) {
    vec2 moon=p-vec2(0.25,0.19);
    float distance=length(moon);
    vec3 color=mix(vec3(0.007,0.016,0.043),vec3(0.09,0.22,0.25),smoothstep(0.05,0.75,p.y));
    color+=vec3(0.13,0.26,0.34)*exp(-distance*distance*9.0);
    float disc=1.0-smoothstep(0.038,0.040,distance);
    float crater=0.82+0.18*mist(moon*170.0);
    color+=vec3(0.65,0.81,0.86)*(disc*crater+exp(-distance*55.0)*0.22);
    for(int i=0;i<4;i++) {
        if(quality<0.5 && i==1) continue;
        float layer=float(i);
        vec2 forest=p+vec2(0.0,0.025*(3.0-layer));
        float silhouette=trees(forest,layer);
        vec3 tint=mix(vec3(0.070,0.16,0.19),vec3(0.003,0.018,0.024),layer/3.0);
        color=mix(color,tint,silhouette*(0.76+layer*0.08));
        float fog=mist(vec2(p.x*3.5+layer*9.0-time*(0.012+layer*0.005),p.y*8.0));
        float bank=exp(-pow((p.y-0.61-layer*0.025)*14.0,2.0));
        color=mix(color,vec3(0.17,0.31,0.34),fog*bank*0.27);
    }
    float fan=(p.x-0.25)/(p.y+0.12);
    float shafts=pow(max(0.0,sin(fan*18.0+sin(fan*7.0+time*0.08))),12.0);
    float clearing=exp(-pow((p.x-0.25)*2.4,2.0));
    color+=vec3(0.14,0.26,0.27)*shafts*clearing*smoothstep(0.22,0.52,p.y)*0.20;
    return color;
}
void main() {
    vec2 uv=qt_TexCoord0;
    float aspect=max(viewport.x,1.0)/max(viewport.y,1.0);
    vec2 p=vec2((uv.x-0.5)*aspect,uv.y);
    const float shore=0.73;
    vec3 color;
    if(p.y>shore) {
        float depth=(p.y-shore)/(1.0-shore);
        float ripple=sin(p.y*180.0-time*1.4+noise(p*14.0)*4.0);
        vec2 reflected=vec2(p.x+ripple*(0.001+depth*0.009),shore-(p.y-shore)*1.95);
        color=woodland(reflected)*vec3(0.42,0.61,0.68);
        float wake=pow(0.5+0.5*sin(p.y*230.0-time*1.3+sin(p.x*25.0)),14.0);
        float moonPath=exp(-pow((p.x-0.25)/(0.035+depth*0.24),2.0));
        color+=vec3(0.32,0.59,0.57)*wake*moonPath*(0.12+depth*0.16);
    } else color=woodland(p);
    // Uneven banks leave an open mirror of water beneath the clearing.
    float bank=1.02-0.19*smoothstep(0.2,1.0,abs(p.x-0.15))+noise(vec2(p.x*5.0,3.0))*0.035;
    color=mix(color,vec3(0.003,0.015,0.019),smoothstep(bank-0.006,bank+0.006,p.y));
    float vignette=1.0-0.34*smoothstep(0.25,1.1,length((uv-0.5)*vec2(1.1,0.8)));
    color=pow(max(color,vec3(0.0)),vec3(0.87))*vignette;
    fragColor=vec4(color,1.0)*qt_Opacity;
}
