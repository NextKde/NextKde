# Dock Architecture and Extension Contract

This document is the source of truth for the Dock's application identity,
window model, grouping, persistence, and future desktop UI features. Read it
before adding Dock, Alt+Tab, preview, workspace, or app-menu behavior.

## Non-negotiable rules

1. Persist canonical desktop IDs such as `org.kde.kate.desktop`.
2. Never compare a pinned desktop ID directly with a provider-specific raw
   window string. Resolve both through `AppIdentityService`.
3. Never persist a Wayland `Toplevel`, a runtime window ID, activation state,
   or a current preview.
4. Never use a positional key such as `win-0` as a window identity. Use the
   stable runtime `windowId` returned by `WindowService`.
5. UI components consume service models and call service actions. They do not
   call `DesktopEntries`, `ToplevelManager`, or provider-specific commands.
6. Hyprland metadata may be added as an adapter, but must not replace the
   provider-neutral `desktopId` contract.

## Pointer magnification

`DockContainer` measures pointer distance from untransformed layout slots in
its content Row, including when that Row is rotated for a side Dock. A quintic smootherstep
spatial field drives the group; pointer travel is bounded to 0.6 logical pixels at low speed and follows raw
samples exactly above 600 pixels/second, while
one shared `FrameAnimation` eases entry/exit with a 26 ms time constant using
the elapsed-time response in `DockMagnification.mjs`. The frame delta is capped
at 1/30 second to avoid a jump after an idle period or stalled frame. Scale, lift and
translations derive from the same frame snapshot.
The container retains one `hoveredApp` for highlights and preview dwell from
that published pointer/layout snapshot, using painted horizontal bounds and the
union of resting and lifted vertical bounds. Name ownership is independently
continuous across adjacent icon spacing, as described below. Rigid accessories
retain their own hover handling and cannot own app hover. An 80 ms exit grace
retains a latched pointer-presence state and last scene position when native
hover briefly loses its surface; a reported position outside the input band
still exits immediately. Interactive previews keep their input. The actual
Dock uses its single immediate in-surface `DockNameLabel`; standalone icon hosts
retain a lazy `DockAppNameTooltip` with a 180 ms fallback dwell.
Do not put separate animations on the composed transforms or add a binary
hover lift to the distance curve: those cause phase mismatch and slot-boundary
jumps. Attention feedback is composed separately, without a second animation.

The response time and settlement epsilon live in `DockAnimation`. The driver
stops at the exact target rather than continuing to schedule idle frames.
Icon slot sizes, hit testing, layout spacing and the existing magnification
radius/maximum scale remain independent of the visual animation. Hosts without
a shared magnification root retain single-icon hover feedback.

Direct action feedback uses 45 ms press/70 ms highlight transitions. Window
activation sends its leading request immediately and coalesces only subsequent
requests in a bounded 24 ms window. Window presentation updates merge for 16 ms
without resetting their deadline. Auto-hide interaction changes evaluate
immediately; ordinary geometry changes use bounded 80 ms coalescing.

Window previews dwell 220 ms on first entry, 75 ms while switching an already
open preview, and recover a still-visible same-icon preview immediately. Their
90 ms entrance starts on a render-frame callback rather than a fixed 16 ms
timer. Info/music/temperature cards dwell 220 ms and enter over 100 ms. Closing
handoff protection remains intact. Stack wheel events accumulate physical
notches or touchpad pixels and merge once per frame instead of dropping events
during a fixed cooldown. Pure text popups have empty pointer input regions.

`tests/dock/motion.test.mjs` checks response equivalence at
30–240 Hz, reversal and settlement. `tests/dock/runtime.mjs magnification` exercises
the shipping QML on all three edges, alongside the existing `dock-hover-hit`
regression test. These are offscreen behavior checks, not GPU frame-rate
benchmarks.

### Selection lighting

For the macOS preset, `DockIconHighlight` replaces the old flat active/hover
plates with one translucent gradient, a thin rim and a top reflection. Hover,
active-window selection and press feedback have separate intensities; leaving
an active task keeps its quieter selected state. The component changes only
paint and opacity, inherits the icon's existing fisheye transform, and
counter-rotates on side Docks to keep its light direction upright. It has no
pointer handlers, blur, offscreen layer or continuously running animation.

Urgent tasks retain their existing colored background; editing/dragging
suppresses the glass highlight. Material and Windows presets keep the legacy
selection plates. `tests/dock/runtime.mjs highlight` tests state transitions and
light/dark rendering values; the magnification runtime fixture also verifies
that the actual DockIcon wires these states without stacking legacy plates.

The paint implementation lives in `shared/qml/controls/SelectionHighlight.qml`;
`DockIconHighlight` remains a compatibility wrapper. The same component lights
Control Center controls (without replacing their enabled-state colors) and
Launcher apps/folders, including explicit keyboard selection. Launcher edit,
reorder and merge feedback retain their own states. `ControlCenterSelection`
observes the existing handler instead of adding one, so clicks, slider grabs
and navigation remain owned by their original controls. `fillStrength` lets
colored controls use a quieter overlay without muting the reflective rim.

`tests/selection-surfaces/run.mjs` checks click-through and keyboard focus with
Qt Quick Test, then loads the shipping Launcher and Control Center as unmapped
Wayland surfaces to verify selection, folder, edit, merge and preset bindings.
The latter check is explicitly skipped when no Wayland compositor is available.

### Launch feedback and names

`DockLaunchService` owns transient, canonical-desktop-ID launch feedback for
Dock clicks on applications without windows. It observes `WindowService`
readiness and `AppActionService.launchFailed`, and expires windowless launches
after 15 seconds. An immediately ready window preserves at least 500 ms of
launch feedback; this only delays clearing the animation state, never launching
or displaying the application. Failed launches still clear immediately.
Repeated clicks while pending do not spawn duplicate launches.
The compositor launch ticket is still prepared before executing the app.

`DockIcon` composes a frame-driven ballistic bounce with its shared hover
transform. Once its feedback state clears, the icon lands within 130 ms rather
than continuing another full bounce. Side Docks bounce towards the workspace. Launch motion does
not alter resting slots or KWin's stable window-animation target.
The animation driver stops for reduced motion, hidden Docks, editing and
dragging. Launch readiness and expiry remain active independently; revealing
the Dock resumes feedback only if that application's launch is still pending.

The Dock owns one `DockNameLabel` in its existing `DockWindow.contentItem`
render tree. Icons publish label eligibility without creating popup windows or
per-icon label frame drivers. The shared layout frame selects names through bounded, continuous ownership
cells meeting at adjacent painted icon-center midpoints. Cells bridge spacing
within each icon run, terminate at dividers/accessories, and also check the
resting-plus-painted normal envelope. This selection does not alter click hit
testing or preview dwell. Running apps retain their names until their own
preview actually becomes visible; exact hover is not a label eligibility gate.
The shared frame positions the selected name:
it follows raw pointer position along the Dock and the transformed artwork edge
across it. Switching icons only changes text; there is no Wayland popup
reposition/configure round trip. The disabled label has no pointer handlers.
The first name appears after a 250 ms dwell on an eligible icon. Moving to
another icon before it appears restarts the dwell; once shown, adjacent names
switch immediately. Leaving the eligible region or opening a preview/menu
clears the dwell state. Standalone tooltip fallbacks use the same 250 ms delay.
Pointer travel follows raw samples directly; only hover entry/exit amplitude
settles over frames. Icon translation updates only the selected label's
geometry, without rescanning the entire Dock for each bouncing icon.

`DockWindow` reserves both combined hover/launch excursion and separate name
paint headroom before interaction starts. Name-only headroom is excluded from
its hover/input region and never changes workspace reservations.
`tests/dock/runtime.mjs launch-feedback` checks readiness, asynchronous failure,
timeout, reduced motion, hidden-Dock suspension, 130 ms landing and label
geometry on all three edges. `tests/dock/motion.test.mjs` covers the bounded
flight curve and checks real thin surface and input budgets for adaptive sizes
and scales 1–3, including name-only pass-through space.
`sweep_wayland.py` drives 1800 px/s synthetic icon/name sweeps on actual thin
Wayland layer surfaces without moving the mouse or intercepting input. It
asserts one mapped layer surface per edge, no popup/reposition requests, and
reports actual EGL frame-commit intervals. It invokes the shipping
`DockContainer.selectNameTarget` against actual shared layouts and mixed running
icons, checking uniform/fast sweeps, gaps, three peak scales, normal/outer exits,
menus, and visible-versus-unmapped previews. Those measurements demonstrate the
render path; they do not substitute for subjective high-refresh desktop use.

## Service layers

```text
AppPresentationService ──→ AppLauncher / QuickSearch / shared AppIcon
        ↑
AppIdentityService → WindowService → AppGroupService → Dock / Alt+Tab / Preview / Stage Manager
AppActionService ──→ launch / pin / unpin / hide / edit requests
```

### AppPresentationService

File: `shell/desktop/modules/common/AppPresentationService.qml`

This is the shared presentation boundary for Dock, QuickSearch and AppLauncher.
Use `catalog()` to enumerate installed visible applications and
`descriptor(entry, rawId)` for display name/defaults/icon source. Both return
the same custom name/icon override, so UI surfaces must not walk
`DesktopEntries` or resolve theme icons themselves. Keep folder layout,
sorting and hidden-app state in AppLauncher-only configuration.

Descriptors carry strings only. A `DesktopEntry` must never be stored in a
descriptor, an identity result or a model item: `DesktopEntries` destroys and
replaces entries on every catalogue rescan, and QML's lifecycle tracking does
not follow a `QObject*` wrapped inside a `QVariantMap`, so a stored entry
becomes a dangling pointer that crashes delegation incubation or teardown.
Anything that has to execute an entry calls `entryFor(id)` at the point of use.

Public functions:

```js
catalog() -> [descriptor] // visible installed apps, sorted by displayName
descriptor(entry, rawId) -> {
    desktopId, rawAppId,
    defaultName, defaultIcon,
    displayName, iconSource, override
}
entryFor(idOrRaw) -> DesktopEntry | null // live entry, resolved at use
iconSource(candidate) -> QML image source
overrideFor(desktopId, rawId) -> override
setOverrides(overrides)
```

`catalogRevision` changes when Quickshell's installed application model
changes. `revision` changes when a user edit changes the shared overrides.
Consumers that keep a derived model bind to both revisions.

`AppIcon.qml` is the common asynchronous rendering wrapper. New visual
surfaces should pass it the already-resolved `descriptor.iconSource`; do not
reintroduce per-surface `IconImage` behaviour.

### AppActionService

File: `shell/desktop/modules/common/AppActionService.qml`

Use this service for every cross-surface application action:

```js
launch(applicationOrDesktopEntry)
launchById(desktopId, launchArguments)
pin(appId)
unpin(appId)
hide(appId)
edit(application)
```

`launch()` accepts a `DesktopEntry` or any object carrying an id (`desktopId`,
`id` or `rawAppId`) and resolves the live entry itself through
`AppPresentationService.entryFor()`. Persistence actions emit requests: Dock
handles pin/unpin, AppLauncher handles hide/edit. This is intentional
dependency inversion; common code must not import either UI module. New
surfaces call the service and never duplicate launch commands or configuration
mutations.

`kos-shell.app-launch-resolution` runs the real presentation, identity and
action services against a stub platform socket. It asserts that descriptors and
identity results carry no `entry`, that `entryFor()` resolves a live entry from
an id with or without the `.desktop` suffix, and that a launch -- including the
Dock's new-window action -- reaches the daemon with the canonical desktop id.


### AppIdentityService

File: `shell/desktop/modules/dock/AppIdentityService.qml`

This is the only service that resolves *runtime window identity*. It currently
uses Quickshell `DesktopEntries` and the Wayland `appId` supplied by a
`Toplevel`.

Public functions:

```js
resolve(rawAppId) -> {
    desktopId,
    normalizedId,
    rawAppId,
    name,
    iconSource,
    hasIconOverride,
    hasPreferredIcon
}

canonicalId(rawAppId) -> "org.kde.kate.desktop"
normalize(value) -> comparison-only string
sameApp(left, right) -> bool
clearCache()
```

`desktopId` is the canonical identity. `rawAppId` is diagnostic/provider
data and must not be persisted. `normalizedId` is only for comparisons and
must not be written to configuration.

Icon resolution order:

```text
AppPresentationService override[desktopId]
    ↓
DesktopEntry.icon
    ↓
raw app ID / candidate IDs
    ↓
application-x-executable
```

Desktop entry lookup deliberately prefers entries with a usable icon during
heuristic matching. Some applications install a URI handler desktop file
alongside the real application desktop file; the handler may have the same
startup class but no `Icon` field. The resolver must not let that handler
shadow the icon-bearing application entry.

`DockConfigService.iconOverrides` remains in old configuration files only for
round-trip compatibility. Do not read or write it for new features: all new
name/icon edits belong to AppLauncher persistence and are published through
`AppPresentationService`.

If a future Hyprland adapter exposes `class` or `initialClass`, pass those as
additional lookup hints into this service. Do not add a second matching
implementation in Dock or WindowService.

### WindowService

File: `shell/desktop/modules/dock/WindowService.qml`

This is the runtime window source. It currently consumes
`Quickshell.Wayland._ToplevelManagement/ToplevelManager`; it does not call
`hyprctl`.

Public properties:

```js
windowModel       // ListModel for QML views
windowCount
records           // runtime records, including the Toplevel reference
revision          // increments after a rebuild
activeWindowId
```

Window model roles:

```js
windowId
desktopId
appId             // compatibility alias; equals desktopId
rawAppId
title
icon
isActivated
isMinimized
isFullscreen
```

Public functions:

```js
windowById(windowId)
windowsForApp(desktopId)
activateWindow(windowId)
minimizeWindow(windowId, value)
closeWindow(windowId)
```

`windowId` is stable while the same Toplevel object remains alive. It is a
runtime identifier only; it is intentionally not persisted. Window order may
change without changing the identity of an existing Toplevel.

### AppGroupService

File: `shell/desktop/modules/dock/AppGroupService.qml`

This derives reusable app groups from the top-level `app` entries in
`ConfigService.dockItems` (currently exposed as the compatibility projection
`ConfigService.pinnedAppIds`) and
`WindowService.records`. The current Dock compatibility facade derives its own
grouped/separate presentation; `AppGroupService` remains available for future
Alt+Tab and Stage Manager views.

Group shape:

```js
{
    desktopId,
    name,
    iconSource,
    pinned,
    windows,
    activeWindow,
    pinnedVisible
}
```

The current Dock exposes two presentation policies through
`DockConfigService.windowGrouping`. In the default `grouped` mode, pinned apps
remain in their fixed position and show running/active state while unpinned
windows are grouped by canonical desktop ID. In `separate` mode, a running
pinned launcher moves into the per-window task section. All windows remain in
`WindowService`, so previews and future Alt+Tab or Stage Manager views can
access every individual window.

## Current Dock compatibility facade

`DockModelService` remains as a compatibility facade for existing QML:

```js
pinnedItems
pinnedCount
windowModel
windowCount
activateApp(appId)
launchNewWindow(appId)
activateWindow(windowId)
toggleWindow(windowId)
minimizeWindow(windowId)
closeWindow(windowId)
pinApp(appId)
isAppPinned(appId)
isAppActivated(appId)
unpinApp(appId)
movePinnedItem(type, key, targetIndex)
```

New UI components should prefer `AppIdentityService`, `WindowService`, and
`AppGroupService` directly. Do not add new identity or window tracking logic
to `DockModelService`.

## Native minimize targets

`DockWindowAnimationTargetService` publishes the stable icon slot to both the
private KOS animation effect and Plasma's taskbar protocol. Its ungrouped
`org.kde.taskmanager.TasksModel` is a protocol adapter only; `WindowService`
retains ownership of application identity and window actions. Match the exact
KWin UUID first, then the canonical/raw app ID of a grouped launcher. Never use
the synthetic `window-N` handle or another window's separate icon as a fallback.

Plasma's Wayland backend ignores the explicit rectangle passed to
`requestPublishDelegateGeometry`: it reads a real `QQuickItem` and that item's
window surface. The adapter therefore creates a non-rendering rectangle directly
under the Dock surface's content item, subtracts the surface origin from the
global target and publishes integer logical pixels. This avoids hover transforms,
side-Dock rotation and double-counting secondary-output offsets or pixel scale.
Missing/unrepresentable slots invalidate their published rectangle; destroying
the Dock surface removes its geometries in KWin. Native publication is independent
of the private effect's availability, payload cache and retry delay.

With KOS **Hide and restore → None**, the enabled KWin minimize effect (for
example Magic Lamp) reads `Window::iconGeometry()` from that protocol target for
titlebar, shortcut and Dock actions. KOS does not claim those animations or change
the user's enabled native effects. The separate KOS Scale/Genie styles still use
their existing private targets and deformation. `tests/dock/native-target.test.mjs`
covers identity precedence and coordinate conversion; real VM acceptance must
also exercise titlebar minimize and Dock restore, grouped/separate windows,
hidden/side Docks and secondary outputs at fractional scale.

## Application launcher module boundary

Files: `shell/desktop/modules/applauncher/AppLauncher.qml`,
`shell/desktop/modules/applauncher/AppLauncherWindow.qml`, and
`shell/desktop/modules/applauncher/AppLauncherService.qml`.

The application launcher is a shell module, not a Dock popup. `shell.qml`
instantiates it independently, which allows a global shortcut, IPC, search,
and application-grid navigation to operate without importing Dock visuals.

Its public control API is:

```js
AppLauncherService.show()
AppLauncherService.hide()
AppLauncherService.toggle()
```

Dock has one strictly presentation-only responsibility: it calls
`setDockPresentation(width, height, position, background, primary, secondary,
foreground, barHeight)` whenever its adaptive layout or material changes. The
launcher independently selects the same preferred output policy as Dock.
Passing geometry and material values through this API is intentional:
`shell/desktop/modules/applauncher` must not import `qs.desktop.modules.dock`,
because Dock already imports the launcher control service.

The launcher supports `bottom`, `center`, and `fullscreen` display modes.
Bottom mode follows Dock geometry with a screen-relative minimum width and a
500px minimum height; center mode uses a bounded floating-dialog size; fullscreen
mode fills the selected output. Each mode owns a semantic icon-size, density,
and font-weight profile. Do not put application search, shortcut registration,
or grid state back into `DockContainer.qml`.

Card presentations keep the search header outside the scrolling app grid: the
grid viewport starts below the header, so a scrolled row is clipped at that
boundary instead of painting over the search field.

`LauncherIconMotion.qml` drives tile position and scale from one animated
progress value, with a separate 200 ms opacity track alongside the 300 ms
spread. Both use GUI-thread `NumberAnimation`, as does the stationary glass
fade in `LauncherMotion.qml`. Keep opacity at its current value when starting
or reversing: forcing it to 1 to prewarm render-thread Animators can expose a
fully visible tile before the fade starts. Hidden neighbor pages snap without
holding the controller open; cold delegates start at the contracted pose and
follow their resolved grid offsets. `tests/interaction-controls/tst_motion.qml`
covers the entrance, reversal, cold delegates and hidden-page lifecycle.

Launcher persistence is separate at
`Quickshell.stateDir + "/applauncher/config.json"`. Schema version 3 owns
`displayMode`, per-mode `layoutProfiles`, `rootItems` (`app` or `folder`),
`hiddenAppIds`, and per-app overrides. Do not store launcher folders or
application-grid order in Dock configuration.

## Persistence contract

File: `Quickshell.stateDir + "/dock/config.json"`. This keeps runtime user
state outside the watched QML source directory.

Core user configuration fields (schema version 12):

```json
{
  "version": 12,
  "baseHeight": 60,
  "theme": "dark",
  "position": "bottom",
  "barHeight": 35,
  "iconOverrides": {},
  "dockItems": [
    { "type": "app", "appId": "org.kde.dolphin.desktop" },
    { "type": "app", "appId": "org.kde.kate.desktop" }
  ],
  "pinnedAppIds": [],
  "proportions": {},
  "iconMode": "grayscale",
  "iconOpacity": 0.5,
  "iconTintColor": "#a855f7",
  "visibilityMode": "always",
  "windowGrouping": "grouped",
  "showLauncher": true,
  "showTrash": true,
  "showRevealIndicator": true,
  "hoverScale": null
}
```

Schema 12 keeps one `hoverScale` setting: the hovered icon's peak scale
(1.0–3.0, displayed as 100–300%). Lift is derived as
`0.2 * (effectiveHoverScale - 1)` of the icon size and follows the same
neighbour influence as magnification. At 100%, both effects stop. `null`
follows the active shell style; a number works in every style. Migration
retains the old scale, clamps values above 3.0 and removes the independent
`hoverLift` key introduced in schema 11. Settings and IPC expose only scale.

The configured scale is a peak: crowded layouts reduce the shared wave to
keep its painted slots within the output, including edge padding. A linear
pass limits scale, lift and translations together; the adaptive resting icon
size is unchanged by hover. At 100%, plate-gap tightening is disabled too.
Relaxed layouts spend their empty middle slot on application growth through
paint translations, keeping trailing controls and resting Row geometry fixed.
Workspace layout publication uses resting physical width/height on every
edge and does not subscribe to the live hover extent or glass shift.
Settings serializes Dock requests and protects in-progress slider previews
from unrelated replies.

Schema 3 contains `visibilityMode` (see the next section), `windowGrouping`,
the legacy icon appearance triplet (`iconMode`: `color | grayscale | tint`,
`iconOpacity`, `iconTintColor`), and explicit `position`/`barHeight`.
`pinnedAppIds` and the icon appearance triplet remain written for compatibility;
new presentation code reads `dockItems` and the shell-wide
`IconAppearanceService`. Legacy `smartHideEnabled: true` migrates to `"smart"`,
legacy `autoHide: true` to `"persistent"`, with `"smart"` winning if both were
set.

Schema 10 adds `showRevealIndicator`, defaulting to `true` unless the stored
value is the boolean `false`. Settings updates it through
`dock-settings.updateRevealIndicatorVisibility(visible)`. Disabling it removes
only the reveal pill and its compositor blur region, for all three Dock edges;
the edge hit target, hover/click reveal, and visibility mode remain unchanged.
The Settings switch follows the confirmed snapshot and handles its own pending
request, so unrelated snapshots cannot prematurely re-enable it.

Schema 9 adds `showLauncher` and `showTrash`. Both default to `true` for old
configurations; only an explicit boolean `false` hides an icon. Settings uses
`dock-settings.updateBuiltinVisibility(id, visible)` with `launcher` or `trash`.
These controls remain outside `dockItems`: hiding one does not change pinned
applications, disable the launcher, or change the contents of the trash.
The Dock excludes hidden controls from both its row and adaptive slot count.
Settings presents these independent choices as checkboxes, with both selected
by default. Updates stay disabled until a configuration snapshot arrives;
failed IPC calls restore the last confirmed selection. Closing an icon also
closes its open menu. An information-only or accessory-only Dock retains usable
dimensions without reserving orphan dividers; an entirely empty Dock has zero
height.

`kos-shell.dock-builtins` checks defaults, independent changes and persistence
across a reload. `kos-settings.builtin-checkboxes` uses the actual Settings page
with a simulated bridge to exercise clicks, pending state, failed replies and
later snapshots. It runs when Qt's `qmltestrunner` is installed. Adaptive layout
tests cover information-only, accessory-only and empty content.

Persist:

- ordered `dockItems`; app IDs are canonical desktop IDs
- layout proportions and size preferences
- theme, position, visibility, and window-grouping preferences
- legacy icon appearance and override fields for round-trip compatibility

Do not persist:

- Toplevel objects
- window IDs
- active/minimized state
- current window title
- preview images
- icon resolution cache

`pinnedAppIds` is retained only as a compatibility projection for the current
flat Dock UI. New features must read and mutate `dockItems` through
`ConfigService.setDockItems`, `addAppItem`, and `removeAppItem`.

When the configuration format changes, increment `version`, provide defaults
for missing fields, preserve unknown fields where practical, and write the
new format only after a successful migration. Runtime state is already stored
under Quickshell's XDG-backed state directory; do not move it back into the
watched QML source tree.

## Visibility modes and auto-hide

`DockConfigService.visibilityMode` is a single mutually exclusive enum:
`always`, `smart` (hide only when a window overlaps the Dock area), or
`persistent` (stay hidden regardless of windows). Never persist separate
booleans for these; that only produces illegal combinations.

The hidden Dock reveals only along its own footprint: a hidden Dock responds in
a 2 logical-pixel strip at the screen edge, over the Dock's actual span, and the
rest of that edge stays pass-through. There is no whole-edge trigger and no user
setting for it -- an earlier `fullEdge`/`dockSpan` choice was removed because the
whole-edge variant only produced accidental reveals. A `revealTriggerMode` field
left in an older configuration is ignored on load.

Components:

- `DockAutoHideController.qml` — a plain per-surface component, **not** a
  singleton, so each screen/position surface owns an independent state machine
  (Bootstrapping/Shown/HidePending/Hiding/Hidden/RevealPending/Showing/Held).
  It drives one `revealProgress` value; every visual offset, opacity and scale
  derives from it. It never persists configuration or creates windows.
- `DockRevealHandle.qml` — the iOS-style white home indicator shown while
  hidden. Pure visual + pointer input; separates the visual pill from the
  invisible edge target and reads no services. `DockRevealGeometry.mjs` owns
  the target geometry; the window supplies its static full-reveal Dock
  rectangle in surface-local logical coordinates.
- `DockAutoHideMath.mjs` + `tests/dock/policy.test.mjs` — pure, unit-tested geometry
  and policy functions (`visibleDockRect`, eligibility filtering, conflict
  hysteresis). Geometry and policy must not be scattered into QML bindings.
- All show-mode timing/easing constants live in `DockAnimation.qml`.

Startup mapping is gated separately in `Dock.qml`: the saved configuration must
finish loading and a real output must be available before any Dock surface
becomes visible. Otherwise the provisional `always` mode can reserve workspace
before a saved `smart` or `persistent` mode arrives. The controller's boot timeout
does not bypass this gate. Output loss still hides and restores the existing
window; ordinary auto-hide and runtime mode changes keep it mapped.

Non-negotiable invariants:

1. Collision judgement always uses the **static rectangle the Dock would
   occupy at full reveal**, computed from screen geometry and configured
   sizes — never the animated transform position, `mapToItem`, or global
   coordinate sampling. A fresh conflict requires a stable 200ms overlap at
   least 12px into that rectangle, avoiding accidental hides during edge
   placement. Once hidden, leaving the real Dock rectangle reveals it; there
   is no invisible spatial release strip.
2. Hiding never destroys the `PanelWindow`, toggles `visible`, changes
   anchors, or spawns a second layer-shell window for the handle; it only
   translates `dockWrapper` inside the permanently mapped surface.
   Once fully hidden, the capsule retires its blur region and exact shape;
   only the visible reveal hint is submitted to the compositor. A fully faded
   hint likewise submits no blur region.
3. Input is shaped by `DockWindow.mask`: the union of the Dock hit region and
   the handle hit target. All other transparent surface area must pass clicks
   through. In `always` mode the handle hit target is zero-sized.
   A hidden Dock only responds in a **2 logical-pixel strip at the screen edge,
   along the Dock's actual span**. The rest of that edge, and the Dock's future
   footprint above it, remain pass-through. The span follows layout changes and
   side-Dock top-bar reservations; it is not screen-centred by assumption and
   does not follow animated transforms. An empty or invalid Dock layout yields an
   empty target, so no edge input is claimed before the layout is ready.
   The strip stays narrow during `RevealPending`. Once showing starts, and
   while reveal progress is nonzero, it extends across the floating gap and
   2 logical pixels into the static Dock rectangle. This allows slow pointer
   travel from the edge into the Dock without losing the hover hold. Once
   fully hidden, it contracts to the edge strip again. Invalid or empty Dock
   geometry produces an empty target. Disabling or shrinking a hovered target
   must release its controller hold if the pointer is no longer inside. The
   decorative pill is centred on the Dock's rectangle; it never defines the
   input region.
4. Dock `exclusiveZone` reserves its full-reveal strip only in `always` mode.
   That mode also gives newly opened windows the same `workspaceGap` as the
   Dock's screen-edge float, preserving visible breathing room. Smart and
   persistent modes publish both values as `0`, so revealing or hiding the
   Dock never reflows windows or leaves an invisible placement gap.
5. Editing, dragging, any `DockModelService.activeDockPopup`, an open App
   Launcher, pointer-inside, or a temporary reveal hold are inhibitors that
   force the Dock visible; popups must join the `activeDockPopup` coordinator
   rather than being special-cased in the controller.

Window data contract: `WindowService` normalized records carry
`geometry`/`screenName`/`isMaximized`/`isVisible` plus `providerReady`; the
KWin bridge publishes `frameGeometry`, output, maximized and visibility per
window and re-snapshots on their change signals (each connection defensively
try/caught). Provider readiness requires both the first window and virtual
desktop snapshots. Until a desktop id is known, KWin `visible` is used as the
membership fallback. When a provider exposes no geometry, degrade to "hide only on
same-screen fullscreen" — never substitute "an active window exists" for
collision.

## Current and planned feature contracts

### Context menus

`DockIcon.qml` lazily creates the shared `ContextMenu` for application and
window actions. `DockContainer.qml` owns the launcher and trash menus. These
menus join `DockModelService`'s popup coordinator so opening one closes the
previous popup and holds the Dock visible. Right-click is handled by `DockIcon`;
left-click behavior is unchanged.

Current context menu actions call service methods:

```text
Pinned App:  activateApp, unpinApp
Window:      activateWindow, minimizeWindow, closeWindow, pinApp/unpinApp
```

Do not mutate `pinnedItems` directly from a menu.

### Window previews

Window previews are implemented by `DockWindowPreview.qml`. Preview state is
transient, opens after the Dock icon hover delay, and is keyed by stable runtime
`windowId` values. Cards request KWin thumbnails through `WindowService`, show
loading/fallback states, activate the selected window, and can close an
individual window. `Toplevel` metadata alone is not treated as a thumbnail.

### Alt+Tab

Alt+Tab consumes `WindowService.records` and an in-memory most-recently-used
order. It must not reuse the Dock's visual order or pinned list.

### Stage Manager / workspace UI

Use `AppGroupService` for grouping and add provider-specific workspace data
as optional runtime metadata. Do not put Hyprland workspace IDs into the
canonical app identity or persisted pinned records.

### Desktop lyrics

Desktop lyrics are an accessory of the desktop music widget, not a Dock
feature: the widget card carries the on/off switch (DeskCenterConfigService,
persisted in deskcenter-widgets.ini), and the HUD exists only while the music
widget itself is on the desktop — hiding the widget through the widget
library or the Settings page also stops the lyric position polling.
The switch itself only appears while the current track actually has lyrics
(KOS live lines, LRC-timed or untimed plain text).
The HUD has an always-visible Move button so placement is discoverable
where lyrics are displayed. Normally only this button accepts pointer input.
Placement temporarily enables pointer input over the lyric card; dragging
stores normalized coordinates, and Done restores click-through behaviour outside the Move button. The
position survives restarts and is bounded to the active output after resizing.
The placement preview works even when no player supplies lyrics.

`DockMprisService` prefers KOS live lyric metadata (including intentional empty
lines). Otherwise it parses LRC in `xesam:asText`, reads the current MPRIS
position every 500 ms only while playing with timed lyrics actually enabled
(MPRIS position is lazy; the poll is skipped entirely for live lyrics and
untimed text), and chooses the current/next timed line.
Seeking recomputes the index; pauses stop polling. Untimed lyrics remain text.


## Test organization

All Dock tests live in `tests/dock/`. Group related checks in these suites
instead of adding a new directory or runner for each regression:

- `model.test.mjs`: process identity, unpinning, window indexing/updates,
  transport fallback, QML payload arrays and lyric parsing.
- `policy.test.mjs`: adaptive layout, auto-hide policy and wallpaper colors.
- `motion.test.mjs`: launch feedback, magnification response/layout and reveal
  geometry. Named Node test cases preserve individual failure diagnostics.
- `runtime.mjs`: one entry point selecting an isolated QML scenario. Each case
  keeps its own scratch configuration and cleanup; QML scenes remain separate.
- `fixtures/`: shared QML service and renderer doubles for runtime scenes.
- `sweep.qml` and `sweep_wayland.py`: the compositor-dependent label/frame probe.

Run checks in the test VM, for example:

```sh
node tests/dock/model.test.mjs
node tests/dock/policy.test.mjs
node tests/dock/motion.test.mjs
node tests/dock/runtime.mjs highlight /usr/lib/qt6/bin/qmltestrunner
node tests/dock/runtime.mjs magnification quickshell
node tests/dock/runtime.mjs lyrics /usr/lib/qt6/bin/qmltestrunner
```

CTest registers the three logic suites as `kos-dock.model`, `kos-dock.policy`
and `kos-dock.motion`; existing runtime test names and dependency gates remain.
The launch-feedback scene and Wayland sweep can also be selected manually in
that VM. Test counts refer to suites after consolidation, rather than one CTest
entry per small file.

## Timing and input review invariants

Evaluate pointer and window events with bounded scheduling; repeatedly restarting a debounce must
not postpone hide/reveal indefinitely. Keep tooltip and interactive popup input masks distinct.
Use actual popup readiness signals instead of an assumed one-frame delay. Intentional hover/preview
and naming delays are separate policies: do not set every timer to zero to hide latency.
Measure input-to-frame behavior in the VM; animation duration arithmetic is not a latency measurement.
