# KOS Weather

**[English](README.md) | [中文](README.zh-CN.md)**

KOS Weather is a standalone Qt Quick forecast application. It and the
Quickshell weather widget consume the same versioned service snapshot; neither
surface owns network or cache state.

## Current status

The application is connected to the version-1 shared weather service. It can
search and save locations, switch metric/imperial units, refresh on demand,
and show current, hourly, and seven-day forecasts. The last complete forecast
remains visible offline and is explicitly marked when stale.

`shell-data-service` is the only network and persistence owner. The Qt client
reads its atomic snapshot and uses a local Unix socket for commands and change
notifications; the Quickshell widget consumes the same contract.

## Build

```bash
cmake --preset weather-dev
cmake --build --preset weather-dev
```

The executable is written below `.build/weather-dev/apps/weather/`.

## Included scope

- Localized location search and multiple saved locations.
- Current, hourly, and seven-day forecasts.
- Metric/imperial units and explicit refresh.
- Atomic offline cache with generated/stale timestamps.
- Shared state with the desktop widget through `shell-data-service`.

Radar, severe-weather push, automatic geolocation, and provider-account sync
are outside version 1.

## Runtime dependency

Start `shell-data-service.service` in the user session. Without it, KOS
Weather still opens and displays a previously cached forecast, but search,
refresh, location changes, and unit changes are unavailable.
