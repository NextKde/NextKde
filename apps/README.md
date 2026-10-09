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

`./tools/kosctl install apps` (or `install-apps.sh`) builds Calendar, Todo,
Weather and ListenFree. It first checks system dependencies and reports missing
packages with Arch `pacman` or Ubuntu `apt` commands. Install the reported
packages and rerun the same command; it does not automatically run sudo.

Arch rolling releases and Ubuntu 26.04+ provide the required Qt 6.10+.
Ubuntu 22.04/24.04/25.10 stock Qt is too old; those releases need a complete
compatible Qt/KF6 toolchain. Go 1.26+ is also required by the data service.
The checker verifies QML runtime modules and the SQLite driver as well as
headers and build tools. Run `python3 tools/check-apps-dependencies.py` for
just the preflight check.

The installer downloads checksum-verified QuickJS-ng and Qmmp sources, applies
the included audio patches and builds a private SDK under
`.build/listenfree-sdk`. If system TagLib is older than 2.3.1, it builds that
privately too. The first installation needs internet access and takes longer;
later installations reuse the SDK while its build fingerprint matches.
No manually prepared SDK is required. `KOS_LISTENFREE_SDK=/path/to/sdk` remains
available for an existing compatible SDK. System packages and CPU architecture
are discovered on the target device; the builder uses no host-specific paths.

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

Run `./tools/kosctl install apps`; see the [Linux build instructions](listenfree/packaging/linux/README.md) for the private SDK layout and manual builds. Dependencies and compilation are checked before deployment. After the new player passes its runtime check, registration removes and backs up the legacy binaries, desktop entry, icon and AppStream metadata. User data is retained. Existing defaults for other music players and later user choices remain unchanged.
