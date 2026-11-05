# Stage sidebar desktop switching

Run project verification in a dedicated VM or CI as described in
[Development](../../docs/Development.md).

The offscreen fixtures execute production visibility bindings, the desktop
controller and sidebar integration handlers:

```sh
node tests/stage-visibility/run.mjs /usr/lib/qt6/bin/qmltestrunner
```

For the compositor path, build the Stage plugin against the VM's KWin SDK:

```sh
cmake -S kwin/kwin-effects-stageanim -B .build/stage-static -G Ninja
cmake --build .build/stage-static
python3 tests/stage-visibility/static_compositor.py \
  .build/stage-static/src/stageanim13.so \
  --quickshell quickshell --output .build/stage-static-evidence
```

The runner starts a virtual KWin and a fixture window on a private D-Bus
without service activation directories, using temporary configuration, state,
runtime and plugin paths. It does not load plugins into the existing compositor.
The tested plugin must provide `Effects.debug("stageanim13", "live-cards")`;
this read-only diagnostic reports card geometry, opacity and render/paint
counters without performing rendering or changing state.

The graphical checks require a real slide to run, verify that fixed opaque
cards continue painting during it, and verify immediate card replacement
without the normal missing-card grace or entrance fade. Logs and per-sample
JSON are retained in the output directory. Shader or startup failures fail
the test. The private compositor and fixture client are stopped afterward.

With a full plugin-enabled testing build and KWin, Quickshell, qdbus6 and
dbus-run-session available, this runner registers as the `ui` test
`kos-stage.static-desktop-compositor`. The pure fullscreen/lock policy test
registers as `kos-stage.desktop-policy` even in builds without KWin plugins.

Installed-session acceptance still requires logout/login after installing
the new native plugin. Restarting Shell alone uses the old compositor guard.
Verify clear-to-clear desktops retain the strip during navigation, and that
fullscreen/overlap retraction follows the destination after switching ends.
Keep Overview and screen-lock suppression intact. Do not hot-reload KWin plugins.
