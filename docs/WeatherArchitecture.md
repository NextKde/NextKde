# Weather architecture

Weather is shared desktop state. `shell-data-service` is the only process that
talks to the provider, chooses the active location and units, and persists the
last complete forecast. KOS Weather and Quickshell are independent consumers.

```text
Open-Meteo forecast/geocoding
            |
            v
shell-data-service/weather.go
    | atomic snapshot.json
    | weather_changed socket marker
    +-------------------------+
    v                         v
KOS Weather              Quickshell WeatherService
```

## Contract

The `weather` member of the service snapshot follows
`shared/contracts/weather-v1.schema.json`. Timestamps are Unix milliseconds;
provider-local forecast times remain ISO strings without a fabricated UTC
conversion. Consumers determine stale data with `staleAt` and may continue to
display cached conditions when `error` is non-empty.

The local newline-delimited socket supports:

- `subscribe_weather`: immediately emits `weather_changed`, then emits it
  after each atomically persisted weather change.
- `weather_refresh`: requests an immediate refresh. Duplicate in-flight work
  is rejected through the response's `accepted` flag.
- `weather_search`: geocodes a 2–128 character query and returns normalized
  locations without persisting them.
- `weather_set_location`: selects and persists one normalized result.
- `weather_set_units`: selects `metric` or `imperial` and refreshes all values.

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
After the first user selection, both the App and Shell consume that selection.
