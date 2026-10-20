# Window appearance: implementation and VM review

[简体中文](WindowAppearance.zh-CN.md)

For AI contributors. Current code lives in `kwin/kos-bridge/windowappearance/`,
`kwin/kos-decoration/`, `kwin/glass-effect/` and `shell/native/surface-shape/`.
Use [Development](Development.md) for VM-only builds and installation; native plugin changes
require logout/login or reboot. This page replaces historical implementation proposals and audits.

## Window ownership and fallback

Bridge continuous corners use KWin `OffscreenEffect` to cache the **window's own content** and
clip the complete SSD/CSD frame. The continuous superellipse exponent is `2 + 2 * smoothness`;
this is not a claim to reproduce Apple's private curve. Continuous clipping, inward outline,
optional frame and contact/diffuse shadow share the contour. Do not additionally draw the native
arc outline/shadow over it. `arc` / zero smoothness use native outlines and decoration/image shadows.
Already painted client corners/shadows cannot be reconstructed; handle application exceptions.

Glass runs before Dock/Stage animation and Bridge in the effect chain (20 → 50 → 100).
Animation captures the clipped source; Bridge must not cache its own later animation output or
background blur. Continuous windows need translucent occlusion semantics so background behind
clipped corners is painted. Removing that flag to improve performance can produce black corners.
Glass must use the actual visual contour rather than reapply an old circular input radius.

The continuous cache has a 256 MiB budget and GPU texture-size checks. Shader/resource/geometry/
budget failure falls back to native arcs with a diagnostic. Reconsider rejection after relevant
geometry/scale/config/budget changes; do not oscillate allocation every frame. Release references on
window removal/disable. Native shadow atlas caching uses a 32 MiB LRU; active references and other
GPU resources are outside that limit. Neither limit is total compositor VRAM usage.

Slide clips continuous windows to outputs touched by their frame. Shader fallback bypasses this guard;
check shader errors before changing the clipping geometry. GLSL 1.40 / GLES 3.00 provide `fwidth` natively;
let KWin generate shader headers without adding a derivatives extension.

Overview and Present Windows thumbnails render scene items directly, bypassing Bridge's draw hook.
While either effect is active, Bridge releases continuous captures and restores native arcs before
thumbnail capture, including previously hidden continuous windows. Normal painting resumes continuous
corners after the effect exits; Slide keeps its output clipping.

## Configuration

`~/.config/kos/window-appearance.json` uses schema 2; the parser accepts schema 1 migration.
Use `window-appearance.example.json` in the source directory as a field reference. Preserve user
rules and merge fields, not a complete example over an existing file. Invalid config retains the
last valid state. App matching uses window class then desktop/resource identifiers, never title guessing.

Preserve physical versus logical outline-width semantics and schema-1 conversion. Gaussian shadow
values are sigma in logical pixels, not total extent. Focus transitions reserve enough cache margin
for both states; bounded repaint timers stop when idle. Fullscreen always disables KOS corners/outlines/shadows/controls to cover the output;
maximized behavior follows configuration. Restore normal appearance on leaving fullscreen.
Clipping does not implement content-protection padding. Settings exposes selected appearance
controls; the parser/example remains the reference for detailed rules. Palette-derived appearance and explicit per-app overrides do not
sample wallpaper or recover content already removed by the client.

## Surface-shape protocol

`kos-surface-shape-v1.xml` defines versioned capability negotiation. Preserve interface/opcode order.
Versions 1–7 apply their established immediate behavior; v8 latches pending shape state via manager
commit at the next `wl_surface.commit`. Rendering reads committed state only. Test atomic batches
and old clients. Explicit v8 geometry owns the surface even when empty/hidden; do not fall back to
whole-window blur for an intentionally empty declaration. Ordinary undeclared windows keep legacy blur.

Rounded-rectangle shapes carry geometry, visual rounding, scrim, continuous blur sigma, material
opacity and reveal/capture parameters. Tint opacity is independent of background blur; material opacity fades the complete finish.
Use explicit shape metadata, not layer-shell namespace heuristics. This contract does not promise
arbitrary rotated paths or per-shape versions of every global Glass optical setting. v8 already
supports explicit liquid/frosted profiles and independent tint; do not label those as future work. Extend existing
negotiated protocol capabilities rather than inventing a second Shell/compositor transport.

## Costs and verification

A small window damage can dirty a full offscreen window texture. Scrolling/video/resizing therefore
cost more than a static cached frame. Bridge, Dock and Stage can hold independent textures.
Shadow occlusion work may be quadratic in window count. Invalidate caches for geometry, output scale,
decoration and rules; do not free an animation source while a visible animation still references it.
Do not claim percentage improvements, leak freedom, HDR compatibility or GPU budgets without measurement.

In the VM, retain evidence for SSD and CSD, arc/continuous, light/dark and app overrides, focus/stacking,
maximized/fullscreen, move/resize, minimize/restore/close, reversal during animation and multi-output
workspace transitions. Inspect clipped corners for black fill, double outlines, stale frames, input
geometry drift and detached shadows. Test mixed scaling and state/config reloads where available.
Run bridge offline tests, actual Wayland readback and GPU readback separately, declaring skipped contexts.
Use static, scroll and video workloads at several window counts for performance review. Keep live
compositor coverage distinct from the three SDK build jobs; see [Releasing](Releasing.md).
