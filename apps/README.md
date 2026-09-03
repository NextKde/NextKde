# Independent desktop applications

**[English](README.md) | [中文](README.zh-CN.md)**

Every direct child is a standalone Qt Quick application and a separate
process. Applications may import `shared/`, communicate with `services/`
through documented contracts, and must never import `desktop/`.

The application workspace is configured from the repository root. Four build
options and matching CMake presets keep the new applications independently
manageable:

| Application | Target | Configure preset |
| --- | --- | --- |
| Calendar | `kos-calendar` | `calendar-dev` |
| Todo | `kos-todo` | `todo-dev` |
| Weather | `kos-weather` | `weather-dev` |
| Music | `kos-music` | `music-dev` |

Use `apps-dev` to build all four. Each application owns its executable, QML
module, desktop entry, tests, and bilingual documentation. `apps/common/` is a
small application runtime rather than a feature layer; applications do not
import one another. The Weather preset additionally builds and installs its Go
data service, which the application starts on demand.

For a persistent per-user installation on Plasma, run:

```sh
./tools/install-apps.sh
```

This performs a Release build and test pass, installs the binaries under
`~/.local`, registers desktop entries, hicolor icons and AppStream metadata,
enables the PIM and shared-data user services, and refreshes Plasma's
application cache. The desktop entries contain absolute executable paths, so
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
