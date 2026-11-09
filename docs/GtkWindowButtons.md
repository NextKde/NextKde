# Native GTK window buttons

[简体中文](GtkWindowButtons.zh-CN.md)

GTK and Qt share **KOS window appearance** and **Window button icons** in Settings.
There is no separate GTK enable preference or user installation step. Enabling
the appearance switch installs standard GTK 3 `GtkHeaderBar` and GTK 4
`GtkWindowControls` traffic lights; disabling it restores the prior GTK configuration.
Green maximizes/restores, yellow minimizes and red closes, using the native GTK
actions and accessibility semantics. Green does not enter fullscreen.

The shared `window-appearance.json` enabled state and `window-buttons.json`
`default.glyphMode` remain authoritative. Always/hover icon mode applies to both
toolkits; hover mode hides only symbols, retaining the colored circles. GTK
applications must restart to read updated CSS. Logging in again applies both the
existing Qt decoration change and the GTK styles. Other toolbar buttons retain
their theme.

## Ownership and lifecycle

`WindowSettings` invokes its embedded GTK adapter and CSS resources with the
requested shared state. The installed Settings binary does not depend on a
checkout. Python 3 is a runtime dependency; GSettings is used when available.
`installDefaults()` also reconciles GTK during installation/upgrades while
preserving a saved opt-out or an externally selected non-KOS decoration.
`--restore-window-defaults` restores GTK as part of the same existing uninstall
path. The internal sync operation never reloads a compositor during installation.

Styles are appended as one marked block in `gtk-3.0/gtk.css` and `gtk-4.0/gtk.css`
under `$XDG_CONFIG_HOME`. Buttons default to the right (`:minimize,maximize,close`)
in `settings.ini` and, when available, `org.gnome.desktop.wm.preferences button-layout`.
An existing right-side layout is retained, including its menu placement and button
order. Upgrades recover the original right-side layout from earlier integration
backups instead of retaining the previously forced left layout. This is a
desktop-wide native layout; applications may override it. Chromium consumes this
setting for its own controls and continues to use the right-side KOS fallback
overlay; it is not excluded or moved to a native-only path. Recovery data lives in
`kos/gtk-buttons-state.json`. Disabling restores original bytes if unchanged;
otherwise it removes only the managed CSS block and restores the managed layout
only if it still has NextKde's value. Later unrelated user changes are preserved.
Symbolic links managed by declarative configurations are not overwritten. Errors
are returned to Settings instead of silently accepting an unsuccessful sync.

## Application compatibility and fallback

Standard GTK 3 windows now use an installed GTK module, not an application-name
allowlist. `libkos-gtk-window-controls.so` inspects the actual GtkHeaderBar and
visible standard close button. It declares client drawing over the existing
Wayland controls protocol, or an event-driven X11 property on XWayland. KWin
then drops overlay input, rendering and background sampling. Removing or hiding
the native buttons revokes the declaration and restores the existing fallback.
Widget events drive detection; no process, pixel or title-bar polling is used.

Fresh installs and upgrades deploy the module with Settings. The shared switch
maintains a marked Plasma startup fragment under
`plasma-workspace/env/kos-gtk-window-controls.sh`, preserving other GTK_MODULES
entries. Log out and back in once after the first module installation/upgrade;
subsequently launched standard GTK 3 applications participate automatically.
Disabling restores managed styles/startup configuration; existing processes
retain their startup environment until restarted, and a new login fully refreshes
it. Saved opt-outs survive upgrades. Missing installed modules cause an explicit
error instead of silently reporting style-only installation as complete.

GTK 4 does not load GTK 3 modules: it receives the common CSS but automatic GTK 4
ownership is not claimed by this implementation. Unknown/custom windows,
Chromium/Edge custom frames, and sandboxed applications unable to load the host
module keep the overlay fallback. Server-decorated windows keep native KDecoration
controls. No Flatpak permissions are changed.

Legacy compatibility rules remain available after application verification; automatic GTK 3 detection does not need them:

```sh
./tools/kosctl gtk-buttons adapt org.example.Application
./tools/kosctl gtk-buttons adapt org.example.Mixed --title 'Standard window'
./tools/kosctl gtk-buttons fallback org.example.Application
```

`adapt` adds an owned `nativeGtkControls: true` rule in `kos/window-buttons.json`
matching one exact app ID / WM_CLASS token and normal windows only. Unknown
applications and dialogs retain the overlay. SSD retains its KOS panel even if
its app matches. Qualified CSD windows skip both overlay painting and input
interception. Within legacy qualification rules, more specific user rules may set
`nativeGtkControls: false` for exceptions. Equally specific user rules take precedence; saved geometry does not
change qualification. Never put `nativeGtkControls` in `default`.

The low-level `gtk-buttons install/uninstall` commands remain available for
isolated developer tests, not as a separate user enable flow. Requalify after
application/toolkit or sandbox packaging changes.

## VM acceptance

All builds, tests and application launches run only in the VM, never on the
maintainer host. Build Settings and KOS Bridge, then run:

```sh
python3 tools/tests/test_gtk_window_buttons.py
ctest --test-dir .build/tests -R 'kos-settings.window-config|kos-window.gtk-buttons-install|kos-settings.window-page' --output-on-failure
ctest --test-dir .build/gtk-buttons -R rules_test --output-on-failure
python3 tests/gtk-buttons/run-vm.py --plugin .build/gtk-buttons/kos_bridge.so --settings .build/tests/apps/settings/kos-settings --output /tmp/gtk-buttons-review
```

The nested KWin runner uses the candidate plugin and an isolated configuration.
With `--settings`, styles are enabled through the real shared default-install
backend, using embedded resources. It runs GTK 3/4 in light/dark appearance and
checks native controls, maximize/restore (not fullscreen), minimize and close.
It requires PyGObject and the corresponding GTK introspection packages.

Wayland does not report minimized state to clients; `minimize-probe.js` observes
it in the nested compositor. The standalone `native_controls.py` accepts
`--kwin-log PATH`, `--dark` and `--hold`; without the probe, minimize-state
assertions explicitly skip. Inspect pointer clicks, fallback, dialogs, SSD,
focus states and scaling separately. Fixture acceptance is not a claim of
compatibility with arbitrary third-party applications.

Firefox browser chrome requires its own [native adapter](FirefoxWindowButtons.md), following the same switch after profile registration.

## Automatic GTK 3 ownership acceptance

Build the module with Settings (GTK 3 development files and wayland-scanner are
required), then run in the VM with an outer X11 display and Remmina installed:

```sh
python3 tests/gtk-buttons/automatic-vm.py \
  --plugin .build/cooperative-bridge/kos_bridge.so \
  --settings /path/to/installed/bin/kos-settings \
  --output /tmp/gtk-auto-fresh
```

Repeat with `--upgrade` and a fresh output path to exercise existing integration
state. The runner sources exactly the generated Plasma startup fragment and
asserts that no application rules were created. It checks Wayland and XWayland
ownership, native-button removal/restoration, and real Remmina with isolated data
and no saved connections. It captures only the nested compositor output.

### GTK 3 button appearance

The module draws existing GtkHeaderBar buttons, preserving GTK input and accessibility without an overlay. Lights use the KWin decoration’s 14 px diameter, 0.75 px border, colors and glyph proportions, inside a minimum 28 px hit target. The green button switches between maximize and restore wedges, and glyph visibility follows the shared setting. Removing the managed style returns drawing to GTK.
