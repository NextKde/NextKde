# KOS project context

This repository is a KDE Plasma 6 Wayland desktop shell built with Quickshell
0.3.x. The runtime boundary is `shell/` (load with `qs -p shell` or `qs -c kos`).

## Runtime products

- `kos-platform` (`platform/`): one C++20/Qt 6 user daemon. It owns KDE-native
  application launching, KWin snapshots/commands, Wayland clipboard MIME ownership, file operations and
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

## Privileged system writes

`tools/kosctl` stages the system-prefix payload under `$build_dir` (inside
`$HOME`) and then copies it into `/usr` with `sudo cp`. Two rules protect that
boundary:

- Never let a copy carry the source's SELinux label across it. `cp -a` restores
  `security.selinux` through the xattr it copies, so a tree staged under `$HOME`
  (labelled `user_home_t`) relabels `/usr`, `/usr/lib64` and `/usr/share`.
  Confined helpers such as `unix_chkpwd` (sudo's password check) and
  `pkla-check-authorization` (polkit) then cannot read their own libraries,
  every privilege-escalation path fails, and the machine is only recoverable
  from a rescue environment. Pass `-Z` so `cp` applies the destination's default
  context, and pass it only when SELinux is active (`getenforce` exists and does
  not report `Disabled`), because `cp` on non-SELinux systems is built without
  that flag. `--no-preserve=context` is not enough on its own: `-a` copies the
  xattr as well. A machine that already received the wrong labels is repaired
  with `sudo restorecon -R /usr` from a TTY or rescue environment.

- Never install anything the invoking user could have rewritten after the check
  that inspected it. Verify ownership and modes on the staged tree, then copy
  with `--no-preserve=ownership` so the installed files land root-owned; see
  `install_kwin_plugins`.

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
copy in progress can never trigger a half-written hot-reload), and `dev` starts
only the Shell from the source tree while reusing the resident
`kos-platform.service` and `kos-data.service` through the standard runtime
sockets. All launch modes share one pinned state directory via the `StateDir`
pragma in `shell/shell.qml`.

Settings follows the session it serves rather than the location of its binary.
`kosctl dev` builds no applications, so the window the Shell starts is the
installed `kos-settings`, and it would load the QML copy installed beside it —
a `kosctl install` per edit, which is what `dev` exists to avoid. The session
directory the platform daemon passes down as `KOS_SHELL_DIR` therefore decides
the tree: a checkout Shell makes Settings load that checkout's own
`apps/settings/main.qml` (and watch it, so a save rebuilds the open window;
text that does not compile is refused and the window stays as it is), while an
ordinary launch keeps loading the installed copy. Development sessions show a
banner saying so, because the settings on those pages belong to the session's
own state directory and not to the ones the installed desktop reads at login.

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
- `KosTextField` is the application-safe wrapper for text input. It injects
  `AppTheme` text, field, border, and focus colors into the Shell-oriented
  `LiquidTextField`; standalone application UI should use the wrapper rather
  than the fixed light-glass defaults.
