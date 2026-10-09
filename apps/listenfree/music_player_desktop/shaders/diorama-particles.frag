#version 440
layout(location=0) in vec2 uv;
layout(location=1) in vec4 ink;
layout(location=0) out vec4 fragColor;
void main(){
    float r=length(uv);
    float core=1.0-smoothstep(.14,.42,r);
    float halo=exp(-r*r*5.5)*.24*(1.0-smoothstep(.8,1.0,r));
    float alpha=ink.a*(core*.85+halo);
    fragColor=vec4(ink.rgb*alpha,alpha);
}
