# KOS platform IPC v1

The platform daemon listens on `$XDG_RUNTIME_DIR/kos-platform.sock`. The
socket is a per-user Unix socket with mode `0600`; it is not a network API.
Messages are UTF-8 JSON objects separated by newlines.

Every request contains `version`, `requestId`, `operation`, and an optional
`payload`. A response echoes `version` and `requestId`, and contains `ok` plus
either `result` or an `error` object. Long-lived subscriptions receive event
objects independently of request responses.

```json
{"version":1,"requestId":"42","operation":"platform.ping","payload":{}}
{"version":1,"requestId":"42","ok":true,"result":{"ready":true}}
```

Errors use stable machine-readable codes:

```json
{"version":1,"requestId":"42","ok":false,"error":{"code":"permission-denied","message":"操作被系统拒绝","retryable":true}}
```

Current operation groups are:

- `clipboard.set`, `clipboard.read`, `clipboard.save-image`,
  `clipboard.history.watch-images`,
  `clipboard.history.list`, `clipboard.history.copy`,
  `clipboard.history.delete`, `clipboard.history.clear`
- `file.open`, `file.copy`, `file.launch`, `file.rename`, `file.create-folder`,
  `file.create-file`, `file.transfer`, `file.trash`, `file.trash-state`,
  `file.empty-trash`, `file.open-trash`, `file.open-with`, `file.set-default`,
  `file.open-kde`
- `kwin.subscribe`, `kwin.command`, `kwin.layout.update`
- `kwin.animation.update-targets`, `kwin.animation.prepare-launch`
- `settings.open` (allow-listed KDE System Settings modules)
- `shortcuts.apply`, `shortcuts.uninstall` (kglobalaccel-owned global
  shortcuts; the Shell composes each Exec line, the daemon validates,
  persists, and registers)
- `network.*` (including `network.traffic` for read-only interface counters),
  `audio.*`, `bluetooth.*`, `display.*`, `session.*`,
  `theme.*`, and `screenshot.*`

KWin events are sent to subscribers as `window.snapshot`, `desktops`,
`thumbnail`, `animation.started`, and related event names. KWin's internal script-to-daemon channel
continues to use the session D-Bus service `org.kos.Platform` at `/Platform`;
clients must not call that private interface directly.

`kwin.layout.update` is an internal Shell-to-compositor layout update. Its
payload is
`{outputName, outputRect, barReservedHeight, dockPosition, dockRect, workspaceGap}`.
Rectangles use global logical coordinates; `dockPosition` is one of `bottom`,
`left`, or `right`. The daemon bounds and validates every field before
forwarding an `update-layout` command to the KWin script. A new normal main
window may use the latest layout for its one-time initial placement; existing,
maximized, fullscreen, dialog, transient, and special windows are not moved.

On `kwin.subscribe`, the daemon replays both its latest `window.snapshot` and
latest `desktops` event when available. Consumers may explicitly request a
fresh desktop event with `kwin.command {action: "desktops"}` during startup.

Platform adapters validate all paths and operation names before executing a
system action. Existing paths are canonicalized and new targets are resolved
through a canonical existing parent. Passwords and raw command output
containing secrets must never be logged.

Global shortcuts are registered by the platform daemon through the
KGlobalAccel client library (the plasma powerdevil mechanism): every KOS
shortcut is a QAction under the single `org.kos.Platform` component, so the
Shortcuts KCM shows ONE "KOS" entry and no service desktop files exist at
all. `shortcuts.apply` carries `{shortcuts:[{id,description,combo,exec}]}`;
on activation the daemon runs the Exec line the Shell supplied, so it always
addresses the live Shell instance (dev `-p` or installed `-c kos`).
`shortcuts.uninstall` unregisters the actions and removes leftover files
from superseded layouts.

`kwin.animation.*` accepts a JSON string payload produced by the Dock animation
model and forwards it only to the project-owned KWin effect. `theme.apply-system`,
`theme.sync-glass`, and `theme.sync-dock-animation` accept bounded values and
own the KDE configuration writes; Shell and Settings never invoke `qdbus6` or
`kwriteconfig6`.
