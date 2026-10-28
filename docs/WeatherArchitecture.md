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

## Ambient weather animation

Thunderstorm scheduling depends on the active weather, visible application window
and reduced-motion preference, independently of the flash Canvas visibility.
The Canvas is drawn only during a strike. Leaving a thunderstorm, hiding the
window or enabling reduced motion stops the sequence and clears its flash alpha.
This prevents both the initial scheduling deadlock and a residual flash.

Lightning uses a thin, recursively fractured channel with tapered branches and
brief, irregular double pulses. Every fourth strike illuminates only the cloud
interior. Brief peak holds keep the pulses legible; channels occupy the exposed
sky beside the city heading. The light sits between the middle and front clouds
inside the captured sky, so existing rain droplets refract it along with the sky
instead of receiving a flat white overlay.

Snow uses `SnowGlass.qml` and the `snow_glass` shaders. Three drifting depth planes
vary flake size, speed and focus. Sparse, stable wet clumps on the glass soften
and melt into small refracting lenses. The existing foreground mask protects
cards and sidebar content. Clouds remain present as structure behind the glass.
This is an in-window Qt Quick effect and does not require a KWin plugin.
The shared rain/snow foreground mask follows sidebar width animation and forecast
layout changes after layout settles. Collapsing the sidebar releases its old
masked area and updates the relocated cards; the divider and sidebar backdrop
capture also stop when closed. Reopening restores their current bounds.
The animation clock pauses for hidden windows and reduced motion; software
rendering falls back to the sky without the snow optical pass.

## Glass temperature display

The hero uses the shared `LiquidGlassNumber` component from nextkdeAppDemo at
108px with heavy strokes to expose the glass interior. A dedicated sibling `LiquidBackdrop` samples only `weatherAtmosphere`:
sky, cloud/lightning layers and the rain/snow glass passes. Foreground labels,
cards and the glass number itself are excluded, preventing capture feedback.
The hero has a 72px top inset, with room for the larger digits before the cards.
Upward scrolling progressively scales the hero to 68% and fades it to zero;
scrolling back restores it. Its layout height stays fixed to avoid changing the
scroll range mid-gesture. Reduced motion uses ordinary scrolling without scale
or fade. The number's backdrop capture stops while the hero is fully faded.
Vertical wheel/touchpad input over the hourly forecast routes to the main page,
using its shared kinetic scrolling. Horizontal gestures and Shift+wheel keep
controlling hourly columns. Vertical input at a page boundary never changes axes.
Reduced transparency or unavailable GPU sampling uses ordinary white glyphs.
The component and matching GLSL/QSB files are kept identical to the Demo source;
weather-specific thickness, refraction and readability values live in Main.qml.
All effects remain in the QQuickWindow, with no KWin liquid plugin.

## Initial window size

Weather opens at 1000 × 618 logical pixels (width/height ≈ 1.618), with normal
free resizing afterwards. This is the project's compact golden-ratio choice,
not a measured macOS 15 Weather default. Other applications keep their sizes.

## City search and removal UI

The search dropdown and city context menu are floating liquid panels, using
`LiquidCompactSurface` over a dedicated `LiquidBackdrop` of the actual page.
A QML `MultiEffect` blurs that page before refraction so underlying text does not
compete with the popup labels.
The page subtree excludes the popup overlay and capture, preventing feedback.
Capture runs only while either popup is visible. Both popups stay in the same
QQuickWindow (`Popup.Item`); no compositor or KWin liquid effect is requested.
Candidate rows and menu items use ordinary hover fills, without nested glass or
an added blue focus border. Reduced transparency or unavailable sampling uses
an opaque dark fallback. Popup tint coverage is 0.7; foreground text stays fully
opaque. The continuous sidebar remains its ordinary 0.8 panel.

Search appears in an anchored dropdown without moving the saved-city list. Queries
under two characters show an input hint; a 450ms debounce/loading state precedes
candidates with region/country and an already-added marker. Empty, failed and timed-out
searches have separate messages, with retry on failure. Arrow keys choose candidates,
Enter accepts and Escape dismisses. Editing/clearing/dismissing invalidates older replies;
search errors never overwrite the displayed forecast's status. Search times out at 15s.

Each saved city has an options button and a right-click/long-press menu with Remove city;
Delete also removes a focused city. The list changes after service acknowledgement,
and failures are shown separately. Deleting the final city exposes an Add a city action.

Weather exposes refresh and temperature units directly in its sidebar. It has no
separate settings button, dialog, Preferences shortcut or desktop Settings action.
Shared application preferences still supply appearance/accessibility defaults.

## Forecast presentation

The daily heading uses the actual number of available days (currently at most
seven), with a generic heading when no daily data is available. The hourly list
shows every remaining point in the service snapshot instead of stopping at ten.
Selection compares provider-local hour buckets, so an observation at 14:15 keeps
the 14:00 point labelled Now; forecasts after midnight remain in the list.

Locations are manually selected: the hero says Selected City and sidebar entries
show their observation time or region. Neither is labelled My Location, since
version 1 does not implement automatic geolocation.

Air quality uses the contract's US AQI bands. Category labels are translated in
the client, including all six severity bands. Missing, null, non-finite or negative
AQI readings display an explicit unavailable message and hide the value, category
and gauge; zero remains a valid reading in the Good band.

## Provider and cache policy

Open-Meteo is accessed through an internal provider interface so fixtures and
future providers do not affect consumers. Requests have a 20-second deadline,
a 2 MiB response limit, and a project User-Agent. Forecasts refresh after one
hour and become stale after two hours. At most 48 hourly points, seven daily
points, and twenty saved locations are persisted.

The previous hard-coded Changsha location is the version-1 migration default.
After the first user selection, both the app and Shell consume that selection.
Failed refreshes preserve the previous complete forecast and surface the error.
