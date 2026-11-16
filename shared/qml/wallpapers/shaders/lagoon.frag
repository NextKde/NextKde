#version 440
// Original shallow-water optics. Surface displacement, refraction and caustic
// focusing use one gravity/capillary wave spectrum and its analytic derivatives.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 viewport;
    float time;
    float variant;
    vec4 pointer;
};

const float ETA = 0.7501875;

float hash21(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

vec2 hash22(vec2 p) {
    return vec2(hash21(p), hash21(p + vec2(39.7, 17.3)));
}

float noise21(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x),
               mix(hash21(i + vec2(0, 1)), hash21(i + 1.0), f.x), f.y);
}

float stoneNoise(vec2 p) {
    return noise21(p) * 0.57 + noise21(p * 2.08 + 5.9) * 0.28
        + noise21(p * 4.21 - 11.2) * 0.15;
}

// h = surface elevation, g = slope, H = (dxx, dxz, dzz).
void waveField(vec2 p, float footprint, int count, out float h, out vec2 g, out vec3 H) {
    h = 0.0; g = vec2(0.0); H = vec3(0.0);
    float k = 2.15;
    float amplitude = 0.041;
    float t = time * 2.0 * 0.36;
    for (int i = 0; i < 8; ++i) {
        if (i >= count) break;
        float fi = float(i);
        float angle = fi * 2.399963 + 0.42 * sin(fi * 4.13);
        vec2 direction = vec2(cos(angle), sin(angle));
        // Gravity and surface tension share a single dispersion relation.
        float frequency = sqrt(9.81 * k + 0.000074 * k * k * k);
        float phase = k * dot(p, direction) - frequency * t + fi * 7.31;
        float a = amplitude * (1.0 - smoothstep(0.5, 2.4, footprint * k));
        float s = sin(phase), c = cos(phase);
        h += a * s;
        g += a * k * c * direction;
        H -= a * k * k * s * vec3(direction.x * direction.x,
                                    direction.x * direction.y, direction.y * direction.y);
        k *= 1.67;
        amplitude *= 0.58;
    }
}

vec3 surfaceNormal(vec2 slope) {
    return normalize(vec3(-slope.x, 1.0, -slope.y));
}

float sandDepth(vec2 p) {
    // An open deeper basin in the upper left and a sunny limestone shoulder.
    float shelf = smoothstep(1.7, 5.5, p.x + 0.25 * p.y + 0.5 * sin(p.y * 0.31));
    return 2.45 - shelf * 1.5 + 0.27 * sin(p.y * 0.19) + 0.11 * noise21(p * 0.41);
}

// Packed bottom sample: height, stone coverage, stone seed, stone radius.
vec4 bottomSample(vec2 p) {
    vec2 grid = p * 0.79;
    vec2 cell = floor(grid);
    float best = 10.0;
    float seed = 0.0;
    for (int j = -1; j <= 1; ++j) {
        for (int i = -1; i <= 1; ++i) {
            vec2 id = cell + vec2(float(i), float(j));
            vec2 random = hash22(id);
            vec2 center = id + 0.18 + 0.64 * random;
            vec2 delta = grid - center;
            float angle = random.x * 6.2831853;
            delta = mat2(cos(angle), -sin(angle), sin(angle), cos(angle)) * delta;
            delta *= vec2(1.0, 1.12 + random.y * 0.6);
            float radius = 0.23 + 0.30 * hash21(id + 81.9);
            float r = length(delta) / radius;
            if (r < best) { best = r; seed = hash21(id + 29.4); }
        }
    }
    float bank = smoothstep(0.2, 4.8, p.x + p.y * 0.18 + 0.55 * sin(p.y * 0.33));
    float isolated = smoothstep(0.83, 0.95, seed) * 0.5;
    float presence = max(bank, isolated);
    float edge = 1.0 - smoothstep(0.70, 1.04, best);
    float dome = pow(max(0.0, 1.0 - best * best), 0.55);
    float height = -sandDepth(p) + dome * (0.18 + seed * 0.30) * presence;
    return vec4(height, edge * smoothstep(0.22, 0.55, presence), seed, best);
}

vec3 bottomAlbedo(vec2 p, vec4 bed) {
    float grain = noise21(p * 95.0);
    float broad = stoneNoise(p * 0.75);
    // Low relief current ripples are in the sand, not a painted water overlay.
    float sandPhase = p.y * 14.0 + 1.1 * noise21(p * 1.7) + p.x * 1.4;
    float ripples = sin(sandPhase) * 0.025;
    vec3 sand = vec3(0.69, 0.63, 0.47) * (0.91 + 0.14 * broad + 0.065 * grain + ripples);
    float mineral = stoneNoise(p * 12.0 + bed.z * 17.0);
    vec3 warmRock = mix(vec3(0.34, 0.37, 0.33), vec3(0.73, 0.72, 0.59), bed.z);
    vec3 rock = warmRock * (0.76 + mineral * 0.37);
    float veins = 1.0 - smoothstep(0.025, 0.075, abs(noise21(p * 6.3 + noise21(p * 2.0)) - 0.54));
    rock = mix(rock, vec3(0.70, 0.70, 0.60), veins * 0.13);
    // Shaded seams connect stones to their bed instead of outlining every cell.
    float contact = (1.0 - smoothstep(0.98, 1.25, bed.w)) * smoothstep(0.70, 1.01, bed.w);
    sand *= 1.0 - contact * bed.y * 0.32;
    return mix(sand, rock, bed.y);
}

float causticFocus(vec2 floorPoint, float depth, float footprint, vec3 sun) {
    vec3 flatRay = refract(-sun, vec3(0.0, 1.0, 0.0), ETA);
    vec2 source = floorPoint - depth * flatRay.xz / -flatRay.y;
    float h; vec2 g; vec3 H;
    // Invert the surface-to-bottom light mapping with two damped iterations.
    // This makes the bright folds travel with the actual refracting ripples.
    for (int i = 0; i < 2; ++i) {
        waveField(source, max(footprint, 0.022), 6, h, g, H);
        vec3 transmitted = refract(-sun, surfaceNormal(g), ETA);
        vec2 projected = source + (depth + h) * transmitted.xz / -transmitted.y;
        source -= (projected - floorPoint) * 0.65;
    }
    waveField(source, max(footprint, 0.022), 6, h, g, H);
    // Analytic Snell-law derivative, including the normalization of the normal.
    vec3 raw = vec3(-g.x, 1.0, -g.y);
    float invLength = inversesqrt(dot(raw, raw));
    vec3 normal = raw * invLength;
    vec3 dnX = (vec3(-H.x, 0.0, -H.y) - normal * dot(normal, vec3(-H.x, 0.0, -H.y))) * invLength;
    vec3 dnZ = (vec3(-H.y, 0.0, -H.z) - normal * dot(normal, vec3(-H.y, 0.0, -H.z))) * invLength;
    vec3 incoming = -sun;
    float cosine = dot(normal, incoming);
    float root = sqrt(max(0.0001, 1.0 - ETA * ETA * (1.0 - cosine * cosine)));
    float coefficient = ETA * cosine + root;
    float derivative = ETA + ETA * ETA * cosine / root;
    vec3 ray = ETA * incoming - coefficient * normal;
    vec3 dtX = -coefficient * dnX - derivative * dot(dnX, incoming) * normal;
    vec3 dtZ = -coefficient * dnZ - derivative * dot(dnZ, incoming) * normal;
    float y2 = max(ray.y * ray.y, 0.01);
    vec2 shift = ray.xz / -ray.y;
    vec2 shiftX = (-dtX.xz * ray.y + ray.xz * dtX.y) / y2;
    vec2 shiftZ = (-dtZ.xz * ray.y + ray.xz * dtZ.y) / y2;
    vec2 columnX = vec2(1.0, 0.0) + g.x * shift + (depth + h) * shiftX;
    vec2 columnZ = vec2(0.0, 1.0) + g.y * shift + (depth + h) * shiftZ;
    float jacobian = abs(columnX.x * columnZ.y - columnX.y * columnZ.x);
    // Finite sun size prevents infinite intensities at a fold caustic.
    float focus = 1.0 / sqrt(jacobian * jacobian + 0.13);
    return clamp(focus, 0.32, 2.65);
}

vec3 skyReflection(vec3 d) {
    float y = clamp(d.y, 0.0, 1.0);
    vec3 c = mix(vec3(0.67, 0.84, 0.87), vec3(0.13, 0.40, 0.64), pow(y, 0.45));
    vec2 p = d.xz / max(d.y + 0.25, 0.25);
    float cloud = smoothstep(0.58, 0.78, stoneNoise(p * 2.1 + vec2(time * 0.004, 0.0)));
    return mix(c, vec3(0.91, 0.94, 0.91), cloud * 0.50);
}

vec3 toneMap(vec3 c) {
    c = max(c, vec3(0.0));
    c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
    return pow(clamp(c, 0.0, 1.0), vec3(1.0 / 2.2));
}

void main() {
    float aspect = viewport.x / max(viewport.y, 1.0);
    vec2 screen = vec2((qt_TexCoord0.x - 0.5) * aspect, 0.5 - qt_TexCoord0.y);
    vec3 ro = vec3(-0.3, 5.7, 7.0);
    vec3 rd = normalize(vec3(screen.x * 1.13, screen.y * 0.88 - 0.94, -1.03));
    float distance = -ro.y / rd.y;
    float h; vec2 g; vec3 H;
    float footprint = distance * 1.5 / max(viewport.y, 1.0);
    for (int i = 0; i < 3; ++i) {
        vec3 p = ro + distance * rd;
        waveField(p.xz, footprint, 8, h, g, H);
        float slope = rd.y - dot(g, rd.xz);
        distance -= (p.y - h) / min(slope, -0.15);
    }
    vec3 surface = ro + distance * rd;
    waveField(surface.xz, footprint, 8, h, g, H);
    vec3 normal = surfaceNormal(g);
    vec3 transmitted = refract(rd, normal, ETA);
    float bottomDistance = (surface.y + sandDepth(surface.xz)) / -transmitted.y;
    vec3 floorPoint;
    vec4 bed;
    for (int i = 0; i < 3; ++i) {
        floorPoint = surface + transmitted * bottomDistance;
        bed = bottomSample(floorPoint.xz);
        bottomDistance = (surface.y - bed.x) / -transmitted.y;
    }
    floorPoint = surface + transmitted * bottomDistance;
    bed = bottomSample(floorPoint.xz);
    vec3 bottomNormal = normalize(cross(dFdx(floorPoint), dFdy(floorPoint)));
    if (bottomNormal.y < 0.0) bottomNormal = -bottomNormal;
    vec3 sun = normalize(vec3(-0.44, 0.84, -0.31));
    float light = max(dot(bottomNormal, sun), 0.0);
    float focus = causticFocus(floorPoint.xz, -bed.x, footprint, sun);
    vec3 albedo = bottomAlbedo(floorPoint.xz, bed);
    vec3 floorLight = albedo * (0.25 + 0.88 * light * focus);
    // Beer-Lambert absorption over the view path and the incident sun path.
    float opticalLength = bottomDistance + max(-bed.x, 0.0) / sun.y;
    vec3 absorption = mix(vec3(0.39, 0.105, 0.065), vec3(0.50, 0.11, 0.07), clamp(variant, 0.0, 1.0));
    vec3 transmission = exp(-absorption * opticalLength);
    vec3 waterColor = vec3(0.018, 0.28, 0.29);
    vec3 underwater = floorLight * transmission + waterColor * (1.0 - transmission) * 0.46;
    float ndv = max(dot(normal, -rd), 0.0);
    float fresnel = 0.02037 + 0.97963 * pow(1.0 - ndv, 5.0);
    vec3 reflected = reflect(rd, normal);
    vec3 color = mix(underwater, skyReflection(reflected), fresnel);
    vec3 halfway = normalize(sun - rd);
    float ndh = max(dot(normal, halfway), 0.0);
    float sunGlitter = pow(ndh, 1500.0) * 2.2 + pow(ndh, 180.0) * 0.035;
    color += vec3(1.0, 0.91, 0.70) * sunGlitter;
    // A restrained exposure falloff anchors the far, deeper basin.
    color *= 1.03 - 0.08 * smoothstep(6.0, 15.0, distance);
    fragColor = vec4(toneMap(color), 1.0) * qt_Opacity;
}
