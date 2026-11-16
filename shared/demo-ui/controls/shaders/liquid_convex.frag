#version 440
// Native derivation; visual/model reference mkj0kjay/vue-web-liquid-glass@934404c.
// See NOTICE.md; no Vue or displacement-map code is embedded.

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
};

float roundedDistance(vec2 p, vec2 halfSize, float r)
{
    vec2 q = abs(p) - halfSize + vec2(r);
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

vec2 roundedNormal(vec2 p, vec2 halfSize, float r)
{
    vec2 q = abs(p) - halfSize + vec2(r);
    vec2 corner = max(q, vec2(0.0));
    if (dot(corner, corner) > 0.0001)
        return normalize(corner) * sign(p);
    return q.x > q.y ? vec2(sign(p.x), 0.0) : vec2(0.0, sign(p.y));
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
    vec2 halfSize = surfaceSize * 0.5;
    float r = clamp(radius, 0.0, min(halfSize.x, halfSize.y));
    vec2 p = (qt_TexCoord0 - 0.5) * surfaceSize;
    float distance = roundedDistance(p, halfSize, r);
    float shape = 1.0 - smoothstep(-max(fwidth(distance), 0.0001), 0.0, distance);
    float edge = 1.0 - clamp(-distance / max(1.0, edgeWidth), 0.0, 1.0);
    vec2 normal = roundedNormal(p, halfSize, r);

    // Convex fourth-order bezel: height is flat at its inner boundary.
    // Refraction is confined to the bezel, leaving central texels unchanged.
    float bezel = min(max(1.0, edgeWidth), min(halfSize.x, halfSize.y) * .72);
    float t = clamp(max(0.0, -distance) / bezel, .0001, 1.0);
    float u = 1.0 - t;
    float cap = max(.0001, 1.0 - u * u * u * u);
    float height = pow(cap, .25);
    float slope = u * u * u / pow(cap, .75);
    vec3 surfaceNormal = normalize(vec3(normal * slope, 1.0));
    vec3 ray = refract(vec3(0.0, 0.0, -1.0), surfaceNormal, 1.0 / 1.5);
    float strength = max(0.0, refractionStrength);
    float travel = strength * 2.4 + height * bezel * min(1.0, strength / 3.0);
    vec2 deviation = ray.xy / max(.05, -ray.z) * travel;
    // magnification changes the edge lens only; no whole-plane translation/zoom.
    deviation *= 1.0 + max(0.0, magnification - 1.0) * 3.0;
    vec2 localUv = qt_TexCoord0 + deviation / surfaceSize;
    // Only the curved bezel needs an antialias footprint after displacement.
    // Cap it at one logical pixel; leave the centre and strength-zero identity
    // untouched instead of restoring a blur across the complete input surface.
    float footprint = length(fwidth(localUv) * surfaceSize) * .5;
    float bezelFilter = min(1.0, footprint) * (1.0 - smoothstep(.60, 1.0, t))
        * smoothstep(0.0, .5, strength);
    float filterRadius = max(max(0.0, blurRadius), bezelFilter);
    vec2 dx = sampleAxisX * filterRadius / surfaceSize.x;
    vec2 dy = sampleAxisY * filterRadius / surfaceSize.y;
    vec4 sampled = blur9(sourceUv(localUv), dx, dy);

    // Both textures and QColor uniforms arrive premultiplied. Preserve alpha
    // when sampling sparse content such as the slider track.
    vec4 glass = mix(sampled, tintColor, clamp(tintStrength, 0.0, 1.0));
    vec3 rgb = glass.rgb / max(glass.a, 0.0001);
    // Continue fallback pigmentation only where the actual scene is transparent.
    float face = .010 * cos((qt_TexCoord0.y - .18) * 3.14159) + .004 * sin(qt_TexCoord0.x * 3.14159);
    float grain = fract(52.9829189 * fract(dot(floor(gl_FragCoord.xy), vec2(.06711056, .00583715)))) - .5;
    rgb = clamp(rgb + vec3((face + .003 * grain) * diffuseStrength * (1.0 - sampled.a)), 0.0, 1.0);
    float luminance = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
    float contrastRisk = mix(luminance, 1.0 - luminance, lightAppearance);
    float scrim = clamp(readability, 0.0, 0.85) * smoothstep(0.08, 0.92, contrastRisk);
    rgb = mix(rgb, vec3(lightAppearance), scrim);
    float alpha = glass.a * shape * qt_Opacity;
    fragColor = vec4(rgb * alpha, alpha);
}
