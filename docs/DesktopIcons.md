# Desktop icon spacing

[简体中文](DesktopIcons.zh-CN.md)

## Desktop shortcuts

Right-click an application icon in the launcher and choose **Send to Desktop** to
create a symbolic link named after the installed `.desktop` entry in the XDG
desktop directory. The link points at the installed entry, so the shortcut
follows application updates. A launcher custom icon still applies through the
file-name lookup; a custom display name is not written into the shortcut.

Sending the same application again does not replace a file or link that already
exists; the launcher reports "Shortcut already exists on Desktop". A missing or
unwritable desktop directory fails with a notification. If the platform daemon
is unavailable the action is refused and the failure is logged, because no
fallback writes desktop files from QML. After a successful creation the Shell
requests `desktop.refresh`, so the icon appears even when the data service's
directory watcher was not installed. Opening, renaming, cutting/moving and
trashing continue to use the existing desktop file operations; rename, move and
trash act on the shortcut link itself and never modify the installed `.desktop`
file it points at.

## Spacing

Right-click the desktop background and choose icon spacing: loose, compact or tighter.
Spacing is independent of icon size, display scaling and files. Labels keep at most two lines,
using actual font height. The preference is `DesktopFiles/iconSpacing` in
`deskcenter-desktop-files.ini`; old configurations default to loose.

## Icon size

Right-click the desktop background and choose **Icon Size**: **Extra Small**, Small,
Medium or Large. The four tiers are 32, 40, 56 and 72 logical pixels; the rendered
artwork is 12 px larger, so Extra Small draws a 44 px icon. File-name labels use the
desktop font; icon size changes the artwork and cell geometry, not the label size.
The preference is `DesktopFiles/iconSize` in `deskcenter-desktop-files.ini`;
existing values remain valid.

Icon size and icon spacing are independent. Sizes are logical pixels and follow the
system scale, which makes Extra Small useful on high-DPI outputs. The grid uses spare
height for another row when it can keep at least a 3 px gutter; only when that is not
possible does it leave a bottom remainder. The extra row fills the columns from the
current alignment edge, so the column at the opposite edge may be shorter. Compact and
denser spacing keep their
108/96 px cell-width floors, so Extra Small mainly adds rows in those modes; whether
it adds a column depends on the actual font line height and the available width.

## Shortcut alignment

Right-click the desktop background and choose **Arrange**, then **Align Left** or
**Align Right** below the sort entries. The default is right alignment. Alignment
applies inside the desktop file area: left alignment starts at the widget boundary,
right alignment at the right edge. The preference is
`DesktopFiles/shortcutAlignment` in `deskcenter-desktop-files.ini`; old
configurations default to right.

Changing the alignment remaps the grid by column: slots still fill one column
top-to-bottom before the next, starting from the chosen edge. Box selection, drag
and drop, insertion markers and folder merging use the same mapping.

## Desktop surface ownership

`DeskCenterWindow.qml` hosts widgets, icons and their context menu on each output.
Its layer-shell namespace is `dock`, which makes KWin exclude it from ordinary
window close/move shortcuts and Show Desktop hiding without making its transparent
surface a wallpaper candidate. Native Overview captures a single Desktop window;
only wallpaper surfaces use `desktop`. Glass composes wallpaper, widgets and Dock
into native Overview's desktop backgrounds, so all scale with the desktop preview.
During native Slide desktop switching, Bridge cancels effect elevation only for
Below-layer Quickshell Dock surfaces. Their desktop content stays behind apps;
Top/Overlay panels retain native elevation. This does not change Overview typing
or virtual-desktop membership. `tests/desktop-slide/run-vm.py` checks repeated
switches with real DeskCenter content, a covering application and a normal panel.
Redundant native panel thumbnails are suppressed only while this composed preview
is available. Keep its Bottom layer: moving it to Background can
put it behind Plasma. `installDesktopStack()` in the platform-owned
`kwin/window-bridge.js` orders existing Below-layer surfaces as wallpaper < widgets
< Stage strip, independently of Stage mode and mapping order. It never changes
visibility or virtual-desktop membership and never recreates a surface.

Glass accepts Desktop-typed Quickshell surfaces and Below-layer Quickshell Docks only when they explicitly declare
a nonempty content region. Wallpapers and legacy empty-region whole-window blur
remain excluded. DeskCenter keeps the desktop content material; Top/Overlay panels
keep the Dock material. `kos-deskcenter.desktop-stack` covers mapping permutations,
reentrant stacking signals, first-buffer readiness and Overview wallpaper candidates;
`kos-glass.desktop-blur` covers the surface classification and opt-in boundary.
`kos-ui.desktop-overview` loads both real Shell surfaces in a private KWin, checks
the actual `DesktopBackground` choice in both mapping orders, and exercises desktop
close/move and Show Desktop. It does not replace visual Overview acceptance.

In a VM, verify native Overview and desktop grid with Plasma-owned and Shell-owned
wallpapers, multiple outputs, Show Desktop, desktop close/move shortcuts, and widget
glass before and after leaving Overview. Source/SDK checks do not establish visual acceptance.

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
Dragging updates the card's `x/y` directly, with position animations disabled until
release. The card is also the native glass anchor: a `Translate` alone does not
trigger `SurfaceShape` geometry sync. Drop snapping reads these coordinates without
adding the drag offset again; release animates to the accepted or original cell.
The Repeater uses a `ListModel` reconciled by widget ID. Position/size snapshots
update layout data without replacing delegates; visibility and order changes only
remove, insert or move the affected rows. This keeps the clock face and other
widget content alive when another widget is moved.
The clock animates a shared page-selection fraction for its face and countdown,
then derives each page's position from the current height. Height changes alone
must keep the hidden countdown below the face rather than replaying a slide.
In edit mode, the clock's Analog/Digital control switches its face without replacing
the countdown. `DeskCenterConfigService` persists the choice as `analog` or `digital`;
missing or invalid values use analog. Both faces use the shared clock and appearance
tokens, with digital retaining the regular rounded card and analog using the flower outline.
`kos-deskcenter.widget-layout` covers geometry and migration-compatible sizes;
`kos-ui.widget-resize` exercises pointer input, glass-anchor geometry after the lift
animation finishes, retained card/clock instances across layout saves and reorder,
and persistence across a Shell restart.
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
