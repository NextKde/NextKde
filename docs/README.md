# Documentation

[简体中文](README.zh-CN.md)

English is the default. Chinese companions are linked from each bilingual guide.
The root [README](../README.md) introduces the desktop; guides below own detailed instructions.

## Users and releases

| Topic | Canonical guide |
| --- | --- |
| Dependencies, install, update, uninstall | [Getting started](GettingStarted.md) |
| NixOS declarative installation | [NixOS](nixos-quickstart.md) |
| Maintenance, acceptance and publication | [Releasing](Releasing.md) |
| Version-specific changes and actual evidence | [v0.1.1](releases/v0.1.1.md), [v0.1.0](releases/v0.1.0.md) |
| Release-note format | [Template](releases/TEMPLATE.md) |

## AI contributor reference

Read [project context](../PROJECT_CONTEXT.md), [contribution rules](../CONTRIBUTING.md) and
[development](Development.md) first. Architecture pages describe current contracts and source
ownership; they are not chronological work logs or proof that a feature passed runtime acceptance.

| Owner/topic | Reference |
| --- | --- |
| Runtime products and service boundaries | [Project architecture](ProjectArchitecture.md) |
| Platform adapters and IPC | [Platform architecture](PlatformArchitecture.md), [wire contract](../shared/contracts/platform.v1.md) |
| Durable data, sockets and concurrency | [Data service](DataServiceArchitecture.md) |
| Appearance, tokens and icons | [Appearance](AppearanceArchitecture.md), [desktop icons](DesktopIcons.md) |
| Window clipping, shadows, resource limits and VM review | [Window appearance](WindowAppearance.md) |
| Dock input, lifecycle and animations | [Dock](DockArchitecture.md) |
| Wallpaper ownership and theme format | [Wallpaper](WallpaperArchitecture.md), [theme packs](ThemePackFormat.md), [depth engine](DepthEngine.md) |
| Network, PIM and weather | [Network](NetworkArchitecture.md), [PIM](PimArchitecture.md), [weather](WeatherArchitecture.md) |
| Optional applications | [Applications](../apps/README.md), [legacy Music](MusicArchitecture.md), [ListenFree build](../apps/listenfree/packaging/linux/README.md) |
| Reusable QML components, Gallery and sidebar demo | [nextkdeAppDemo](https://github.com/NextKde/nextkdeAppDemo) |

The component Gallery and sidebar demo are maintained in `nextkdeAppDemo`. Their preview
entry points are no longer shipped with NextKde. This repository retains the shared QML
components and Shell glass implementation used by its runtime; changes in the demo repository
are not automatically synchronized here.

## Keeping this reference current

Update the canonical page with code changes, including its maintained translation. Link instead
of duplicating implementation detail. Contracts and source are authoritative when prose conflicts;
fix the prose in the same PR. Keep known limits distinct from plans and measured results.

Do not commit session diaries, process screenshots, captured logs or temporary review reports to
`docs/`. Keep scratch material in ignored `tmp/`; durable release evidence belongs in CI/Release
artifacts. Keep project illustrations, required assets and third-party provenance. Removing a file
from the current tree does not erase historical Git objects; shallow clones avoid downloading the
old history. Do not rewrite published history as part of normal documentation cleanup.
