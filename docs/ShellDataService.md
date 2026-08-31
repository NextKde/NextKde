# KOS data service

`services/data-service` builds `kos-data-service`, a GUI-free Go process owned
by `kos-data.service` (systemd `--user`). It is the sole owner of durable
telemetry and activity history:

- CPU, memory, disk, frequency, temperature, and sensor sampling;
- boot uptime and foreground-application attribution;
- desktop-directory watching and atomic snapshots;
- the `kos-data.sock` JSONL API.

The service deliberately does not own a Wayland clipboard. Clipboard MIME
ownership requires a Qt GUI event loop and is held directly by the resident
`kos-platform` process.

## State and sockets

State remains at:

```text
$XDG_STATE_HOME/quickshell/shell-data-service/state.json
$XDG_STATE_HOME/quickshell/shell-data-service/snapshot.json
```

The runtime API is:

```text
$XDG_RUNTIME_DIR/kos-data.sock
```

The socket is mode `0600`. Requests are versioned JSON Lines:

```json
{"version":1,"requestId":"42","operation":"metrics.snapshot","payload":{}}
{"version":1,"requestId":"42","ok":true,"result":{"metrics":{}}}
```

Supported operations are `metrics.snapshot`, `activity.snapshot`,
`activity.active-app`, `desktop.snapshot`, and `desktop.refresh`. Desktop
changes are pushed as `desktop.changed` events after the complete directory
scan has been atomically persisted.

## Build and run

From the repository root:

```sh
go build ./services/data-service
./tools/kosctl install
systemctl --user status kos-data.service
journalctl --user -u kos-data.service -f
```

`kosctl uninstall` stops and removes the service binary and unit but keeps the
state directory. If a Go module proxy is unavailable, set `GOPROXY` to a
reachable mirror and retry the build.
