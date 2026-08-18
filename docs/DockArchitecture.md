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

File: `desktop/modules/common/AppPresentationService.qml`

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

File: `desktop/modules/common/AppActionService.qml`

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

File: `desktop/modules/dock/AppIdentityService.qml`

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

File: `desktop/modules/dock/WindowService.qml`

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

File: `desktop/modules/dock/AppGroupService.qml`

This derives app groups from the top-level `app` entries in
`ConfigService.dockItems` (currently exposed as the compatibility projection
`ConfigService.pinnedAppIds`) and
`WindowService.records`. It is the shared model for future grouped Dock,
Alt+Tab, and Stage Manager views.

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

The current Dock uses an iPadOS-style policy: pinned apps always remain in
their fixed position. A running pinned app displays a dot and active state;
its windows are omitted only from the Dock's separate unpinned-window section.
All windows remain in `WindowService`, so a future preview, Alt+Tab, or Stage
Manager view can still access every individual window.

## Current Dock compatibility facade

`DockModelService` remains as a compatibility facade for existing QML:

```js
pinnedItems
pinnedCount
windowModel
windowCount
activateApp(appId)
activateWindow(windowId)
pinApp(appId)
unpinApp(appId)
```

New UI components should prefer `AppIdentityService`, `WindowService`, and
`AppGroupService` directly. Do not add new identity or window tracking logic
to `DockModelService`.

## Application launcher module boundary

Files: `desktop/modules/applauncher/AppLauncher.qml`,
`desktop/modules/applauncher/AppLauncherWindow.qml`, and
`desktop/modules/applauncher/AppLauncherService.qml`.

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
`setDockPresentation(width, height, background, primary, secondary)` whenever
its adaptive layout or material changes. The launcher independently selects
the same preferred output policy as Dock. Passing material values through this
API is intentional: `desktop/modules/applauncher` must not import `qs.desktop.modules.dock`,
because Dock already imports the launcher control service.
The launcher uses that published geometry to remain exactly Dock-width and
half-screen-height without reimplementing adaptive layout math. For an
initially narrow Dock it uses a minimum usable launcher size of `600×500px`;
once the Dock reaches 600px it resumes the Dock-width / half-screen-height
rule. Do not put application search, shortcut registration, or grid state back
into `DockContainer.qml`.

Launcher persistence is separate at
`Quickshell.stateDir + "/applauncher/config.json"`. Its versioned schema owns
`rootItems` (`app` or future `folder`), `hiddenAppIds`, and per-app overrides.
Do not store launcher folders or application-grid order in Dock configuration.

## Persistence contract

File: `Quickshell.stateDir + "/dock/config.json"`. This keeps runtime user
state outside the watched QML source directory.

Current user configuration fields:

```json
{
  "version": 2,
  "baseHeight": 60,
  "maxWidthRatio": 0.9,
  "theme": "dark",
  "iconOverrides": {},
  "dockItems": [
    { "type": "app", "appId": "code.desktop" },
    { "type": "app", "appId": "org.kde.kate.desktop" }
  ],
  "proportions": {}
}
```

Persist:

- ordered `dockItems`; app IDs are canonical desktop IDs
- layout proportions and size preferences
- theme and behavior preferences
- canonical-ID keyed icon overrides

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

## Planned feature contracts

### Context menus

The current implementation is `DockContextMenu.qml`, anchored with a
Quickshell `PopupWindow` so the menu does not change the adaptive Dock height.
Right-click is handled by `DockIcon`; left-click behavior is unchanged.

Current context menu actions call service methods:

```text
Pinned App:  activateApp, unpinApp
Window:      activateWindow, minimizeWindow, closeWindow, pinApp
```

Do not mutate `pinnedItems` directly from a menu.

### Window previews

Preview state is transient. A preview should be created only after a hover
delay, keyed by `windowId`, and destroyed when the window disappears. The
preview implementation must use a capture backend (Quickshell Screencopy or
another Wayland-compatible provider); `Toplevel` metadata alone is not a
thumbnail.

### Alt+Tab

Alt+Tab consumes `WindowService.records` and an in-memory most-recently-used
order. It must not reuse the Dock's visual order or pinned list.

### Stage Manager / workspace UI

Use `AppGroupService` for grouping and add provider-specific workspace data
as optional runtime metadata. Do not put Hyprland workspace IDs into the
canonical app identity or persisted pinned records.
