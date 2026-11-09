#version 440
layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D maskSource;
layout(binding = 3) uniform sampler2D bevelSource;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 surfaceSize;
    vec2 sampleOrigin;
    vec2 sampleAxisX;
    vec2 sampleAxisY;
    float thickness;
    float refractionStrength;
    float blurRadius;
    float tintStrength;
    vec4 tintColor;
    float reflectionStrength;
    float shadowOpacity;
};

vec2 mapScene(vec2 local) {
    return clamp(sampleOrigin + sampleAxisX * local.x + sampleAxisY * local.y, vec2(0), vec2(1));
}
vec4 scene(vec2 local) { return texture(source, mapScene(local)); }
void main() {
    float coverage = texture(maskSource, uv).a;
    vec2 px = 1.0 / surfaceSize;
    // Cast shadow uses the same registered glyph field as the bevel. Keeping
    // it in this pass avoids a second effect's padded source-coordinate space.
    float shadow = texture(bevelSource, uv - vec2(.25, .65) * thickness * px).a
                 * shadowOpacity;
    if (coverage < .001) { fragColor = vec4(0, 0, 0, shadow) * qt_Opacity; return; }
    float field = texture(bevelSource, uv).a;
    // Gradient of a softened glyph, including counters and punctuation. Its
    // normal rounds the real font contour instead of drawing an outline font.
    vec2 gradient = vec2(
        texture(bevelSource, uv + vec2(px.x, 0)).a - texture(bevelSource, uv - vec2(px.x, 0)).a,
        texture(bevelSource, uv + vec2(0, px.y)).a - texture(bevelSource, uv - vec2(0, px.y)).a);
    vec2 slope = -gradient * max(1.0, thickness) * 1.8;
    vec3 normal = normalize(vec3(slope, 1.0));
    float bevel = (1.0 - smoothstep(.54, .98, field)) * smoothstep(0.0, .5, thickness);
    vec2 lens = normal.xy * refractionStrength * px;
    vec2 p = uv - lens;
    vec2 blur = blurRadius * px;
    vec4 bg = scene(p) * .4;
    bg += (scene(p + vec2(blur.x, 0)) + scene(p - vec2(blur.x, 0))
         + scene(p + vec2(0, blur.y)) + scene(p - vec2(0, blur.y))) * .15;
    vec3 rgb = bg.a > .001 ? bg.rgb / bg.a : vec3(0);
    rgb = mix(rgb, tintColor.rgb, tintStrength);
    vec2 edgeNormal = normalize(slope + vec2(.00001));
    float upperLight = max(0.0, dot(edgeNormal, normalize(vec2(-.55, -.83))));
    float lowerShade = max(0.0, dot(edgeNormal, normalize(vec2(.55, .83))));
    // Directional white sheen and a softer opposite rim give a clear bevel,
    // while most of each stroke retains the actual transmitted background.
    float contour = 1.0 - min(min(texture(maskSource, uv + vec2(px.x, 0)).a,
                                 texture(maskSource, uv - vec2(px.x, 0)).a),
                             min(texture(maskSource, uv + vec2(0, px.y)).a,
                                 texture(maskSource, uv - vec2(0, px.y)).a));
    float light = bevel * (.38 * pow(upperLight, 2.0) + .16 * pow(lowerShade, 5.0))
                + contour * (.72 * pow(upperLight, 3.0) + .24 * pow(lowerShade, 5.0));
    rgb *= 1.0 - bevel * lowerShade * .22 * reflectionStrength;
    rgb = mix(rgb, vec3(1), clamp(light * reflectionStrength, 0.0, .85));
    float alpha = coverage * mix(bg.a, 1.0, max(tintStrength, light * reflectionStrength));
    fragColor = vec4(rgb * alpha, alpha + shadow * (1.0 - alpha)) * qt_Opacity;
}
