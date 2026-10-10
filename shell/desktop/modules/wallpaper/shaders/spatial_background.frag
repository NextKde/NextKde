// A restrained background defocus; the subject retains its original sharpness.
VARYING vec2 backgroundUv;

void MAIN() {
    vec2 uv = backgroundUv;
    vec2 d = 1.5 / vec2(textureSize(backgroundTexture, 0));
    vec3 color = texture(backgroundTexture, uv).rgb * 0.25;
    color += texture(backgroundTexture, uv + vec2(d.x, 0)).rgb * 0.125;
    color += texture(backgroundTexture, uv - vec2(d.x, 0)).rgb * 0.125;
    color += texture(backgroundTexture, uv + vec2(0, d.y)).rgb * 0.125;
    color += texture(backgroundTexture, uv - vec2(0, d.y)).rgb * 0.125;
    color += texture(backgroundTexture, uv + d).rgb * 0.0625;
    color += texture(backgroundTexture, uv - d).rgb * 0.0625;
    color += texture(backgroundTexture, uv + vec2(d.x, -d.y)).rgb * 0.0625;
    color += texture(backgroundTexture, uv + vec2(-d.x, d.y)).rgb * 0.0625;
    FRAGCOLOR = vec4(color, 1.0);
}
