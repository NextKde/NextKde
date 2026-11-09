# Appearance architecture

[简体中文](AppearanceArchitecture.zh-CN.md)

For AI contributors. Read [project boundaries](ProjectArchitecture.md) and
[window rendering](WindowAppearance.md) before changing presentation or compositor code.
This is the current design, not a runtime acceptance report.

## Ownership and source entry points

| Owner | Contract |
| --- | --- |
| `shell/desktop/modules/common/AppearanceConfigService.qml` | Validated Shell appearance settings, migrations and snapshots |
| `AppearanceTokens.qml` in the same directory | Derived visual tokens, version 10; consumers use tokens rather than duplicate style branches |
| `IconAppearanceService.qml`, `BundledIcons.qml`, `BundledIcon.qml`, `SystemIconResolver.qml` | Icon mode/persistence, named bundled assets and centralized system-theme fallback |
| `shell/desktop/DesktopEnvironment.qml` | `appearance-settings` IPC endpoint |
| `apps/settings/` | Separate process; edits through IPC, never imports Shell internals |
| `shared/qml/colorize/` | Portable pure-JS palette/HCT algorithms; no dependency on Quickshell |
| `shared/qml/controls/` and Shell common components | Reusable surfaces/controls that consume explicit theme inputs |

`AppearanceConfigService` owns Shell configuration; `AppearanceTokens` derives colors, geometry,
opacity and motion. Shell style (`windows12` / `macos` / `material`), widget style, glass preset
(`liquid` / `soft` / `frosted`), bar integration/layout/visibility and Dock configuration are
separate choices. Do not reset Dock pins, sizes or independent state when changing style.
Standalone app preferences remain separate; see [project context](../PROJECT_CONTEXT.md).

## Persistence and IPC

`Quickshell.stateDir/appearance/config.json` is currently written with schema **31**; source
`serialize()`/load migrations are authoritative for the full field set. Do not copy a partial
JSON example over a user's whole file. Keep old-version migration, per-preset optical values,
validation and range clamping. Unsupported style values must not become unvalidated runtime state.
Icon settings use separate `appearance/icon-appearance.json` (schema 1), including the one-time
legacy Dock migration. Saving is debounced through `JsonConfigStore` → platform `state.write`
→ `QSaveFile`, rather than a QML shell command.

Settings calls `appearance-settings` snapshot/update operations and receives a complete snapshot.
Check the endpoint when adding a setting; expose bounded values, preserve compatibility aliases
and handle unavailable Shell/platform services. Glass style changes apply the complete preset;
Material has its own blur policy. A glass-strength reset does not reset every user preference.

## Color and contrast invariants

Use `AppearanceTokens.isDarkTheme` and semantic content tokens, especially `content.glassInk`.
Do not pick foreground ink directly from the system dark-mode flag. When
`glassFollowsAppearanceMode` is false, dark glass can remain on a light desktop and still needs
light ink. Separate material fill opacity, scrim and background blur; zero tint/fill opacity does not
imply zero blur. Protocol material opacity fades the complete finish, including blur. See protocol ownership in [window appearance](WindowAppearance.md).

Material palettes are generated locally in `shared/qml/colorize/`: `monet` uses CAM16/HCT,
while `chinese` and `japanese` select traditional-color data with the shared contrast policy.
Keep sRGB byte rounding, HCT gamut handling and contrast regression tests together; do not replace
the algorithm with external `matugen` processes or approximate Lab conversion. Extract wallpaper
colors from the original image, not Plasma's black/white placeholder. Resolve Plasma's wallpaper
configuration through the current `plasmashellrc` ShellPackage, not a hardcoded old appletsrc.

The source colorize directory is not a compiled `Kos.Ui` module. Keep source aliases, `qmldir`,
resource deployment and relative imports working in both Shell and Settings. Portable app/shared
code must not import Quickshell-specific adapters. Material card surfaces/flower blur geometry
use shared components; do not scatter individual style checks throughout every control.

## Icons, geometry and motion

Register Shell-owned imagery by stable name in `BundledIcons`; render through `BundledIcon` or
its registry source. Do not depend on workstation absolute paths or font glyphs. Application
icons, media art and file thumbnails follow their own contracts. System-theme exceptions such as
the Dock trash icon resolve through `SystemIconResolver`, with centralized candidates and bundled fallback.

Tray identity resolution lives in `modules/bar/TrayIdentity.mjs`: explicit tooltip/title
labels and app-specific IDs win over daemon fallback names keyed by a shared generated ID.
Two anonymous entries sharing an ID remain unresolved; topology changes invalidate cached
names and stale in-flight replies. Monochrome templates use exact app aliases, preserve live
attention/status artwork, and fall back to original artwork when a replacement cannot load.

Use token geometry and motion values consistently across Dock, bar and widgets. Dock window-animation
targets use stable layout slot centers and static icon size in compositor-global coordinates;
hover magnification must not move a minimize target. Keep desktop file spacing in
[DesktopIcons](DesktopIcons.md). Material surfaces and continuous compositor corners have different
rendering owners; a visual style change must not duplicate clipping or shadows.

## Launcher folder focus

`modules/applauncher/AppLauncherWindow.qml` blurs the root application page while a
folder is open, rather than painting a black dimming overlay. The folder page is
outside the filtered root-page subtree, keeping its icons, labels and input sharp.
A 220 ms transition drives the root-page `MultiEffect` (maximum blur radius 32)
and raises the glass backdrop sigma to at least 20. Stronger configured blur is
preserved; closing restores the ordinary blur binding without changing settings.
Material retains its existing compositor blur policy. The root-page layer is
released after the folder teardown and blur transition finish. The input-only
outside-click dismiss area and existing folder interactions remain in place.

## Shell text rendering

`common/ShellText.qml` uses platform-native rendering for stationary small text,
matching the bar's native labels. `GlassText`, context-menu rows, launcher labels
and Dock name tooltips share this policy. Notification/history, Control Center,
Quick Search, desktop widgets and Dock information popups inherit it through
`GlassText`. Font families, sizes, weights and system hinting preferences remain
owned by their existing callers/platform settings.

`ShellText` tracks its own and ancestor Item scale/rotation and uses distance-field
rendering while transformed; it returns to native rendering at rest. A host using
an explicit Scale/Rotation transform list must set `scalableRendering` while that
transform is active. Launcher search/rename inputs follow their motion wrappers
and use native rendering at rest too.

Context menus mask the full content during capsule reveal and for overflowing
lists, whose partially scrolled rows can cross the corners. Settled menus that
fit draw their inset rows directly into the window. `LiquidGlassPanel.maskContent: false`
keeps the QML body independently masked, so Material/fallback corners remain
shaped without rasterizing text into the same offscreen texture.

## Verification and review

Run tests only in VM/CI per [Development](Development.md). Cover migrations, snapshot/IPC values,
light/dark/system themes, dark glass on a light desktop, all glass/material/color schemes,
bar/Dock integration, source/installed module paths, icon fallback and reduced motion.
Review fullscreen/maximized/mixed-scale window behavior separately in [WindowAppearance](WindowAppearance.md).
A passed offscreen token test is not proof of live blur, GPU cost or multi-display behavior.
For text changes, compare Chinese/Latin labels and inputs at 100%, 125%, 150%
and 200% output scales, including moving between outputs. Exercise menu reveal,
submenus/scrolling, launcher search/folders/edit/drag and open/close reversal;
check both settled text and moving text in glass and Material themes.

## System fonts

Settings → Theme → Fonts is a secondary page (route 14); the Theme row has only
its name and a trailing `>`. Navigation history and the Theme sidebar selection
remain active on the secondary page. `FontSettingsPage.qml` receives an explicit
`FontSettings` backend and the existing appearance bridge.

`FontSettings` loads Plasma's `kcm_fonts` backend through `KF6::KCMUtilsQuick` in
the Settings QML engine, without launching System Settings. KCMUtils' host item is
initialized once, detached and hidden, to establish the preview-provider context.
The native NextKde form exposes general, fixed-width, small, toolbar, menu and
window-title fonts, family/style/size selection and previews, selective adjustment
of all fonts, anti-aliasing and its excluded size range, sub-pixel rendering,
hinting and X11-only forced font DPI. KDE owns defaults, immutable settings,
fontconfig persistence, GTK/Xft exports and application refresh notifications.
This is an in-process KCM adapter, not a new command-execution or IPC path.
The runtime requires the Plasma workspace font KCM; missing/incompatible modules
show an unavailable state. Pending edits survive page navigation and are saved
with Apply, discarded with Reset, or replaced with KDE defaults before applying.

The independent “Desktop follows system font” switch uses `appearance-settings`
IPC and persists as `useSystemFont` (default false) in appearance schema 31.
`SystemFontService` watches `kdeglobals`; `AppearanceTokens.typography` projects
the selected general family into Shell text/display roles. Desktop pixel sizes
stay per-surface and the emoji role stays `Noto Color Emoji`. Successful reads
without `font=` clear the previous family; failed reads preserve the last value.

Regression coverage: `kos-settings.fonts` loads the real KDE backend with isolated
user roots and a private D-Bus session, `kos-settings.page-contracts` covers the
secondary route and asynchronous Shell switch, and `kos-ui.system-font-policy`
plus `kos-shell.system-font` cover parsing and resolved Shell families. All are
registered in the CI inventory. Runtime and visual acceptance must run in a VM
or hosted CI, never on the maintainer workstation.
