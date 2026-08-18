# Shared code

Only pure Qt Quick / JavaScript code belongs here. This directory must not
import Quickshell, KWin, Wayland-only APIs, or a desktop module.

- `qml/foundation/`: design tokens and small non-visual utilities.
- `qml/controls/`: genuinely reusable controls.
- `qml/glass/`: portable liquid-glass visuals. KWin blur adapters remain in
  `desktop/`.
- `assets/`: assets used by more than one independent application.
- `contracts/`: versioned IPC and persisted-data schemas.
