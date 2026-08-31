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
the shell to `~/.config/quickshell/kos`, and enables the two systemd user units.
The data service keeps its existing state root under
`$XDG_STATE_HOME/quickshell/shell-data-service` so an architecture migration
does not erase preferences or history. `kosctl uninstall` removes binaries,
units, and shell files but leaves that state directory intact.

## Change strategy

Directory moves, platform daemon, Shell client migration, data-service
migration, build/install tooling, and documentation are separate commits. Each
stage is buildable or has an explicit external prerequisite called out in its
commit validation. This keeps rollback and review boundaries clear during the
one-time cutover.
