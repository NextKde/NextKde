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
  watches the desktop directory, and serves `$XDG_RUNTIME_DIR/kos-data.sock`.
- `kos-settings` (`apps/settings/`): independent Qt Quick settings process;
  it talks to Shell `IpcHandler` endpoints and never imports Shell modules.
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

## Build and operations

Use the root entry point:

```sh
./tools/kosctl doctor
./tools/kosctl build
./tools/kosctl install
./tools/kosctl run
./tools/kosctl uninstall
```

`CMakePresets.json` provides Debug/Release configurations. Go dependencies are
resolved by the configured Go module proxy. KWin plugin builds may be disabled
with `KOS_BUILD_KWIN_PLUGINS=OFF` when development headers are unavailable.

## Change boundaries

The one-time migration is intentionally split into independently reviewable
commits: repository layout, platform daemon/contracts, Shell socket clients,
data-service protocol, build/install tooling, and documentation. Preserve
unrelated worktree changes and validate each stage before committing.
