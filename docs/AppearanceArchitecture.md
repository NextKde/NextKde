# Appearance architecture

[简体中文](AppearanceArchitecture.zh-CN.md)

For AI contributors. Read [project boundaries](ProjectArchitecture.md) and
[window rendering](WindowAppearance.md) before changing presentation or compositor code.
This is the current design, not a runtime acceptance report.

## Ownership and source entry points

| Owner | Contract |
| --- | --- |
| `shell/desktop/modules/common/AppearanceConfigService.qml` | Validated Shell appearance settings, migrations and snapshots |
| `AppearanceTokens.qml` in the same directory | Derived visual tokens, version 9; consumers use tokens rather than duplicate style branches |
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

`Quickshell.stateDir/appearance/config.json` is currently written with schema **30**; source
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
