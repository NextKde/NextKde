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

- `application.launch` (KDE-native desktop-entry launch; accepts a desktop ID
  and optional URLs, never an arbitrary command)
- `clipboard.set`, `clipboard.read`, `clipboard.save-image`,
  `clipboard.history.watch-images`,
  `clipboard.history.list`, `clipboard.history.copy`,
  `clipboard.history.delete`, `clipboard.history.clear`
- `input.paste` (synthesise Ctrl+V into the focused window through the KWin
  effect; a desktop-level injection, never a clipboard data operation)
- `clipboard.thumb`, `clipboard.pinned.list`, `clipboard.pinned.add`,
  `clipboard.pinned.remove`, `clipboard.pinned.copy` (entry previews and a pin
  store under `$XDG_STATE_HOME/quickshell/<shell id>/clipboard`; every file is
  content-addressed and removed together with the entry that owns it, so
  deleting never leaves state behind)
- `file.open`, `file.copy`, `file.launch`, `file.rename`, `file.create-folder`,
  `file.create-file`, `file.transfer`, `file.trash`, `file.trash-state`,
  `file.empty-trash`, `file.open-trash`, `file.open-with`, `file.set-default`,
  `file.open-kde`
- `kwin.subscribe`, `kwin.command`, `kwin.layout.update`
- `kwin.animation.update-targets`, `kwin.animation.prepare-launch`
- `settings.open` (allow-listed KDE System Settings modules) and
  `settings.launch` (launch the `kos-settings` app with a fixed argv; the
  only accepted payload field is `shellDir`, an optional absolute path that
  must canonicalise to an existing directory and is exported to the child as
  `KOS_SHELL_DIR` so a development Settings session reconnects to the Shell
  that launched it; no caller-supplied arguments)
- `state.read`, `state.write` (bounded read/write of UTF-8 state files under
  `$XDG_STATE_HOME/quickshell`; payload `{dir, file[, data]}` where `dir` is a
  relative sub-path -- or an absolute path that must stay under the state root
  -- and `file` is a bare file name (`dir` <=512 chars, `file` <=255 chars).
  Paths are canonicalized and must remain under the root (`..` and symlink
  escapes are rejected); payloads are capped at 1 MiB. `state.write` commits
  rename. `state.read` returns `{data, exists}` and reports `exists:false`
  with an empty `data` for a missing file)
- `notify` (freedesktop notification; payload `{summary, body?, icon?,
  appName?, urgency?}` with `urgency` one of `low`/`normal`/`critical` and
  `appName` (<=128 chars) the notification's grouping/app label, defaulting
  to `"KOS Shell"`. The daemon calls `org.freedesktop.Notifications.Notify`
  when the service is registered and otherwise spawns `notify-send` with a
  fixed argv; fields are length-capped and never reach a shell)
- `nightlight.get`, `nightlight.toggle` (KWin Night Color; `toggle` writes
  `NightColor/Active` to kwinrc and applies through the NightLight D-Bus
  interface. Once the config write has committed, a failure to uninhibit /
  inhibit / reconfigure is partial application, not a failed toggle: the
  response stays `ok:true` with `result.applied:false` and a `warning`
  string, so callers align their UI to the persisted `enabled` state rather
  than rolling back to a value that no longer matches kwinrc)
- `shortcuts.apply`, `shortcuts.uninstall` (kglobalaccel-owned global
  shortcuts; the Shell composes each Exec line, the daemon validates,
  persists, and registers)
- `tray.identify` (friendly names for StatusNotifierItem entries whose `Id` is
  a generated token such as an Electron `chrome_status_icon_*`; the daemon
  reads the SNI watcher's registration list, each item's `Id`/`Title`, and the
  owning connection's PID -- then `/proc/<pid>/comm` and `cmdline` -- on its
  worker pool, so the Shell never spawns a helper process to resolve them.
  Returns `{"names": {"<itemId>": "<friendly name>"}}`; an item whose name
  cannot be derived is omitted rather than mapped to an empty string, and the
  Shell keeps its own fallback for those)
- `network.*` (including `network.traffic` for read-only interface counters),
  `audio.*` (including `audio.applications`,
  `audio.application.set-volume`, and `audio.application.set-mute` for
  per-application PipeWire/PulseAudio sink-input control), `bluetooth.*`, `display.*`, `session.*`,
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
`workspaceGap` remains accepted for v1 compatibility, but initial placement
meets the Bar/Dock safe edges directly and does not create an invisible gap.

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
the daemon allow-lists each exec — it must parse (shell quoting rules, no
metacharacters) into `qs|quickshell [-c name] [-p|--path dir] ipc call
<target> <action>...` and is spawned as an argv array, never through a
shell; anything else is rejected and logged. On activation the daemon runs
the validated command the Shell supplied, so it always addresses the live
Shell instance (dev `-p` or installed `-c kos`).
`shortcuts.uninstall` unregisters the actions and removes leftover files
from superseded layouts.

`kwin.animation.*` accepts a JSON string payload produced by the Dock animation
model and forwards it only to the project-owned KWin effect. `theme.apply-system`,
`theme.sync-glass`, and `theme.sync-dock-animation` accept bounded values and
own the KDE configuration writes; Shell and Settings never invoke `qdbus6` or
`kwriteconfig6`. `theme.apply-system` and `theme.toggle` change only the KDE
color scheme when that tool is available; applying a complete Look-and-Feel
package is a compatibility fallback, because replacing icons and workspace
defaults is outside the light/dark toggle contract.
