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
- Export audio through the GStreamer encoders installed on the system. FLAC,
  Vorbis, Opus, WAV, and MP3 appear only when their required elements exist.
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
is playable or exportable only when the matching GStreamer decoder/encoder is
installed. The conversion dialog reports the encoders detected at runtime.

## Data and integration

The database defaults to `$XDG_DATA_HOME/kos/music/library.sqlite` (normally
`~/.local/share/kos/music/library.sqlite`), with imported sources in `sources/`.
Artwork and lyrics are cached below `$XDG_CACHE_HOME/kos/music/{artwork,lyrics}`. Tests may override these paths with
`KOS_MUSIC_DATA_DIR` and `KOS_MUSIC_CACHE_DIR`.

MPRIS `OpenUri` accepts only local `file:` URIs. MPRIS registration requires
the desktop session D-Bus. A service-name collision does not stop the player;
it only disables external MPRIS control for that instance.

## Current boundary

Included are local folders/files, incremental metadata scans, embedded cover
art, albums/artists, playlists, a durable queue and settings, common playback
controls, MPRIS, and explicit audio conversion with atomic output replacement.
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
