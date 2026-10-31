#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D source;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 surfaceSize;
    vec2 sampleOrigin;
    vec2 sampleAxisX;
    vec2 sampleAxisY;
    float radius;
    vec4 tintColor;
    float tintStrength;
    float blurRadius;
    float readability;
    float lightAppearance;
    float refractionStrength;
    float magnification;
    float edgeWidth;
    float diffuseStrength;
    float materialOpacity;
    float arrowHeight;
    float arrowWidth;
    float arrowX;
    float arrowOnBottom;
    float highlightStrength;
    vec2 lightDirection;

};

// Closest boundary of the same quadratic body + arrow path used by QML.
// Clockwise screen-space path: its right-facing normal points outwards.
void segment(vec2 p, vec2 a, vec2 b, inout float best, inout vec2 normal, inout float side)
{
    vec2 v = b-a;
    float len2 = dot(v,v);
    if (len2 < 0.000001) return;
    float t = clamp(dot(p-a,v)/len2, 0.0, 1.0);
    vec2 delta = p-(a+t*v);
    float d = dot(delta,delta);
    if (d < best) {
        best = d;
        normal = normalize(vec2(v.y,-v.x));
        side = dot(delta,normal);
    }
}
void curve(vec2 p, vec2 a, vec2 control, vec2 b,
           inout float best, inout vec2 normal, inout float side)
{
    vec2 previous = a;
    for (int i=1; i<=16; ++i) {
        float t = float(i)/16.0;
        vec2 current = mix(mix(a,control,t),mix(control,b,t),t);
        segment(p,previous,current,best,normal,side);
        previous = current;
    }
}
float contourDistance(vec2 p, out vec2 normal)
{
    float w=surfaceSize.x, h=surfaceSize.y;
    float top=arrowOnBottom>0.5 ? 0.0 : arrowHeight;
    float bottom=arrowOnBottom>0.5 ? h-arrowHeight : h;
    float r=clamp(radius,0.0,min(w*0.5,(bottom-top)*0.5));
    float x=clamp(arrowX,r+arrowWidth*0.5,w-r-arrowWidth*0.5);
    float halfArrow=arrowWidth*0.5;
    float best=1e20, side=0.0;
    normal=vec2(0.0,-1.0);
    if (arrowOnBottom<0.5) {
        segment(p,vec2(r,top),vec2(x-halfArrow,top),best,normal,side);
        segment(p,vec2(x-halfArrow,top),vec2(x,0),best,normal,side);
        segment(p,vec2(x,0),vec2(x+halfArrow,top),best,normal,side);
        segment(p,vec2(x+halfArrow,top),vec2(w-r,top),best,normal,side);
    } else segment(p,vec2(r,top),vec2(w-r,top),best,normal,side);
    curve(p,vec2(w-r,top),vec2(w,top),vec2(w,top+r),best,normal,side);
    segment(p,vec2(w,top+r),vec2(w,bottom-r),best,normal,side);
    curve(p,vec2(w,bottom-r),vec2(w,bottom),vec2(w-r,bottom),best,normal,side);
    if (arrowOnBottom>0.5) {
        segment(p,vec2(w-r,bottom),vec2(x+halfArrow,bottom),best,normal,side);
        segment(p,vec2(x+halfArrow,bottom),vec2(x,h),best,normal,side);
        segment(p,vec2(x,h),vec2(x-halfArrow,bottom),best,normal,side);
        segment(p,vec2(x-halfArrow,bottom),vec2(r,bottom),best,normal,side);
    } else segment(p,vec2(w-r,bottom),vec2(r,bottom),best,normal,side);
    curve(p,vec2(r,bottom),vec2(0,bottom),vec2(0,bottom-r),best,normal,side);
    segment(p,vec2(0,bottom-r),vec2(0,top+r),best,normal,side);
    curve(p,vec2(0,top+r),vec2(0,top),vec2(r,top),best,normal,side);
    return sqrt(best)*(side>0.0 ? 1.0 : -1.0);
}

vec2 sourceUv(vec2 localUv)
{
    return sampleOrigin + sampleAxisX * localUv.x + sampleAxisY * localUv.y;
}

vec4 blur9(vec2 uv, vec2 dx, vec2 dy)
{
    vec4 color = texture(source, uv) * 0.25;
    color += (texture(source, uv + dx) + texture(source, uv - dx)
        + texture(source, uv + dy) + texture(source, uv - dy)) * 0.125;
    color += (texture(source, uv + dx + dy) + texture(source, uv - dx - dy)
        + texture(source, uv + dx - dy) + texture(source, uv - dx + dy)) * 0.0625;
    return color;
}

void main()
{
    vec2 normal;
    float distance = contourDistance(qt_TexCoord0 * surfaceSize, normal);
    float shape = 1.0 - smoothstep(-max(fwidth(distance), 0.0001), 0.0, distance);
    float edge = 1.0 - clamp(-distance / max(1.0, edgeWidth), 0.0, 1.0);

    // Warp the actual source coordinates, not a painted colour gradient.
    vec2 localUv = 0.5 + (qt_TexCoord0 - 0.5) / max(1.0, magnification);
    localUv -= normal * max(0.0, refractionStrength) * edge * edge / surfaceSize;
    vec2 dx = sampleAxisX * max(0.0, blurRadius) / surfaceSize.x;
    vec2 dy = sampleAxisY * max(0.0, blurRadius) / surfaceSize.y;
    vec4 sampled = blur9(sourceUv(localUv), dx, dy);

    // Both textures and QColor uniforms arrive premultiplied. Preserve alpha
    // when sampling sparse content such as the slider track.
    vec4 glass = mix(sampled, tintColor, clamp(tintStrength, 0.0, 1.0));
    vec3 rgb = glass.rgb / max(glass.a, 0.0001);
    float luminance = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
    float contrastRisk = mix(luminance, 1.0 - luminance, lightAppearance);
    float scrim = clamp(readability, 0.0, 0.85) * smoothstep(0.08, 0.92, contrastRisk);
    rgb = mix(rgb, vec3(lightAppearance), scrim);
    // Thin specular bevel follows the true boundary normal, including the arrow.
    // Direction is supplied in local coordinates so flipping a popup keeps the light fixed.
    float facing = max(dot(normal, normalize(lightDirection)), 0.0);
    float rim = exp(-max(0.0,-distance)/1.25);
    float glint = rim * (0.12 + 0.88 * pow(facing, 2.0));
    rgb = mix(rgb, vec3(1.0), clamp(glint * highlightStrength, 0.0, 1.0));
    // Composite the glass layer over the softened underlay, not the sharp page.
    // Opacity controls that layer; tintStrength controls its independent colour.
    vec4 underlay = blur9(sourceUv(qt_TexCoord0), dx, dy);
    vec4 composed = mix(underlay, vec4(rgb * glass.a, glass.a),
                        clamp(materialOpacity, 0.0, 1.0));
    fragColor = composed * shape * qt_Opacity;
}
