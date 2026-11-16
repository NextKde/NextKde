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
from [nextkdeAppDemo's settings contract](https://github.com/NextKde/nextkdeAppDemo/blob/main/docs/Settings.md).
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

Wallpaper rows use the same `SettingsSelect` control and opaque menu contract
as other settings pages. Wallpaper-specific tiles and pickers live in `pages/`.
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

## Applications and services

The page reads a signed, refreshable catalog instead of a compiled application list.
See [architecture, sources and automatic checks](../../docs/app-store/SignedCatalog.md)
([简体中文](../../docs/app-store/SignedCatalog.zh-CN.md)) and the
[submission / Qt runtime guide](https://github.com/NextKde/appCatalog).
`kos-app-update-agent` is installed alongside Settings and starts in the user session;
checks do not install updates. Catalog metadata and UI strings support English,
Simplified Chinese and Brazilian Portuguese. Perform builds, tests and GUI acceptance
only in a development VM or CI, not on the host workstation.

[Developer test mode](../../docs/app-store/DeveloperTesting.md) keeps original app IDs while selecting a separate GitHub test catalog and published release. Test installations must be removed manually.

## About

The About sidebar entry (`--page=about` or `--page=15`) links to the official
website, NextKde repository, new Issue chooser, Pull Request comparison, and the
localized appCatalog submission guide. Links open in the default browser.
Contributors load in pages of 100 with an explicit Load more action. Public GitHub
responses and 72 px avatars persist in the application's cache directory under
`about/` (normally `~/.cache/Quickshell/kos-settings/about`). Reopening Settings
immediately displays cached pages and avatars. Lists older than one day and
avatars older than seven days refresh lazily in the background when requested,
retaining the cached content if refresh fails. There is no refresh button;
failed background requests have a 15-minute retry cooldown within the process.
Fresh cache entries need no network request. Avatar cache maintenance caps storage at
16 MiB / 500 files; evicted or corrupt entries are downloaded again when needed.
List requests time out after 15 seconds and are cancelled when the page is
destroyed. Avatar downloads belong to the application so navigation does not
discard in-progress cache writes. Failed requests can be retried; the full GitHub
contributors link remains available offline or when rate limited. Avatars have
an initial fallback, and each contributor links to their profile.
