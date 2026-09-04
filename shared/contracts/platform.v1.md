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
- `kwin.subscribe`, `kwin.command`
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

Platform adapters validate all paths and operation names before executing a
system action. Existing paths are canonicalized and new targets are resolved
through a canonical existing parent. Passwords and raw command output
containing secrets must never be logged.

`kos-platform shortcuts install` (CLI fallback reading
`shortcuts.v1.json`) refuses to overwrite a shortcut owned by a different
desktop service; so does `shortcuts.apply`, which reports the conflict as an
error instead of applying a partial set. Both paths also remove superseded
`net.local.quickshell-*` entries from earlier generations. Uninstall removes
only the declared IDs, then asks `kglobalaccel` to unregister those actions.

`kwin.animation.*` accepts a JSON string payload produced by the Dock animation
model and forwards it only to the project-owned KWin effect. `theme.apply-system`,
`theme.sync-glass`, and `theme.sync-dock-animation` accept bounded values and
own the KDE configuration writes; Shell and Settings never invoke `qdbus6` or
`kwriteconfig6`.
