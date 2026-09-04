# KOS project context

This repository is a KDE Plasma 6 Wayland desktop shell built with Quickshell
0.3.x. The runtime boundary is `shell/` (load with `qs -p shell` or `qs -c kos`).

## Runtime products

- `kos-platform` (`platform/`): one C++20/Qt 6 user daemon. It owns KWin
  snapshots/commands, Wayland clipboard MIME ownership, file operations and
  Open-With, NetworkManager, PipeWire, BlueZ, brightness, session actions,
  themes, screenshots, and global shortcut installation.
- `kos-data-service` (`services/data-service/`): one Go user daemon. It samples
  CPU/memory/disk/frequency/temperature, stores history and activity attribution,
  watches the desktop directory, owns shared weather state, and serves
  `$XDG_RUNTIME_DIR/kos-data.sock`.
- `kos-settings` (`apps/settings/`): independent Qt Quick settings process;
  it talks to Shell `IpcHandler` endpoints and never imports Shell modules.
- `kos-calendar`, `kos-todo`, `kos-weather`, and `kos-music`: optional,
  independently built Qt Quick applications. Calendar/Todo share the
  D-Bus-activated PIM service; Weather uses `kos-data-service`.
- `integrations/kwin/`: the two project-owned KWin plugin libraries.
- `vendor/kwin-effects-glass/`: third-party glass effect source with its own
  license.

## IPC and state

Shell clients use `PlatformClient.qml` and `DataClient.qml`, which send
versioned JSON Lines over:

```text
$XDG_RUNTIME_DIR/kos-platform.sock
$XDG_RUNTIME_DIR/kos-data.sock
```

Sockets are mode `0600`; every request has an operation and `requestId`, and
responses use the shared `{ok,result,error}` model in
`shared/contracts/platform.v1.md`. The data service keeps its existing state
root at `$XDG_STATE_HOME/quickshell/shell-data-service/` so refactors never
delete user history.

## UI ownership

`NetworkService`, `ControlCenterService`, `DesktopFilesService`, and
`WindowService` are presentation adapters only. They do not invoke `nmcli`,
`wpctl`, `bluetoothctl`, `qdbus6`, `systemctl`, `gio`, `socat`, or `sh -c`.
`MetricsService` and `ActivityUsageService` consume `DataClient` snapshots.

## Code-review gate

Reject QML or Settings changes that execute desktop-integration or
system-control commands, or call desktop integration APIs directly. In
particular, QML must not use `qdbus6`, `kwriteconfig6`, `nmcli`, `wpctl`,
`bluetoothctl`, `systemctl`, or `gio` for desktop integration.
Add a bounded, versioned operation to `shared/contracts/platform.v1.md`,
implement it in `kos-platform`, and call it through `PlatformClient.qml` (or
through a Shell `IpcHandler` for Settings). Review the behavior when the daemon
is unavailable, including the user-visible fallback or retry path.

An existing atomic write of module-owned configuration under
`Quickshell.stateDir` is a narrow legacy exception; keep it limited to local
state persistence and track its service-owned replacement separately.

## Build and operations

Use the root entry point:

```sh
./tools/kosctl doctor
./tools/kosctl build
./tools/kosctl install
./tools/kosctl start
./tools/kosctl sync
./tools/kosctl dev
./tools/kosctl run
./tools/kosctl uninstall
```

`install` is non-disruptive: it installs files and enables the user units but
never restarts running services or hot-loads KWin effects (replacing plugin
files in place and reloading them has crashed `kwin_wayland`). `start` applies
the latest installed revision immediately by restarting the services; the KWin
effects are only persisted to kwinrc and load on the next KWin/session start.
It also adopts manually launched `qs -c kos` instances under systemd
supervision. `sync` copies QML-only changes into the installed config (no
hot-reload — the installed shell runs with its file watcher disabled, so a
copy in progress can never trigger a half-written hot-reload), and `dev` runs
the full stack from the source tree on dedicated sockets (`KOS_PLATFORM_SOCKET`,
`KOS_DATA_SOCKET`) beside the installed services. All launch modes share one
pinned state directory via the `StateDir` pragma in `shell/shell.qml`.

`CMakePresets.json` provides core Debug/Release configurations plus all-app and
per-app presets. Optional application switches default to `OFF`, so a core
Shell build does not pull application dependencies. Go dependencies are
resolved by the configured Go module proxy. KWin plugin builds may be disabled
with `KOS_BUILD_KWIN_PLUGINS=OFF` when development headers are unavailable.

## Change boundaries

The one-time migration is intentionally split into independently reviewable
commits: repository layout, platform daemon/contracts, Shell socket clients,
data-service protocol, build/install tooling, and documentation. Preserve
unrelated worktree changes and validate each stage before committing.

## Known integration gaps

Tracked follow-ups from the apps-platform merge, not merge defects:

- Appearance has two sources of truth: the Shell stores its settings in
  `Quickshell.stateDir/appearance/config.json` while Kos applications read
  `QSettings("NextKde", "KosApplications")` through `Kos::App::ApplicationPreferences`.
  The two are not bridged, so Shell appearance changes do not reach
  applications. The designed bridge point is the `KOS_APPEARANCE`,
  `KOS_MATERIAL`, `KOS_ACCENT`, ... environment overrides honored by
  `ApplicationPreferences`, which `AppActionService.launchById` could inject.
- Standalone applications use `LiquidTextField` with its fixed light-glass
  palette, which is unreadable on light `AppTheme` surfaces. Applications
  should receive a theme-aware wrapper (a `KosTextField` in `Kos.Ui` that
  injects `AppTheme` colors) instead of editing the shared control.
