# Independent desktop applications

**[English](README.md) | [中文](README.zh-CN.md)**

Every direct child is a standalone Qt Quick application and a separate
process. Applications may import `shared/`, communicate with `services/`
through documented contracts, and must never import `shell/desktop/`.

The application workspace is configured from the repository root. Build
options and matching CMake presets keep the new applications independently
manageable:

| Application | Target | Configure preset |
| --- | --- | --- |
| Calendar | `kos-calendar` | `calendar-dev` |
| Calculator | `kos-calculator` | `apps-dev` |
| Todo | `kos-todo` | `todo-dev` |
| Weather | `kos-weather` | `weather-dev` |
| KOS ListenFree (opt-in music player) | `listenfree` | `listenfree-dev` |

`apps-dev` builds Calendar, Calculator, Todo and Weather. Each application owns its executable, QML
module, desktop entry, tests, and bilingual documentation. `apps/common/` is a
small application runtime rather than a feature layer; applications do not
import one another. The Weather preset additionally builds and installs its Go
data service, which the application starts on demand.

Contributor builds, tests, launches and graphical checks run only in a dedicated VM/hosted CI;
see [Development](../docs/Development.md).

## Development: QML hot reload

Apps using `apps/common` can load their QML from a source tree and hot reload it, so QML
edits need neither a rebuild nor a restart:

```bash
.build/calendar-dev/apps/calendar/kos-calendar --watch-qml apps/calendar/qml
# or skip the argument via the environment
KOS_APP_QML_DIR=apps/calendar/qml .build/calendar-dev/apps/calendar/kos-calendar
```

The path names the directory holding `Main.qml` (or the entry file itself).
`*.qml`/`*.mjs` files in the tree are watched and the window is rebuilt after a
300 ms debounce; the new code is fully compiled on a throwaway engine first
(including referenced siblings), and text that does not compile reports its
errors and keeps the current window. Controllers created in C++ and injected
into QML through initial properties survive a reload. QML-owned state
(the current page, open dialogs) resets.
`shared/qml` (Kos.Ui) is compiled into the binary and still needs a rebuild.

A watch run is an isolated development instance: it never displaces the
single-instance activation of the running application. C++ edits still need a
rebuild; only QML/JS edits go through hot reload.

For a persistent per-user installation on Plasma, run:

```sh
./tools/install-apps.sh
```

`./tools/kosctl install apps` (or `install-apps.sh`) builds Calendar, Calculator,
Todo and Weather by default. Preflight checks only their dependencies: Qt 6.5+,
compatible KF6, Go 1.26+, QML runtime modules and the SQLite driver. Missing
packages are reported as Arch `pacman` or Ubuntu `apt` commands; no automatic sudo.

ListenFree and its private audio SDK require explicit selection:

```sh
./tools/kosctl install apps --with-listenfree
```

This additionally requires Qt 6.10+ and the audio dependencies. Its first build
downloads and verifies QuickJS-ng and Qmmp and builds TagLib when needed, which
can take considerably longer. Later runs reuse `.build/listenfree-sdk` when
the fingerprint matches; select an existing SDK with `KOS_LISTENFREE_SDK=/path/to/sdk`.
Standard installs neither prepare that SDK nor remove existing music players or
change audio associations. See the [ListenFree build guide](listenfree/packaging/linux/README.md).

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

Application installation preserves core Settings and its shared runtime QML; an apps-only prefix
does not require an installed core.

`settings` predates this workspace and remains on its existing build path
until its source-path-dependent QML loader is migrated separately.

## Default applications

The four standard apps retain their `kos-*` desktop IDs, services and data.
Legacy `kos-music` source and build targets have been removed. Standard installation
and upgrades leave an existing legacy player, its library and audio associations intact.
Only `--with-listenfree` registers ListenFree and retires legacy KOS Music after
checking the replacement. User data, other players' defaults and later choices
are preserved. The desktop music widget raises the current MPRIS player, or
attempts to open ListenFree when none exists; install a player separately if needed.
