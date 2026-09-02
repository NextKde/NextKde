# Shared code

Only portable Qt Quick / JavaScript code and cross-process contracts belong
here. This directory must not import Quickshell, KWin, Wayland-only APIs, or a
shell desktop module.

- `qml/foundation/`: design tokens and small non-visual utilities.
- `qml/controls/`: genuinely reusable controls.
- `qml/glass/`: portable liquid-glass visuals. KWin blur adapters remain in
  `shell/desktop/`.
- `assets/`: assets used by more than one independent application.
- `contracts/`: versioned IPC and persisted-data schemas. These files are the
  source of truth for socket envelopes, error codes, and shortcut defaults.

Because this tree must stay portable (no Quickshell-only APIs), QML consumers
import controls through a relative filesystem path, never the Quickshell
`qs.*` module alias. `shell/desktop/` and `apps/*` both sit below the
repository root alongside `shared/`, so an import looks like
`import "../../shared/qml/controls"` (adjust the `../` count to the importing
file's depth).
