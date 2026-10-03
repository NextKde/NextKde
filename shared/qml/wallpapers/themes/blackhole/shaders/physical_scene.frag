/**
 * Copyright (c) 2020 Eric Bruneton
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the copyright holders nor the names of its
 *    contributors may be used to endorse or promote products derived from
 *    this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */
#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 viewport;
    float time;
    float scene;
    float quality;
    float storm;
    float daylight;
    vec4 pointer;
    vec4 clickPulse;
    vec4 obstacle0;
    vec4 obstacle1;
    vec4 obstacle2;
    vec4 obstacle3;
    vec4 obstacle4;
    vec4 obstacle5;
    vec4 obstacle6;
    vec4 obstacle7;
} u;

layout(binding=1) uniform sampler2D deflectionTable;
layout(binding=2) uniform sampler2D inverseRadiusTable;
layout(binding=3) uniform sampler2D blackBodyTable;
layout(binding=4) uniform sampler2D noiseTexture;
layout(binding=5) uniform sampler2D dopplerTable;
#define IN(T) T
#define OUT(T) out T
#define RAY_DEFLECTION_TEXTURE_WIDTH 512
#define RAY_DEFLECTION_TEXTURE_HEIGHT 512
#define RAY_INVERSE_RADIUS_TEXTURE_WIDTH 64
#define RAY_INVERSE_RADIUS_TEXTURE_HEIGHT 32
const float rad=1.0;
const float pi=3.141592653589793;
#define Angle float
#define Real float

// An angle and a time (in the 1st and 2nd components, respectively).
#define TimedAngle vec2

// An inverse distance and a time (in the 1st and 2nd components, respectively).
#define TimedInverseDistance vec2

// A 2D texture with TimedAngle values.
#define RayDeflectionTexture sampler2D

// A 2D texture with TimedInverseDistance values.
#define RayInverseRadiusTexture sampler2D





const Real kMu = 4.0 / 27.0;

Real GetRayDeflectionTextureUFromEsquare(const Real e_square) {
  if (e_square < kMu) {
    return 0.5 - sqrt(-log(1.0 - e_square / kMu) * (1.0 / 50.0));
  } else {
    return 0.5 + sqrt(-log(1.0 - kMu / e_square) * (1.0 / 50.0));
  }
}



Real GetUapsisFromEsquare(const Real e_square) {
  Real x = (2.0 / kMu) * e_square - 1.0;
  return 1.0 / 3.0 + (2.0 / 3.0) * sin(asin(x) * (1.0 / 3.0));
}

Real GetRayDeflectionTextureVFromEsquareAndU(const Real e_square,
                                             const Real u) {
  if (e_square > kMu) {
    Real x = u < 2.0 / 3.0 ? -sqrt(2.0 / 3.0 - u) : sqrt(u - 2.0 / 3.0);
    return (sqrt(2.0 / 3.0) + x) / (sqrt(2.0 / 3.0) + sqrt(1.0 / 3.0));
  } else {
    return 1.0 - sqrt(max(1.0 - u / GetUapsisFromEsquare(e_square), 0.0));
  }
}



Real GetTextureCoordFromUnitRange(const Real x, const int texture_size) {
  return 0.5 / Real(texture_size) + x * (1.0 - 1.0 / Real(texture_size));
}

TimedAngle LookupRayDeflection(IN(RayDeflectionTexture) ray_deflection_texture,
                               const Real e_square, const Real u,
                               OUT(TimedAngle) deflection_apsis) {
  Real tex_u = GetTextureCoordFromUnitRange(
      GetRayDeflectionTextureUFromEsquare(e_square),
      RAY_DEFLECTION_TEXTURE_WIDTH);
  Real tex_v = GetTextureCoordFromUnitRange(
      GetRayDeflectionTextureVFromEsquareAndU(e_square, u),
      RAY_DEFLECTION_TEXTURE_HEIGHT);
  Real tex_v_apsis =
      GetTextureCoordFromUnitRange(1.0, RAY_DEFLECTION_TEXTURE_HEIGHT);
  deflection_apsis =
      texture(ray_deflection_texture, vec2(tex_u, tex_v_apsis)).xy;
  return texture(ray_deflection_texture, vec2(tex_u, tex_v)).xy;
}



Angle GetPhiUbFromEsquare(const Real e_square) {
  return (1.0 + e_square) / (1.0 / 3.0 + 2.0 * e_square * sqrt(e_square)) * rad;
}



Real GetRayInverseRadiusTextureUFromEsquare(const Real e_square) {
  return 1.0 / (1.0 + 6.0 * e_square);
}



TimedInverseDistance LookupRayInverseRadius(IN(RayInverseRadiusTexture)
                                                ray_inverse_radius_texture,
                                            const Real e_square,
                                            const Angle phi) {
  Real tex_u = GetTextureCoordFromUnitRange(
      GetRayInverseRadiusTextureUFromEsquare(e_square),
      RAY_INVERSE_RADIUS_TEXTURE_WIDTH);
  Real tex_v = GetTextureCoordFromUnitRange(phi / GetPhiUbFromEsquare(e_square),
                                            RAY_INVERSE_RADIUS_TEXTURE_HEIGHT);
  return texture(ray_inverse_radius_texture, vec2(tex_u, tex_v)).xy;
}



// Anti-aliased pulse function. See
// https://renderman.pixar.com/resources/RenderMan_20/basicAntialiasing.html.
Real FilteredPulse(Real edge0, Real edge1, Real x, Real fw) {
  fw = max(fw, 1e-6);
  Real x0 = x - fw * 0.5;
  Real x1 = x0 + fw;
  return max(0.0, (min(x1, edge1) - max(x0, edge0)) / fw);
}

Angle TraceRay(IN(RayDeflectionTexture) ray_deflection_texture,
               IN(RayInverseRadiusTexture) ray_inverse_radius_texture,
               const Real u, const Real u_dot, const Real e_square,
               const Angle delta, const Angle alpha, const Real u_ic,
               const Real u_oc, OUT(Real) u0, OUT(Angle) phi0, OUT(Real) t0,
               OUT(Real) alpha0, OUT(Real) u1, OUT(Angle) phi1, OUT(Real) t1,
               OUT(Real) alpha1) {
  // Compute the ray deflection.
  u0 = -1.0;
  u1 = -1.0;
  if (e_square < kMu && u > 2.0 / 3.0) {
    return -1.0 * rad;
  }
  TimedAngle deflection_apsis;
  TimedAngle deflection = LookupRayDeflection(ray_deflection_texture, e_square,
                                              u, deflection_apsis);
  Angle ray_deflection = deflection.x;
  if (u_dot > 0.0) {
    ray_deflection =
        e_square < kMu ? 2.0 * deflection_apsis.x - ray_deflection : -1.0 * rad;
  }
  // Compute the accretion disc intersections.
  Real s = sign(u_dot);
  Angle phi = deflection.x + (s == 1.0 ? pi - delta : delta) + s * alpha;
  Angle phi_apsis = deflection_apsis.x + pi / 2.0;
  phi0 = mod(phi, pi);
  TimedInverseDistance ui0 =
      LookupRayInverseRadius(ray_inverse_radius_texture, e_square, phi0);
  if (phi0 < phi_apsis) {
    Real side = s * (ui0.x - u);
    if (side > 1e-3 || (side > -1e-3 && alpha < delta)) {
      u0 = ui0.x;
      phi0 = alpha + phi - phi0;
      t0 = s * (ui0.y - deflection.y);
    }
  }
  phi = 2.0 * phi_apsis - phi;
  phi1 = mod(phi, pi);
  TimedInverseDistance ui1 =
      LookupRayInverseRadius(ray_inverse_radius_texture, e_square, phi1);
  if (e_square < kMu && s == 1.0 && phi1 < phi_apsis) {
    u1 = ui1.x;
    phi1 = alpha + phi - phi1;
    t1 = 2.0 * deflection_apsis.y - ui1.y - deflection.y;
  }
  // Compute the anti-aliasing opacity values.
  Real fw0 = min(fwidth(ui0.x), fwidth(u0 == -1.0 ? u1 : u0));
  Real fw1 = min(fwidth(ui1.x), fwidth(u1 == -1.0 ? u0 : u1));
  alpha0 = FilteredPulse(u_oc, u_ic, u0, fw0);
  alpha1 = FilteredPulse(u_oc, u_ic, u1, fw1);
  if (s == 1.0 && abs(e_square - kMu) < min(fwidth(e_square), kMu)) {
    if (alpha0 < 0.99) u0 = 2.0 / (1.0 / u_ic + 1.0 / u_oc);
    if (alpha1 < 0.99) u1 = 2.0 / (1.0 / u_ic + 1.0 / u_oc);
  }
  return ray_deflection;
}

Angle TraceRay(IN(RayDeflectionTexture) ray_deflection_texture,
               IN(RayInverseRadiusTexture) ray_inverse_radius_texture,
               const Real p_r, const Angle delta, const Angle alpha,
               const Real u_ic, const Real u_oc, OUT(Real) u0,
               OUT(Angle) phi0, OUT(Real) t0, OUT(Real) alpha0, OUT(Real) u1,
               OUT(Angle) phi1, OUT(Real) t1, OUT(Real) alpha1) {
  Real u = 1.0 / p_r;
  Real u_dot = -u / tan(delta);
  Real e_square = u_dot * u_dot + u * u * (1.0 - u);
  return TraceRay(ray_deflection_texture, ray_inverse_radius_texture, u,
                  u_dot, e_square, delta, alpha, u_ic, u_oc, u0, phi0, t0,
                  alpha0, u1, phi1, t1, alpha1);
}

float hash(vec3 p) { p=fract(p*0.1031); p+=dot(p,p.yzx+33.33); return fract((p.x+p.y)*p.z); }
float noise(vec3 p) {
    vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),
               mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
float fbm(vec3 p) {
    float v=0.0, a=0.5;
    for(int i=0;i<5;i++) { v+=a*noise(p); p=p*2.03+vec3(3.7,1.1,7.2); a*=0.48; }
    return v;
}
vec3 stars(vec2 uv) {
    vec3 c=vec3(0);
    for(int j=0;j<3;j++) {
        float scale=170.0+float(j)*113.0;
        vec2 cell=floor(uv*scale), f=fract(uv*scale)-0.5;
        float seed=hash(vec3(cell,float(j)));
        vec2 pos=vec2(seed,hash(vec3(cell,8.0)))*0.68-0.34;
        float d=length(f-pos);
        float lum=pow(seed,24.0);
        // Fade unresolved lensed stars rather than drawing stretched dotted arcs.
        vec2 footprint=fwidth(uv*scale);
        float resolved=1.0-smoothstep(0.35,0.9,max(footprint.x,footprint.y));
        float star=exp(-d*d*850.0)*lum*2.0*resolved;
        float halo=exp(-d*d*48.0)*lum*0.05*resolved;
        vec3 tint=mix(vec3(0.42,0.65,1.0),vec3(1.0,0.72,0.42),seed);
        c+=tint*(star+halo);
    }
    return c;
}
vec3 nebula(vec2 p) {
    vec3 q=vec3(p*2.3,u.time*0.008);
    float warp=fbm(q*0.7+vec3(9.0));
    float n=fbm(q+vec3(warp*1.9,warp*1.4,0));
    float ridge=pow(max(0.0,1.0-abs(p.y+p.x*0.3+sin(p.x*2.1)*0.11)*2.4),2.0);
    float dust=pow(fbm(q*2.0+vec3(7.0)),3.0);
    float emission=pow(n,3.1)*ridge*3.8;
    vec3 color=mix(vec3(0.05,0.22,0.42),vec3(0.8,0.21,0.07),smoothstep(0.35,0.8,p.x*0.3+n));
    return color*emission*(1.0-dust*1.6)+vec3(0.004,0.008,0.017);
}
vec3 temperature(float t) {
    return mix(vec3(1.0,0.15,0.015),mix(vec3(1.0,0.62,0.18),vec3(0.75,0.9,1.0),smoothstep(4000.0,11000.0,t)),smoothstep(1000.0,4500.0,t));
}
const float INNER_DISC_R=3.0;
const float OUTER_DISC_R=12.0;
const int NUM_DISC_PARTICLES=12;
const vec4 DISC_PARTICLE_PARAMS[12]=vec4[12](vec4(0.296423430,0.333333333,4.913633352,0.115682782),vec4(0.252554380,0.266666667,5.556656508,0.236118677),vec4(0.185960761,0.222222222,6.001172779,0.312571862),vec4(0.167869332,0.190476190,2.069687666,0.341462680),vec4(0.141404052,0.166666667,0.702912415,0.368253695),vec4(0.132742168,0.148148148,0.858312186,0.381973414),vec4(0.113865387,0.133333333,3.557023995,0.398301270),vec4(0.103635455,0.121212121,0.869676545,0.408778116),vec4(0.095992543,0.111111111,4.992856473,0.416908079),vec4(0.099849754,0.102564103,0.652948428,0.419030971),vec4(0.093777694,0.095238095,1.638588313,0.425033835),vec4(0.076798751,0.088888889,0.585343390,0.435290654));

float RayTrace(float u,float ud,float es,float delta,float alpha,float ui,float uo,
    out float u0,out float phi0,out float t0,out float a0,out float u1,out float phi1,out float t1,out float a1);
vec3 Doppler(vec3 rgb,float factor);
vec3 GalaxyColor(vec3 d);
vec3 StarColor(vec3 d,float amplification);
float Noise(vec2 p);
vec4 DiscColor(vec2 p,float t,bool top,float doppler);
vec3 BlackBodyColor(sampler2D black_body_texture, float temperature) {
  float tex_u = (1.0 / 6.0) * log(temperature * (1.0 / 100.0));
  return texture(black_body_texture, vec2(tex_u, 0.5)).rgb;
}



// Returns the light emitted by the accretion disc at 'p', at time 'p_t',
// shifted by the given Doppler factor. The 1D texture should contain the light
// emitted by a black body at temperature T at texture coord log(T / 100) / 6.
// The following constants must be provided by the user:
// - const float INNER_DISC_R = ...;
// - const float OUTER_DISC_R = ...;
// - const int NUM_DISC_PARTICLES = ...;
// - const vec4 DISC_PARTICLE_PARAMS[NUM_DISC_PARTICLES] = ...;
// They define the inner and outer radius of the disc, the number of particles
// used to compute its density, and the orbital parameters for each particle
// (inverse max and min radius, initial azimuth angle, precession 'ratio').
vec4 DefaultDiscColor(vec2 p, float p_t, bool top_side, float doppler_factor,
                      float disc_temperature, sampler2D black_body_texture) {
  float p_r = length(p);
  float p_phi = atan(p.y, p.x);

  float density = 0.0;
  for (int i = 0; i < NUM_DISC_PARTICLES; ++i) {
    vec4 params = DISC_PARTICLE_PARAMS[i];
    float u1 = params.x;
    float u2 = params.y;
    float phi0 = params.z;
    float dtheta_dphi = params.w;
    float u_avg = (u1 + u2) * 0.5;
    float dphi_dt = u_avg * sqrt(0.5 * u_avg);
    float phi = dphi_dt * p_t + phi0;
    float a = mod(p_phi - phi, 2.0 * pi);
    float s = sin(dtheta_dphi * (a + phi));
    float r = 1.0 / (u1 + (u2 - u1) * s * s);
    vec2 d = vec2(a - pi, r - p_r) * vec2(1.0 / pi, 0.5);
    float noise = Noise(d * vec2(p_r / OUTER_DISC_R, 1.0));
    density += smoothstep(1.0, 0.0, length(d)) * noise;
  }

  const float r_max = 49.0 / 12.0;
  const float temperature_profile_max =
      pow((1.0 - sqrt(3.0 / r_max)) / (r_max * r_max * r_max), 0.25);
  float temperature_profile =
      pow((1.0 - sqrt(3.0 / p_r)) / (p_r * p_r * p_r), 0.25);
  float temperature =
      disc_temperature * temperature_profile * (1.0 / temperature_profile_max);

  vec3 color = max(density, 0.0) *
      BlackBodyColor(black_body_texture, temperature * doppler_factor);
  float alpha = smoothstep(INNER_DISC_R, INNER_DISC_R * 1.2, p_r) *
      smoothstep(OUTER_DISC_R, OUTER_DISC_R / 1.2, p_r);
  return vec4(color * alpha, alpha);
}



// Finds the intersection of the given view ray with the scene, computes the
// emitted light at these intersection points, computes the corresponding
// received light, and composites and returns the final pixel color.
//
// Inputs:
// - camera_position: the camera position, in Schwarzschild coordinates
//     (p^t, p^r, p^theta, p^phi).
// - p: the camera position, in (pseudo-)Cartesian coordinates.
// - k_s: the camera 4-velocity, in Schwarzschild coordinates.
// - e_tau, e_w, e_h, e_d: the base vectors of the camera reference frame, in
//     (pseudo-)Cartesian coordinates.
// - view_dir: the view ray direction, in the camera reference frame.
vec3 SceneColor(vec4 camera_position, vec3 p, vec4 k_s, vec3 e_tau, vec3 e_w,
                vec3 e_h, vec3 e_d, vec3 view_dir) {
  vec3 q = normalize(view_dir);
  vec3 d = -e_tau + q.x * e_w + q.y * e_h + q.z * e_d;

  vec3 e_x_prime = normalize(p);
  vec3 e_z_prime = normalize(cross(e_x_prime, d));
  vec3 e_y_prime = normalize(cross(e_z_prime, e_x_prime));

  const vec3 e_z = vec3(0.0, 0.0, 1.0);
  vec3 t = normalize(cross(e_z, e_z_prime));
  if (dot(t, e_y_prime) < 0.0) {
    t = -t;
  }

  float alpha = acos(clamp(dot(e_x_prime, t), -1.0, 1.0));
  float delta = acos(clamp(dot(e_x_prime, normalize(d)), -1.0, 1.0));

  float u = 1.0 / camera_position[1];
  float u_dot = -u / tan(delta);
  float e_square = u_dot * u_dot + u * u * (1.0 - u);
  float e = -sqrt(e_square);

  const float U_IC = 1.0 / INNER_DISC_R;
  const float U_OC = 1.0 / OUTER_DISC_R;
  float u0, phi0, t0, alpha0, u1, phi1, t1, alpha1;
  float deflection = RayTrace(u, u_dot, e_square, delta, alpha, U_IC, U_OC,
                              u0, phi0, t0, alpha0, u1, phi1, t1, alpha1);

  vec4 l = vec4(e / (1.0 - u), -u_dot, 0.0, u * u);
  float g_k_l_receiver = k_s.x * l.x * (1.0 - u) - k_s.y * l.y / (1.0 - u) -
                         u * dot(e_tau, e_y_prime) * l.w / (u * u);

  float delta_prime = delta + max(deflection, 0.0);
  vec3 d_prime = cos(delta_prime) * e_x_prime + sin(delta_prime) * e_y_prime;

  vec3 color = vec3(0.0, 0.0, 0.0);
  if (deflection >= 0.0) {
    float g_k_l_source = e;
    float doppler_factor = g_k_l_receiver / g_k_l_source;

    // The solid angle (times 4pi) of the pixel.
    float omega = length(cross(dFdx(q), dFdy(q)));
    // The solid angle (times 4pi) of the deflected light beam.
    float omega_prime = length(cross(dFdx(d_prime), dFdy(d_prime)));

    float lensing_amplification_factor = omega / omega_prime;
    // Clamp the result (otherwise potentially infinite).
    lensing_amplification_factor = min(lensing_amplification_factor, 1e6);

    // The galaxy texture contains the radiant intensity of stars, per unit area
    // on the celestial sphere, i.e. radiance values (using omega0 as area unit,
    // with omega0 = 4pi * the solid angle of the center texel of a cube face).
    // The stars texture contains radiant intensities. To convert the total
    // intensity inside a pixel to a radiance, this intensity must be divided by
    // the pixel area on the celestial sphere. Expressed in the units used for
    // the galaxy texture, this area is omega / omega0 (where, since the galaxy
    // texture is a 2048x2048 cubemap, omega0 is 1 / 1024^2).
    float pixel_area = max(omega * (1024.0 * 1024.0), 1.0);

    color += GalaxyColor(d_prime);
    // Procedural star points become concentric streaks under extreme lensing.
    // Keep the close black-hole background diffuse rather than drawing a false rim.
    color += StarColor(d_prime, lensing_amplification_factor / pixel_area)*0.08;
    color = Doppler(color, doppler_factor);
  }
  if (u1 >= 0.0 && alpha1 > 0.0) {
    float g_k_l_source = e * sqrt(2.0 / (2.0 - 3.0 * u1)) -
                         u1 * sqrt(u1 / (2.0 - 3.0 * u1)) * dot(e_z, e_z_prime);
    float doppler_factor = g_k_l_receiver / g_k_l_source;
    bool top_side =
        (mod(abs(phi1 - alpha), 2.0 * pi) < 1e-3) == (e_x_prime.z > 0.0);

    vec3 i1 = (e_x_prime * cos(phi1) + e_y_prime * sin(phi1)) / u1;
    vec4 disc_color =
        DiscColor(i1.xy, camera_position[0] - t1, top_side, doppler_factor);
    color = color * (1.0 - disc_color.a) + alpha1 * disc_color.rgb;
  }
  if (u0 >= 0.0 && alpha0 > 0.0) {
    float g_k_l_source = e * sqrt(2.0 / (2.0 - 3.0 * u0)) -
                         u0 * sqrt(u0 / (2.0 - 3.0 * u0)) * dot(e_z, e_z_prime);
    float doppler_factor = g_k_l_receiver / g_k_l_source;
    bool top_side =
        (mod(abs(phi0 - alpha), 2.0 * pi) < 1e-3) == (e_x_prime.z > 0.0);

    vec3 i0 = (e_x_prime * cos(phi0) + e_y_prime * sin(phi0)) / u0;
    vec4 disc_color =
        DiscColor(i0.xy, camera_position[0] - t0, top_side, doppler_factor);
    color = color * (1.0 - disc_color.a) + alpha0 * disc_color.rgb;
  }
  return color;
}

float RayTrace(float u,float ud,float es,float delta,float alpha,float ui,float uo,
    out float u0,out float phi0,out float t0,out float a0,out float u1,out float phi1,out float t1,out float a1) {
    return TraceRay(deflectionTable,inverseRadiusTable,u,ud,es,delta,alpha,ui,uo,u0,phi0,t0,a0,u1,phi1,t1,a1);
}
// Exact trilinear sampling of the original 64x32x64 LUT in a 2D atlas.
vec3 DopplerSlice(vec2 uv,float z) {
    vec2 tile=vec2(mod(z,8.0),floor(z/8.0));
    vec2 pixel=clamp(uv*vec2(64,32),vec2(0.5),vec2(63.5,31.5));
    return texture(dopplerTable,(tile*vec2(64,32)+pixel)/vec2(512,256)).rgb;
}
vec3 Doppler(vec3 rgb,float factor) {
    float sum=rgb.r+rgb.g+rgb.b;
    if(sum<=0.0) return vec3(0);
    vec3 uv=vec3(rgb.r/sum,2.0*rgb.g/sum,atan(log(max(factor,1e-6))/0.21)/3.0+0.5);
    float z=clamp(uv.z*64.0-0.5,0.0,63.0);
    return sum*mix(DopplerSlice(uv.xy,floor(z)),DopplerSlice(uv.xy,min(floor(z)+1.0,63.0)),fract(z));
}
vec3 GalaxyColor(vec3 d) {
    vec2 sky=vec2(atan(d.x,-d.y),asin(clamp(d.z,-1.0,1.0)));
    return nebula(sky)*0.045;
}
vec3 StarColor(vec3 d,float amplification) {
    vec2 sky=vec2(atan(d.x,-d.y),asin(clamp(d.z,-1.0,1.0)));
    return stars(sky)*0.8*clamp(amplification,0.3,2.0);
}
float Noise(vec2 p) { return 3.0*(texture(noiseTexture,p).r-0.5)+1.0; }
vec4 DiscColor(vec2 p,float t,bool top,float doppler) {
    vec4 color=DefaultDiscColor(p,t,top,doppler,5600.0,blackBodyTable);
    float radius=length(p), angle=atan(p.y,p.x);
    // Advected multi-scale disc filaments retain structure in the close view.
    float grain=fbm(vec3(radius*9.0,angle*radius*3.0-t*0.22,radius*0.8));
    color.rgb*=0.65+0.70*grain;
    return vec4(color.rgb*1.0e-6,color.a);
}

vec3 blackhole(vec2 pixel) {
    vec3 camera=vec3(0.0,-22.0,1.8);
    float radius=length(camera), inverseCameraRadius=1.0/radius;
    vec3 f=normalize(-camera), right=normalize(cross(f,vec3(0,0,1))), up=cross(right,f);
    vec3 ex=normalize(camera);
    // Static orthonormal observer frame in pseudo-Cartesian coordinates.
    float radial=sqrt(1.0-inverseCameraRadius)-1.0;
    vec3 ew=right+ex*dot(right,ex)*radial;
    vec3 eh=up+ex*dot(up,ex)*radial;
    vec3 ed=f+ex*dot(f,ex)*radial;
    vec3 traced=SceneColor(vec4(u.time*8.0,radius,0,0),camera,
        vec4(1.0/sqrt(1.0-inverseCameraRadius),0,0,0),vec3(0),ew,eh,ed,vec3(mat2(0.951,0.309,-0.309,0.951)*pixel*0.20,1.0));
    return traced;
}
vec3 atmosphere(vec2 p) {
    // Single-scattering optical-depth integration. The phase function uses a
    // Henyey-Greenstein aerosol lobe plus Rayleigh scattering; procedural
    // density is artistic, rather than a numerical fluid solver.
    vec3 light=vec3(0); float trans=1.0;
    vec3 ro=vec3(0,0,-2), rd=normalize(vec3(p,1.3));
    vec3 sunDir=normalize(vec3(0.6,-0.24,1.0));
    float mu=dot(rd,sunDir), g=0.78;
    float rayleigh=0.75*(1.0+mu*mu);
    float mie=(1.0-g*g)/pow(max(0.04,1.0+g*g-2.0*g*mu),1.5);
    vec3 drift=vec3(u.time*0.018,0,u.time*0.009);
    vec3 sunColor=mix(vec3(0.09,0.28,0.65),vec3(1.0,0.61,0.25),u.daylight);
    for(int i=0;i<28;i++) {
        vec3 pos=ro+rd*(float(i)*0.19);
        float n=fbm(pos*1.85+drift);
        float density=smoothstep(0.39,0.70,n)*(0.75+u.storm)*0.38;
        float occlusion=0.0;
        for(int j=1;j<=3;j++) {
            float sampleDensity=fbm((pos+sunDir*float(j)*0.28)*1.85+drift);
            occlusion+=smoothstep(0.40,0.67,sampleDensity)*0.8;
        }
        float visibility=exp(-occlusion*2.3);
        vec3 ambient=vec3(0.015,0.048,0.080);
        vec3 scatter=ambient+sunColor*visibility*(0.15*rayleigh+0.16*mie);
        light+=trans*scatter*density*2.5;
        trans*=exp(-density*1.6);
    }
    light+=trans*(vec3(0.004,0.014,0.032)+sunColor*pow(max(0.0,mu),4200.0)*1.8);
    // Filamentary mist catches grazing blue light, not cartoon cloud shapes.
    vec3 q=vec3(p*3.8,u.time*0.015);
    float turbulence=fbm(q+vec3(fbm(q*0.65)*2.0));
    float filament=pow(max(0.0,1.0-abs(turbulence-0.53)*19.0),7.0);
    float band=exp(-pow(p.y+sin(p.x*1.8)*0.18-0.15,2.0)*5.0);
    light+=vec3(0.024,0.15,0.24)*filament*band*(0.5+u.storm);
    return light;
}
vec3 aces(vec3 x) { return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14),0.0,1.0); }
void main() {
    vec2 aspect=vec2(u.viewport.x/u.viewport.y,1.0);
    vec2 at=qt_TexCoord0;
    vec2 relative=(at-u.pointer.xy)*aspect;
    float radius=length(relative);
    float influence=exp(-radius*radius*70.0)*u.pointer.z;
    vec2 displacement=(relative*0.15+vec2(-relative.y,relative.x)*0.22)*influence;
    float age=u.time-3.8-u.clickPulse.z;
    vec2 burst=(at-u.clickPulse.xy)*aspect;
    float burstRadius=length(burst);
    float wave=exp(-pow((burstRadius-age*0.24)*65.0,2.0))*exp(-max(age,0.0)*1.2)*step(0.0,age);
    displacement+=burst/max(burstRadius,0.005)*wave*0.012;
    vec4 obstacles[8]=vec4[8](u.obstacle0,u.obstacle1,u.obstacle2,u.obstacle3,u.obstacle4,u.obstacle5,u.obstacle6,u.obstacle7);
    float edgeLight=0.0;
    for(int i=0;i<8;i++) {
        vec4 card=obstacles[i];
        if(card.z<=0.0) continue;
        vec2 middle=card.xy+card.zw*0.5;
        vec2 delta=(at-middle)*aspect;
        vec2 halfSize=card.zw*aspect*0.5;
        float corner=min(0.018,min(halfSize.x,halfSize.y)*0.3);
        vec2 edgeDelta=abs(delta)-halfSize+corner;
        vec2 outside=max(edgeDelta,vec2(0));
        float distance=length(outside)+min(max(edgeDelta.x,edgeDelta.y),0.0)-corner;
        float activation=exp(-pow(length(max(abs((u.pointer.xy-middle)*aspect)-halfSize,vec2(0)))*9.0,2.0))*u.pointer.z;
        vec2 normal=normalize(sign(delta)*outside+vec2(0.00001));
        float skirt=exp(-distance*distance*1600.0)*smoothstep(0.0,0.004,distance);
        displacement+=normal*skirt*0.008;
        edgeLight+=skirt*activation*(0.7+0.3*sin((delta.x+delta.y)*24.0-u.time*4.0));
    }
    vec2 p=(at+displacement/aspect-0.5)*aspect*2.0;
    vec3 color;
    if(u.scene<0.5) color=nebula(p)+stars(p*0.55);
    else if(u.scene<1.5) color=blackhole(p-vec2(0.70*u.viewport.x/u.viewport.y,-0.08))*0.12;
    else color=atmosphere(p);
    // Input distorts the scene itself, and adds a short-lived energy response.
    vec3 tint=u.scene>0.5 && u.scene<1.5 ? vec3(1.0,0.55,0.20) : vec3(0.15,0.65,1.0);
    color+=tint*(wave*0.30+edgeLight*0.06+influence*0.035);
    float vignette=1.0-smoothstep(0.5,2.0,length(p))*0.45;
    color=pow(aces(color*1.35),vec3(1.0/2.2))*vignette;
    fragColor=vec4(color,1.0)*u.qt_Opacity;
}
