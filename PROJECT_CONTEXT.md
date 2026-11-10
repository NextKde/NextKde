# NextKDE context for AI contributors

[简体中文](PROJECT_CONTEXT.zh-CN.md)

KDE Plasma 6 **Wayland**, Quickshell 0.3.x. Start with this file, then
[documentation](docs/README.md), [architecture](docs/ProjectArchitecture.md),
[development](docs/Development.md) and [contribution rules](CONTRIBUTING.md).

## Boundaries to preserve

- `shell/` owns presentation; `platform/` owns C++/Qt desktop integration;
  `services/data-service/` owns Go telemetry, history, desktop snapshots and shared weather.
- Settings is a separate Qt Quick process. Use Shell `IpcHandler` endpoints, not imports of Shell modules.
- QML must not execute desktop/system-control commands (`nmcli`, `wpctl`, `qdbus6`, `systemctl`,
  `gio`, etc.) or bypass the service boundary. Add bounded operations to the
  [versioned platform contract](shared/contracts/platform.v1.md); review disconnected/error paths.
- Local atomic persistence of existing module-owned state is a narrow legacy exception.
  New integration belongs in the service. Preserve state roots, socket envelopes and migrations.
- Calendar (including tasks), Calculator, Weather and ListenFree are owned by the independent
  NextKde/kos-apps repository (first three, `apps/org.nextks.<app>`) and
  NextKde/ListenFree, including their private PIM/runtime code. The first three
  share a version/Release, not an installation; package availability depends on
  the actual application Release. Root app presets/targets and extracted app sources
  are removed; deprecated ON build switches fail explicitly.
- Core installation owns the complete Settings/runtime QML trees. The compatibility
  apps dispatcher defaults to GitHub Release Flatpak bundles; source is explicit
  --backend=source. Signed catalogs supply app identities; package SHA-256 is mandatory,
  developer signatures are optional unless pinned by the entry. See
  [catalog architecture](docs/app-store/SignedCatalog.md). No compatible Release/runtime policy means unavailable.
  Default selection is Calendar (including tasks), Calculator and Weather; ListenFree is explicit.
  Lifecycle actions never activate services, modify MIME defaults, remove legacy players
  or overwrite core Settings. Core data-service remains a Shell dependency.
- Never hot-replace/reload KWin plugins in a running compositor. Install, then logout/login or reboot.
- Run project verification only in a VM or hosted CI. Preserve unrelated worktree changes.

## Privileged install boundary

`tools/kosctl` stages files under the user's build directory before installing system plugins.
Preserve its ownership/mode validation and root-owned destination files
(`--no-preserve=ownership`). A checked staging tree must not become user-rewritable before use.

On active SELinux systems, copying a home-staged tree with `cp -a` can transfer `user_home_t`
labels into `/usr` and break privilege helpers. Preserve the conditional `cp -Z` destination
relabel behavior; `--no-preserve=context` alone does not suppress all copied xattrs.
Do not pass `-Z` to systems whose `cp` lacks SELinux support. Verify labels in an appropriate VM;
Ubuntu runtime acceptance does not establish SELinux acceptance.

## Appearance boundary

Shell settings live in its pinned state directory; standalone apps read
`QSettings("NextKde", "KosApplications")` through `ApplicationPreferences`.
They are not automatically synchronized. Existing `KOS_APPEARANCE` / `KOS_MATERIAL` /
`KOS_ACCENT` environment overrides are a possible bridge, not an implemented synchronization claim.
Use application-safe `KosTextField` and `AppTheme` in portable apps.

## Release boundary

Only the latest official release is maintained. `main` is development; `release/X.Y` accepts
patches and release preparation. Tags are immutable. A public RC is optional.
Source selection, deployment and service activation are separate steps.
Follow [Releasing](docs/Releasing.md); require explicit publication authorization and evidence
for the exact release commit. Never infer completed runtime verification from an old audit note.
