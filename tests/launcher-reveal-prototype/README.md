# Launcher motion prototype: 50 icons and a fixed-size SDF plate

This implements stages 1 and 2 only. The plate is a flat color; background
capture, blur, refraction and highlights are not connected in this prototype.

```sh
bash tests/launcher-reveal-prototype/compile.sh
quickshell --path tests/launcher-reveal-prototype --no-color
```

The normal test window provides combined, icons-only and SDF-only modes. Space
opens/closes, Escape closes the animation, and the rapid reversal button opens,
closes after 70 ms and reopens after another 70 ms. Closing the window exits this
prototype instance.

- Fixed launcher and ShaderEffect size: 1100 × 650 logical pixels.
- Fixed grid: 10 × 5 numbered tiles, 64 pixels, 24-pixel spacing.
- Icon start scale: 0.8; start position contracts toward the grid center by
  20%, capped at 32 pixels horizontally and 24 vertically.
- X/Y/scale: 300 ms; opacity: 200 ms; all use OutCubic and Animator jobs.
- SDF: a 160 × 64 bottom-center capsule expands to the complete plate in
  320 ms, using UniformAnimator with OutCubic. Distance-based coverage keeps
  corners anti-aliased. Closing fades the last capsule to completely transparent.
- The cell and plate dimensions never animate. No item inside the plate accepts
  pointer events; this is a regular test window, not an input-catching desktop
  overlay.

The explicit Animator endpoints avoid binding-update ordering inside a change
handler. Stopping a job first makes reversals start from its current render value.
Uniform changes use the same Animator path for both motion and static test poses.

Verify on the actual Wayland scene graph:

```sh
python3 tests/launcher-reveal-prototype/run.py
```

The test checks all 50 delegates, displacement limits, fixed cell positions,
open/close endpoints and interrupted reversals. It also reads actual ShaderEffect
PNG pixels for closed, half-open, fully open and an in-flight UniformAnimator
frame. Logs and images are saved under `.build/launcher-reveal-prototype/`.
