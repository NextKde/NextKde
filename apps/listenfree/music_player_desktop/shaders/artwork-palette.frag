#version 440
// LX PlayDetail getColorScore weighting; low-chroma rejection follows
// KDE Kirigami ImageColors. See phase-two-motion-reference.md.
// Render ONLY into a 1x1 texture; this is not a full-screen sampling shader.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float dark;
};
layout(binding = 1) uniform sampler2D source;
float hue(vec3 c, float high, float delta) {
    if (delta < 0.0001) return 0.0;
    float h = high == c.r ? (c.g-c.b)/delta : high == c.g ? (c.b-c.r)/delta+2.0 : (c.r-c.g)/delta+4.0;
    return fract(h/6.0+1.0);
}
vec3 hsv(float h, float s, float v) {
    vec3 channels=clamp(abs(fract(vec3(h)+vec3(0.0,2.0/3.0,1.0/3.0))*6.0-3.0)-1.0,0.0,1.0);
    return v*mix(vec3(1.0),channels,s);
}
void main() {
    // Sylvakru's independent 20x20 whole-image arithmetic mean. Keep the
    // existing perceptual palette branch for Now Playing and other modes.
    if (dark < 0.0) {
        vec3 sum = vec3(0.0);
        for (int y=0; y<20; ++y) for (int x=0; x<20; ++x) {
            vec4 pixel=texture(source,(vec2(x,y)+0.5)/20.0);
            sum += pixel.a == 0.0 ? vec3(128.0/255.0) : pixel.rgb / pixel.a;
        }
        fragColor=vec4(sum/400.0,1.0)*qt_Opacity;
        return;
    }
    vec3 colors[12]; float scores[12];
    for (int i=0;i<12;++i) { colors[i]=vec3(0.0); scores[i]=0.0; }
    for (int y=0;y<24;++y) for (int x=0;x<24;++x) {
        vec4 pixel=texture(source,(vec2(x,y)+.5)/24.0);
        float high=max(pixel.r,max(pixel.g,pixel.b));
        float low=min(pixel.r,min(pixel.g,pixel.b));
        float delta=high-low;
        if (pixel.a<.2 || delta<.08 || high<.10) continue;
        float saturation=delta/max(high,.0001), lightness=(high+low)*.5;
        float weight=(.4+saturation*2.2+(1.0-min(1.0,abs(lightness-.5)*1.9))*.85)*pixel.a;
        int bucket=int(fract(hue(pixel.rgb,high,delta)+1.0/24.0)*12.0);
        colors[bucket]+=pixel.rgb*weight; scores[bucket]+=weight;
    }
    int best=0;
    for (int i=1;i<12;++i) if (scores[i]>scores[best]) best=i;
    vec3 result=vec3(mix(.28,.20,dark));
    if (scores[best]>0.0) {
        vec3 color=colors[best]/scores[best];
        float high=max(color.r,max(color.g,color.b)), low=min(color.r,min(color.g,color.b));
        float saturation=clamp((high-low)/max(high,.0001)*1.1,.45,.86);
        result=hsv(hue(color,high,high-low),saturation,mix(.60,.43,dark));
    }
    vec3 linear=pow(result,vec3(2.2));
    linear*=min(1.0,.17/max(.001,dot(linear,vec3(.2126,.7152,.0722))));
    fragColor=vec4(pow(linear,vec3(1.0/2.2)),1.0)*qt_Opacity;
}
