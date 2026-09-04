# Functional architecture

KOS is a presentation shell over KDE services. Visual modules stay in the
Quickshell process; lifecycle-sensitive integration is centralized in two
resident services.

```text
                    ┌──────────────────────────────┐
                    │ qs -c kos                    │
                    │ Bar · Dock · DeskCenter · UI  │
                    └──────────────┬───────────────┘
                                   │ JSONL Unix sockets
                 ┌─────────────────┴─────────────────┐
                 │                                   │
       kos-platform.sock                    kos-data.sock
       C++/Qt platform daemon                Go data daemon
                 │                                   │
  KWin/D-Bus, clipboard, files,       metrics, activity, desktop snapshot
  network, audio, Bluetooth, etc.
```

## Layer responsibilities

| Layer | Location | Owns |
| --- | --- | --- |
| Shell presentation | `shell/desktop/` | windows, panels, models, animations, QML state |
| Platform adapters | `platform/` | live desktop integration and allow-listed system operations |
| Durable data | `services/data-service/` | sampling, history, activity ledger, desktop watcher |
| Independent apps | `apps/` | settings and future utilities; Shell IPC only |
| KWin integrations | `integrations/kwin/` | the two plugin `.so` targets required by KWin |

The former collection of helper projects is intentionally not a runtime layer.
One-shot operations are platform modules or `tools/` commands; only a process
with a distinct lifecycle remains a service.

## Shell features

- Bar and control centre consume `NetworkService` and
  `ControlCenterService`; neither invokes system commands.
- Dock and workspace overview consume `WindowService`, which subscribes to
  KWin events and sends window commands through `PlatformClient`.
- DeskCenter consumes `DesktopFilesService` and `DataClient` for atomic desktop
  snapshots; file and clipboard mutations go through `kos-platform`.
- Metrics and activity cards consume `MetricsService` and
  `ActivityUsageService`, backed by `kos-data-service`.
- Settings remains a separate Qt Quick process and uses the narrow Shell IPC
  handlers (`dock-settings`, `appearance-settings`, `applauncher-settings`,
  `shortcuts-settings`, and the read-only `integration-status`).

## Startup and recovery

Systemd user units may start in any order. QML clients queue socket requests,
reconnect after a daemon restart, and re-subscribe to KWin/window or desktop
events. If an optional host adapter is unavailable, only that feature reports a
stable error; the shell process and other features remain usable.

## Contracts and tests

The versioned JSONL envelope and error model are defined in
[`shared/contracts/platform.v1.md`](../shared/contracts/platform.v1.md). The
default shortcut table is `shared/contracts/shortcuts.v1.json`. Contract tests
run with `python3 platform/tests/test_contract.py`; C++ builds use
`cmake --preset debug && cmake --build --preset debug`.
