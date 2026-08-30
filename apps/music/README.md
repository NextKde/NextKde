# KOS Music

KOS Music is a standalone Qt Quick local-library player. It owns playback and
publishes a standards-compliant MPRIS service; the existing Quickshell Dock,
Control Center, and DeskCenter remain ordinary MPRIS clients.

## Current status

The first milestone provides an independently buildable application and the
library/player layout. Playback controls remain disabled until the native
GStreamer engine and persistent library are connected.

## Build

```bash
cmake --preset music-dev
cmake --build --preset music-dev
```

The executable is written below `.build/music-dev/apps/music/`.

## Architecture

- A C++ GStreamer `playbin3` engine behind a testable engine interface.
- TagLib workers for metadata and embedded artwork.
- A migrated SQLite library for roots, tracks, albums, artists, playlists,
  queue state, and playback history.
- A Qt D-Bus MPRIS provider named `org.mpris.MediaPlayer2.kosmusic`.
- GStreamer `encodebin` jobs for explicit format conversion and export.

## Planned scope

Local folders, asynchronous scanning, search, albums/artists, playlists,
persistent queue, shuffle/repeat, seek, volume, gapless playback, ReplayGain,
cover art, metadata errors, and common system-provided codecs are in scope.

DRM services, online accounts, podcasts, CD ripping, and an audio editor are
deferred. Codec binaries are never bundled by this application.
