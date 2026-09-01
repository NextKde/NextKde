# Project architecture

The repository has two separate UI runtimes.

```text
shell.qml -> desktop/                 Quickshell desktop environment
apps/<name>/                          independent Qt Quick application process
shared/                               pure, opt-in cross-process QML and contracts
services/                             resident background processes
helpers/                              on-demand native executables
integrations/                         external desktop integrations such as KWin
```

## Dependency direction

`desktop/` and `apps/` may import `shared/`. Neither may import the other.
`shared/` must be portable: no Quickshell, KWin, or Wayland-only imports.
Cross-process state uses a service or a contract under `shared/contracts/`.

## Global appearance

Shell-wide glass strength and shape style are owned by
[`AppearanceConfigService.qml`](../desktop/modules/common/AppearanceConfigService.qml).
Consumers use semantic values from
[`AppearanceTokens.qml`](../desktop/modules/common/AppearanceTokens.qml); the
standalone Settings app reaches them only through `appearance-settings` IPC.
The schema, token tables, migration rules, and rollout sequence are documented
in [`AppearanceArchitecture.md`](AppearanceArchitecture.md).

## Desktop environment

The root [`shell.qml`](../shell.qml) is intentionally only a stable Quickshell
entrypoint. [`desktop/DesktopEnvironment.qml`](../desktop/DesktopEnvironment.qml)
creates the current Bar, Dock, desktop icon surface, notifications, launcher,
and search overlay. Existing desktop modules remain under `desktop/modules/`
without an internal rewrite.

## Independent applications

Each application is its own normal Qt Quick window and process. Its `main.qml`,
window, data model, and application-specific assets remain inside its own
`apps/<name>/` directory. A future `.desktop` file belongs under
`packaging/desktop/`.

### Optional application contract

Applications are optional companions, not dependencies of the Quickshell
desktop path. When an application platform has a top-level CMake build, every
application option must default to `OFF`; its documented build preset or
command enables only the requested application and its direct dependencies.
Building, installing, or running the Shell must neither build nor install an
optional application.

An application-owned service must be activated on demand by that application
or through D-Bus activation. It must not install a session autostart entry by
default. This keeps calendar, todo, music, and similar future applications from
creating resident processes for Shell-only users.

Optional services are enhancements, never a single point of failure for an
existing Shell feature. If a Shell surface consumes optional service data, it
must retain a local, documented fallback. In particular, weather surfaces must
continue to use the existing keyless Open-Meteo request/cache path whenever the
shared weather service is not installed, unavailable, or returns an invalid
snapshot.

`apps/settings/` is the first application. The desktop top-bar gear only
starts its process through `DesktopAppLauncher`; it never loads Settings UI
into the Quickshell process.

## Shared glass

Portable liquid-glass controls may be added to `shared/qml/glass/`. The visual
base stays portable; any KWin background blur or Quickshell region adapter stays
inside `desktop/`.
