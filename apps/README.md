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
import one another.

`settings` predates this workspace and remains on its existing build path
until its source-path-dependent QML loader is migrated separately.
