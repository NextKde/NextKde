# Independent desktop applications

**[English](README.md) | [中文](README.zh-CN.md)**

The core `apps/` source tree contains `settings/`, `lockscreen/` and the retained
`sddm/` theme (no supported SDDM installer).
Calendar (including tasks), Calculator and Weather share the independent kos-apps
repository, version and Release, with separate install/update/uninstall. ListenFree remains separate:

| Application | Source, releases and application tests |
| --- | --- |
| Calendar with integrated tasks | [NextKde/kos-apps](https://github.com/NextKde/kos-apps) |
| Calculator | [NextKde/kos-apps](https://github.com/NextKde/kos-apps) |
| Weather | [NextKde/kos-apps](https://github.com/NextKde/kos-apps) |
| ListenFree | [NextKde/ListenFree](https://github.com/NextKde/ListenFree) |

The root build no longer compiles these applications, their private runtime or PIM
service. App CMake presets are removed. Enabling a former `KOS_BUILD_CALENDAR`,
`KOS_BUILD_TODO`, `KOS_BUILD_CALCULATOR`, `KOS_BUILD_WEATHER` or
`KOS_BUILD_LISTENFREE` option fails with migration guidance. Build and contribute
in the corresponding independent repository. Source directories retained during
cutover are not an alternative build/install path and must not be deleted until
the independent gates have been validated.

The first three source directories/IDs are `apps/org.nextks.calendar`,
`apps/org.nextks.calculator` and `apps/org.nextks.weather` (IDs omit `apps/`).
The new remote is not created/pushed; old repositories retain history. Old
`org.nextkde.*` Flatpaks are not automatically renamed, uninstalled or migrated.

## Installation and lifecycle

```sh
./tools/kosctl install apps
./tools/kosctl install apps --app calendar
./tools/kosctl install apps --with-listenfree
./tools/kosctl install apps check-update --app weather
./tools/kosctl install apps update --app weather
./tools/kosctl install apps status --app calendar
./tools/kosctl install apps uninstall --app calculator
```

`tools/install-apps.sh` is the compatibility dispatcher for the same commands.
The default selection is Calendar (including tasks), Calculator and Weather;
ListenFree requires explicit selection. `--app todo` aliases Calendar.
`--update` and `--uninstall` are aliases for the matching lifecycle actions.
Mutations require terminal confirmation or `--yes`. The default backend is the
shared `kos-apps` user-Flatpak backend using signed GitHub Release bundles; it
never adds online sources and needs no hosted NextKde app repository. The
local publisher key is configured, but runtime policy remains empty and no signed
Release exists; installation/update remains unavailable without a source fallback.
Use `--backend=source` for legacy/developer source installation explicitly;
`--app APP --version X.Y.Z` and build-dependency `check` are source-only.
`--with-listenfree-video` is rejected: use the independent ListenFree build guide
for custom video features, rather than overriding a stable Release manifest.

Flatpak owns its installation records; external Flatpak tools can remove the same
ref. Settings/CLI discovers signed GitHub bundle updates, not Discover or
`flatpak update` for URL-less app origins. Libflatpak may create a local origin/key
record even if a transaction is later refused. Runtime distribution still requires
separately approved existing sources. No production signed bundle is published yet.
Status and uninstall of an unambiguous user Flatpak work without publisher approval;
normal uninstall preserves data. No automatic legacy migration occurs.

The explicit source backend downloads stable **source** Releases from the fixed
NextKde repositories and builds locally. Its private ownership records are not
Discover packages. Neither backend falls back to this checkout or a development
branch. A batch stops at the first failure, retaining completed operations.
See the [lifecycle and trust contract](../docs/app-store/IndependentApps.md).

Core `services/data-service` remains a Shell dependency, including shared weather
and its Go coverage. Calendar PIM and application-specific tests belong to their
independent repositories. Core CI checks the independent installer and release
contracts, not obsolete monorepo application directories. See
[Development](../docs/Development.md) for the remaining core verification gates.
