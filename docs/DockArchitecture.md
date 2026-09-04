# Dock Architecture and Extension Contract

This document is the source of truth for the Dock's application identity,
window model, grouping, persistence, and future desktop UI features. Read it
before adding Dock, Alt+Tab, preview, workspace, or app-menu behavior.

## Non-negotiable rules

1. Persist canonical desktop IDs such as `code.desktop`.
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

Public functions:

```js
catalog() -> [descriptor] // visible installed apps, sorted by displayName
descriptor(entry, rawId) -> {
    desktopId, rawAppId, entry,
    defaultName, defaultIcon,
    displayName, iconSource, override
}
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
pin(appId)
unpin(appId)
hide(appId)
edit(application)
```

`launch()` executes the DesktopEntry once in the common layer. Persistence
actions emit requests: Dock handles pin/unpin, AppLauncher handles hide/edit.
This is intentional dependency inversion; common code must not import either
UI module. New surfaces call the service and never duplicate launch commands
or configuration mutations.


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
    entry
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

Launcher persistence is separate at
`Quickshell.stateDir + "/applauncher/config.json"`. Schema version 3 owns
`displayMode`, per-mode `layoutProfiles`, `rootItems` (`app` or `folder`),
`hiddenAppIds`, and per-app overrides. Do not store launcher folders or
application-grid order in Dock configuration.

## Persistence contract

File: `Quickshell.stateDir + "/dock/config.json"`. This keeps runtime user
state outside the watched QML source directory.

Current user configuration fields (schema version 3):

```json
{
  "version": 3,
  "baseHeight": 60,
  "theme": "dark",
  "position": "bottom",
  "barHeight": 35,
  "iconOverrides": {},
  "dockItems": [
    { "type": "app", "appId": "code.desktop" },
    { "type": "app", "appId": "org.kde.kate.desktop" }
  ],
  "pinnedAppIds": [],
  "proportions": {},
  "iconMode": "grayscale",
  "iconOpacity": 0.5,
  "iconTintColor": "#a855f7",
  "visibilityMode": "always",
  "windowGrouping": "grouped"
}
```

Schema 3 contains `visibilityMode` (see the next section), `windowGrouping`,
the legacy icon appearance triplet (`iconMode`: `color | grayscale | tint`,
`iconOpacity`, `iconTintColor`), and explicit `position`/`barHeight`.
`pinnedAppIds` and the icon appearance triplet remain written for compatibility;
new presentation code reads `dockItems` and the shell-wide
`IconAppearanceService`. Legacy `smartHideEnabled: true` migrates to `"smart"`,
legacy `autoHide: true` to `"persistent"`, with `"smart"` winning if both were
set.

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

Components:

- `DockAutoHideController.qml` — a plain per-surface component, **not** a
  singleton, so each screen/position surface owns an independent state machine
  (Bootstrapping/Shown/HidePending/Hiding/Hidden/RevealPending/Showing/Held).
  It drives one `revealProgress` value; every visual offset, opacity and scale
  derives from it. It never persists configuration or creates windows.
- `DockRevealHandle.qml` — the iOS-style white home indicator shown while
  hidden. Pure visual + pointer input; separates the visual pill from a larger
  invisible hit target and reads no services.
- `DockAutoHideMath.mjs` + `test_autohide.mjs` — pure, unit-tested geometry
  and policy functions (`visibleDockRect`, eligibility filtering, conflict
  hysteresis). Geometry and policy must not be scattered into QML bindings.
- All show-mode timing/easing constants live in `DockAnimation.qml`.

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
3. Input is shaped by `DockWindow.mask`: the union of the Dock hit region and
   the handle hit target. All other transparent surface area must pass clicks
   through. In `always` mode the handle hit target is zero-sized.
4. Dock `exclusiveZone` is fixed at `0` in every visibility mode. New normal
   windows receive one initial KWin placement inside the Bar/Dock safe area;
   maximized windows may extend behind the Dock and therefore naturally drive
   smart hide. Existing or user-moved windows are never continuously clamped.
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

The current implementation is `DockContextMenu.qml`, backed by the native
`Qt.labs.platform` `Menu` so the window system owns pointer grabs and outside
clicks. Right-click is handled by `DockIcon`; left-click behavior is unchanged.

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
