# Settings backend boundaries

`main.cpp` only creates the application, composes the backends and QML runtime,
and handles application command-line entry points. The QML context still exposes
`settingsBridge` and `windowSettings`; preserve the existing
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

Existing tests exercise the compiled facade through actual QML, including notification IPC,
color generation, installed entry selection, hot reload, pages and controls. Lifecycle tests cover
completion on the owning thread and destruction with both probes running, with no stale callback.
Run all verification only in the VM/hosted CI per [Development](../../../docs/Development.md).
Do not treat a historical refactoring report as evidence for the current source.

## Window and background task lifetime

Settings is a session-scoped single instance. Closing its window leaves the
process and application operations running, including final installation-state
verification. Launching Settings again activates that owner; when a mutation is
active, ordinary launch opens application management with the existing progress.
Explicit page and Calendar/Weather navigation still take precedence. Cancellation
is only performed through the application's existing task controls.

The process stays resident after completion to retain its task state. Mutation
completion emits one desktop notification after verification; read-only inventory
and update queries do not notify. Notification delivery is asynchronous and a
missing notification service does not change the task result. This is window-close
continuation within the login session, not task recovery after logout, reboot, or
process termination.

`kos-settings.close-policy` launches the real Settings binary with an isolated
installer fixture and notification bus, closes and relaunches it mid-operation,
and checks success, installer failure, and final-verification failure while hidden.
The builtin QML suite also closes and reopens the real Settings window while busy.
