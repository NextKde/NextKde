# Adaptive glass scrim regression checks

Run `tests/glass-scrim/run.sh` from a graphical session with a C++ compiler,
pkg-config, Qt 6 Core/Gui/OpenGL development libraries and the KWin runtime.
The executable goes under `.build/glass-scrim-check/`.

The test creates its own offscreen GL surface, compiles the complete material
shader with KWin's SDF resource, and renders the actual scrim helpers to a
floating-point framebuffer. It does not install or reload the running effect.

Checks cover monotonic gradients without added contrast, matching light/dark
curves, the combined opacity ceiling for presets and fading/custom settings,
retained local tone on a two-thirds-light/one-third-dark backdrop, smooth
boundaries and suppression of fine backdrop detail.
