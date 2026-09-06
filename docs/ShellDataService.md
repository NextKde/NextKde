# KOS data service

`services/data-service` builds `kos-data-service`, a GUI-free Go process owned
by `kos-data.service` (systemd `--user`). It is the sole owner of durable
telemetry and activity history:

- CPU, memory, disk, frequency, temperature, and sensor sampling;
- boot uptime and foreground-application attribution;
- desktop-directory watching and atomic snapshots;
- Open-Meteo location search, forecast refresh, units, and offline weather cache;
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

Supported operations are:

- `metrics.snapshot`;
- `activity.snapshot` and `activity.active-app`;
- `desktop.snapshot` and `desktop.refresh`;
- `weather.snapshot`, `weather.search`, `weather.refresh`,
  `weather.set-location`, and `weather.set-units`.

Desktop changes are pushed as `desktop.changed` events after a complete
directory scan has been persisted. A completed weather state transition is
pushed as `weather.changed`; clients then request `weather.snapshot`, so every
response uses the same versioned envelope and request correlation.

Example weather requests:

```json
{"version":1,"requestId":"w1","operation":"weather.search","payload":{"query":"Changsha","language":"en","limit":8}}
{"version":1,"requestId":"w2","operation":"weather.set-units","payload":{"units":"metric"}}
```

The weather payload itself follows
[`shared/contracts/weather-v1.schema.json`](../shared/contracts/weather-v1.schema.json).
The service requests at most 48 hourly and seven daily points, refreshes after
one hour, and marks data stale after two hours. Failed refreshes preserve the
last complete forecast and expose the error alongside it.

## Build and run

From the repository root:

```sh
GOPROXY="${GOPROXY:-https://goproxy.cn,direct}" go build ./services/data-service
./tools/kosctl install
systemctl --user status kos-data.service
journalctl --user -u kos-data.service -f
```

`kosctl uninstall` stops and removes the service binary and unit but keeps the
state directory. `kosctl build` uses `https://goproxy.cn,direct` by default;
set `GOPROXY` to a reachable mirror or `off` for an offline module cache when
the default proxy is unavailable.
