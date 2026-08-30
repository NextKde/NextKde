# Shared code

Only pure Qt Quick / JavaScript code belongs here. This directory must not
import Quickshell, KWin, Wayland-only APIs, or a desktop module.

- `qml/foundation/`: portable design tokens and application surfaces, built
  together with the controls as the static `Kos.Ui` QML module.
- `qml/controls/`: genuinely reusable controls.
- `qml/glass/`: portable liquid-glass visuals. KWin blur adapters remain in
  `desktop/`.
- `assets/`: assets used by more than one independent application.
- `contracts/`: versioned IPC and persisted-data schemas.

Standalone applications link `Kos::Ui` and `Kos::UiPlugin` statically. This
keeps each executable independently deployable while preserving a single
source of truth for portable controls. Shell QML may continue using direct
directory imports and is not coupled to the application build.
