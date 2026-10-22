# Controls

[English integration guide](../../../docs/Components.md) · [简体中文](../../../docs/Components.zh-CN.md)

Canonical portable liquid controls, exported by the static `Kos.Ui` module.
The preview host maps `demo/Kos/Ui/controls` to this directory.

Keep effects in QML/shaders and service operations in application adapters.
`LiquidBackdrop` shares one in-window capture; `LiquidSurface` performs sampled
optics or transparent fallback. Neither supplies a texture of the real desktop.
Text fields opt in with `liquidFinish: true` and `materialForm: false`.
The slider samples its own track; other existing liquid controls retain their
gradient/mask rendering until explicitly migrated.

GLSL and matching QSB assets live in `shaders/`. Only regenerate or run them in
a VM/CI when requested. See the guide for host-owned state and source registration.
