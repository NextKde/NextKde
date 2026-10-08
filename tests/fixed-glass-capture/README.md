# Fixed capture with an animated glass outline

Build the client and effect, then run the isolated compositor test:

```sh
cmake --build .build/kosctl --target kos_surface_shape -j 4
cmake --build .build/kosctl/kwin-effects-glass --target glass -j 4
python3 tests/fixed-glass-capture/run.py
```

The runner stages the built effect in a temporary plugin directory and starts
KWin with its own D-Bus session, virtual output, and configuration. It never
installs or reloads the running desktop's effect. Unrelated window-opening
animations are disabled so the test exercises the surface's outline animation.

The real effect trace must report one 832 × 532 texture-chain allocation,
unchanged capture bounds, and more than ten distinct visible outlines through
expansion, contraction, and expansion again. The existing legacy blur-region
C++ test also checks fixed capture bounds through 61 intermediate shapes,
nonzero coordinates, disabled shapes, and reset to the legacy policy.

Protocol v5 adds a fixed capture rectangle to the existing shape metadata.
Clients send it only at the negotiated version. Older compositors retain the
stationary full-size launcher backdrop while content animates. For production,
the new KWin plugin loads at the next session start; do not reload the desktop's
in-use plugin to run this test.

The production launcher keeps its glass outline and capture bounds stationary
and animates application tiles with `LauncherIconMotion.qml`. On the
`codex/launcher-glass-fade` variant, protocol v6 additionally fades the complete
compositor material over 180 ms on opening and 260 ms on closing. The QML-painted
fallback fades separately; icon opacity stays independent. An older plugin keeps
its stationary glass finish without this fade. Both the native bridge and KWin
plugin need rebuilding and installing for the v6 compositor fade to take effect.
The motion controller retains the panel during the 300 ms tile closing animation. The
fixed-capture protocol remains available to other clients; this isolated test
exercises that capability independently of the production launcher's policy.

Fixed capture avoids resizing the texture chain; it does not freeze background
updates or remove the per-frame blur work. The application catalog remains
unrestricted; the 50-tile prototype is a separate repeatable motion fixture.
