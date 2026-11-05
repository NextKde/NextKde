# Firefox integration acceptance (VM only)

Requires a VM graphical session, nested KWin, qdbus6, gsettings, Firefox and Mozilla's `marionette_driver` Python package. Build the candidate Bridge first. Never run this harness or the installer unit tests on the host desktop.

```sh
XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 \
python3 tests/firefox-buttons/run-vm.py \
  --bridge .build/cooperative-bridge/kos_bridge.so \
  --firefox /path/to/firefox \
  --output /tmp/firefox-buttons-acceptance
```

The output must not exist. Optional `--gnome-theme /path/to/firefox-gnome-theme` installs that theme into the throwaway profile, including a theme-owned user.js symlink. The harness uses isolated config, data, DBus and browser profiles; it does not copy personal browsing data or install into the outer compositor.

Checks cover original chrome button dimensions/colors, always/hover glyphs, real light/dark themes, disabling the shared switch, native maximize/restore/minimize/close, and Bridge diagnostics showing no overlay or sampling. A positive control removes qualification to prove the overlay would otherwise be rendered. With automatic background sampling enabled, it then creates/removes unrelated configuration files and checks that the legacy panel remains present throughout; this guards against cooperative directory watchers clearing every window's tint cache. Screenshots and evidence.json accompany the passed marker. Marionette's striped address bar is Firefox's automation indicator.

Installer and embedded Settings coverage is registered as `kos-window.firefox-buttons-install` and `kos-settings.window-install`. Run those CTest entries only in the VM as well.
