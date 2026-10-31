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

`kos-data-service` is the only network and persistence owner. The Qt client
uses the versioned `kos-data.sock` JSONL API for commands and change events,
with the atomic snapshot retained as an offline fallback. The Quickshell widget
consumes the same contract.

## Build

```bash
cmake --preset weather-dev
cmake --build --preset weather-dev
```

The application is written below `.build/weather-dev/apps/weather/`. The same
preset builds the Go data service, so a Go toolchain is required in addition
to Qt 6.

## Included scope

- Localized location search and multiple saved locations.
- Current conditions, all remaining hourly points, and up to seven daily forecasts; the heading reflects the actual day count.
- City removal, search loading/empty/retry states, and localized air quality categories with an explicit unavailable state.
- Metric/imperial units and explicit refresh.
- Atomic offline cache with generated/stale timestamps.
- Shared state with the desktop widget through `kos-data-service`.

Radar, severe-weather push, automatic geolocation, and provider-account sync
are outside version 1.

## Runtime service

CMake installs `kos-data-service` under the selected prefix's `libexec`. KOS
Weather reuses an already-running core service and can start the installed
binary on demand for a Weather-only development install. The complete app
installer enables `kos-data.service`. A previously cached forecast remains
visible if the service or network is temporarily unavailable.

## Compact interface

The interface follows the NextKde App Demo compact desktop specification: a 224 px sidebar, 28 px search/actions, 80 px city rows, and denser forecast cards. Light liquid material is limited to search and floating actions; weather scenes and charts retain their own visual treatment. Narrow windows show hourly and daily forecasts before secondary metrics. Reduced transparency uses solid controls.

Search suggestions and city context menus share the Demo `LiquidPanelSurface`
with Calendar dialogs: 0.95 material coverage, QML blur/refraction and a single
composition pass. Rows remain ordinary; reduced transparency uses an opaque
fallback. The application links the same portable `Kos.Demo` component module.
