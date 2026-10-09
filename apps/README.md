# Independent desktop applications

**[English](README.md) | [中文](README.zh-CN.md)**

Every direct child is a standalone Qt Quick application and a separate
process. Applications may import `shared/`, communicate with `services/`
through documented contracts, and must never import `shell/desktop/`.

The application workspace is configured from the repository root. Five build
options and matching CMake presets keep the new applications independently
manageable:

| Application | Target | Configure preset |
| --- | --- | --- |
| Calendar | `kos-calendar` | `calendar-dev` |
| Todo | `kos-todo` | `todo-dev` |
| Weather | `kos-weather` | `weather-dev` |
| Music (legacy, retained) | `kos-music` | `music-dev` |
| KOS ListenFree (default music player) | `listenfree` | `listenfree-dev` |

Use `apps-dev` to build all five. Each application owns its executable, QML
module, desktop entry, tests, and bilingual documentation. `apps/common/` is a
small application runtime rather than a feature layer; applications do not
import one another. The Weather preset additionally builds and installs its Go
data service, which the application starts on demand.

## Development: QML hot reload

The four apps using `apps/common` can load their QML from a source tree and hot reload it, so QML
edits need neither a rebuild nor a restart:

```bash
.build/music-dev/apps/music/kos-music --watch-qml apps/music/qml
# or skip the argument via the environment
KOS_APP_QML_DIR=apps/music/qml .build/music-dev/apps/music/kos-music
```

The path names the directory holding `Main.qml` (or the entry file itself).
`*.qml`/`*.mjs` files in the tree are watched and the window is rebuilt after a
300 ms debounce; the new code is fully compiled on a throwaway engine first
(including referenced siblings), and text that does not compile reports its
errors and keeps the current window. Controllers created in C++ and injected
into QML through initial properties (such as music's `music`) survive a reload:
playback, the queue, the database connection, and the MPRIS registration keep
running. QML-owned state (the current page, open dialogs) resets.
`shared/qml` (Kos.Ui) is compiled into the binary and still needs a rebuild.

A watch run is an isolated development instance: it never displaces the
single-instance activation of the running application. C++ edits still need a
rebuild; only QML/JS edits go through hot reload.

For a persistent per-user installation on Plasma, run:

```sh
./tools/install-apps.sh
```

`install-apps.sh` builds Calendar, Todo, Weather and ListenFree, rather than only the app you
intend to open. In addition to the base requirements in the repository README,
install these Arch build dependencies first:

```sh
sudo pacman -S --needed kcalendarcore gstreamer gst-plugins-base-libs taglib
```

`kcalendarcore` is required by Calendar and Todo; GStreamer and TagLib are
required by Music. Go is required by Weather and is already part of the core
KOS build requirements. Runtime GStreamer codec/plugin packages are separate:
install the ones needed for the audio formats and output backends you use.
Building a single app with its corresponding CMake preset needs only that
app's direct dependencies.

This performs a Release build, installs the binaries under
`~/.local`, registers desktop entries, hicolor icons and AppStream metadata,
enables the core `kos-data.service`, registers the D-Bus-activated PIM service,
and refreshes Plasma's application cache. The desktop entries contain absolute executable paths, so
the applications remain available after login without a source-tree build.
Re-run the same command to perform an in-place upgrade.

Each application exposes the same appearance settings with the platform Preferences shortcut
(typically `Ctrl+,`): system,
light or dark appearance; automatic, glass or solid material; opacity; accent
colour; reduced transparency; and reduced motion. Preferences use one shared
store and propagate to other running KOS applications. On KDE Plasma the app
runtime uses `KWindowEffects` for native blur and background contrast when the
compositor advertises them, with a readable solid fallback everywhere else.

`settings` predates this workspace and remains on its existing build path
until its source-path-dependent QML loader is migrated separately.

## Default applications

Todo, Calendar and Weather update their existing directories and desktop IDs, retaining their services and data. ListenFree replaces legacy KOS Music in the installed bundle; the old source remains in the repository for now. The music widget raises the current MPRIS player, or opens ListenFree when no session exists.

Prepare the SDK described in the [Linux build instructions](listenfree/packaging/linux/README.md), then run `KOS_LISTENFREE_SDK=/path/to/sdk ./tools/install-apps.sh`. The installer checks this prerequisite before deployment. After the new player passes its runtime check, registration removes and backs up the legacy binaries, desktop entry, icon and AppStream metadata. User data is retained. Existing defaults for other music players and later user choices remain unchanged.
