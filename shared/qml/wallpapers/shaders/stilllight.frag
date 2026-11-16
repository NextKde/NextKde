#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 viewport;
    float time;
    float scene;
};
layout(binding = 1) uniform sampler2D motionMask;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
    float aspect = viewport.x / max(1.0, viewport.y);
    vec2 crop = aspect > 1.7777778 ? vec2(1.0, 1.7777778 / aspect)
        : vec2(aspect / 1.7777778, 1.0);
    vec2 uv = (qt_TexCoord0 - 0.5) * crop + 0.5;
    vec3 mask = texture(motionMask, uv).rgb;
    vec3 light = vec3(0.0);
    float t = time;

    if (scene < 0.5) {
        // Three luminous curtains: no raymarching, fractal noise or feedback.
        for (int i = 0; i < 3; ++i) {
            float k = float(i);
            float curve = 0.20 + k * 0.064 + 0.085 * sin(uv.x * 5.5 + k * 0.6)
                + 0.038 * sin(uv.x * 11.0 - 1.0)
                + 0.012 * sin(uv.x * 8.0 + t * 0.22 + k);
            float d = curve - uv.y;
            float curtain = exp(-max(0.0, d) / (0.10 + k * 0.025))
                * smoothstep(-0.004, 0.012, d);
            float strands = 0.55 + 0.24 * sin(uv.x * 108.0 + t * 0.42 + sin(uv.x * 17.0) * 4.0)
                + 0.14 * sin(uv.x * 237.0 - t * 0.29);
            float envelope = smoothstep(0.0, 0.15, uv.x) * (1.0 - smoothstep(0.78, 1.1, uv.x));
            vec3 color = i == 0 ? vec3(0.15, 0.85, 0.57)
                : i == 1 ? vec3(0.08, 0.53, 0.69) : vec3(0.32, 0.22, 0.64);
            light += color * curtain * strands * envelope * (0.18 - k * 0.035) * mask.r;
        }
    } else if (scene < 1.5) {
        vec2 p = (uv - vec2(0.64, 0.43)) * vec2(1.7777778, 1.0);
        float r = length(p);
        float angle = atan(p.y, p.x);
        float outside = smoothstep(0.219, 0.223, r);
        float halo = exp(-max(0.0, r - 0.219) / 0.033) * outside;
        float threads = 0.5 + 0.23 * sin(angle * 39.0 + sin(angle * 11.0 + t * 0.13) * 2.0)
            + 0.12 * sin(angle * 83.0 - t * 0.19);
        light = vec3(1.0, 0.61, 0.28) * halo * threads * 0.19 * mask.r;
        float flare = exp(-dot((p - vec2(-0.158, 0.151)) / 0.018,
            (p - vec2(-0.158, 0.151)) / 0.018));
        light += vec3(1.0, 0.84, 0.58) * flare * (0.035 + 0.025 * sin(t * 0.25));
    } else if (scene < 2.5) {
        float drift = sin(uv.x * 13.0 + uv.y * 8.0 + t * 0.10)
            + 0.45 * sin(uv.x * 29.0 - uv.y * 17.0 - t * 0.14);
        float veil = exp(-pow((uv.y - 0.71 - 0.013 * drift) / 0.065, 2.0));
        light = vec3(0.79, 0.55, 0.56) * veil * (0.025 + 0.018 * drift) * mask.g;
        float sun = exp(-dot((uv - vec2(0.70, 0.49)) * vec2(5.0, 7.0),
            (uv - vec2(0.70, 0.49)) * vec2(5.0, 7.0)));
        light += vec3(0.90, 0.50, 0.25) * sun * (0.017 + 0.008 * sin(t * 0.18));
    } else if (scene < 3.5) {
        vec2 p = uv * vec2(83.0, 51.0);
        float a = sin(p.x + sin(p.y * 0.7 + t * 0.29) * 2.2 + t * 0.20);
        float b = sin(p.y + sin(p.x * 0.6 - t * 0.21) * 2.1 - t * 0.18);
        float caustic = pow(max(0.0, 1.0 - abs(a + b) * 0.9), 12.0);
        light = vec3(0.38, 0.78, 0.68) * caustic * 0.055 * mask.g;
        float waves = pow(0.5 + 0.5 * sin(uv.y * 490.0 + sin(uv.x * 47.0) * 2.0 - t * 0.8), 14.0);
        light += vec3(0.61, 0.90, 0.84) * waves * mask.b * 0.04;
    } else {
        float mist = 0.5 + 0.3 * sin(uv.x * 12.0 + t * 0.12)
            + 0.2 * sin(uv.x * 29.0 + uv.y * 9.0 - t * 0.08);
        light = vec3(0.29, 0.53, 0.51) * mask.b * mist * 0.07;
        float ripple = pow(0.5 + 0.5 * sin(uv.y * 380.0 + uv.x * 33.0 - t * 0.7), 12.0);
        light += vec3(0.44, 0.71, 0.69) * mask.g * ripple * 0.09;
        // Sparse tiny fireflies in a fixed grid, evaluated in one small buffer.
        vec2 grid = uv * vec2(29.0, 17.0);
        vec2 cell = floor(grid);
        float seed = hash(cell);
        vec2 center = vec2(0.5) + 0.19 * vec2(sin(t * 0.23 + seed * 43.0), cos(t * 0.19 + seed * 21.0));
        vec2 offset = fract(grid) - center;
        float fly = exp(-dot(offset, offset) * 700.0) * step(0.93, seed)
            * smoothstep(0.66, 0.85, uv.y);
        float pulse = pow(0.5 + 0.5 * sin(t * 0.7 + seed * 51.0), 3.0);
        light += vec3(0.55, 0.79, 0.27) * fly * pulse * 0.5;
    }
    // Premultiplied translucent light over the sharp plate.
    float alpha = clamp(max(light.r, max(light.g, light.b)), 0.0, 0.65);
    fragColor = vec4(light, alpha) * qt_Opacity;
}
