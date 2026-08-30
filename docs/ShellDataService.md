# Shell Data Service

`shell-data-service` is the user-session data layer for this configuration.
QML is presentation and interaction only; it must not own durable telemetry,
high-frequency sampling, or cross-surface history.

## Ownership

Put a data source in the service when it is shared by two or more surfaces,
must survive a Quickshell reload, needs historical aggregation, or is driven
by system/KWin/logind events. Examples: CPU/temperature histories, activity
duration, boot/awake history, battery health, and network-quality history.

Keep it in QML when it is purely visual or local interaction state: animation,
popup visibility, card layout, hover state, and formatting.

## Interfaces

The service writes an atomic snapshot at:

`$XDG_STATE_HOME/quickshell/shell-data-service/snapshot.json`

It accepts newline-delimited JSON events on:

`$XDG_RUNTIME_DIR/shell-data-service.sock`

`{"type":"active_app","appID":"firefox.desktop","name":"Firefox"}`
starts attribution; `{"type":"active_app","appID":""}` pauses it, and
`{"type":"session","active":false}` pauses attribution too.
`{"type":"refresh_desktop"}` requests an immediate desktop-directory scan
after a shell-originated rename, deletion, paste, or folder creation.

The desktop reader opens one persistent connection and writes
`{"type":"subscribe_desktop"}`. The service immediately responds with a
`desktop_changed` marker, then sends the same marker after every changed full
snapshot. One-shot clipboard requests use:

```json
{"type":"clipboard_set","mode":"cut","paths":["/home/user/Desktop/a.txt"]}
{"type":"clipboard_read"}
```

Clipboard replies are JSON lines containing `ok`, `mode`, `paths`, and an
optional `error`.

Weather clients keep a separate persistent connection and write
`{"type":"subscribe_weather"}`. The service immediately sends a
`weather_changed` marker and repeats it only after a complete weather snapshot
has been atomically written. Control requests are newline-delimited JSON:

```json
{"type":"weather_refresh"}
{"type":"weather_search","query":"Changsha","language":"en","limit":8}
{"type":"weather_set_location","location":{"id":"open-meteo:1815577","name":"Changsha","latitude":28.19874,"longitude":112.97087,"timezone":"Asia/Shanghai"}}
{"type":"weather_set_units","units":"metric"}
```

The versioned weather object is documented in `WeatherArchitecture.md` and
validated by `shared/contracts/weather-v1.schema.json`.

## Metrics

The service samples CPU (delta of `/proc/stat`), memory (`/proc/meminfo`),
root-disk usage (`df`), CPU frequency (`cpufreq` policies with a
`/proc/cpuinfo` fallback), and temperatures every ten seconds. The current CPU
temperature prefers the direct `coretemp`/`k10temp` package sensor, then falls
back to CPU package thermal zones; it is not an average of duplicate ACPI and
per-core readings. `maximum5MinuteMilliC` is the rolling maximum of those
package samples over the latest five minutes. A full `hwmon`/`thermal` sensor
listing remains available for the detail view, and history keeps the latest
360 samples. QML consumes the `metrics` section through the
`MetricsService` singleton in `qs.desktop.modules.common`; it never polls `/proc`.

## Activity

Boot uptime is seeded once from `journalctl --list-boots` (streamed per boot
so a years-long journal costs one line per boot, not a full copy), and the
running session's online/app time is settled every second and persisted every
ten seconds. The QML `ActivityUsageService` singleton reports the foreground
window via `active_app` events and reads the `activity` section for the
desk cards.

Desktop changes are watched by the Go service through `fsnotify` (Linux:
`inotify`) and debounced for 100ms. Filesystem events are wake-up signals only:
after a burst, the service rescans the complete directory, compares it with the
last state, atomically writes the changed snapshot, and only then sends
`desktop_changed`. A five-second low-frequency reconciliation repairs an
overflowed or missed inotify event. QML never constructs state from individual
create/remove events.

The initial complete desktop snapshot is written before the socket begins
accepting clients. Every new desktop subscription also receives an immediate
marker. If another marker arrives while QML is reading `snapshot.json`, QML
queues one more read rather than dropping it. These guarantees prevent the
startup-empty and “one file behind” failure modes.
KWin and logind adapters belong beside the service, not in individual widgets.

## Weather

The Go service is the only Open-Meteo client. It owns location search, selected
location, metric/imperial units, refresh deadlines, failure state, and the
offline forecast. Quickshell no longer invokes `curl` or maintains a second
cache. The service requests at most 48 hourly and seven daily points, refreshes
after one hour, and marks data stale after two hours. Failed refreshes preserve
the last complete conditions and publish an explicit error.

## Desktop files

The service also publishes `desktop` in the snapshot: the current XDG Desktop
directory and its visible entries. It resolves the directory with
`xdg-user-dir DESKTOP`, keeps folders first, then orders files by modification
time. The watcher only writes a new snapshot if the directory contents
changed. QML consumes this list for the desktop file
grid; it must not scan directories itself. `.desktop` launchers additionally
publish their display name and icon, while activation is delegated to
`gio launch` rather than manually interpreting their command line.

## File clipboard

The Go process remains the only service managed by systemd. It starts and
supervises `quickshell-file-clipboard-helper` when the desktop copies or cuts
files. This helper is a small windowless Qt program because Wayland requires
the clipboard owner to remain alive and Qt exposes the required multi-format
`QMimeData` API.

The helper publishes all of the following together:

- `text/uri-list`
- `application/x-kde-cutselection` (`1` for cut, `0` for copy)
- `x-special/gnome-copied-files`

This lets Dolphin and compatible file managers distinguish copy from cut. On
paste, the helper reads the current clipboard formats; QML never trusts stale
in-process cut state after another application has replaced the clipboard.
The helper is not a second systemd service and must be installed beside
`shell-data-service` so the Go process can locate and supervise it.

## Installation

Dependencies are Go, CMake, a C++ compiler, Qt 6 Gui development files,
`socat`, and systemd user services. On Arch-based systems the build packages
are typically `go cmake gcc qt6-base`; on Debian/Ubuntu they are typically
`golang cmake g++ qt6-base-dev`.

From the repository root:

```sh
./tools/install-shell-data-service.sh
```

The installer builds both binaries, installs them to
`~/.local/lib/quickshell`, installs the user unit, and restarts the Go service.
Only `shell-data-service.service` is enabled.

Useful checks:

```sh
systemctl --user status shell-data-service.service
journalctl --user -u shell-data-service.service -f
```

## GitHub release checklist

- Keep both helper sources in the repository; do not commit `build/`, CMake
  caches, or newly built executables.
- Treat the Go service and Qt helper as one release unit. Prebuilt archives
  must contain both binaries in the same directory.
- Source installation is the portable default. Linux binaries should be built
  per supported distribution/runtime because glibc and dynamically linked Qt
  versions are not universally compatible.
- Document the required Qt 6 runtime even for prebuilt releases. Plasma 6
  normally already provides it, but this must not be assumed for other
  compositors.
- Test on a real Wayland session: desktop-to-Dolphin copy and cut,
  Dolphin-to-desktop copy and cut, filenames containing spaces/non-ASCII text,
  service restart, Quickshell-first startup, and service-first startup.
- Package managers may install to a system libexec directory, but must either
  keep the two binaries together or set
  `QUICKSHELL_FILE_CLIPBOARD_HELPER` in the service environment.
- If the Qt helper is unavailable, cut must report an explicit error; silently
  downgrading a move to a copy is not an acceptable fallback.
