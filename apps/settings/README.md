# Settings

Standalone Qt Quick settings application. It is opened from the gear button
in the top bar or Dock-hosted status area and runs as its own process. Build
the small native host once:

```sh
cmake -S apps/settings -B .build/apps/settings
cmake --build .build/apps/settings
```

The host exposes only explicit Settings IPC methods to QML. It does not import
desktop UI. The current pages cover display, theme, bar, Dock, launcher,
shortcuts, notifications, and read-only integration status through narrow Shell IPC targets.

Notifications uses the `notification-settings` endpoint of the active Shell.
It controls Do Not Disturb, banners, session history, content previews, Dock
badges and permissions for applications that have sent notifications. Policies
persist in the Shell state directory; history keeps the latest 50 messages for
this session. The Control Center and the dedicated notification popup share
one card deck, showing three independent messages until expanded. Card identities
are preserved during expansion; each card has its own compositor glass outline
over one fixed popup capture. Short outputs scroll rather than shrinking controls.

Notification regression checks:

```sh
node tests/notification-history/run.mjs
node tests/notification-history/run-visual.mjs
node tests/notification-history/run-pane.mjs
node tests/notification-history/run-production.mjs
node apps/settings/tests/notifications/bridge.mjs /path/to/kos-settings
/usr/lib/qt6/bin/qmltestrunner -input apps/settings/tests/notifications
```

Run these only in the environment authorized for the current session.

For actual compositor glass (including screenshots), the isolated virtual KWin
fixture uses synthetic messages and a temporary effect configuration:

```sh
python3 tests/notification-history/run-native.py
python3 tests/notification-history/run-native.py --screenshots
python3 tests/notification-history/run-native.py --width 320 --height 540
```

It checks one capture allocation through opening, unfolding, scrolling and
folding; retained visible card instances; clipping; and popup bounds. Screenshot
requests use additional render targets and are measured separately. Frame
intervals in its report describe software OpenGL in the isolated compositor.
Artifacts are saved under `.build/qa/notification-history`.

## Compact desktop interface

The default window is 850×650 px, with a 214 px ordinary sidebar at 0.98 opacity.
The macOS sidebar uses `#ececeb` in light mode and `#242426` in dark mode;
Material uses the matching `surface_container_low` scheme role, paired with
`on_surface` text. The macOS selected navigation uses standard blue with white
text. The title and canonical 26 px back/forward button group share the
window controls' vertical center. Back/forward follows visit history and supports
Alt+Left/Right. KDE System Settings is opened from the canonical 26 px liquid
button with the KDE mark, 22 px left of the traffic lights, aligned to their center.
It uses the existing launch command and is no longer a sidebar entry.

All settings forms use the canonical `Kos.Demo.SettingsGroup` and `SettingsItem`
from [nextkdeAppDemo's settings contract](../../../nextkdeAppDemo/docs/Settings.md).
The Theme **Interface shape** group is the reference composition. Do not add
page-specific card, heading, row, outline, shadow or leading setting-icon variants.
Application and wallpaper artwork remains content rather than a setting icon.
Settings with three or more options use `SettingsSelect`; only two-choice settings
remain segmented. All dropdown options use Normal (400) weight. It displays the current value and canonical up/down
chevrons, with the same right alignment and 24 px height. The trigger is plain
text plus the icon: no liquid/solid button fill, capsule, outline or hover fill.
Only the up/down icon has an ordinary gray rounded background. The compact
settings menu is opaque `#f0f0f1`, with 24 px rows. Selection is shown only with a leading
dark checkmark; no blue active fill or blue text. Menu width follows the longest
option plus its checkmark gutter and padding, without a 160 px minimum. The
background stays fully opaque, including opening/closing. The popup has no border;
one subtle QML shadow spreads equally on all sides with zero X/Y offset. This is the settings-select exception to liquid popups.

- Group heading: 15 px Bold, 6 px above the ordinary surface.
- Group surface: light `#f7f7f7`, radius 12, no border/shadow; group spacing 12 px.
- Item: one 12 px normal name, optional 10 px muted description, minimum 36 px,
  16 px horizontal / 5 px vertical padding, no extra gap between items.
- Trailing controls: right aligned with a 16 px inset, including stacked narrow
  rows. Switches have a 44×20 px body in a 24 px slot; selectors and sliders use
  24 px height. Sliders use a 26×14 px thumb and 4 px track.

`SettingsNavBar`, `SettingsSelect`, `SettingsSwitch` and `SettingsSlider` adapt only application
models/signals and these reference dimensions. Optics and animation come from
Demo. Confirmed snapshots, preview/commit/cancel and existing backend commands
remain owned by the pages. No new persistence layer is introduced.

Build and verify only in a VM or hosted CI. With `BUILD_TESTING=ON`, build
`kos-settings` and `kos-settings-qml-tests`, then run the relevant settings CTest
suite. Page contracts also check actual trailing-control geometry at 560 px and
306 px content widths, rather than checking source declarations alone.

The custom wallpaper menu uses one 0.7-coverage liquid surface with actual
same-window content sampling and QML blur. Its 28 px option rows remain ordinary.
There are no additional colored rims, per-row glass or KWin liquid requests.
Standalone QuickTest tests link the same static module as the app; configure with
`-DBUILD_TESTING=ON` and build `kos-settings-qml-tests` before running CTest.

## Help tooltips

Use canonical `Kos.Demo.KosToolTip` for compact floating liquid hover/keyboard help
(0.7 material coverage, 14 px corners, 11 px opaque secondary text). The sibling help backdrop
captures actual settings content while excluding the popup overlay. This shared
component serves the sidebar, the KDE action and the back/forward group. Sidebar labels only
show their full text when elided; fully visible names never repeat themselves.
The KDE action uses an action-oriented hint. Do not use attached Qt `ToolTip`
properties or a page-specific bubble style. See nextkdeAppDemo `docs/Tooltips.md`.
