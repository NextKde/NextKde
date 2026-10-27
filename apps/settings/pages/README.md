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
- FgSchedSettingsPage owns the whole stage-manager surface: the master switch
  and the three style presets. A preset is a complete feel bundle written key by
  key through `stageSet(key, value)`; the snapshot stays authoritative until a
  reply, and no preset highlights while the live values match none of them.
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
QML watcher discovers these directories for development reloads. Run verification only in a VM or hosted CI, as required by
[Development](../../../docs/Development.md). Store run-specific logs and screenshots
outside the source tree; this contract is not an acceptance report.
