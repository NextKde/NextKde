#include "sdf.glsl"

uniform sampler2D texUnit;
uniform vec2 noiseTextureSize;
uniform vec4 box;
uniform vec4 cornerRadius;
uniform float cornerExponent;

float squircleNorm(vec2 q)
{
    float exponent = clamp(cornerExponent, 2.0, 8.0);
    if (exponent <= 2.0001)
        return length(q);
    return pow(pow(q.x, exponent) + pow(q.y, exponent), 1.0 / exponent);
}

float squircleBoxDist(vec2 position, vec2 center, vec2 extents, vec4 radius)
{
    vec2 p = position - center;
    float r = p.x > 0.0
        ? (p.y < 0.0 ? radius.y : radius.w)
        : (p.y < 0.0 ? radius.x : radius.z);
    vec2 q = abs(p) - extents + vec2(r);
    return min(max(q.x, q.y), 0.0) + squircleNorm(max(q, 0.0)) - r;
}

in vec2 vertex;

void main(void)
{
    vec2 uvNoise = vec2(gl_FragCoord.xy / noiseTextureSize);

    // Match the onscreen glass pass even when its geometry spans the full
    // rectangular card. Noise is additively blended, so mask RGB, not alpha.
    float f = squircleBoxDist(vertex, box.xy, box.zw, cornerRadius);
    float df = fwidth(f);
    float coverage = 1.0 - clamp(0.5 + f / df, 0.0, 1.0);
    fragColor = vec4(texture(texUnit, uvNoise).rrr * coverage, 0);
}
