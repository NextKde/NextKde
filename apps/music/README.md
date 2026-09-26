# KOS Music

**[English](README.md) | [中文](README.zh-CN.md)**

KOS Music is a standalone Qt Quick player for local libraries and opt-in LX
custom sources. It owns
decoding and playback and publishes MPRIS; the Quickshell Dock, Control Center,
and DeskCenter remain independent MPRIS clients.

## Current status

The native player is functional:

- Add and remove library folders, scan them asynchronously, search tracks, and
  browse recently added music, songs, albums, and artists.
- Read common metadata and embedded artwork with TagLib and persist a migrated
  SQLite library without modifying source files.
- Play through GStreamer `playbin3`, with pause, seek, volume, persistent queue,
  play-next, shuffle, and track/queue repeat.
- Create, rename, remove, and play playlists.
- Use context-specific menus: trash library files, reorder/remove queue entries,
  insert/append online results, and remove playlist membership. Conversion and
  add-to-playlist entries are removed from the UI.
- Expose `org.mpris.MediaPlayer2.kosmusic` for media keys and desktop clients,
  including metadata, position, seek, volume, shuffle, repeat, `OpenUri`, and
  `Raise`.
- Search NetEase metadata and resolve temporary playback URLs on demand through
  a user-selected LX Music `user_api` script imported from a file or HTTPS URL.
- Keep a persistent Mini Player and a cache-managed Now Playing view with local
  artwork ambience, sidecar/online LRC caching, and synchronized lyric lines.

## Build and install

From the repository root:

```bash
cmake --preset music-dev
cmake --build --preset music-dev
ctest --test-dir .build/music-dev -R kos-music --output-on-failure
cmake --install .build/music-dev --prefix "$HOME/.local"
```

The uninstalled executable is below `.build/music-dev/apps/music/`. The install
step also adds `kos-music.desktop`; update the desktop database or sign out and
back in if the launcher is not visible immediately.

## Dependencies

- Qt 6 Core, Gui, QML/Quick, Quick Controls, Quick Dialogs, Concurrent, D-Bus,
  and SQL with the SQLite driver.
- GStreamer 1.x development files for `gstreamer-1.0`, `gstreamer-audio-1.0`,
  and `gstreamer-pbutils-1.0`.
- TagLib 1.12 or newer.
- Node.js for modern LX sources, which commonly use async/await in the separate
  source-host helper process.
- Runtime GStreamer plugin packages for the formats and audio output required
  by the system. KOS Music does not bundle codec binaries.

The scanner recognizes a broad set of TagLib-supported extensions, but a file
is playable only when the matching GStreamer decoder is installed. The conversion
backend remains independently tested but has no entry point in the music UI.

## Data and integration

The database defaults to `$XDG_DATA_HOME/kos/music/library.sqlite` (normally
`~/.local/share/kos/music/library.sqlite`), with imported sources in `sources/`.
Artwork, lyrics and online audio are cached below `$XDG_CACHE_HOME/kos/music/{artwork,lyrics,audio}`. Tests may override these paths with
`KOS_MUSIC_DATA_DIR` and `KOS_MUSIC_CACHE_DIR`.

Online tracks play while downloading through one GStreamer transfer, with preparation,
buffering and cache progress, cancellation and retry controls. Complete downloads are
published after the stream closes and its final writes are flushed. Stable track/quality
keys avoid resolving expiring URLs again. Persistent audio uses a 1 GiB LRU budget and
256 MiB per-entry limit; an unwritable cache does not prevent streaming. Partial or
failed responses are never published. Pause/resume preserves position; progress is
saved every five seconds, on pause/seek and exit, and restored without autoplay.

Failures try the imported sources in preference order without changing the saved
preferred source. Each attempt has a 12-second deadline and track preparation has a
45-second budget. Exhausted tracks show a three-second skip notice and advance in
queue order (or shuffle), ignoring repeat-current for failed songs. An all-failed queue
stops rather than looping. Pause/stop, manual selection and queue removal cancel recovery.
The source page exposes recent attempt diagnostics.

Lyrics animate between lines and have a persistent app toggle; the Dock popup also
has a desktop-lyrics toggle. Horizontal and side Dock players remain available while
paused or buffering. Desktop, Dock and Control Center share vector transport buttons
with fixed hit targets.

Library deletion confirms the file, moves local audio to the system trash, and removes
queue and playlist references. A failed trash operation preserves the library record;
an already missing file allows stale-record cleanup. Deleting a playing track advances
to its successor; deleting while paused never starts playback. In-flight scans cannot
restore deleted entries. Menus, menu items, dialogs, quality choices, sidebar and
artwork use rounded surfaces.

MPRIS `OpenUri` accepts only local `file:` URIs. MPRIS registration requires
the desktop session D-Bus. A service-name collision does not stop the player;
it only disables external MPRIS control for that instance.

## Current boundary

Included are local folders/files, incremental metadata scans, embedded cover
art, albums/artists, playlists, a durable queue and settings, common playback
controls, MPRIS, and confirmed deletion of local audio to the system trash.
Online support currently means platform metadata search plus on-demand LX
custom-source resolution; it does not include remote music libraries.

Custom sources are third-party code. The helper adds crash and timeout
containment but is not a security sandbox, so import only scripts you trust.
Source availability can change and does not confer copyright or redistribution
rights.

Deferred are remote libraries, streaming/DRM accounts, podcasts, CD ripping, tag editing,
metadata copying into converted exports, ReplayGain, gapless preloading,
crossfade, an equalizer, waveform editing, cloud sync, and remote libraries.
These features should be added behind the existing engine/library boundaries,
not by coupling the application to the desktop shell.

See [Music architecture](../../docs/MusicArchitecture.md) for the component
model, database and threading rules, open-source research, licensing boundary,
MPRIS behavior, and verification matrix.
