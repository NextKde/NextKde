# Desktop icon spacing

[简体中文](DesktopIcons.zh-CN.md)

Right-click the desktop background and choose icon spacing: loose, compact or tighter.
Spacing is independent of icon size, display scaling and files. Labels keep at most two lines,
using actual font height. The preference is `DesktopFiles/iconSpacing` in
`deskcenter-desktop-files.ini`; old configurations default to loose.

## Desktop surface ownership

`DeskCenterWindow.qml` hosts widgets, icons and their context menu on each output.
Its layer-shell namespace is `desktop`, which makes KWin exclude it from ordinary
window close/move shortcuts. Keep its Bottom layer: moving it to Background can
put it behind Plasma. `installDesktopStack()` in the platform-owned
`kwin/window-bridge.js` orders existing Below-layer surfaces as wallpaper < widgets
< Stage strip, independently of Stage mode and mapping order. It never changes
visibility or virtual-desktop membership and never recreates a surface.

Glass accepts Desktop-typed Quickshell surfaces only when they explicitly declare
a nonempty content region. Wallpapers and legacy empty-region whole-window blur
remain excluded. `kos-deskcenter.desktop-stack` covers mapping permutations and
reentrant stacking signals; `kos-glass.desktop-blur` covers this opt-in boundary.

## Widget placement and resizing

In desktop edit mode, drag a widget to a free grid rectangle or use its bottom-right
handle to resize it to 1×1, 1×2, 2×2 or 2×1. The drop preview distinguishes occupied
cells from available cells. Moving a widget fixes the other visible cards in place.
Widget spans and per-output positions are stored alongside the existing size/order
preferences by `DeskCenterConfigService`; existing small/medium/large values remain valid.
Packing reserves saved positions first, expands into available desktop columns, and
projects conflicting or out-of-bounds positions onto the current output without
rewriting the original coordinates. On short outputs it temporarily compacts cards.
The desktop file area starts after the occupied widget columns. Widget expansion
reserves at least one file/drop column, and more for current files up to the original
four-widget-column layout capacity. Resize previews reject occupied/out-of-bounds
rectangles instead of repacking neighbours. Moving a card only persists that card
and previously unpositioned neighbours; other projected positions remain in memory
for the current grid geometry and their original saved positions are retained.

`WidgetLayout.mjs` owns packing, snapping and collision checks. `WidgetResizeHandle.qml`
previews spans and commits only on release; resizing and moving are mutually exclusive.
`kos-deskcenter.widget-layout` covers geometry and migration-compatible sizes;
`kos-ui.widget-resize` exercises pointer input and persistence across a Shell restart.
Run both in a VM/CI with the required graphical environment; live screenshots remain
part of VM review.

## Spacing geometry

For AI contributors: `DesktopGridMetrics.mjs` owns cell, gap and content geometry. Selection,
input and rubber-band hit areas use the same content boundaries; gaps remain desktop background.
Preserve valid manual positions when capacity changes, fill free slots and defer capacity changes
during dragging. Reduced capacity hides excess items without deleting files; larger capacity
restores them. Capacity depends on scale, font, widgets and Dock space, not a fixed promised count.

In the VM, run `./tools/run-tests.sh --all`: `kos-deskcenter.density-metrics` checks geometry and
font bounds; `kos-deskcenter.density-runtime` checks the actual component with isolated fixture
items/state. These fixtures do not replace live desktop acceptance or touch real desktop files.
