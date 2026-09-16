# Platform service architecture

`kos-platform` is the user-session adapter boundary. It is one C++20/Qt 6
process started by `kos-platform.service`; its internal modules are grouped by
capability (`applications`, `kwin`, `clipboard`, `files`, `network`, `audio`, `bluetooth`,
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
`integrations/kwin/decoration-liquid-glass` is a KDecoration3 plugin rather
than an effect: it installs to the `org.kde.kdecoration3` plugin directory and
kwinrc selects it with `[org.kde.kdecoration3] library=kos_liquid_glass`.

It is compiled C++ rather than a QML Aurorae theme for one reason:
`KDecoration3::Decoration::setBorderRadius()` is the only way to make KWin clip
a window — the client's own opaque content included — to rounded corners, and
`org.kde.kwin.aurorae.so` does not link that symbol at all. A QML theme can
only round the rectangle it paints inside its own title bar strip, so the
window's bottom two corners stay square no matter what the QML says.

The frosted material is likewise not painted here. The decoration publishes its
title bar via `setBlurRegion()` and the Glass effect blurs what is behind it.
Glass deliberately has two rendering paths: Quickshell surfaces receive the
full liquid/soft material, while ordinary application windows receive only the
blur result. The latter path does not refract, tint, highlight, add noise, or
apply an SDF corner mask; application content and decoration remain responsible
for their own shape. The vendored effect also subtracts opaque client content,
which prevents transparent layer-shell windows from blurring unused space and
avoids painting behind opaque application content.

## Per-surface glass shape protocol

`ext-background-effect` carries only a union of integer rectangles. There is no
radius or corner field, so the effect infers the mask by reading the top-row
inset of the published region. That is enough for exactly one card per surface
and only for a circular corner; it cannot describe the superellipse, and it
cannot hold two shapes in one surface (the Dock pill and its Home Indicator, or
several control-centre cards). Re-drawing the outline on the QML side does not
close the gap either: once the region looks like a single rounded card the
effect discards the client region and substitutes its own SDF.

`protocols/kos-surface-shape-v1.xml` is a project-local protocol that carries the
missing fields. It is deliberately not a Quickshell fork:

```text
kos_surface_shape_manager_v1.get_shape(wl_surface) ──► kos_surface_shape_v1
    set_geometry(x, y, width, height)   surface-local logical units
    set_corner(radius, exponent)        both wl_fixed
    set_enabled(enabled)
```

One surface may hold any number of shapes, which is what keeps the multi-card
case open. Three pieces implement it and all three build from this repository:

| Piece | Path | Role |
| --- | --- | --- |
| Protocol | `protocols/kos-surface-shape-v1.xml` | Shared wire definition. |
| Client | `integrations/quickshell/surface-shape/` | QML native module `Kos.SurfaceShape`. Its `SurfaceShape` type attaches to any `QQuickItem`, publishes the item's `mapRectToScene()` rectangle, and walks the ancestor chain so a parent move is not missed. |
| Server | `vendor/kwin-effects-glass/src/surfaceshapemanager.{h,cpp}` | Creates the global inside the glass effect and keeps per-surface state. |

`LiquidGlassPanel` owns the only declaration today; one is created per panel, so
each popup's shape objects are independent. Where a surface declares shapes the
effect replaces its region-reconstructed content geometry with one draw per
shape, re-uploading `box`, `cornerRadius` and `cornerExponent` between draws; the
noise pass is per shape as well. Blur Region still decides which background
pixels are captured, and surfaces that declare nothing keep the plain path
described above.

The replacement is all-or-nothing, and it excludes the effect's other geometry
substitution. A surface whose published region reads as one smooth card also
gets its content geometry rewritten to the whole background rectangle; letting
that run after the shapes have been accepted leaves each shape's recorded
vertex range describing a buffer layout that no longer exists, and the shape
material is then painted over rectangles that do not belong to it -- the pill
loses its glass while stray edges keep the refraction. So the smooth-card path
is skipped whenever shapes were accepted, and a declared shape that turns out
not to be drawable (zero-sized, clipped away, off-screen) abandons the whole
swap instead of the surface's glass: the region geometry it was meant to refine
is what remains.

Three properties of this arrangement are load-bearing:

- **Its build is not a plugin build.** The client module links Qt and
  wayland-client only -- no KWin. It needs `enable_language(C)` in its own
  `CMakeLists.txt`, because `project(KOS ... LANGUAGES CXX)` makes CMake accept
  the `wayland-…-protocol.c` that `ecm_add_wayland_client_protocol()` appends and
  then silently never compile it: the module still links, and fails only at
  `dlopen` with `undefined symbol: kos_surface_shape_v1_interface`.
- **It must reach Qt's import path, not `KDE_INSTALL_QMLDIR`.** The latter
  resolves to `<prefix>/lib/qml`, which is not a directory Qt searches;
  `QT_INSTALL_QML` is `<prefix>/lib/qt6/qml` and holds every module on the
  system. The install target uses the latter, which is why the source-tree run
  needs `QML2_IMPORT_PATH` (set by `kosctl dev`) and the installed run does not.
- **The global is owned by the effect, so its teardown is a contract.** Disabling
  the glass effect destroys the manager, and `wl_global_destroy` blanks the
  server-side implementation of every bound manager resource. Therefore the
  server must *detach* client-owned shape resources rather than destroy them:
  destroying one drops its id from the client's object map, and the `destroy`
  the client is about to send for the vanished global returns as
  `invalid object` -- a fatal protocol error that takes the whole connection
  with it. Detached resources no-op every request and are reclaimed by the
  client's own destroy. On the client side the mirror rule is that
  `global_remove` must release the proxies locally (`wl_proxy_destroy`) and must
  not marshal, because the implementation it would reach is already gone. Every
  `SurfaceShape` re-attaches off the next `global` event, so a toggle costs one
  round trip and no explicit re-registration.

> **Packaging status.** The module is currently built and installed through
> `KOS_BUILD_KWIN_PLUGINS` / the `kwin_plugins` install component, even though it
> has no KWin dependency. Consequences today: `nix/package.nix` copies `shell/`
> and `shared/` only, so the NixOS package ships no module at all and
> `import Kos.SurfaceShape 1.0` fails there; and a user-only install
> (`KOS_BUILD_KWIN_PLUGINS=OFF`) skips it as well. Both break the whole `common`
> module, not just the panel. Resolving this means shipping the module with the
> shell payload and putting its directory on `QML2_IMPORT_PATH`.

> **Applying a rebuilt effect.** KWin keeps the effect library mapped for as long
> as the compositor lives. The `Effects` D-Bus `unloadEffect` / `loadEffect` pair
> re-instantiates the effect object from the copy already in memory, so a
> rebuilt `glass.so` installed underneath a running session is never read: the
> effect reloads, reports itself loaded, and keeps rendering the old code. A
> rebuild takes effect on the next compositor start and nowhere else, which is
> why a fix can look inert while the file on disk is already correct. Check the
> timestamp of the installed plugin against the compositor's start time before
> concluding a change did nothing.

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
| `applications` | launch installed desktop entries with optional URLs | KDE `KService` + `KIO::ApplicationLauncherJob`; desktop-entry parsing, activation and process grouping remain KDE-owned |
| `clipboard` | `clipboard.set/read/save-image`, history watch/list/copy/delete/clear | Qt `QClipboard`, Wayland MIME ownership, platform-supervised cliphist |
| `files` | open, copy, launch, transfer, trash, Trash state/empty, Open-With | Qt file APIs and `gio` |
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
