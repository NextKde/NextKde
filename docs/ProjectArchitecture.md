# Project architecture

KOS is organized by runtime boundary and lifecycle, not by the command used
to reach a feature. The core produces one Quickshell process, one C++ platform
daemon, one Go data daemon, one settings app, and KWin effects and decoration.
Calendar, Calculator, Todo and Weather form the optional standard app bundle.
ListenFree is separately opt-in.
Legacy Music source and build targets have been removed; existing installations are preserved
on standard upgrades. Explicit ListenFree installation owns legacy player migration.

```text
NextKde/
├── shell/                    Quickshell configuration root
│   ├── shell.qml
│   ├── desktop/              UI feature modules
│   └── native/               shell-owned QML native plugins (SurfaceShape, Spatial3D)
├── apps/                     settings plus optional standalone applications
├── shared/
│   ├── qml/                  portable controls
│   └── contracts/            JSONL and shortcut contracts
├── services/                 long-running process owners
│   ├── ai/                   portable C++ local inference library (kos-ai)
│   ├── data-service/         Go metrics/history/desktop service
│   └── pim-service/          D-Bus activated Calendar/Todo storage
├── platform/                 kos-platform C++/Qt daemon
├── kwin/                     project-owned KWin plugins, bridge script, and glass-effect
├── packaging/                systemd, desktop files, and the nix packages
├── tools/kosctl              lifecycle entry point
└── docs/                     architecture and operational docs
```

## Dependency direction

```text
apps/settings ── Shell IPC ──► Quickshell
Quickshell ── JSONL sockets ──► kos-platform / kos-data-service
kos-platform ── D-Bus/argv ──► KDE, KWin, NetworkManager, PipeWire, BlueZ
kos-platform ── bounded JSONL ──► kos-ai-worker ──► kos-ai ──► ONNX Runtime / OpenCV
```

`apps/settings` never imports `shell/desktop`; it uses the narrow
`IpcHandler` endpoints exposed by the shell. Shell QML does not parse system
command output. It consumes `PlatformClient.qml` and `DataClient.qml`, which
queue requests and correlate responses by `requestId`.

`shared/qml` contains portable Qt Quick controls and shell-specific adapters.
The `colorize` JS algorithms are portable; Shell adapters use Quickshell image quantization.
Standalone applications must avoid importing Shell-specific adapters. Shared components
must not import `shell/desktop` feature modules. `shared/contracts` is the source of truth for protocol
versions, error codes, and default shortcut definitions.

## Runtime products

| Product | Lifecycle | Responsibility |
| --- | --- | --- |
| Quickshell (`qs -c kos`) | interactive | visual shell surfaces and presentation models |
| `kos-platform` | systemd `--user` resident | live desktop integration, privileged adapters, and bounded AI worker supervision |
| `kos-ai-worker` | lazily started child process | isolated local model download, CPU inference, and depth cache; exits after 15 idle seconds |
| `kos-data-service` | systemd `--user` resident | telemetry, activity ledger, desktop snapshots, weather cache |
| `kos-settings` | on demand | settings UI; communicates with Shell IPC only |
| `kos-calendar`, `kos-calculator`, `kos-todo`, `kos-weather`, opt-in `listenfree` | on demand | optional independent Qt Quick applications; ListenFree is explicitly selected |
| `kos-pim-service` | D-Bus activated | shared Calendar/Todo storage and reminders |
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
adopted). `./tools/kosctl dev` runs only the Shell from the source tree and
reuses the installed systemd platform and data services through their standard
sockets.
Every launch mode shares one pinned state directory
(`$XDG_STATE_HOME/quickshell/kos`), so user data such as dock pins and launcher
icons is independent of how the shell was started. The data service keeps its
existing state root under
`$XDG_STATE_HOME/quickshell/shell-data-service` so an architecture migration
does not erase preferences or history. `kosctl uninstall` removes binaries,
units, and shell files but leaves those state directories intact.

### systemd user units

Installation registers three `systemd --user` units, generated from
`packaging/systemd/` (and, for `kos-data.service`, from
`services/data-service/systemd/kos-data.service.in` — the unit lives next
to the service it starts) into `~/.config/systemd/user/`. All three are
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
default. Calendar and Todo therefore share the D-Bus-activated PIM service;
Music keeps playback in its application process.

Optional services are enhancements, never a single point of failure for an
existing Shell feature. Weather is not application-owned: it is an operation
set in the core `kos-data-service`, so the Shell and standalone Weather app
share one Open-Meteo request policy and persisted cache. Consumers preserve
their previous complete conditions and show an unavailable/error state while
the core service reconnects.

`apps/settings/` is the first application. The gear exposed by the top bar or
Dock-hosted status area starts its process through `DesktopAppLauncher`; it
never loads Settings UI into the Quickshell process.

The optional applications are separate CMake modules under `apps/<name>/`.
They link portable `shared/` modules but never import `shell/desktop`. Calendar
and Todo share the contracts in `shared/pim`; Weather speaks the versioned
`kos-data.sock` protocol; Music exposes MPRIS for ordinary shell consumers.

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

## Testing layers

Tests use CTest `LABELS` to describe their runtime dependencies.
`tools/run-tests.sh` configures and builds the suite; CI uses `--build-only`
then runs each group independently so one failure does not suppress the rest.
Run desktop integration checks in a virtual machine.

| Label | What it covers | Needs | Runs in CI |
|---|---|---|---|
| `data` | service and application core tests | compiler, Go, optional application dependencies | registered tests; optional suites are not guaranteed |
| `platform` | daemon startup, isolated D-Bus integration and protocol contracts | node, python, private D-Bus sessions | yes |
| `logic` | shell computations, source contracts and translation catalogs | node, python, some offscreen QML | yes |
| `ui` | QML behavior and desktop flows | QML runtime; desktop flows need a compositor | only tests also labelled `headless` |
| `headless` | Settings, shared controls, lyrics and lockscreen regressions | offscreen Qt, KDE QML modules and private D-Bus sessions | yes |

```sh
# Run these in the test VM:
./tools/run-tests.sh                    # data (default)
./tools/run-tests.sh --layer platform
./tools/run-tests.sh --layer headless
./tools/run-tests.sh --all              # includes compositor-dependent flows
```

`.github/ci-tests.json` lists the tests that must register in the CI environment.
`tools/ci_tests.py inventory` compares that list with CTest discovery after the
build. Missing dependencies, disabled tests, missing executables and incorrect
labels fail the check. Newly registered tests with the selected labels also run
automatically; add mandatory tests to the manifest to guard their registration.

Each group writes its own JUnit XML and log. `tools/ci_tests.py report` compares
those results with the discovered inventory, reports passed/failed/skipped/missing
counts in the Actions summary, and fails for incomplete or skipped coverage.
Actions uploads the inventory, reports and build diagnostics even after a failure.
A green run covers these groups, not compositor integration, ListenFree or every
optional application suite.

The `kos-data-service.go` test needs `GOCACHE` pointed at a warm cache to stay
fast: compiling the Go standard library cold takes well over a minute, against
about a second warm. `services/data-service/CMakeLists.txt` passes an absolute
`GOCACHE`, so exporting one from a wrapper script has no effect — CI caches
`.build/tests/services/data-service/go-test-cache`, which is the directory the
ctest entry point actually uses.

KWin compatibility uses three complete SDK jobs (6.6, 6.7 and 6.8). Each builds and
links the root plugins and Glass, runs offline bridge regressions and checks official API headers.
Container GPU skips require VM coverage. Live compositor loading, rendering and platform-specific
installation checks remain separate VM acceptance; see [Releasing](Releasing.md).

## Change strategy

Directory moves, platform daemon, Shell client migration, data-service
migration, build/install tooling, and documentation are separate commits. Each
stage is buildable or has an explicit external prerequisite called out in its
commit validation. This keeps rollback and review boundaries clear during the
one-time cutover.

Changes to `data` or `platform` layer tests must keep those layers green, and
a pull request that touches them should say which layers were run.
