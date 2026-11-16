# Control Center feature boundaries

ControlCenterPanel remains the composition root. It owns the popup anchor,
keyboard/input lifetime, navigation state, shared slider previews, card geometry,
morph/crossfade bindings and the union of native glass regions. Its external
signals and open/close behavior remain unchanged.

These components inherit the existing ControlCenterCard directly, so the panel
still sees and positions the same top-level card objects. They introduce no
intermediate visual wrapper, independent window, motion controller or registry.

- WifiCard / BluetoothCard: connectivity pills and their toggle/navigation hit areas.
- MediaCard: player information and transport controls.
- StageModeCard / KeepAwakeCard: independent feature toggles.
- BrightnessCard / SoundCard: compact sliders.
- SessionCard / SessionConfirmationDialog: session action list and confirmation view.
- SubmenuCard: shared navigation header and submenu content composition.
- WifiPage / BluetoothPage / BrightnessPage / SoundPage: detailed feature views.

## Interface contracts

- Network views receive `network` (the existing NetworkService interface).
  Other system views receive `service` (ControlCenterService), media receives
  `media` plus `player`, and the stage toggle receives `stageMode`. Dependencies
  are provided by the panel; feature components do not discover a window id or
  a backend from their creation context. Shared theme/i18n modules stay shared.
- Navigation, back and settings launches are signals. The panel retains
  authority over navigation and maps settings requests to platform operations.
- `volumePreview` / `brightnessPreview` are owner-provided values. Preview and
  dragging signals update the owner's shared state. Sliders issue backend writes
  only on commit; cancellation restores the confirmed service value.
- `wifiNetworkSelected(network)` carries a copied credential request. The panel
  closes and forwards it to its external listener in one handler. A delegate
  must never close/destroy its list and then continue resolving its QML context.
- SessionCard only emits an action intent. The confirmation view only emits
  cancel/confirm. The panel owns pending action state and performs execution.
- SubmenuCard receives the displayed page, including the outgoing page while it
  fades. Feature views do not own a second navigation state. Native glass,
  clipping, morph geometry and the host's positioning bindings remain intact.

## Verification

`kos-ui.control-center-modules` runs the actual QML components on a private
virtual KWin display and bus, with fake injected services for action checks. It
covers toggle/navigation separation, Wi-Fi credential and saved-profile routing,
shared slider preview/cancel/commit, media commands, real submenu geometry,
confirmation cancellation, close/reopen and Dock-hosted placement.

`kos-shell.control-center-submenu-state` retains the existing navigation/native
region source contracts. The settings test group covers the independently
changed background probe lifecycle.

The focused runtime test waits for settled states. It does not establish the
visual quality of intermediate frames; check animation timing separately in a VM
graphical session and retain run-specific evidence outside the source tree.
