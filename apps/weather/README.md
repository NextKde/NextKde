# KOS Weather

KOS Weather is a standalone Qt Quick forecast application. It and the
Quickshell weather widget consume the same versioned service snapshot; neither
surface owns network or cache state.

## Current status

The first milestone provides an independently buildable application and the
complete loading/empty-state layout. Network controls remain disabled until
the weather module is extracted from the existing monolithic data service.

## Build

```bash
cmake --preset weather-dev
cmake --build --preset weather-dev
```

The executable is written below `.build/weather-dev/apps/weather/`.

## Planned scope

- Localized location search and multiple saved locations.
- Current, hourly, and seven-day forecasts.
- Metric/imperial units and explicit refresh.
- Atomic offline cache with generated/stale timestamps.
- Shared state with the desktop widget through `shell-data-service`.

Radar, severe-weather push, and automatic geolocation are deferred.
