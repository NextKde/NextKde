# Weather architecture

Shell weather is shared desktop state owned by core `kos-data-service`: it
queries Open-Meteo, chooses the Shell's active location and units, and persists
the last complete forecast. The independently maintained
[NextKde/kos-apps](https://github.com/NextKde/kos-apps) Weather application instead
owns a private `kos-weather-backend`, endpoint and state. It does not share the
core service's ownership or install/activate `kos-data.service`.

```text
Open-Meteo forecast/geocoding
            |
            v
services/data-service/weather.go
    | snapshot.json (offline fallback)
    | kos-data.sock JSONL requests and weather.changed events
    v
Quickshell WeatherService
```

## Service delivery and lifecycle

Core builds and deploys `kos-data-service` for the Shell. Application CMake
presets no longer exist in this repository. The independent Weather project
builds and installs `bin/kos-weather-backend` with its own application; its
installer does not enable, stop or restart a core service. Application build,
private backend lifecycle and runtime verification belong to that repository.
The contract below describes the retained core Shell weather endpoint.

## Contract

All socket messages use the version-1 envelope documented in
[`DataServiceArchitecture.md`](DataServiceArchitecture.md). Weather clients use these
operations:

- `weather.snapshot`: returns the current weather object;
- `weather.refresh`: requests an immediate refresh and reports whether work was accepted;
- `weather.search`: geocodes a 2–128 character query without persisting it;
- `weather.set-location`: selects and persists one normalized result;
- `weather.remove-location`: removes the saved city identified by payload `id` (idempotent);
  when removing the selected city, selects a remaining city or leaves an explicit empty state;
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

An intentionally empty saved list persists as `locations: []`, with an empty location
sentinel (`id`/`name` empty, coordinates zero), `status: "idle"`, no current forecast,
and empty hourly/daily arrays. It survives normalization/restart; automatic refresh
stops until a city is added. A legacy missing list still receives the initial default.
Deletion invalidates the selected city's in-flight forecast and removes its cache.

## Shell source selection and consumers

`WeatherService.qml` supplies one source to Dock, desktop widgets, wallpaper and
lock-screen publication. With no independent Weather app it uses core telemetry;
with one unambiguous current app it reads that app's versioned summary. Missing,
invalid, ambiguous and stale app data remain explicit instead of silently using
core data. See [widget integration](app-store/WidgetIntegration.md) for exact
identity, path, validation and launch rules.

Application windows, effects, city search UI and their tests live in
[NextKde/kos-apps](https://github.com/NextKde/kos-apps). They are not core-owned
controls or evidence of current core acceptance.

## Provider and cache policy

Open-Meteo is accessed through an internal provider interface so fixtures and
future providers do not affect consumers. Requests have a 20-second deadline,
a 2 MiB response limit, and a project User-Agent. Forecasts refresh after one
hour and become stale after two hours. At most 48 hourly points, seven daily
points, and twenty saved locations are persisted.

The previous hard-coded Changsha location is the version-1 migration default.
It initializes core Shell weather only; the independent application owns its
private location selection.
Failed refreshes preserve the previous complete forecast and surface the error.
The Shell also retains its last forecast through widget inspection failures,
repeated polls and transport reconnects, marking retained data as cached while
loading or in error. A confirmed source change invalidates that forecast. An
empty loading/error snapshot may retain data only for the same city and units;
an explicit empty selection still clears the display.
The shared widget adapter polls installation state and local summaries every
30 seconds. WeatherService also requests a core snapshot every five minutes as
a missed-event fallback; neither read directly fetches Open-Meteo. Identical hourly/daily arrays retain their model
identity so polling does not recreate forecast delegates.
