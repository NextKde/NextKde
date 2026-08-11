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

## Metrics

The service samples CPU (delta of `/proc/stat`), memory (`/proc/meminfo`),
root-disk usage (`df`), CPU frequency (`cpufreq` policies with a
`/proc/cpuinfo` fallback), and temperatures (CPU/PKG thermal zones, plus a
full `hwmon`/`thermal` sensor listing) every ten seconds. History keeps the
latest 360 samples. QML consumes the `metrics` section through the
`MetricsService` singleton in `qs.modules.common`; it never polls `/proc`.

## Activity

Boot uptime is seeded once from `journalctl --list-boots` (streamed per boot
so a years-long journal costs one line per boot, not a full copy), and the
running session's online/app time is settled every second and persisted every
ten seconds. The QML `ActivityUsageService` singleton reports the foreground
window via `active_app` events and reads the `activity` section for the
desk cards.

Desktop changes are watched by the Go service through `fsnotify` (Linux:
`inotify`) and debounced for 120ms; neither the service nor QML polls the
Desktop directory. After writing a changed snapshot, the service sends
`desktop_changed` to connected local socket clients, so the desktop grid
reloads the atomic snapshot immediately. The QML desktop reader keeps one
connection open; one-shot event senders simply close after writing.
KWin and logind adapters belong beside the service, not in individual widgets.

## Desktop files

The service also publishes `desktop` in the snapshot: the current XDG Desktop
directory and its visible entries. It resolves the directory with
`xdg-user-dir DESKTOP`, keeps folders first, then orders files by modification
time. The watcher only writes a new snapshot if the directory contents
changed. QML consumes this list for the desktop file
grid; it must not scan directories itself. `.desktop` launchers additionally
publish their display name and icon, while activation is delegated to
`gio launch` rather than manually interpreting their command line.

## Installation

```sh
cd tools/shell-data-service
go build -o ~/.local/lib/quickshell/shell-data-service .
mkdir -p ~/.config/systemd/user
cp systemd/shell-data-service.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now shell-data-service.service
```
