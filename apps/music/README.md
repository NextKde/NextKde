# KOS Music

**[English](README.md) | [中文](README.zh-CN.md)**

KOS Music is a standalone Qt Quick player for local music libraries. It owns
decoding and playback and publishes MPRIS; the Quickshell Dock, Control Center,
and DeskCenter remain independent MPRIS clients.

## Current status

The version-1 local player is functional:

- Add and remove library folders, scan them asynchronously, search tracks, and
  browse recently added music, songs, albums, and artists.
- Read common metadata and embedded artwork with TagLib and persist a migrated
  SQLite library without modifying source files.
- Play through GStreamer `playbin3`, with pause, seek, volume, persistent queue,
  play-next, shuffle, and track/queue repeat.
- Create, rename, remove, and play playlists.
- Export audio through the GStreamer encoders installed on the system. FLAC,
  Vorbis, Opus, WAV, and MP3 appear only when their required elements exist.
- Expose `org.mpris.MediaPlayer2.kosmusic` for media keys and desktop clients,
  including metadata, position, seek, volume, shuffle, repeat, `OpenUri`, and
  `Raise`.

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
- Runtime GStreamer plugin packages for the formats and audio output required
  by the system. KOS Music does not bundle codec binaries.

The scanner recognizes a broad set of TagLib-supported extensions, but a file
is playable or exportable only when the matching GStreamer decoder/encoder is
installed. The conversion dialog reports the encoders detected at runtime.

## Data and integration

The database defaults to `$XDG_DATA_HOME/kos/music/library.sqlite` (normally
`~/.local/share/kos/music/library.sqlite`). Extracted artwork is cached below
`$XDG_CACHE_HOME/kos/music/artwork`. Tests may override these paths with
`KOS_MUSIC_DATA_DIR` and `KOS_MUSIC_CACHE_DIR`.

Only local `file:` URIs are accepted in version 1. MPRIS registration requires
the desktop session D-Bus. A service-name collision does not stop the player;
it only disables external MPRIS control for that instance.

## Version-1 boundary

Included are local folders/files, incremental metadata scans, embedded cover
art, albums/artists, playlists, a durable queue and settings, common playback
controls, MPRIS, and explicit audio conversion with atomic output replacement.

Deferred are streaming/DRM accounts, podcasts, CD ripping, tag editing,
metadata copying into converted exports, ReplayGain, gapless preloading,
crossfade, an equalizer, waveform editing, cloud sync, and remote libraries.
These features should be added behind the existing engine/library boundaries,
not by coupling the application to the desktop shell.

See [Music architecture](../../docs/MusicArchitecture.md) for the component
model, database and threading rules, open-source research, licensing boundary,
MPRIS behavior, and verification matrix.
