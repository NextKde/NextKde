# Shared code

This tree contains portable Qt Quick / JavaScript code, cross-process contracts,
and explicitly shell-only adapters. Portable modules must not import Quickshell,
KWin, Wayland-only APIs, or a shell desktop module.

- `qml/foundation/`: portable design tokens and application surfaces, built
  with the controls as the static `Kos.Ui` QML module for standalone apps.
- `qml/controls/`: reusable controls.
- `qml/colorize/`: shell colour adapters; the QML samplers and singleton use
  Quickshell and are excluded from the standalone `Kos.Ui` build. Pure `.mjs`
  colour math remains reusable.
- `qml/wallpapers/`: shell wallpaper scenes and assets; not part of standalone
  `Kos.Ui`.
- `qml/glass/`: portable liquid-glass visuals. KWin blur adapters remain in
  `shell/desktop/`.
- `assets/`: assets used by more than one independent application.
- `contracts/`: versioned IPC and persisted-data schemas. These files are the
  source of truth for socket envelopes, error codes, and shortcut defaults.

Portable consumers must restrict imports to portable components. Shell QML can
use its filesystem `Kos.Ui` module, which also registers the shell adapters. `shell/desktop/` and `apps/*` both sit below the
repository root alongside `shared/`, so an import looks like
`import "../../shared/qml/controls"` (adjust the `../` count to the importing
file's depth).

Standalone applications link `Kos::Ui` and `Kos::UiPlugin` statically. The
`pim/` module similarly provides the portable D-Bus client shared by Calendar
and Todo; shell consumers remain decoupled from application processes.
