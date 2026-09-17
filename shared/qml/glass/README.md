# Glass

Portable QML-only liquid-glass visuals and fallback layers. This directory is
usable by standalone applications and must not import Quickshell, KWin, Wayland
or compositor blur APIs.

`shell/desktop/modules/common/LiquidGlassPanel.qml` is the shell-specific
counterpart: when `useKwinEffect` is enabled it publishes the compositor blur
region, exact surface shape and optional contrast scrim, while KWin paints the
glass finish. When disabled, it uses the portable QML surface as its fallback.
Keep compositor integration in `shell/desktop/` and reusable visual primitives
here.
