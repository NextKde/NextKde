#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf { mat4 qt_Matrix; float qt_Opacity; float phase; vec2 viewport; float energy; float kind; vec3 bands; };
vec3 rainbow(float t){return .55+.45*cos(6.28318*(t+vec3(0.,.33,.67)));}
void main(){
 vec2 uv=qt_TexCoord0;
 if(kind<.5){
  vec2 d=min(uv,1.-uv)*viewport;
  float edge=min(d.x,d.y);
  // Logical pixel distance: strictly zero beyond 12px, including at corners.
  // Bass, mid and treble are real FFT envelopes, not a free-running oscillator.
  float response=mix(bands.x,bands.y,uv.x)*.6+mix(bands.y,bands.z,uv.y)*.4;
  float extent=4.+8.*response;
  float glow=pow(1.-smoothstep(0.,extent,edge),1.65);
  float rim=exp(-edge/1.2)*response*.35;
  vec3 c=rainbow(uv.x*.32+uv.y*.38+bands.x*.1-bands.z*.12);
  float a=clamp(glow*(.04+.7*response)+rim,0.,.88)*(1.-step(12.,edge))*qt_Opacity;
  fragColor=vec4(c*a,a);
 }else{
  float fog=pow(.5+.5*sin(uv.x*4.3+uv.y*2.+phase),4.)*pow(.5+.5*cos(uv.y*5.-uv.x+phase*.7),3.);
  float line=1.-smoothstep(.0002,.0009,abs(fract(uv.x*.72+uv.y*.41+phase*.015)-.5));
  float a=(fog*.075+line*.035)*qt_Opacity;
  fragColor=vec4(vec3(.85,.89,.96)*a,a);
 }
}
