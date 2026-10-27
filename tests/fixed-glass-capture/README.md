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

The fixture declares a fixed 832 × 532 capture and sigma 12. With v8, the
Gaussian kernel adds a 3σ margin on each side, producing one 904 × 604
texture-chain allocation; legacy protocols retain 832 × 532. The runner reads
the fixture's capture configuration and negotiated capability to calculate the
expected size and position. The real effect trace must report unchanged
capture bounds and more than ten distinct visible outlines through
expansion, contraction, and expansion again. The existing legacy blur-region
C++ test also checks fixed capture bounds through 61 intermediate shapes,
nonzero coordinates, disabled shapes, and reset to the legacy policy.

Protocol v5 adds a fixed capture rectangle to the existing shape metadata.
Clients send it only at the negotiated version. Older compositors retain the
stationary full-size launcher backdrop while content animates. For production,
the new KWin plugin loads at the next session start; do not reload the desktop's
in-use plugin to run this test.

This fixture verifies fixed capture bounds, not launcher transition timing or
completion events. Keep launcher motion coverage in the dedicated launcher tests
and the [50-tile prototype](../launcher-reveal-prototype/README.md).

Fixed capture avoids resizing the texture chain; it does not freeze background
updates or remove per-frame blur work while the material is visible. Run all
builds and checks only in a VM or hosted CI per
[Development](../../docs/Development.md).
