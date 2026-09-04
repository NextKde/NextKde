# Project architecture

KOS is organized by runtime boundary and lifecycle, not by the command used
to reach a feature. The repository intentionally produces one Quickshell
process, one C++ platform daemon, one Go data daemon, one settings app, and
two KWin plugin libraries.

```text
NextKde/
├── shell/                    Quickshell configuration root
│   ├── shell.qml
│   └── desktop/              UI feature modules
├── apps/settings/            independent Qt Quick application
├── shared/
│   ├── qml/                  portable controls
│   └── contracts/            JSONL and shortcut contracts
├── services/data-service/    Go metrics/history/desktop service
├── platform/                 kos-platform C++/Qt daemon
├── integrations/kwin/        project-owned KWin plugins
├── vendor/kwin-effects-glass/ third-party KWin effect
├── packaging/                systemd and desktop files
├── tools/kosctl               lifecycle entry point
└── docs/                     architecture and operational docs
```

## Dependency direction

```text
apps/settings ── Shell IPC ──► Quickshell
Quickshell ── JSONL sockets ──► kos-platform / kos-data-service
kos-platform ── D-Bus/argv ──► KDE, KWin, NetworkManager, PipeWire, BlueZ
```

`apps/settings` never imports `shell/desktop`; it uses the narrow
`IpcHandler` endpoints exposed by the shell. Shell QML does not parse system
command output. It consumes `PlatformClient.qml` and `DataClient.qml`, which
queue requests and correlate responses by `requestId`.

`shared/qml` is portable Qt Quick code. It must not import Quickshell, KWin, or
Wayland-only modules. `shared/contracts` is the source of truth for protocol
versions, error codes, and default shortcut definitions.

## Runtime products

| Product | Lifecycle | Responsibility |
| --- | --- | --- |
| Quickshell (`qs -c kos`) | interactive | visual shell surfaces and presentation models |
| `kos-platform` | systemd `--user` resident | live desktop integration and privileged adapters |
| `kos-data-service` | systemd `--user` resident | telemetry, activity ledger, desktop snapshots |
| `kos-settings` | on demand | settings UI; communicates with Shell IPC only |
| KWin effect `.so` files | KWin managed | compositor effects, independent plugin IDs |

The old `helpers/` category is intentionally gone. A short-lived utility is
either a `tools/` script or an internal operation in `kos-platform`; a
long-running owner belongs in `services/`. This avoids duplicated lifecycle,
logging, and IPC code while preserving host boundaries that cannot be merged.

## State and installation

`./tools/kosctl install` installs user-owned products under `~/.local`, copies
the shell to `~/.config/quickshell/kos`, and enables the systemd user units for
the next session without disturbing the running one. It never touches the
running session: no service restart, no KWin effect hot-load, and kwinrc is
written with `--notify false` so the running compositor is not signalled. The
install prompt tells the user to log out/in (or reboot) to apply, with
`./tools/kosctl start` as the opt-in way to apply immediately. `./tools/kosctl
start` restarts the units (KWin effects are only persisted to kwinrc and load
on the next KWin/session start, and manually launched shell instances are
adopted). `./tools/kosctl sync` copies QML-only edits into the installed config
without hot-reloading (the installed shell runs with its file watcher disabled
so a copy in progress can never trigger a half-written reload), and
`./tools/kosctl dev` runs only the Shell from the source tree and reuses the
installed systemd platform and data services through their standard sockets.
Every launch mode shares one pinned state directory
(`$XDG_STATE_HOME/quickshell/kos`), so user data such as dock pins and launcher
icons is independent of how the shell was started. The data service keeps its
existing state root under
`$XDG_STATE_HOME/quickshell/shell-data-service` so an architecture migration
does not erase preferences or history. `kosctl uninstall` removes binaries,
units, and shell files but leaves those state directories intact.

### systemd user units

Installation registers three `systemd --user` units, generated from
`packaging/systemd/` into `~/.config/systemd/user/`. All three are
`PartOf=graphical-session.target` (so logout stops them cleanly) and
`WantedBy=graphical-session.target` (so each login starts them again —
`default.target` would only start them once at boot).

| Unit | Description | ExecStart |
| --- | --- | --- |
| `kos-shell.service` | Quickshell desktop shell: the dock, launcher, bar, notifications, and every visual surface. `--no-duplicate` exits if an instance is already running; `-c kos` loads `~/.config/quickshell/kos`. `KillMode=process` stops only the main `qs` process so desktop apps it launched via `QProcess::startDetached()` survive a restart, and `QS_DISABLE_FILE_WATCHER=1` disables hot-reload of the installed config. | `/usr/bin/qs --no-duplicate -c kos` |
| `kos-platform.service` | C++ platform daemon: KWin bridge, live window events, thumbnails, and privileged host adapters. Loads the bridge QtScript from `~/.local/share/kos/platform/kwin/window-bridge.js`. | `~/.local/libexec/kos-platform daemon` |
| `kos-data.service` | Go data daemon: telemetry, activity ledger, and desktop-directory snapshots served on `$XDG_RUNTIME_DIR/kos-data.sock`. | `~/.local/libexec/kos-data-service` |

The shell requires the platform daemon (`Requires=kos-platform.service`) and
wants the data daemon (`Wants=kos-data.service`). All three wait on
`plasma-kwin_wayland.service` because Plasma marks `graphical-session.target`
active before the Wayland socket is ready; starting earlier aborts with
`could not connect to display`. Inspect them with
`systemctl --user status kos-shell kos-platform kos-data` and
`journalctl --user -u kos-shell.service -f`.

### Optional application contract

Applications are optional companions, not dependencies of the Quickshell
desktop path. When an application platform has a top-level CMake build, every
application option must default to `OFF`; its documented build preset or
command enables only the requested application and its direct dependencies.
Building, installing, or running the Shell must neither build nor install an
optional application.

An application-owned service must be activated on demand by that application
or through D-Bus activation. It must not install a session autostart entry by
default. This keeps calendar, todo, music, and similar future applications from
creating resident processes for Shell-only users.

Optional services are enhancements, never a single point of failure for an
existing Shell feature. If a Shell surface consumes optional service data, it
must retain a local, documented fallback. In particular, weather surfaces must
continue to use the existing keyless Open-Meteo request/cache path whenever the
shared weather service is not installed, unavailable, or returns an invalid
snapshot.

`apps/settings/` is the first application. The gear exposed by the top bar or
Dock-hosted status area starts its process through `DesktopAppLauncher`; it
never loads Settings UI into the Quickshell process.

## Code-review rules

Shell QML and Settings must not directly execute desktop-integration or
system-control commands, or access desktop integration APIs. Reject changes
that invoke `qdbus6`, `kwriteconfig6`, `nmcli`, `wpctl`, `bluetoothctl`,
`systemctl`, `gio`, or similar host commands from QML. Add a bounded, versioned operation to
`shared/contracts/platform.v1.md` and implement it in `kos-platform`; use
`PlatformClient.qml` from Shell QML and an `IpcHandler` endpoint from Settings.
The review must also cover the unavailable-daemon path and document the user
visible fallback or retry behavior.

Existing atomic writes of a module's own configuration under
`Quickshell.stateDir` are a narrow legacy exception, not a pattern for new
desktop integration. Keep them local to configuration persistence and plan
their service-owned replacement separately.

## Change strategy

Directory moves, platform daemon, Shell client migration, data-service
migration, build/install tooling, and documentation are separate commits. Each
stage is buildable or has an explicit external prerequisite called out in its
commit validation. This keeps rollback and review boundaries clear during the
one-time cutover.
