#version 440

// Original KOS studio-crystal renderer; no sampled images or borrowed scene.
// Geometry: analytic quadrics. Optics: Snell refraction, unpolarized dielectric
// Fresnel and Beer-Lambert absorption. The floor's caustic is a deliberately
// bounded, soft focusing approximation, not a photon simulation.
// Tone curve: Krzysztof Narkowicz, "ACES Filmic Tone Mapping Curve" (2016),
// used under the author's explicit CC0 option. Source and license statement:
// https://knarkowicz.wordpress.com/2016/01/06/aces-filmic-tone-mapping-curve/
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

const float EPS = 0.0005;
const float FAR = 10000.0;

struct Crystal {
    vec3 center;
    vec3 radii;
    mat3 rotation;
    vec3 absorption;
    vec3 ior;
    vec3 tint;
};

mat3 rotateY(float angle)
{
    float c = cos(angle), s = sin(angle);
    return mat3(c, 0.0, -s, 0.0, 1.0, 0.0, s, 0.0, c);
}

mat3 rotateZ(float angle)
{
    float c = cos(angle), s = sin(angle);
    return mat3(c, s, 0.0, -s, c, 0.0, 0.0, 0.0, 1.0);
}

Crystal crystalScene(float seconds)
{
    Crystal glass;
    float selection = mod(floor(max(variant, 0.0) + 0.5), 4.0);
    glass.radii = vec3(1.27, 1.64, 0.66);
    glass.absorption = vec3(0.31, 0.085, 0.045);
    glass.ior = vec3(1.503, 1.510, 1.520);
    glass.tint = vec3(0.62, 0.83, 1.0);
    float tilt = -0.37;
    if (selection > 0.5 && selection < 1.5) {
        glass.radii = vec3(1.36, 1.53, 0.71);
        glass.absorption = vec3(0.055, 0.26, 0.17);
        glass.tint = vec3(1.0, 0.70, 0.79);
        tilt = -0.29;
    } else if (selection > 1.5 && selection < 2.5) {
        glass.radii = vec3(1.21, 1.66, 0.70);
        glass.absorption = vec3(0.035, 0.15, 0.43);
        glass.tint = vec3(1.0, 0.80, 0.49);
        tilt = -0.41;
    } else if (selection > 2.5) {
        glass.radii = vec3(1.44, 1.46, 0.91);
        glass.absorption = vec3(0.065, 0.055, 0.048);
        glass.ior = vec3(1.512, 1.520, 1.532);
        glass.tint = vec3(0.80, 0.89, 1.0);
        tilt = -0.24;
    }
    glass.rotation = rotateZ(tilt + 0.018 * sin(seconds * 0.037))
        * rotateY(0.34 + 0.045 * sin(seconds * 0.029));
    // Exact support height keeps the slowly turning lens touching the ground.
    vec3 vertical = transpose(glass.rotation) * vec3(0.0, 1.0, 0.0);
    float support = length(vertical * glass.radii);
    glass.center = vec3(1.38, support + 0.018, 0.0);
    return glass;
}

// Roots remain world-space ray distances: the transformed direction is NOT
// normalized. This also makes absorption independent of the ellipsoid scale.
vec2 intersectCrystal(vec3 origin, vec3 direction, Crystal glass)
{
    mat3 inverseRotation = transpose(glass.rotation);
    vec3 o = (inverseRotation * (origin - glass.center)) / glass.radii;
    vec3 d = (inverseRotation * direction) / glass.radii;
    float a = dot(d, d);
    float b = dot(o, d);
    float c = dot(o, o) - 1.0;
    float discriminant = b * b - a * c;
    if (discriminant < 0.0)
        return vec2(FAR, -FAR);
    float root = sqrt(max(discriminant, 0.0));
    return vec2((-b - root) / a, (-b + root) / a);
}

vec3 crystalNormal(vec3 position, Crystal glass)
{
    vec3 local = transpose(glass.rotation) * (position - glass.center);
    return normalize(glass.rotation * (local / (glass.radii * glass.radii)));
}

float fresnelDielectric(float incidentCosine, float etaIncident, float etaTransmitted)
{
    float ci = clamp(incidentCosine, 0.0, 1.0);
    float eta = etaIncident / etaTransmitted;
    float st2 = eta * eta * (1.0 - ci * ci);
    if (st2 >= 1.0)
        return 1.0;
    float ct = sqrt(max(1.0 - st2, 0.0));
    float rs = (etaIncident * ci - etaTransmitted * ct)
        / max(etaIncident * ci + etaTransmitted * ct, 0.00001);
    float rp = (etaTransmitted * ci - etaIncident * ct)
        / max(etaTransmitted * ci + etaIncident * ct, 0.00001);
    return 0.5 * (rs * rs + rp * rp);
}

vec3 keyPosition(float seconds)
{
    return vec3(-3.8 + 0.24 * sin(seconds * 0.031), 6.1, 3.2);
}

// Finite rectangular emitters are intersected in world space. Curved white
// ribbons and their perspective therefore come from the lens normals, not UV
// bands painted on the object. Diffuser falloff gently rounds the card edges.
float softbox(vec3 origin, vec3 direction, vec3 center, vec2 halfSize, float edge)
{
    vec3 normal = normalize(vec3(1.1, 1.5, 0.0) - center);
    vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), normal));
    vec3 up = cross(normal, right);
    float denominator = dot(direction, normal);
    if (denominator > -0.00001)
        return 0.0;
    float distanceToCard = dot(center - origin, normal) / denominator;
    if (distanceToCard <= EPS)
        return 0.0;
    vec3 offset = origin + distanceToCard * direction - center;
    vec2 p = vec2(dot(offset, right), dot(offset, up));
    vec2 q = abs(p) - halfSize + vec2(edge);
    float roundedDistance = length(max(q, vec2(0.0)))
        + min(max(q.x, q.y), 0.0) - edge;
    float diffuser = 1.0 - smoothstep(-edge, edge * 0.35, roundedDistance);
    // The broad center remains soft, without a clipped neon-looking outline.
    return diffuser * (0.88 + 0.12 * exp(-dot(p / halfSize, p / halfSize)));
}

vec3 studioEnvironment(vec3 origin, vec3 direction, float seconds)
{
    float elevation = smoothstep(-0.18, 0.92, direction.y);
    vec3 color = mix(vec3(0.052, 0.066, 0.092), vec3(0.011, 0.017, 0.029), elevation);
    // Broad out-of-focus cyclorama illumination; these lobes remain in the
    // same world coordinate frame for camera, reflection and refraction rays.
    vec3 coolDirection = normalize(vec3(0.8, 0.55, -1.0));
    vec3 warmDirection = normalize(vec3(-0.9, 0.10, -1.0));
    float cool = pow(max(dot(direction, coolDirection), 0.0), 7.0);
    float warm = pow(max(dot(direction, warmDirection), 0.0), 12.0);
    color += vec3(0.055, 0.086, 0.13) * cool;
    color += vec3(0.052, 0.043, 0.034) * warm;
    color += vec3(9.8, 10.0, 10.4)
        * softbox(origin, direction, keyPosition(seconds), vec2(1.45, 2.65), 0.17);
    color += vec3(3.5, 4.3, 5.3)
        * softbox(origin, direction, vec3(5.2, 3.3, 2.2), vec2(0.32, 2.05), 0.095);
    color += vec3(5.7, 5.3, 4.7)
        * softbox(origin, direction, vec3(0.6, 5.8, -3.6), vec2(2.3, 0.55), 0.14);
    return color;
}

vec3 studioFloor(vec3 position, vec3 direction, Crystal glass, float seconds)
{
    vec3 toLight = keyPosition(seconds) - position;
    float falloff = 42.0 / (18.0 + dot(toLight, toLight));
    float lambert = max(normalize(toLight).y, 0.0);
    vec3 color = vec3(0.022, 0.030, 0.044)
        * (0.7 + 2.5 * lambert * falloff);
    vec2 fromCenter = position.xz - glass.center.xz;
    float pool = exp(-dot((fromCenter - vec2(0.25, -0.85)) / vec2(3.8, 3.0),
        (fromCenter - vec2(0.25, -0.85)) / vec2(3.8, 3.0)));
    color += vec3(0.021, 0.030, 0.045) * pool;

    // Area-light penumbra projected from the same key used in reflections.
    vec3 light = keyPosition(seconds);
    float projection = glass.center.y / (light.y - glass.center.y);
    vec2 shadowCenter = glass.center.xz + (glass.center.xz - light.xz) * projection;
    vec2 shadowOffset = position.xz - shadowCenter;
    vec2 shadowAxis = normalize(glass.center.xz - light.xz);
    vec2 shadowSide = vec2(-shadowAxis.y, shadowAxis.x);
    vec2 shadowLocal = vec2(dot(shadowOffset, shadowSide), dot(shadowOffset, shadowAxis));
    float broadShadow = exp(-dot(shadowLocal / vec2(1.45, 1.2), shadowLocal / vec2(1.45, 1.2)));
    // Contact follows the actual ellipsoid support point, including its tilt.
    vec3 localDown = transpose(glass.rotation) * vec3(0.0, -1.0, 0.0);
    vec3 supportPoint = glass.center + glass.rotation
        * (glass.radii * glass.radii * localDown / length(glass.radii * localDown));
    vec2 contactOffset = position.xz - supportPoint.xz;
    float contact = exp(-dot(contactOffset / vec2(0.56, 0.36), contactOffset / vec2(0.56, 0.36)));
    color *= 1.0 - 0.28 * broadShadow;
    color *= 1.0 - 0.69 * contact;

    // A finite softbox through a thick lens produces a spread focus. This is
    // an analytic energy-bounded proxy for that footprint, with a dispersed
    // crescent rather than a procedural noise pattern or animated stripes.
    vec2 focusOffset = position.xz - (shadowCenter + shadowAxis * 0.47);
    vec2 focus = vec2(dot(focusOffset, shadowSide), dot(focusOffset, shadowAxis));
    vec2 causticScale = vec2(1.17, 0.76);
    vec2 elliptic = focus / causticScale;
    float radius = length(elliptic);
    float openCrescent = smoothstep(-0.75, 0.65, elliptic.y);
    float width = 0.095 + 0.035 * abs(elliptic.x);
    vec3 arcDistance = vec3(radius) - vec3(0.94, 0.96, 0.98);
    vec3 arc = exp(-(arcDistance * arcDistance) / (width * width));
    float focusedPool = exp(-dot(focus / vec2(0.87, 0.57), focus / vec2(0.87, 0.57)));
    color += glass.tint * (arc * (0.085 * openCrescent) + vec3(0.045 * focusedPool));
    // A matte studio floor avoids a second expensive recursive glass image.
    float grazing = pow(1.0 - abs(direction.y), 5.0);
    color += vec3(0.016, 0.022, 0.032) * grazing;
    return color;
}

vec3 outsideRadiance(vec3 origin, vec3 direction, Crystal glass, float seconds)
{
    if (direction.y < -0.0001) {
        float planeDistance = -origin.y / direction.y;
        if (planeDistance > EPS) {
            vec3 floorColor = studioFloor(origin + direction * planeDistance, direction, glass, seconds);
            vec3 horizon = vec3(0.052, 0.066, 0.092);
            vec3 ground = mix(floorColor, horizon, 1.0 - exp(-0.018 * planeDistance));
            // The low side card can be encountered by a descending ray before
            // the floor. Its whole emitting rectangle is above the plane.
            ground += vec3(3.5, 4.3, 5.3) * softbox(origin, direction,
                vec3(5.2, 3.3, 2.2), vec2(0.32, 2.05), 0.095);
            return ground;
        }
    }
    return studioEnvironment(origin, direction, seconds);
}

// Each channel follows its own ray through both ellipsoid interfaces. Internal
// Fresnel reflections retain energy and total internal reflection remains in
// the solid. Four bounded interactions also handle the flattened lens edges.
float transmittedChannel(vec3 entry, vec3 incoming, vec3 normal, Crystal glass,
    float seconds, int channel)
{
    float ior = glass.ior[channel];
    float entryReflectance = fresnelDielectric(dot(-incoming, normal), 1.0, ior);
    vec3 direction = refract(incoming, normal, 1.0 / ior);
    vec3 origin = entry + direction * EPS;
    float throughput = 1.0 - entryReflectance;
    float radiance = 0.0;
    for (int bounce = 0; bounce < 4; ++bounce) {
        vec2 roots = intersectCrystal(origin, direction, glass);
        float travel = roots.y;
        if (travel <= EPS || travel >= FAR)
            break;
        vec3 exitPoint = origin + direction * travel;
        vec3 outward = crystalNormal(exitPoint, glass);
        throughput *= exp(-glass.absorption[channel] * travel);
        float internalReflectance = fresnelDielectric(dot(direction, outward), ior, 1.0);
        if (internalReflectance < 0.9999) {
            vec3 escaped = refract(direction, -outward, ior);
            radiance += throughput * (1.0 - internalReflectance)
                * outsideRadiance(exitPoint + escaped * EPS, escaped, glass, seconds)[channel];
        }
        throughput *= internalReflectance;
        if (throughput < 0.002)
            break;
        direction = reflect(direction, outward);
        origin = exitPoint + direction * EPS;
    }
    return radiance;
}

vec3 shadeCrystal(vec3 entry, vec3 direction, Crystal glass, float seconds)
{
    vec3 normal = crystalNormal(entry, glass);
    vec3 reflection = outsideRadiance(entry + normal * EPS, reflect(direction, normal), glass, seconds);
    vec3 color = vec3(0.0);
    for (int channel = 0; channel < 3; ++channel) {
        float fresnel = fresnelDielectric(dot(-direction, normal), 1.0, glass.ior[channel]);
        color[channel] = fresnel * reflection[channel]
            + transmittedChannel(entry, direction, normal, glass, seconds, channel);
    }
    return color;
}

vec3 displayTransform(vec3 color)
{
    // A gentle filmic shoulder preserves the broad white softboxes.
    color *= 1.18;
    color = clamp((color * (2.51 * color + 0.03))
        / (color * (2.43 * color + 0.59) + 0.14), 0.0, 1.0);
    return pow(color, vec3(1.0 / 2.2));
}

void main()
{
    float seconds = time * 2.0;
    Crystal glass = crystalScene(seconds);
    float aspect = viewport.x / max(viewport.y, 1.0);
    vec2 screen = vec2((qt_TexCoord0.x * 2.0 - 1.0) * aspect,
        1.0 - qt_TexCoord0.y * 2.0);
    // Portrait keeps the complete sculpture and modest negative space instead
    // of cropping the lens. Landscape reserves the left half for desktop use.
    float narrow = 1.0 - smoothstep(0.85, 1.45, aspect);
    vec3 target = vec3(0.0, 1.54, 0.0);
    target.x = mix(0.0, 1.12, narrow);
    vec3 camera = target + vec3(0.0, 1.15, 7.7);
    vec3 forward = normalize(target - camera);
    vec3 right = normalize(cross(forward, vec3(0.0, 1.0, 0.0)));
    vec3 up = cross(right, forward);
    float focal = 3.4 * min(1.0, aspect / 0.93);
    vec3 direction = normalize(forward * focal + right * screen.x + up * screen.y);
    vec3 color = outsideRadiance(camera, direction, glass, seconds);

    // Coverage derivatives are evaluated before divergence at the silhouette.
    mat3 inverseRotation = transpose(glass.rotation);
    vec3 localOrigin = (inverseRotation * (camera - glass.center)) / glass.radii;
    vec3 localDirection = (inverseRotation * direction) / glass.radii;
    float nearest = max(-dot(localOrigin, localDirection) / dot(localDirection, localDirection), 0.0);
    float signedEdge = length(localOrigin + nearest * localDirection) - 1.0;
    float pixelWidth = max(fwidth(signedEdge), 0.00015);
    vec2 hit = intersectCrystal(camera, direction, glass);
    if (hit.x > EPS && hit.x < FAR) {
        vec3 entry = camera + direction * hit.x;
        vec3 crystalColor = shadeCrystal(entry, direction, glass, seconds);
        float coverage = smoothstep(0.0, pixelWidth, -signedEdge);
        color = mix(color, crystalColor, coverage);
    }
    // No temporal grain: stationary desktop text remains visually undisturbed.
    float vignette = 1.0 - 0.12 * smoothstep(0.55, 1.5, length(screen / vec2(max(aspect, 1.0), 1.0)));
    fragColor = vec4(displayTransform(color * vignette), 1.0) * qt_Opacity;
}
