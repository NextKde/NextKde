# Glass

Ground-up rewrite of the NextKDE KWin Glass effect. The tree started clean:
no code, comments or documentation were carried over from the previous
`kwin/glass-effect` implementation, which has since been removed.

Status: feature-complete against the v9 `kos_surface_shape_v1` contract. The
effect captures the backdrop under each declared shape, runs a four-level Dual
Kawase chain and composites a rounded, tinted material with the liquid edge
lens, rim glints and soft-glass diffusion/sheen. Capture rects are
grid-stabilised, the chain result is reused while no backdrop pixel changes,
and each Kawase level is redrawn only inside the propagated damage region.
Implemented on top of that: readability scrim, per-shape blur levels, reveal
animation, per-shape pointer effects (hover light, edge-only lens parallax,
click ripple, muxed by the v9 `set_pointer_effects` mask), and the
`kwin_glass_config` settings module. Not implemented: per-shape noise,
Mica/wallpaper backdrop sources, global color-matrix grading.

## Build

```sh
cmake -S kwin/glass -B .build/glass -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build .build/glass
```

The plugin installs to `kwin/effects/plugins` under the configured install
prefix. KWin plugin changes require a logout/login; never hot-replace the `.so`.
The optional settings module needs KF6 KCMUtils and KWin's Effects D-Bus
interface; without them only the effect is built.

## Provenance

The rewrite follows KWin's public effect API and the behavior contract described
in [Window appearance](../../docs/WindowAppearance.md). The previous
`kwin/glass-effect` tree was deleted after parity; its translations live beside
this tree under the repository license, and the repository-level Nix packaging
builds this one.
