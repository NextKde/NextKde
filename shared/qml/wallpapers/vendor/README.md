# Community wallpaper ports

## David Li Flow (MIT)

Source: https://github.com/dli/flow. `flow/flow.js` is an unmodified reference;
`flow/LICENSE` retains copyright and license. The GPU simulation ports its
analytic 4D simplex derivatives and curl velocity, with deterministic seeds,
seconds clock, three octaves and bounded lifetime/domain. Each shell surface
holds a recursive RGBA32F state texture with explicit updates (`live: false`).
Sprites sample this texture even before initialization; masking by lifetime
prevents startup dots. Hiding the delegates before the first texture update
caused a circular initialization wait and has been corrected.

Local sprites, orbital/weather drift and count limits remain adaptations.
Upstream half-angle volume slicing, shadow accumulation and opacity sorting are
not implemented. Independent windows can still differ under missed frames.

## Eric Bruneton Black Hole (BSD-3-Clause)

Source: https://github.com/ebruneton/black_hole_shader. Original definitions,
TraceRay functions, model.glsl, shader manager reference and LICENSE are retained.
The scene now uses the upstream SceneColor, DefaultDiscColor and BlackBodyColor,
including disc-plane intersection coordinates, retarded travel time, elliptical
orbital density, near/far opacity compositing and source/observer frequency ratio.
Ring parameters use the upstream generation algorithm with deterministic seed 129.

Official data downloaded from https://ebruneton.github.io/black_hole_shader/demo/:
deflection.dat, inverse_radius.dat, black_body.dat, doppler.dat and noise_texture.png.
Hashes are recorded in `black-hole/SHA256SUMS.json`. `encode_tables.py` preserves
all float32 bits in opaque PNGs; decode_table.frag reconstructs these once into
RGBA32F textures. This avoids normalized image quantization and premultiplication.
Doppler's original 64x32x64 LUT is tiled into an 8x8 2D atlas; the shader performs
equivalent trilinear interpolation. Decoder requires OpenGL 3.3 / GLES 3.0 or a
modern Qt RHI backend, rather than GLES 2.

Local changes: fixed static camera, scaled radiance, disc temperature/opacity,
ACEs tone mapping, bounded bloom, procedural sky in place of the Gaia cube maps,
and bounded foreground sprites. The full demo UI, orbiting camera and spacecraft
are not part of this wallpaper port. The Gaia/star data and original star filtering
remain unported; no claim of pixel-identical output to the original demo is made.

## Verification

After user authorization to override the repository's manual-only restriction,
real Quickshell windows rendered screenshots and timing logs. The GPU state
advances; animated frames differ in RGB and paused frames are identical. Logs
contained no new QML/shader errors. Timings are Qt render-thread wall times, not
a standalone GPU benchmark. Results: `.build/wallpaper-review/`.
