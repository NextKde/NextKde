# Music architecture

KOS Music is an independent Qt Quick process. It owns the local library,
playback engine, conversion jobs, and MPRIS provider. Quickshell and the other
standalone applications do not import its implementation.

```text
Qt Quick views
     |
MusicController ---------------- MprisService
     |                         session D-Bus
     +-- TrackListModel              |
     +-- MusicDatabase/SQLite        +--> Dock / media keys / other clients
     +-- MetadataScanner/TagLib
     +-- PlaybackEngine/GStreamer playbin3 --> system audio output
     +-- Transcoder/GStreamer -------------> user-selected local file
```

## Design research and code provenance

The implementation was informed by mature upstream projects and the standard,
using their architectural lessons rather than copying their source:

- [KDE Elisa](https://github.com/KDE/elisa) separates collection discovery,
  database/model concerns, playback, and MPRIS. KOS follows the same broad
  separation while keeping a smaller local-only controller.
- [Strawberry Music Player](https://github.com/strawberrymusicplayer/strawberry)
  demonstrates the long-lived Qt combination of GStreamer, TagLib, SQLite,
  playlists, MPRIS, and runtime codec/plugin discovery. KOS delegates media
  formats to those mature system libraries instead of implementing codecs.
- [GNOME Amberol](https://apps.gnome.org/Amberol/) validates a focused local
  queue, direct playback controls, artwork-led presentation, and MPRIS without
  requiring an online-service architecture.
- The D-Bus surface follows the
  [MPRIS 2.2 specification](https://specifications.freedesktop.org/mpris/latest/).

No source code from these applications is vendored or copied. KOS Music's C++,
QML, schema, and tests are original repository code. GStreamer, TagLib, Qt, and
SQLite are consumed as system dependencies under their own licenses. Codec
plugins remain distribution-provided and are never redistributed by KOS.

## Component ownership

### MusicController

The QML-facing controller coordinates state but does not decode files itself.
It restores volume, repeat, shuffle, queue order, and the current queue index;
starts serialized folder scans; builds album/artist summaries; and translates
UI or MPRIS actions into engine/database operations. Album identity combines
album title and album artist so two unrelated albums with the same title do
not merge. Artist browsing uses track artist, falling back to album artist only
when the track artist is absent.

### MetadataScanner

TagLib reads tags, duration, track/disc numbers, and embedded MP3, FLAC, MP4,
Vorbis, or Opus artwork. Artwork is size-limited to 20 MiB and cached under a
SHA-256 name derived from source path, modification time, and file size. The
scanner runs through `QtConcurrent`; only immutable fingerprints and paths
cross the worker boundary.

Incremental scans compare canonical path, modification time, and size. Files
with recognized extensions but unreadable metadata are retained if previously
known and reported as warnings. A scan never writes tags or audio files.

### MusicDatabase

One named Qt SQL connection owns `$XDG_DATA_HOME/kos/music/library.sqlite`.
SQLite foreign keys, WAL, a five-second busy timeout, and schema migrations are
enabled before use. Version 1 contains:

| Table | Ownership |
| --- | --- |
| `library_roots` | Canonical folders and scan timestamps |
| `tracks` | Paths, tags, artwork URL, fingerprints, duration, and play history |
| `playlists` / `playlist_items` | Named ordered sets; track deletion cascades |
| `queue` | Durable playback order; duplicate tracks are allowed |
| `settings` | Volume, shuffle, repeat, and current queue index |

Opening one file directly creates a track with no library root, so removing a
folder cannot delete an unrelated explicitly opened item. Removing a library
root cascades only its indexed tracks, queue entries, and playlist references;
the source directory and files are never touched.

### PlaybackEngine

The engine creates GStreamer `playbin3`, falling back to `playbin`. Bus and
position polling are integrated into the Qt event loop; no GLib main loop is
embedded. The public state is `Loading`, `Playing`, `Paused`, `Stopped`, or
`Error`. Local path existence is checked before loading, seeks are bounded by
duration, and volume is bounded to 0–150%.

Decoding and audio output are capabilities of the installed GStreamer stack.
`KOS_MUSIC_AUDIO_SINK` may select a sink for diagnostics, while
`KOS_MUSIC_FAKE_AUDIO=1` uses a synchronized fake sink in automated tests.

### Transcoder

Conversion builds one dynamic pipeline:

```text
uridecodebin3 -> queue -> audioconvert -> audioresample
              -> encoder -> optional muxer -> temporary filesink
```

The format list is generated only from available element factories. Output is
written to a hidden temporary file in the destination directory and finalized
with the Linux atomic rename operation; a failed overwrite therefore preserves
the old destination. Cancellation and errors remove the temporary file.
Version 1 exports decoded audio but does not copy source tags or artwork.

## MPRIS behavior

The service is `org.mpris.MediaPlayer2.kosmusic` at
`/org/mpris/MediaPlayer2`. It implements the root and Player interfaces. Track
IDs use `/org/nextkde/KosMusic/track/t<ID>`, durations/positions use MPRIS
microseconds, and `PropertiesChanged` is emitted for metadata and control
capabilities but not continuously for `Position`, as required by the standard.

`OpenUri` accepts only a readable local file. `Raise` asks the QML window to
show, raise, and request activation. If the session bus is absent or another
instance owns the name, playback remains available and `mprisRegistered` is
false.

## Failure and threading rules

- Tag parsing runs off the UI thread; the database connection remains on its
  owner thread and scan commits are transactional.
- Scanner warnings are capped at 100 per controller session. Fatal database,
  engine, and conversion errors are exposed in the application instead of
  being silently ignored.
- Conversion never edits the source and writes beside the destination so final
  replacement cannot cross filesystems.
- The queue and playlists reference track IDs with foreign-key cleanup, so a
  rescan cannot leave dangling rows.
- No network URI, shell command, plugin download, or codec installation is
  initiated by the application.

## Verification matrix

`kos-music.core` covers schema persistence, incremental scans, missing-file
cleanup, queue/playlists, filtering, sorting, and album identity.
`kos-music.engine` decodes and plays a generated WAV through synchronized
GStreamer, pauses, seeks, resumes, converts it with an installed encoder, and
tests atomic overwrite. `kos-music.mpris` runs under a private session bus and
checks metadata, playback state, pause/play/stop, volume, shuffle, repeat,
seek, `OpenUri`, and `Raise`. Version and full-QML smoke tests load the normal
application root with software rendering. Engine/MPRIS tests make GLib critical
warnings fatal to catch ownership mistakes.

## Deliberate boundary and future refactors

Version 1 is a local single-user player. Streaming/DRM accounts, remote
libraries, sync, and podcasts require a provider and credential boundary, not
extensions to `MusicController`. Editing tags requires a transactional write
service with backup/conflict behavior. Gapless preloading, crossfade,
ReplayGain, and DSP require a queue-aware engine API instead of adding policy
to the QML layer. Very large-library pagination would replace the current
in-memory list models with query-backed models and move database commits to a
dedicated worker connection. These are explicit future refactors, not hidden
version-1 promises.
