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

The macOS form follows the NextKde App Demo compact specification: 224 px
scrollable sidebar, 30 px navigation rows, 28 px search, and 26 px liquid segmented
controls. Content uses opaque neutral planes. The sidebar is a single ordinary plane at 0.95 opacity with a transparent window
background. Search uses the canonical Demo `LiquidTextField`, with an explicit
sibling backdrop, no added accent focus ring, and an opaque fallback. Material palette roles remain supported.

The content column adapts from the 860 px minimum window width up to 740 px.
Theme previews and common appearance, window, bar, Dock and launcher rows use
smaller spacing without changing their backend commands.

Capture only the application window for local review:

```sh
.build/settings-preview/kos-settings --page=11 --screenshot /tmp/settings.png
```

`KOS_SCREENSHOT_DELAY_MS` overrides the default 1500 ms capture delay. The process
exits after saving the image and returns a failure code if capture fails.

## Canonical component alignment (2026-10-27)

Recovered settings work from `codex/calendar-weather-settings-compact-liquid`:
compact layout, original navigation icon assets and neutral desktop typography.
The application now statically links `Kos.Demo`, also used by Calendar. Search,
segmented selectors, switches, sliders and selects use byte-identical upstream
components. `SettingsNavBar` adapts only the existing model and confirmation signal;
backend-owned state and commands are unchanged. Switches retain the Demo aspect
ratio at 60×26; selectors use 26 px height, gray selection and medium-weight labels.

The custom wallpaper menu uses one 0.7-coverage liquid surface with actual
same-window content sampling and QML blur. Its 28 px option rows remain ordinary.
There are no additional colored rims, per-row glass or KWin liquid requests.
Standalone QuickTest tests link the same static module as the app; configure with
`-DBUILD_TESTING=ON` and build `kos-settings-qml-tests` before running CTest.
