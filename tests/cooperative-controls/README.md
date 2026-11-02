# Cooperative controls integration test (VM only)

Run inside a VM with KWin, Quickshell, qdbus6 and Python 3. Build `kos_bridge` and the `kos_surface_shape` QML module first. Do not run on the host desktop.

```sh
python3 tests/cooperative-controls/run-vm.py \
  --bridge .build/cooperative-bridge/kos_bridge.so \
  --qml .build/tests/qml \
  --output /tmp/cooperative-controls-run
```

The output directory must not already exist. The test creates an isolated config/data directory and DBus session, launches nested KWin with Breeze, and loads the candidate effect. It never installs/reloads the plugin in the outer desktop.

Set `XDG_RUNTIME_DIR` and `WAYLAND_DISPLAY` for the VM graphical session. To exercise button input, also set the VM outer X11 `DISPLAY` and `XAUTHORITY` and pass `--outer-x11 :0`. The helper locates only the nested compositor output by its PID and sends X11 input events directly to it; it does not click unrelated windows.

`passed`, `client.log` and `kwin.log` provide evidence. The effect's standard read-only `debug("window-controls")` response reports surface ownership, exact hit geometry and background/sampling status. Tests assert those properties rather than claiming screenshot verification.

Pass `--apps .build/tests` to additionally launch the built Calendar, Weather and Settings
applications and assert transparent takeover. Run a separate output directory
with `--without-service` to check self-rendering when Bridge is disabled.

The list contract covers each single action, reordered pairs, empty lists, and removal of old hit rectangles. Pointer acceptance also clicks an obsolete maximize position after switching to close-only and checks that the client receives the click.

Use `--installed-layout --apps .build/tests` to copy the native module into
an isolated `config/quickshell/kos/Kos/SurfaceShape` deployment and resolve it
via `QML2_IMPORT_PATH` alone, matching desktop launchers. The default build-tree
imports cannot detect an outdated Shell copy shadowing the system module.
All three actual applications must declare their own cooperative controls.

For raster edge coverage, configure the VM Bridge build with
`-DKOS_BRIDGE_BUILD_PREVIEW=ON`, build `cooperative_light_preview`, and run it
with `QT_QPA_PLATFORM=offscreen` plus an output PNG path. It checks the production
cooperative texture at 100%, 125%, 150% and 200%, including transparent space
around the complete stroke and hover halo. This preview also runs only in the VM.

`--capture-only --installed-layout --apps .build/tests --outer-x11 :0` captures
actual Calendar/Weather/Settings controls in a 1x nested X11 output (requires Pillow).
The mode checks normal, hovered and pointer-leave frames. It waits for presented
pixels instead of assuming a fixed delay means the software-rendered VM has
finished swapping buffers. Crop comparisons include the full hover gutter but
exclude animated application content below it. Fractional-scale texture checks
remain the separate raster preview above; the X11 backend does not reliably
apply the nested compositor's scale argument.
