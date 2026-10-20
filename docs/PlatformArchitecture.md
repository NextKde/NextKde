# Platform service architecture

`kos-platform` is the user-session adapter boundary. It is one C++20/Qt 6
process started by `kos-platform.service`; its internal modules are grouped by
capability (`applications`, `kwin`, `clipboard`, `files`, `network`, `audio`, `bluetooth`,
`display`, `session`, `theme`, `screenshot`, and `shortcuts`). They are not
separate helper executables.

## Daemon source modules

`platform/src/daemon/PlatformServer.cpp` owns JSONL framing, version checks,
connections, event delivery, the reply cache and in-flight request queues. Its
private feature handlers return `true` after accepting a request (including
asynchronous replies), and `false` without replying when the operation belongs
to another handler. The dispatcher alone emits the final `unknown-operation`.
The wire contract remains [platform.v1](../shared/contracts/platform.v1.md).

| Files under `platform/src/daemon/` | Responsibility |
| --- | --- |
| `PlatformServerApplications.cpp`, `PlatformServerFiles.cpp` | KDE application launch and file operations |
| `PlatformServerWindows.cpp`, `PlatformServerAppMenu.cpp` | KWin commands, input bridge and application menus |
| `PlatformServerClipboard.cpp`, `PlatformServerClipboardPins.cpp` | Clipboard/history/preview requests and persistent pins |
| `PlatformServerNetwork.cpp` | Network payload validation, cache keys and worker completion |
| `PlatformNetworkRead.cpp`, `PlatformNetworkConnect.cpp` | Bounded NetworkManager reads and connection transactions |
| `PlatformServerAudio.cpp`, `PlatformServerBluetooth.cpp` | Audio and Bluetooth operations |
| `PlatformServerDisplay.cpp`, `PlatformServerTheme.cpp` | Brightness/night light and desktop appearance |
| `PlatformServerDesktop.cpp` | Settings launch, notifications, shortcuts, session actions and screenshot tools |
| `PlatformServerState.cpp`, `PlatformServerWallpaper.cpp` | Shell state storage, wallpaper and optional depth requests |
| `PlatformServerTray.cpp`, `PlatformServerWatches.cpp` | Tray identity and D-Bus cache invalidation watches |
| `PlatformDbus.*`, `PlatformPaths.*`, `PlatformProcess.*` | Shared bounded bus calls, path policy and process watchdog/output helpers |

All feature adapters are private member implementations of the same server.
They do not own additional sockets, caches or thread pools. Socket writes,
watch subscriptions and cache changes stay on the Qt event loop. Network
workers receive value arguments and return `NetworkWorkerResult` through the
implementation-only `PlatformNetworkBackend.h` contract; they open private
bus connections and never write to client sockets. `PlatformClipboardStorage.h`
shares only storage/thumbnail helpers between history and pins. Helpers used
by one module remain in its unnamed namespace.

`PlatformServer.h` retains lifecycle-sensitive state and pool declaration
order: destruction waits for worker completion before the shared state goes
away. New operations should extend their feature handler and the public
protocol document, without adding business logic to the transport dispatcher.
The startup test pipelines requests through different adapters; media, file,
keep-awake and protocol tests exercise the built daemon on isolated buses.

## Runtime boundaries

```text
Quickshell ── JSONL ──► $XDG_RUNTIME_DIR/kos-platform.sock
Go data service ───────► platform operations when needed
kos-platform ── D-Bus ─► KWin / KDE services
kos-platform ── argv ───► nmcli, wpctl, bluetoothctl, loginctl, gio, etc.
```

The KWin script is installed as data and loaded by the daemon. Its private
session-D-Bus object is `org.kos.Platform` at `/Platform`; Shell never calls
that object directly. KWin effects under `kwin/` remain separate
`.so` targets because KWin discovers each plugin by ID.
`kwin/kos-decoration` is a KDecoration3 plugin rather
than an effect: it installs to the `org.kde.kdecoration3` plugin directory.
`kosctl install` installs the decoration and selects KOS on first installation through the
Settings backend, saving the prior choice. Later choices are preserved. Bridge's controls are tied
to that decoration. Geometry belongs to Bridge: the decoration consumes its resolved corner/shadow
properties and must not introduce another radius/outline. The title bar fills its intersection with
the resolved contour; without Bridge metadata it stays square. See [WindowAppearance](WindowAppearance.md).

## Per-surface glass shape protocol

The shared definition is [`kos-surface-shape-v1.xml`](../shell/native/surface-shape/kos-surface-shape-v1.xml),
currently **v8** for manager and shape. Capability negotiation preserves old request numbering.
The client `Kos.SurfaceShape` QML native module lives in `shell/native/surface-shape/`; the server
is `kwin/glass-effect/src/surfaceshapemanager.{h,cpp}`, owned by the effect.

Versions 1–7 keep established immediate updates. v8 adds manager-committed batches latched with
`wl_surface.commit`, explicit material profiles, continuous blur sigma and tint independent of
readability scrim. Material opacity fades the complete effect. Explicit v8 shape ownership remains
active even for empty/hidden geometry; falling back to whole-surface blur there would paint pixels
the client intentionally removed. Legacy clients/undeclared windows retain their compatible paths.
See [WindowAppearance](WindowAppearance.md#surface-shape-protocol) for geometry/fallback invariants.
The XML is authoritative for clamps and legacy scrim encodings; do not send unnegotiated requests.

`SurfaceShape` maps item geometry to surface-local coordinates and tracks ancestor movement.
`LiquidGlassPanel` owns one declaration per panel, permitting several distinct shapes on one surface.
Material/frosted and ordinary-window paths must not accidentally acquire liquid refraction.
Per-shape metadata and the standard region are different contracts; do not infer geometry from a
layer-shell namespace or reintroduce legacy alignment heuristics for v8.

Preserve these lifecycle/build requirements:

- The client links Qt/wayland-client, without KWin. Enable C for generated Wayland protocol `.c`
  sources, or linking can succeed while dlopen fails with a missing interface symbol.
- Deploy native QML modules on actual Qt import paths. Source launchers set both `QML_IMPORT_PATH`
  and `QML2_IMPORT_PATH` to matching build modules; installed/Nix launchers expose deployed modules.
  SurfaceShape builds if platform or KWin builds are enabled; disabling both requires it separately.
- Removing a Wayland global does not free bound resources. On effect teardown, detach client-owned
  resources and clear user data; detached requests no-op until client destruction. On global removal,
  clients destroy local proxies without sending requests to the removed server and reattach when it returns.
- KWin holds native libraries for the compositor lifetime. Install rebuilt effects and logout/login
  or reboot; unloading/loading effect objects cannot prove new disk code is executing. No host validation.

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
- Wi-Fi credentials are passed in typed NetworkManager D-Bus settings and are
  not logged or persisted by QML; NetworkManager owns saved profile credentials.
- Destructive session operations are explicit (`session.reboot`,
  `session.poweroff`, etc.) and are not run by automated tests.
- QML clients keep one connection, queue writes while a service restarts, and
  match every response by `requestId`.
- `kos-data-service` owns durable state and history; `kos-platform` owns live
  desktop integration. Neither process embeds the other.

## Adapter ownership

| Module | Operations | Implementation boundary |
| --- | --- | --- |
| `applications` | launch installed desktop entries with optional URLs | KDE `KService` + `KIO::ApplicationLauncherJob`; desktop-entry parsing, activation and process grouping remain KDE-owned |
| `clipboard` | `clipboard.set/read/save-image`, history watch/list/copy/delete/clear | Qt `QClipboard`, Wayland MIME ownership, platform-supervised cliphist |
| `files` | open, copy, launch, transfer, trash, Trash state/empty, Open-With | Qt file APIs, KDE application launch jobs and `gio` for file operations |
| `kwin` | snapshots, activation, desktops, thumbnails, Dock animation tickets | KWin script + internal D-Bus |
| `network` | refresh, scan, connect, 802.1X, radio, traffic counters | NetworkManager/sysfs adapter |
| `audio` | get volume, set volume/mute | PipeWire/WirePlumber adapter |
| `bluetooth` | power, list, connect/disconnect | BlueZ adapter |
| `display` | per-display brightness get/set | KDE ScreenBrightness (including DDC/CI) / brightnessctl / sysfs fallback |
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
