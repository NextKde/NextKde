# Settings page contracts

`main.qml` is the composition root. It owns navigation, lazy Loader lifetimes,
window chrome and the application palette. `pages/` owns feature views and
feature-local state; `components/` owns reusable presentation controls. Existing
wallpaper, services and notifications pages retain their established interfaces.
No registry, dependency container or second IPC protocol is introduced.

## Inputs and outputs

- `colors` is a required palette object: the semantic color roles and
  `role(name, fallback)` supplied by the root. Pages must not access the root's
  `theme` id. `materialForm` is a presentation input where applicable.
- `bridge` is the existing SettingsBridge interface, explicitly injected by the
  root; `null` means unavailable. Pages retain their existing method and snapshot
  signal contracts. The window appearance page instead receives `backend`, the
  existing WindowSettings object. Neither dependency is discovered from context
  properties inside extracted pages.
- `glassStyles` provides `options`, `indexOf(id)` and `labelOf(id)` to appearance
  views. This catalog stays owned by the composition root.
- `shellStyleObserved(style)` and `materialSeedObserved(seed)` report confirmed
  appearance state to the root. They do not issue backend writes. Nested display
  sections forward observations through the theme page; pages never mutate the
  application window directly.
- StageAdvancedSettings takes `stageSnapshot` and emits
  `settingRequested(key, value)`. FgSchedSettingsPage translates the request into
  the existing bridge call. The snapshot remains authoritative until a reply.
- ResourceSchedulingSettings takes `snapshot`, `memStatus`, `runningApps` and
  `bridge`, and emits `refreshRequested()`. Polling and snapshot subscriptions
  remain in FgSchedSettingsPage, so destroying the Loader also stops polling.

Keep feature state next to its view. Extract another component when it owns a
coherent responsibility, not to satisfy an arbitrary line count. New controls
must receive their palette explicitly; do not pass the whole application window
or introduce dependencies on sibling page ids.

## Regression coverage

`kos-settings.page-contracts` creates every extracted page without main.qml or
backend context properties, checks appearance observations and stage request
semantics. Existing settings tests cover widget confirmation, built-in controls,
segmented layout, window interactions, wallpaper, notifications and entry paths.
Run the settings CTest group in a configured VM build:

```sh
ctest --test-dir <vm-build-directory> -R '^kos-settings\.' --output-on-failure
```

Installation must include both `pages/` and `components/`. The existing recursive
QML watcher discovers these directories for development reloads. Runtime tests
default to the VM unless the user explicitly authorizes a host run.

### 2026-10-15 authorized host run

Built kos-settings and kos-window-settings-test from current sources in
`tmp/settings-modules/build`. All 15 settings CTest groups passed (16.55 seconds),
including 19 passing checks in page-contracts. The first contract run exposed an
incorrect test assumption: resource controls intentionally have zero height when
the scheduler is unavailable. The test now covers both unavailable and available
states. No production fix was needed for that failure.

A CMake install into `tmp/settings-modules/stage` included all extracted QML
modules, and the staged binary passed `--smoke-test-windows`. Tests used the
offscreen software backend and isolated configuration/cache/state directories;
these results do not establish visual correctness in a live compositor session.
