#version 440

// Original procedural artwork for KOS; no sampled imagery or third-party shader code.
// Aurora model: bounded optically thin emission, folded field-aligned sheets,
// altitude-dependent oxygen / nitrogen colour, and finite pixel-footprint filtering.
// This is an artistic radiance model, not a spectral atmospheric simulation.
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

const int MARCH_STEPS = 40;

// Fractional polynomial coordinate mixers; no sine evaluations in the march.
float hash11(float p)
{
    float q = fract(p * 0.754877666 + 0.113);
    q = fract(q * (q + 17.17));
    return fract(q * (q + 43.71));
}

float hash21(vec2 p)
{
    vec2 q = fract(p * vec2(0.754877666, 0.569840296) + vec2(0.113, 0.197));
    q += dot(q, q.yx + 19.19);
    return fract((q.x + q.y) * (q.x + 0.37 * q.y));
}

vec2 hash22(vec2 p)
{
    return vec2(hash21(p), hash21(p.yx + vec2(17.13, 31.71)));
}

// Quintic interpolation keeps drifting folds smooth through lattice boundaries.
float noise1(float x)
{
    float i = floor(x);
    float f = fract(x);
    float u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return mix(hash11(i), hash11(i + 1.0), u);
}

// Value and analytic derivative of the same noise. The derivative allows the
// marcher to integrate a thin curtain even when a step crosses it obliquely.
vec2 noiseD(float x)
{
    float i = floor(x);
    float f = fract(x);
    float a = hash11(i);
    float b = hash11(i + 1.0);
    float u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float du = 30.0 * f * f * (f - 1.0) * (f - 1.0);
    return vec2(mix(a, b, u), (b - a) * du);
}

vec3 starField(vec3 ray, float pixelAngle)
{
    // Stereographic sky coordinates, fixed in space. Stars do not slide with
    // the aurora or change randomly between animation frames.
    vec2 sky = ray.xy / (1.0 + ray.z);
    vec3 result = vec3(0.0);
    for (int layer = 0; layer < 2; ++layer) {
        float scale = layer == 0 ? 92.0 : 173.0;
        vec2 grid = sky * scale + vec2(19.3, 71.9) * float(layer);
        vec2 cell = floor(grid);
        vec2 random = hash22(cell + 37.0);
        vec2 centre = 0.22 + 0.56 * random;
        vec2 offset = fract(grid) - centre;
        float seed = hash21(cell + 117.0);
        float present = step(layer == 0 ? 0.967 : 0.987, seed);
        float radius = max(0.018, pixelAngle * scale * 0.55);
        float distance2 = dot(offset, offset);
        float core = exp(-distance2 / (radius * radius));
        float halo = exp(-distance2 / (radius * radius * 9.0)) * 0.026;
        float magnitude = 0.10 + 0.75 * pow(random.x, 5.0);
        vec3 colour = mix(vec3(0.54, 0.71, 1.0), vec3(1.0, 0.83, 0.62), random.y);
        result += colour * (core + halo) * magnitude * present;
    }
    return result * smoothstep(0.015, 0.20, ray.y);
}

vec3 aurora(vec3 origin, vec3 ray, float seconds, float pixelAngle, float seed)
{
    if (ray.y <= 0.025)
        return vec3(0.0);

    // The camera looks through an atmospheric slab, not a screen-space mask.
    // Clip both its altitude and depth so near-horizon rays have bounded cost.
    float entry = max(0.92 / ray.y, (-1.8 - origin.z) / ray.z);
    float exitDistance = min(4.25 / ray.y, (9.5 - origin.z) / ray.z);
    if (entry >= exitDistance)
        return vec3(0.0);

    float stepLength = (exitDistance - entry) / float(MARCH_STEPS);
    float distanceAlongRay = entry + stepLength * (0.18 + 0.64 * seed);
    float drift = seconds * 0.022;
    vec3 radiance = vec3(0.0);

    // variant 0: jade curtain; 1: cooler blue/violet; 2: pale oxygen green.
    float cool = clamp(variant, 0.0, 1.0) * (1.0 - clamp(variant - 1.0, 0.0, 1.0));
    float pale = clamp(variant - 1.0, 0.0, 1.0);
    vec3 oxygen = mix(vec3(0.055, 1.0, 0.40), vec3(0.035, 0.69, 0.89), cool * 0.55);
    oxygen = mix(oxygen, vec3(0.23, 0.90, 0.48), pale);
    vec3 nitrogen = mix(vec3(0.35, 0.075, 0.67), vec3(0.28, 0.12, 0.91), cool);

    for (int i = 0; i < MARCH_STEPS; ++i) {
        vec3 p = origin + ray * distanceAlongRay;
        // Field lines lean very slightly with altitude, retaining long coherent
        // vertical rays. Large folds drift slowly; fine folds advect with them.
        float x = p.x + 0.075 * (p.y - 1.1);
        vec2 broad = noiseD(x * 0.42 + drift * 0.22 + 13.7);
        vec2 folds = noiseD(x * 1.55 - drift * 0.34 + broad.x * 1.7);
        float foldSlope = folds.y * (1.55 + broad.y * 0.42 * 1.7);
        float centre = 0.45 + 0.20 * x + 0.065 * x * x
            + 1.45 * (broad.x - 0.5) + 0.72 * (folds.x - 0.5);
        float slope = 0.20 + 0.13 * x + 1.45 * broad.y * 0.42 + 0.72 * foldSlope;
        float sheetDistance = p.z - centre;
        float crossingRate = abs(ray.z - slope * (ray.x + 0.075 * ray.y));
        float footprint = distanceAlongRay * pixelAngle * (1.0 + abs(slope));
        float width = sqrt(0.075 * 0.075 + footprint * footprint
            + stepLength * stepLength * crossingRate * crossingRate * 0.18);
        float sheet = exp(-0.5 * sheetDistance * sheetDistance / (width * width)) * (0.075 / width);

        // A faint, more distant fold is part of the same auroral oval. Its
        // vertical parallax supplies depth without duplicating the hero's edge.
        float rearDistance = sheetDistance - 3.6 - 0.35 * broad.x;
        float rearWidth = width * 1.45;
        float rear = exp(-0.5 * rearDistance * rearDistance / (rearWidth * rearWidth))
            * (0.075 / rearWidth) * 0.27;

        float base = 1.06 + 0.10 * broad.x + 0.035 * folds.x;
        float altitude = p.y - base;
        float ignition = smoothstep(0.0, 0.11, altitude);
        float ceiling = 2.05 + 0.65 * noise1(x * 0.67 + 45.0 + drift * 0.16);
        float taper = 1.0 - smoothstep(ceiling - 0.75, ceiling, altitude);
        float oxygenProfile = exp(-max(altitude, 0.0) * 1.45) * ignition * taper;
        float violetProfile = exp(-pow((altitude - 1.65) / 0.85, 2.0))
            * ignition * taper * 0.19;

        // Nonperiodic, vertically coherent striation. Remove subpixel detail
        // in the distance instead of allowing bright filaments to shimmer.
        float filamentCoord = x + 0.045 * broad.x + drift * 0.14;
        float medium = noise1(filamentCoord * 13.0 + 101.0);
        float fine = noise1(filamentCoord * 37.0 + 219.0);
        float resolved = 1.0 - smoothstep(0.25, 0.9, footprint * 37.0);
        fine = mix(0.5, fine, resolved);
        float filaments = 0.17 + 1.48 * medium * medium + 0.58 * fine * fine;
        float activity = 0.38 + 0.90 * noise1(x * 0.63 - drift * 0.12 + 5.4);
        float ends = exp(-pow(abs(x + 0.6) / 10.0, 4.0));
        float distanceHaze = exp(-distanceAlongRay * 0.028);
        vec3 emission = oxygen * oxygenProfile + nitrogen * violetProfile;
        // A broad, dim scattering skirt gives a photographic glow without a
        // framebuffer blur, texture sample, or a second integration pass.
        float skirt = exp(-abs(sheetDistance) * 2.2) * 0.016;
        radiance += emission * (sheet + rear + skirt) * filaments * activity
            * ends * distanceHaze * stepLength * 4.9;
        distanceAlongRay += stepLength;
    }
    return radiance;
}

vec3 toneMap(vec3 x)
{
    // Soft photographic shoulder; preserves coloured detail in the green edge.
    x = max(x, vec3(0.0));
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

void main()
{
    vec2 size = max(viewport, vec2(1.0));
    float aspect = size.x / size.y;
    vec2 screen = (qt_TexCoord0 - 0.5) * vec2(2.0 * aspect, -2.0);
    vec3 origin = vec3(0.0, 0.0, -4.8);
    vec3 ray = normalize(vec3(screen.x * 0.90, screen.y * 0.82 + 0.36, 1.5));
    // The host's phase runs at half wall-clock speed.
    float seconds = time * 2.0;
    // viewport is logical; the wallpaper host caps its render target at 1280.
    // Filter against that target rather than losing stars on high-DPI displays.
    float renderHeight = size.y * min(1.0, 1280.0 / max(size.x, size.y));
    float pixelAngle = 1.1 / max(renderHeight, 1.0);
    float elevation = max(ray.y, 0.0);
    float horizon = exp(-elevation * 16.0);
    vec3 sky = mix(vec3(0.0014, 0.0031, 0.0090), vec3(0.008, 0.017, 0.026), horizon);
    // Thin airglow, below the luminous curtain, keeps the horizon legible.
    sky += vec3(0.006, 0.016, 0.017) * exp(-pow((elevation - 0.045) / 0.055, 2.0));
    sky += starField(ray, pixelAngle);
    float jitter = hash21(floor(qt_TexCoord0 * size));
    sky += aurora(origin, ray, seconds, pixelAngle, jitter);

    // A low, uninterrupted polar horizon grounds the altitude of the curtain.
    // No foreground peaks or repeated procedural mountain noise.
    float azimuth = ray.x / ray.z;
    float ridge = 0.006 + 0.012 * exp(-pow((azimuth + 0.58) * 2.8, 2.0))
        + 0.006 * exp(-pow((azimuth - 0.82) * 3.8, 2.0));
    float land = 1.0 - smoothstep(ridge - pixelAngle, ridge + pixelAngle, ray.y);
    float nearHorizon = exp(-abs(ray.y - ridge) * 35.0);
    vec3 ground = vec3(0.0011, 0.0027, 0.0040)
        + vec3(0.0015, 0.0031, 0.0035) * nearHorizon;
    vec3 colour = mix(sky, ground, land);
    float vignette = 1.0 - 0.13 * smoothstep(0.15, 1.3, length((qt_TexCoord0 - 0.5) * vec2(1.1, 1.0)));
    colour = pow(toneMap(colour * 1.22 * vignette), vec3(1.0 / 2.2));
    // Sub-LSB fixed dithering prevents banding in the broad, near-black sky.
    colour += (hash21(gl_FragCoord.xy + 53.7) - 0.5) / 255.0;
    fragColor = vec4(clamp(colour, 0.0, 1.0), 1.0) * qt_Opacity;
}
