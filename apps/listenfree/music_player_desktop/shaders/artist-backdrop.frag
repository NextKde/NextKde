#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float sidebarFraction;
    float heroFraction;
    float scrollFraction;
    float collapse;
    float fieldOnly;
};
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D blurredSource;
layout(binding = 3) uniform sampler2D boundsSource;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
    vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void main() {
    // One cached texel stores content bounds. Ignore sparse specks in black
    // padding; wholly dark artwork keeps its original extent and palette.
    if(fieldOnly>1.5 && fieldOnly<2.5) {
        vec2 low=vec2(32),high=vec2(-1);
        for(int y=0;y<32;++y) {
            int rowCount=0,colCount=0;
            for(int x=0;x<32;++x) {
                vec4 row=texture(source,(vec2(x,y)+.5)/32.0);
                vec4 col=texture(source,(vec2(y,x)+.5)/32.0);
                if(max(row.r,max(row.g,row.b))>.094 && row.a>.5)++rowCount;
                if(max(col.r,max(col.g,col.b))>.094 && col.a>.5)++colCount;
            }
            if(rowCount>=3){low.y=min(low.y,float(y));high.y=max(high.y,float(y));}
            if(colCount>=3){low.x=min(low.x,float(y));high.x=max(high.x,float(y));}
        }
        vec2 span=high-low+1.0;
        if(min(span.x,span.y)<6.0) {fragColor=vec4(0,0,1,1);return;}
        // Require meaningful padding; trim one extra sample to keep the blur
        // from pulling the black fringe back into the background field.
        vec2 inset=step(vec2(2),low)+step(vec2(2),vec2(31)-high);
        low=mix(vec2(0),low+.5,step(vec2(.5),inset));
        high=mix(vec2(32),high+.5,step(vec2(.5),inset));
        fragColor=vec4(low/32.0,(high-low)/32.0);return;
    }
    if(fieldOnly>2.5) {
        vec4 bounds=texture(boundsSource,vec2(.5));
        fragColor=texture(source,bounds.xy+qt_TexCoord0*bounds.zw)*qt_Opacity;return;
    }
    vec2 scene = qt_TexCoord0;
    vec2 p = vec2((scene.x-sidebarFraction)/max(.01,1.0-sidebarFraction),
                  (scene.y+scrollFraction)/max(.01,heroFraction));
    // Preserve the complete photo. Only the separately blurred field warps
    // broad edge bands; domain distortion breaks up long, aligned silhouettes.
    vec2 uv=clamp(p,vec2(0),vec2(1));
    if(fieldOnly>.5) {
        vec2 domain=scene*3.4;
        domain+=vec2(noise(domain+vec2(3.7,8.1)),noise(domain+vec2(17.3,2.9)))*2.8;
        float n=noise(domain),m=noise(domain+vec2(13.7,8.1));
        float leftExtent=1.0-smoothstep(-.12,.055,p.x);
        float lowerExtent=smoothstep(.75,1.3,p.y);
        if(p.x<.055) {
            uv.x=mix(uv.x,.02+.18*n,leftExtent);
            uv.y=clamp(uv.y+leftExtent*.9*(m-.5),0.0,1.0);
        }
        if(p.y>.75) {
            uv.y=mix(uv.y,.80+.18*m,lowerExtent);
            uv.x=clamp(uv.x+lowerExtent*1.25*(n-.5),0.0,1.0);
        }
        fragColor=texture(source,uv)*qt_Opacity;return;
    }
    vec4 sharp=texture(source,uv);
    float left=1.0-smoothstep(0.0,.055,p.x);
    float lower=smoothstep(.78,1.0,p.y);
    float softness=max(max(left,lower),smoothstep(.85,1.0,collapse)*.96);
    vec4 color=mix(sharp,texture(blurredSource,scene),softness);
    // Broad tonal shading keeps controls legible without a panel seam.
    float shade=.04+lower*.24+left*.12+collapse*.05;
    color.rgb*=1.0-shade;
    fragColor=color*qt_Opacity;
}
