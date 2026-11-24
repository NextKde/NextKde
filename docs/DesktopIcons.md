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

## Copying and dropping files

Ctrl+V or **Paste** on the desktop accepts a local file list copied in another
application. The platform service first asks Qt's clipboard; when the background
daemon cannot see a foreign Wayland selection, it falls back to
`wl-paste --type text/uri-list`. That fallback reports a copy; a cut in another
application is therefore pasted as a copy rather than moved. Copied image data
(from a browser or a screenshot) has no file path, so it is saved as
`Clipboard image <timestamp>.png` in the desktop directory and placed on the
current output.

Dragging accepts local file URLs over the desktop file area (the right side,
after reserved widget columns) and performs `file.transfer` with the proposed
copy or move action. Remote URLs and bitmap-only drags are rejected; hidden
dot-files are not shown. The desktop directory comes from `xdg-user-dir DESKTOP`
and must be writable. File copies are recursive; the platform bounds concurrent
copy jobs (32 total, 8 per client).

## Grouped view

The grouped view is a built-in desktop widget (`groups`), managed like the clock and
weather. It starts hidden so upgrades keep the normal desktop. Show it from
**Widgets** in desktop edit mode, or right-click the desktop background and choose
**Grouped View**; hiding it restores the normal file icons.

The widget is anchored to the top-right of the desktop grid and defaults to a 2×3
span (about 370 × 560 logical pixels), while the other widgets stay in the left flow.
Its supported spans are 2×2, 2×3, 3×2 and 3×3; 2×2 is the floor because the header
and four type tabs need about 222 px and a one-cell column cannot fit a member tile.
A screen too short to place the 2×2 floor keeps the normal file icons instead.
It uses the same surface backend as the other widgets: the compositor glass in a glass
form, or the tonal plate in Material. It opts out of the colour-artwork widget style
so it keeps that material, and its frost joins the same window-wide blur union as the
other cards. Move and resize it in desktop edit mode; the widget layout stores its
position and span per output. The last tab the user explicitly chose is shared and
stored in `DesktopFiles/groupSelectedCategory`; a screen without that type falls back
locally to its first non-empty type. The widget does not participate in shortcut
alignment, box selection, drag reordering or **Reset icon order**.

The preset types and their order are fixed:

| Tab | Members |
| :-- | :-- |
| App shortcuts | `.desktop` launchers |
| Pictures | image files |
| Folders | real folders |
| Files | every other kind, including PDF, text, code and unknown/future kinds |

All four tabs stay in place for muscle memory. Each shows its member count; an empty
type is dimmed and cannot be selected, and the view falls back to the first non-empty
type. The right side shows the selected type's members in a scrolling grid;
single-clicking an item selects it with the same filled highlight as the normal
icon field, and double-clicking opens it. Member artwork follows the desktop icon
size setting (Small/Medium/Large), and the grid cell size and label font grow
with it.

The search button in the widget header opens a bubble with a single input. It filters
only the type currently selected on the left by item name. Escape or a click outside
the bubble only closes it; the filter stays active so the grid does not change under
the pointer. Clear the input to restore the full type. The search button stays
highlighted while a filter is active.

The grouped view is a projection of the same desktop snapshot and never rewrites
saved slots. Right-clicking a member opens the same file menu as the normal icon
field, so it can rename, copy/cut, open with, or move the file to the trash through
the same platform operations. Rename uses an inline editor inside the card because
the normal icon field is hidden. Member labels honour **Show file extensions**, and
customized folders keep their colour and emblem. While the widget is shown on an
output, that output hides its normal file icons; dragging a file into a real folder
therefore requires hiding the widget first, and the Folders tab is an index, not a
replacement for the folder's drop target. The widget is authored on the active
output only, like the other desktop widgets; other outputs keep their file icons.

`DesktopGroups.mjs` owns the kind-to-group mapping and tab glyphs;
`DesktopGroupsContent.qml` is the widget content; `DesktopGroupMemberIcon.qml`
resolves each member's artwork; `WidgetLayout.mjs` owns the top-right anchored
placement and the 2×2 floor with the 2×3/3×2/3×3 span limits. `kos-deskcenter.group-by-type` covers the pure
mapping and QML wiring, `kos-deskcenter.widget-layout` covers anchored placement and
span limits, and `kos-deskcenter.group-by-type-runtime` loads the real content with
isolated fixture entries. None of them replaces visual VM acceptance of the glass,
widget edit mode, tab reflow and multiple outputs.

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
handle to resize it. Ordinary cards stay within 1×1–2×2; the weather card can also
open to 3×1 and 3×2; the grouped view uses its four readable spans from 2×2 to 3×3.
The handle's ceiling and floor come from each widget's declared limits, so grabbing a
card never snaps it to a smaller span than it already has. The drop preview distinguishes occupied
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
