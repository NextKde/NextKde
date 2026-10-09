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

The `codex/launcher-compositor-reveal` variant adds protocol v7: the client sends
an enabled flag, an open/closed endpoint, duration and request serial. KWin
advances the OutCubic progress on compositor frames, interpolates a bottom-center
160 × 64 capsule to the final SDF outline, and composites the entire client
surface at 0.8→1 scale with a fade. No per-icon entrance jobs or client-driven
per-frame geometry updates are used on this path.

Capture bounds remain at the final rectangle throughout the transition. The
controller stays enabled at rest, so reaching progress 1 does not switch shader
paths. On closing, a transparent declaration remains authoritative until the
client's blur-region commit catches up; zero-opacity material skips capture and
blur work. Serial-tagged completion events retire the panel instead of a fixed
client timer, and reversals continue from the current compositor progress.

Both the native bridge and KWin plugin must be rebuilt and installed. An older
plugin, fullscreen launcher or QML-painted theme uses one whole-content
ScaleAnimator/OpacityAnimator group and one material-opacity scalar; completion
is tied to the animation jobs. The 50-tile prototype remains an independent
reference fixture. The isolated test above exercises fixed capture, not the new
v7 timeline or completion events.

Fixed capture avoids resizing the texture chain; it does not freeze background
updates or remove per-frame blur work while the material is visible.
