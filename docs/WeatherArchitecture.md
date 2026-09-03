# Weather architecture

Weather is shared desktop state. `kos-data-service` is the only process that
talks to Open-Meteo, chooses the active location and units, and persists the
last complete forecast. KOS Weather and Quickshell are independent consumers.

```text
Open-Meteo forecast/geocoding
            |
            v
services/data-service/weather.go
    | snapshot.json (offline fallback)
    | kos-data.sock JSONL requests and weather.changed events
    +-------------------------+
    v                         v
KOS Weather              Quickshell WeatherService
```

## Service delivery and lifecycle

The Weather CMake preset includes the core Go data service and installs
`kos-data-service` under `libexec`. The Qt client first connects to
`$XDG_RUNTIME_DIR/kos-data.sock`; after a failed connection it can start an
executable selected from the `KOS_DATA_SERVICE` override, the application
prefix's `libexec`, the current build output, or `PATH`. A non-blocking lock at
`kos-data.sock.lock` prevents concurrent application and systemd launches from
creating competing state owners.

The complete application installer enables `kos-data.service`. A development
Weather-only build can still launch the build-tree service on demand.

## Contract

All socket messages use the version-1 envelope documented in
[`ShellDataService.md`](ShellDataService.md). Weather clients use these
operations:

- `weather.snapshot`: returns the current weather object;
- `weather.refresh`: requests an immediate refresh and reports whether work was accepted;
- `weather.search`: geocodes a 2–128 character query without persisting it;
- `weather.set-location`: selects and persists one normalized result;
- `weather.set-units`: selects `metric` or `imperial` and refreshes all values.

After a persisted state transition, the service sends `weather.changed` to
connected clients. Each client then requests a correlated snapshot. The
weather object follows
[`shared/contracts/weather-v1.schema.json`](../shared/contracts/weather-v1.schema.json).
Timestamps are Unix milliseconds; provider-local forecast times remain ISO
strings without a fabricated UTC conversion.

Location and unit changes invalidate data from the previous configuration.
Each asynchronous provider request carries a process-local serial so a slow
old response cannot overwrite a newer selection.

## Provider and cache policy

Open-Meteo is accessed through an internal provider interface so fixtures and
future providers do not affect consumers. Requests have a 20-second deadline,
a 2 MiB response limit, and a project User-Agent. Forecasts refresh after one
hour and become stale after two hours. At most 48 hourly points, seven daily
points, and twenty saved locations are persisted.

The previous hard-coded Changsha location is the version-1 migration default.
After the first user selection, both the app and Shell consume that selection.
Failed refreshes preserve the previous complete forecast and surface the error.
