# Foundation

Portable Qt Quick foundations for standalone applications. The components in
this directory are built as the static `Kos.Ui` QML module and must not import
Quickshell, KWin, or Wayland-specific APIs.

The module currently provides the application window, palette, cards, empty
states, navigation controls, and the portable `LiquidTextField`. Other legacy
controls stay on their existing direct-import path until their lint and
accessibility debt is addressed.
