# Music architecture

KOS Music is an independent Qt Quick process. It owns the local and online
track catalog, playback engine, and MPRIS provider. The conversion backend remains
available to engine tests; track menus no longer expose conversion jobs. Quickshell
and the other standalone applications do not import its implementation.

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
     +-- OnlineMusicProvider/HTTPS --------> provider metadata search
     +-- LxSourceService/JSONL ------------> separate custom-source host
                                                   |
                                      Node vm + restricted lx bridge
                                                   |
                                           playable URL resolution
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
- [SPlayer](https://github.com/imsyy/SPlayer) informed the Track identity,
  summary/detail separation, provider boundary, bounded page lifecycle,
  persistent mini player, dedicated Now Playing surface, and isolation of
  untrusted LX-compatible scripts. KOS retains its native Qt/GStreamer stack;
  no Electron implementation was ported.
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
UI or MPRIS actions into engine/database operations. It remains a QML
compatibility facade while provider/search/source behavior lives in dedicated
services. Album identity combines
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
enabled before use. Schema version 2 contains:

| Table | Ownership |
| --- | --- |
| `library_roots` | Canonical folders and scan timestamps |
| `tracks` | Stable local/LX identities, provider metadata, tags, artwork, fingerprints, duration, and play history |
| `playlists` / `playlist_items` | Named ordered sets; track deletion cascades |
| `queue` | Durable playback order; duplicate tracks are allowed |
| `settings` | Volume, shuffle, repeat, and current queue index |

Opening one file directly creates a track with no library root, so removing a
folder cannot delete an unrelated explicitly opened item. Removing a library
root cascades only its indexed tracks, queue entries, and playlist references;
the source directory and files are never touched.

Online tracks use `source + provider_id` semantics and a stable synthetic path
such as `lx://wy/347230`. Their `source_data` stores the metadata required by
an LX resolver. Resolved audio URLs are deliberately not stored: they are
short-lived links and are requested only when no complete audio cache entry is available.

### Track actions and deletion

`TrackListView` selects actions by page context. Library rows can delete music;
queue rows can move an entry immediately after the current one or remove that entry;
online results can play, insert next, or append; playlist rows can remove membership.
Actions that cannot change the current queue are hidden. Inserting an already queued
track moves its existing entry and preserves the current playback position.

Deletion binds confirmation to both the track ID and the displayed path. Local files
move to the system trash before their catalog record is removed. A trash failure leaves
the record intact; an already missing file allows stale-record cleanup. Database foreign
keys remove queue and playlist references, and the controller removes every matching
in-memory queue entry. A scan already in progress filters deleted paths before applying
its result. Deleting a playing track advances to an available successor; a paused player
never starts automatically. Online catalog deletion removes its persistent audio cache.

The music app owns its rounded menu, menu item, dialog, and quality selector components.
Shared UI changes only add `KosLyricLine` and its module registrations. Desktop changes
are limited to MPRIS presentation, lyric visibility/transitions and media transport
controls in DeskCenter, Dock and Control Center. Desktop typography, desktop-file slot
persistence, audio-service configuration and session setup are outside this boundary.

Cancellation detaches each network reply before calling `abort()`, which may dispatch
`finished` synchronously. Generation checks keep old lyrics/search results from replacing
new content; source imports discard replies that no longer own the active request.

### OnlineMusicProvider

The initial provider performs NetEase (`wy`) metadata search over HTTPS and
maps results into the same `TrackRecord` domain type used by the local library.
It does not obtain or cache playable URLs. Search replies are bounded by the
network timeout and stale requests are aborted when a new query begins. This
boundary can accept more search providers without changing queue or playback
code.

### LxSourceService and source host

Users can import a local JavaScript file or an HTTPS URL compatible with LX
Music's `user_api` request/inited contract. Scripts are SHA-256 identified,
atomically copied under `$XDG_DATA_HOME/kos/music/sources`, explicitly
activated, and never evaluated in the UI process. The source host exchanges
one bounded JSON object per line with the application and exposes only the LX
event/request/crypto/buffer compatibility bridge inside a Node `vm` context;
`require`, `process`, and the filesystem are not exposed. A 35-second command
deadline terminates a hung host. The small Qt JS implementation is retained as
a legacy fallback if Node cannot be executed, but modern sources require a
Node.js runtime because they commonly use async/await and newer syntax.

Custom sources remain third-party code. The helper provides crash/timeout
containment and reduces the directly exposed API surface, but Node's `vm` is
not a security sandbox. Only trusted scripts should be imported. A source can
observe the track metadata and its own HTTP traffic, may stop working, and
grants no music copyright or redistribution rights.

### LyricsService and Now Playing

Lyrics are intentionally outside `MusicController` and the playback engine.
For local tracks the service looks for a same-name `.lrc`/`.LRC` sidecar. For
NetEase tracks it requests synchronized LRC text, writes successful responses
atomically under the music cache, and reuses them offline. The parser accepts
multiple timestamps per line, normalizes fractional seconds, and sorts the
timeline. GStreamer remains the playback clock; its existing 250 ms position
updates select the active line while QML owns scrolling and transitions.

The persistent Mini Player stays outside the bounded page cache. The heavier
Now Playing page is cache-managed, applies artwork only as a local translucent
backdrop, and never mutates `AppTheme` or the rest of the desktop. Its lyric
view therefore stops rendering when the page is evicted.

### PlaybackEngine

The engine creates GStreamer `playbin3`, falling back to `playbin`. Bus and
position polling are integrated into the Qt event loop; no GLib main loop is
embedded. The public state is `Loading`, `Playing`, `Paused`, `Stopped`, or
`Error`. Local path existence is checked before loading, seeks are bounded by
duration, and volume is bounded to 0–150%.

Pause/resume reuses the loaded track ID even when its playable URL differs from
the online metadata URL. The controller stores the current track ID and position
as one JSON setting every five seconds while playing and on pause, seek and exit.
Startup restores the position without autoplay; the engine prerolls in PAUSED,
then seeks after ASYNC_DONE before honoring the requested playback state.

GStreamer progressive download uses `downloadbuffer` so playback and persistent caching
share one HTTP transfer. `AudioCache` is a disk index keyed by stable track/quality,
with 1 GiB LRU retention and a 256 MiB per-entry limit. The download-complete message
can precede the sparse file's final stdio flush: the engine retains the temporary file,
closes the pipeline on stop/track change/exit, and only then publishes it atomically.
Errors and partial downloads are discarded. An unwritable cache uses ordinary streaming.
The UI distinguishes resolution, buffering and download progress, with cancel and retry.

The controller bounds source attempts at 12 seconds and track preparation at 45 seconds.
`LxSourceService::useSourceForPlayback` changes only the running helper, preserving the
saved preferred source. Incompatible platform/quality, resolver errors, host crashes,
network errors and decoder failures all move to the next imported source. Recovery is
queued outside signal dispatch; generation checks discard stale callbacks. Exhausted
tracks show a 3-second notice then advance, bypassing repeat-current and avoiding songs
already failed in this recovery run. An exhausted queue stops; a successful track clears
the failure set. Pause/stop/selection/removal cancel pending automatic actions.

The app exports preparation text/state in MPRIS metadata. Dock eligibility follows player
presence so paused and buffering sessions remain resumable. Transport controls share
`MediaControlButton`; `KosLyricLine` animates desktop/widget lines, while Now Playing
uses an animated ListView highlight range. The app lyric preference persists in SQLite;
the independent desktop-lyric preference persists in Dock configuration.

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
- Source imports accept local files, HTTPS, and loopback HTTP for test tooling;
  arbitrary clear-text remote import URLs are rejected. Resolved playback URLs
  may be HTTP because existing LX sources return them.
- Custom scripts are not given `require`, `process`, or application objects.
  The helper is killable and all source HTTP responses are size-limited; this
  is defense in depth, not permission to run untrusted code.

## Verification matrix

`kos-music.core` covers schema persistence, incremental scans, missing-file
cleanup, queue/playlists, filtering, sorting, album identity, provider parsing,
online-track persistence without resolved URLs, and LRC parsing/timestamp
normalization. `kos-music.source-host`
checks the LX request/inited contract through the real subprocess boundary.
`kos-music.engine` decodes and plays a generated WAV through synchronized
GStreamer, pauses, seeks, resumes, converts it with an installed encoder, and
tests atomic overwrite. `kos-music.mpris` runs under a private session bus and
checks metadata, playback state, pause/play/stop, volume, shuffle, repeat,
seek, `OpenUri`, and `Raise`. Version and full-QML smoke tests load the normal
application root with software rendering. Progressive HTTP fixtures verify first audio
before download completion, one transfer, exact cached bytes, failures and cancellation.
Data-driven controller tests cover resolver rejection/hang, late replies, blocked helpers,
HTTP failures/stalls, invalid media, unsupported platforms, track deadlines, all playback
modes, all-failed queues and user cancellation. A private bus without desktop service
activation isolates these tests. `kos-music.lyric-transition` checks intermediate animation
frames, rapid seeks and hiding. `kos-music.context-menus` exercises each page context,
queue deduplication, confirmation/cancellation, rounded controls and quality selection.
Controller fixtures test deletion during playback, pause and scanning, duplicate queue
entries, the last queued track, missing files, stale confirmations and unavailable trash.
Local proxy/HTTP fixtures cover synchronous cancellation of lyrics, search and source
imports without depending on a remote response. Engine/MPRIS tests make GLib critical
warnings fatal to catch ownership mistakes.

`kos-music-live-source-check` is an opt-in network integration executable. It
searches through `OnlineMusicProvider`, imports a selected LX script, loads
lyrics, resolves the first result, and asks the real GStreamer engine to fetch
and decode the stream through a synchronized fake audio sink. It is intentionally not a
default CTest because public search and third-party source endpoints are
external and unstable.

## Deliberate boundary and future refactors

The current milestone is a local single-user player plus opt-in LX custom
sources. Remote library servers, authenticated streaming/DRM accounts, sync,
and podcasts remain out of scope and require separate provider and credential
boundaries, not extensions to `MusicController`. Editing tags requires a transactional write
service with backup/conflict behavior. Gapless preloading, crossfade,
ReplayGain, and DSP require a queue-aware engine API instead of adding policy
to the QML layer. Very large-library pagination would replace the current
in-memory list models with query-backed models and move database commits to a
dedicated worker connection. These are explicit future refactors, not hidden
version-1 promises.
