# Platform service architecture

`kos-platform` is the user-session adapter boundary. It is one C++20/Qt 6
process started by `kos-platform.service`; its internal modules are grouped by
capability (`kwin`, `clipboard`, `files`, `network`, `audio`, `bluetooth`,
`display`, `session`, `theme`, `screenshot`, and `shortcuts`). They are not
separate helper executables.

## Runtime boundaries

```text
Quickshell ── JSONL ──► $XDG_RUNTIME_DIR/kos-platform.sock
Go data service ───────► platform operations when needed
kos-platform ── D-Bus ─► KWin / KDE services
kos-platform ── argv ───► nmcli, wpctl, bluetoothctl, loginctl, gio, etc.
```

The KWin script is installed as data and loaded by the daemon. Its private
session-D-Bus object is `org.kos.Platform` at `/Platform`; Shell never calls
that object directly. KWin effects under `integrations/kwin/` remain separate
`.so` targets because KWin discovers each plugin by ID.

## JSONL contract

Requests and responses are UTF-8 JSON objects separated by `\n`:

```json
{"version":1,"requestId":"uuid","operation":"audio.get","payload":{}}
{"version":1,"requestId":"uuid","ok":true,"result":{"available":true}}
```

Failures use stable codes and never include passwords or raw command output:

```json
{"version":1,"requestId":"uuid","ok":false,
 "error":{"code":"permission-denied","message":"无法修改亮度","retryable":true}}
```

Events are independent messages (`window.snapshot`, `thumbnail`,
`desktop.changed`, and so on) and do not carry a request ID. The complete
operation list and examples live in
[`shared/contracts/platform.v1.md`](../shared/contracts/platform.v1.md).

## Security and lifecycle

- Both sockets are created under `$XDG_RUNTIME_DIR` with mode `0600`.
- Operations are explicit allow-listed names; clients cannot provide a shell
  command. Paths must be absolute, canonicalized (including existing symlinks),
  and validated against an existing parent directory before use.
- Wi-Fi credentials are positional process arguments and are never logged or
  persisted by the platform service.
- Destructive session operations are explicit (`session.reboot`,
  `session.poweroff`, etc.) and are not run by automated tests.
- QML clients keep one connection, queue writes while a service restarts, and
  match every response by `requestId`.
- `kos-data-service` owns durable state and history; `kos-platform` owns live
  desktop integration. Neither process embeds the other.

## Adapter ownership

| Module | Operations | Implementation boundary |
| --- | --- | --- |
| `clipboard` | `clipboard.set/read` | Qt `QClipboard`, Wayland MIME ownership |
| `files` | open, launch, transfer, trash, Trash state/empty, Open-With | Qt file APIs and `gio` |
| `kwin` | snapshots, activation, desktops, thumbnails, Dock animation tickets | KWin script + internal D-Bus |
| `network` | refresh, scan, connect, 802.1X, radio, traffic counters | NetworkManager/sysfs adapter |
| `audio` | get volume, set volume/mute | PipeWire/WirePlumber adapter |
| `bluetooth` | power, list, connect/disconnect | BlueZ adapter |
| `display` | brightness get/set | brightnessctl/PowerDevil fallback |
| `session` | lock, suspend, hibernate, logout, power | logind/systemd adapter |
| `theme` | toggle/reconfigure, glass and Dock-animation sync | KDE config and KWin reconfigure |
| `screenshot` | interactive capture | first available supported utility |
| `shortcuts` | install/uninstall, conflict checks, live registration | atomic `kglobalshortcutsrc` + desktop entries |

## Failure and recovery

An unavailable optional adapter returns `ok:false` with `retryable` set by the
adapter; the daemon remains alive and other operations continue. A service
restart removes and recreates only its own socket. Clients reconnect and
re-issue subscriptions (`kwin.subscribe`) after observing the connection
transition.
