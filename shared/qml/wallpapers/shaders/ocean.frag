#version 440
// Original procedural ocean. Gravity-wave dispersion, Stokes crest sharpening,
// dielectric Fresnel and a finite-roughness sun reflection; no image inputs.
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

const float PI = 3.14159265359;

float hash21(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

float noise21(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x),
               mix(hash21(i + vec2(0, 1)), hash21(i + 1.0), f.x), f.y);
}

float cloudNoise(vec2 p) {
    return 0.57 * noise21(p) + 0.28 * noise21(p * 2.07 + 13.4)
        + 0.15 * noise21(p * 4.19 - 7.8);
}

vec3 lightDirection() {
    return variant < 0.5 ? normalize(vec3(-0.46, 0.095, -0.89))
                         : normalize(vec3(0.42, 0.245, -0.89));
}

// The reflected sky omits the disk: the finite sun is integrated by the BRDF.
vec3 skyRadiance(vec3 d, bool disk) {
    float night = step(0.5, variant);
    vec3 sun = lightDirection();
    float y = max(d.y, 0.0);
    float elevation = pow(clamp(y, 0.0, 1.0), 0.48);
    vec3 horizon = mix(vec3(0.76, 0.385, 0.185), vec3(0.065, 0.105, 0.19), night);
    vec3 zenith = mix(vec3(0.115, 0.245, 0.365), vec3(0.008, 0.021, 0.067), night);
    vec3 color = mix(horizon, zenith, elevation);
    float facing = max(dot(d, sun), 0.0);
    vec3 glow = mix(vec3(0.95, 0.40, 0.12), vec3(0.17, 0.23, 0.34), night);
    color += glow * (0.15 * pow(facing, 8.0) + 0.30 * pow(facing, 90.0));
    // Broad, wind-stretched cloud banks, projected onto an atmospheric layer.
    vec2 cp = d.xz / max(0.13, y + 0.12);
    cp = cp * vec2(1.0, 4.1) + vec2(time * 0.006, 0.0);
    float clouds = smoothstep(0.53, 0.79, cloudNoise(cp));
    clouds *= smoothstep(0.035, 0.16, y) * (1.0 - smoothstep(0.6, 0.95, y));
    vec3 cloudColor = mix(mix(vec3(0.34, 0.36, 0.41), vec3(1.05, 0.69, 0.41), pow(facing, 6.0)),
                          vec3(0.10, 0.14, 0.23), night);
    color = mix(color, cloudColor, clouds * mix(0.48, 0.21, night));
    if (disk) {
        float angle = acos(clamp(dot(d, sun), -1.0, 1.0));
        float radius = mix(0.0125, 0.014, night);
        float aa = max(0.0004, 0.72 / max(viewport.y, 1.0));
        float disc = 1.0 - smoothstep(radius - aa, radius + aa, angle);
        vec3 illuminant = mix(vec3(8.0, 4.9, 2.3), vec3(1.65, 1.95, 2.65), night);
        // A little lunar albedo variation stays inside the analytic disk.
        float lunar = 0.82 + 0.18 * noise21(d.xz * 320.0);
        color += illuminant * disc * mix(1.0, lunar, night);
        if (night > 0.5 && y > 0.12) {
            vec2 starUv = vec2(atan(d.x, -d.z), asin(clamp(d.y, -1.0, 1.0))) * 165.0;
            vec2 cell = floor(starUv);
            vec2 center = vec2(hash21(cell + 9.2), hash21(cell - 7.1));
            float star = exp(-dot(fract(starUv) - center, fract(starUv) - center) * 350.0);
            color += vec3(0.35, 0.44, 0.61) * star * step(0.993, hash21(cell))
                   * smoothstep(0.12, 0.34, y) * (1.0 - clouds);
        }
    }
    return color;
}

// xyz = height and its analytic x/z gradient; w = negative Laplacian.
// Noncommensurate wave vectors prevent a repeating grid. Higher frequencies
// disappear continuously as their wavelength approaches the pixel footprint.
vec4 waves(vec2 p, float footprint, int count) {
    vec4 result = vec4(0.0);
    float k = 0.31;
    float amplitude = 0.55;
    float t = time * 2.0 * 0.46;
    for (int i = 0; i < 11; ++i) {
        if (i >= count) break;
        float fi = float(i);
        float angle = -0.48 + 1.23 * sin(fi * 2.39996 + 0.3);
        vec2 direction = vec2(cos(angle), sin(angle));
        float phase = k * dot(direction, p) - sqrt(9.81 * k) * t + fi * 5.721;
        float s = sin(phase), c = cos(phase);
        float second = 2.0 * s * c;
        float filterWidth = k * footprint;
        float a = amplitude * (1.0 - smoothstep(0.55, 2.3, filterWidth));
        float shape = s + 0.18 * second;
        float slope = c + 0.36 * (c * c - s * s);
        result.x += a * shape;
        result.yz += a * k * slope * direction;
        result.w += a * k * k * (s + 0.72 * second);
        k *= 1.82;
        amplitude *= 0.49;
    }
    return result;
}

float heightResidual(vec3 ro, vec3 rd, float distance) {
    vec3 p = ro + rd * distance;
    float footprint = distance * 1.6 / max(viewport.y, 1.0);
    return p.y - waves(p.xz, footprint, 6).x;
}

float intersectOcean(vec3 ro, vec3 rd) {
    // The six displacement waves lie strictly inside this vertical bracket.
    float low = max(0.0, (ro.y - 1.28) / -rd.y);
    float high = (ro.y + 1.28) / -rd.y;
    float fl = heightResidual(ro, rd, low);
    float fh = heightResidual(ro, rd, high);
    float distance = (ro.y / -rd.y);
    for (int i = 0; i < 7; ++i) {
        float fraction = clamp(fl / max(fl - fh, 0.0001), 0.08, 0.92);
        distance = mix(low, high, fraction);
        float f = heightResidual(ro, rd, distance);
        if (f > 0.0) { low = distance; fl = f; }
        else { high = distance; fh = f; }
    }
    return distance;
}

vec3 toneMap(vec3 c) {
    c = max(c, vec3(0.0));
    c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
    return pow(clamp(c, 0.0, 1.0), vec3(1.0 / 2.2));
}

void main() {
    float aspect = viewport.x / max(viewport.y, 1.0);
    vec2 screen = vec2((qt_TexCoord0.x - 0.5) * aspect, 0.5 - qt_TexCoord0.y);
    // Fixed horizon and gentle off-centre composition keep the desktop stable.
    vec3 ro = vec3(0.0, 3.35, 9.0);
    vec3 rd = normalize(vec3(screen.x, screen.y - 0.105, -1.03));
    vec3 color;
    float night = step(0.5, variant);
    if (rd.y >= -0.0035) {
        color = skyRadiance(rd, true);
    } else {
        float distance = intersectOcean(ro, rd);
        vec3 p = ro + rd * distance;
        float footprint = distance * 1.6 / max(viewport.y, 1.0);
        vec4 wave = waves(p.xz, footprint, 11);
        vec3 n = normalize(vec3(-wave.y, 1.0, -wave.z));
        vec3 view = -rd;
        // Subpixel facets near the horizon gradually become a rough surface.
        float ndv = max(dot(n, view), 0.001);
        vec3 reflected = reflect(rd, n);
        reflected.y = max(reflected.y, 0.005);
        float fresnel = 0.02037 + 0.97963 * pow(1.0 - ndv, 5.0);
        vec3 sun = lightDirection();
        float ndl = max(dot(n, sun), 0.0);
        vec3 body = mix(vec3(0.009, 0.073, 0.093), vec3(0.003, 0.017, 0.043), night);
        float crestLight = smoothstep(-0.4, 0.85, wave.x) * pow(max(dot(view, -sun), 0.0), 3.0);
        vec3 subsurface = mix(vec3(0.035, 0.19, 0.15), vec3(0.006, 0.038, 0.075), night);
        color = (body * (0.58 + 0.42 * ndl) + subsurface * crestLight * 0.24) * (1.0 - fresnel);
        color += skyRadiance(normalize(reflected), false) * fresnel;
        vec3 halfway = normalize(sun + view);
        float ndh = max(dot(n, halfway), 0.0);
        float vdh = max(dot(view, halfway), 0.0);
        float roughness = 0.115 + 0.065 * smoothstep(0.0, 0.8, footprint);
        float alpha = roughness * roughness;
        float a2 = alpha * alpha;
        float denominator = ndh * ndh * (a2 - 1.0) + 1.0;
        float distribution = a2 / max(PI * denominator * denominator, 0.000001);
        float gv = 2.0 * ndv / (ndv + sqrt(a2 + (1.0 - a2) * ndv * ndv));
        float gl = 2.0 * ndl / max(ndl + sqrt(a2 + (1.0 - a2) * ndl * ndl), 0.0001);
        float specularFresnel = 0.02037 + 0.97963 * pow(1.0 - vdh, 5.0);
        float specular = distribution * gv * gl * specularFresnel / max(4.0 * ndv, 0.0001);
        color += mix(vec3(10.0, 5.4, 2.15), vec3(2.0, 2.8, 4.3), night) * min(specular, 35.0);
        // Only rare converging swell crests receive a trace of broken foam.
        float foam = smoothstep(0.68, 0.98, wave.x) * smoothstep(0.35, 1.4, wave.w);
        foam *= smoothstep(0.58, 0.78, noise21(p.xz * 7.0 + wave.yz * 2.0));
        foam *= 1.0 - smoothstep(18.0, 70.0, distance);
        color = mix(color, mix(vec3(0.40, 0.40, 0.34), vec3(0.12, 0.18, 0.27), night), foam * 0.45);
        float haze = 1.0 - exp(-distance * mix(0.0055, 0.003, night));
        vec3 horizon = skyRadiance(normalize(vec3(rd.x, 0.006, rd.z)), false);
        color = mix(color, horizon * mix(0.82, 0.62, night), haze);
    }
    color *= mix(1.12, 1.25, night);
    fragColor = vec4(toneMap(color), 1.0) * qt_Opacity;
}
