uniform sampler2D texUnit;
uniform vec2 direction;
// Normalized weight and bilinear offset; center followed by paired taps.
uniform vec2 kernel[49];
uniform int pairCount;
in vec2 uv;
void main()
{
    vec4 color = texture(texUnit, uv) * kernel[0].x;
    for (int i = 1; i <= pairCount; ++i) {
        vec2 delta = direction * kernel[i].y;
        color += (texture(texUnit, uv + delta) + texture(texUnit, uv - delta)) * kernel[i].x;
    }
    fragColor = color;
}
