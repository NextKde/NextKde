# Settings backend boundaries

`main.cpp` only creates the application, composes the backends and QML runtime,
and handles application command-line entry points. The QML context still exposes
`settingsBridge` and `windowSettings`; this refactor preserves all 101 existing
SettingsBridge invokable signatures and their default arguments.

## Modules

| Module | Responsibility |
| --- | --- |
| SettingsBridge.h / SettingsBridge.cpp | Stable QML facade, session metadata, reply/error dispatch and module ownership |
| SettingsBridgeDesktop.cpp | Dock/notifications, launcher/shortcuts/language, desktop integration probes |
| SettingsBridgeAppearance.cpp | Theme and glass settings, snapshot validation, glass debug specifications |
| SettingsBridgeWallpaper.cpp | Wallpaper IPC, color generation, model inspection and QML resource adapters |
| SettingsBridgeScheduling.cpp | Scheduler configuration, resource snapshots and stage settings |
| SettingsProbeTasks | Background probe ownership, UI-thread delivery and shutdown joins |
| ShellIpcClient | Asynchronous process transport, session candidates, retries, watchdog and diagnostics |
| WallpaperLibrary | Local gallery imports, content deduplication, migration and thumbnail cache/workers |
| SettingsRuntime | QML entry selection and the existing development reload watcher |

The feature .cpp files implement the same facade; they are not separately
registered QML backends. Keep existing feature state here unless it gains a real
independent lifecycle. Transport and local resources already have independent
lifecycles and are concrete owned modules. No service registry, inheritance tree
or second IPC schema is needed.

## Contracts and ownership

- `ShellIpcClient::request` never waits on the UI thread. While the client is
  alive, completion occurs once on its owning thread. A nonempty `Result.error`
  means failure; an empty payload is a valid success for void verbs. Destroying
  the client cancels pending callbacks with its QObject-owned processes.
- The preferred Shell gets at most two attempts, subsequent candidates one.
  Quickshell diagnostic sentences are failures even with exit code zero. The
  successful directory identifies the session; only the facade updates its
  QML-visible session metadata.
- Dock and wallpaper queues stay in the facade, where feature ordering belongs.
  Transport knows nothing about RequestKind, snapshots, queue coalescing or QML
  signals. Error dispatch still releases the corresponding pending state and
  advances the queue. The last confirmed stage snapshot survives void/error replies.
- WallpaperLibrary receives filesystem paths/URLs and owns its fingerprint
  cache, migration marker and bounded thumbnail pool. Errors and thumbnail-ready
  events are forwarded by the facade to its existing QML signals. Destruction
  clears queued work and joins running thumbnail tasks before releasing state.
- Entry selection/reload uses SettingsRuntime and remains independent of IPC.
  Source paths remain compile definitions on kos-settings, so installed versus
  checkout behavior and recursive module watching keep their existing contract.

Integration and model verification both use SettingsProbeTasks. Worker closures
capture only input values and produce QVariantMap results; they never read the
bridge or a QPointer to it. Completion belongs to the task owner on the UI thread.
The task owner is the bridge's last member, so it disconnects queued completions,
requests interruption and joins every worker before captured UI state is torn
down. Model hashing checks interruption between chunks.

## Regression coverage

`kos-settings.backend-modules` uses temporary image resources and a fake process
executable. It covers exact argument forwarding, void replies, preferred-session
retry/fallback, diagnostic replies, failed start/exit, watchdog responsiveness,
local gallery deduplication/name collisions, managed deletion boundaries, and
asynchronous thumbnail caching with rounded alpha.

Existing tests continue to exercise the compiled facade through actual QML,
including notification IPC round trips, color image generation, installed entry
selection, hot reload, pages and controls. Host execution was explicitly
permitted for this work; all runtime data is isolated from user configuration.

2026-10-15 validation: current sources built successfully; all 16 settings CTest
groups passed, including 14 checks in backend-modules. The source review also
confirmed that 130 unchanged feature method bodies retain their original logic.

Follow-up lifecycle validation adds two deterministic checks: completion is
returned to the owning thread, and destroying an owner with both probes running
joins both workers without delivering a stale callback. Backend-modules now has
16 passing checks.
