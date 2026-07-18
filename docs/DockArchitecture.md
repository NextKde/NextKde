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
AppIdentityService
        ↓
WindowService
        ↓
AppGroupService
        ↓
Dock / Alt+Tab / Preview / Stage Manager
```

### AppIdentityService

File: `modules/dock/AppIdentityService.qml`

This is the only service that resolves application identity. It currently
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
ConfigService.iconOverrides[desktopId]
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

If a future Hyprland adapter exposes `class` or `initialClass`, pass those as
additional lookup hints into this service. Do not add a second matching
implementation in Dock or WindowService.

### WindowService

File: `modules/dock/WindowService.qml`

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

File: `modules/dock/AppGroupService.qml`

This derives app groups from `ConfigService.pinnedAppIds` and
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

The current Dock policy is `pinnedVisible === true` only when a pinned app
has no open windows. A future macOS/KDE grouped view may show the pinned app
and its windows together without changing identity or persistence code.

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

## Persistence contract

File: `config/dock/config.json` relative to the current shell directory.

Current user configuration fields:

```json
{
  "version": 1,
  "baseHeight": 60,
  "maxWidthRatio": 0.9,
  "theme": "dark",
  "iconOverrides": {},
  "pinnedAppIds": [],
  "proportions": {}
}
```

Persist:

- canonical `pinnedAppIds`
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

When the configuration format changes, increment `version`, provide defaults
for missing fields, preserve unknown fields where practical, and write the
new format only after a successful migration. Future work should move the
file to an XDG configuration path while retaining a one-time migration from
the current shell-directory path.

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
