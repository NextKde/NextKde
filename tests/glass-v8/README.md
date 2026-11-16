# v8 glass comparison

Run on a disposable VM graphical session after installing both the native QML
bridge and the KWin effect, and logging out/in. Do not reload either plugin into
a running process. Use the project's local VM skill for sync/build/install/login.

Launch `quickshell --path tests/glass-v8 --no-color` with the built/installed
`Kos.SurfaceShape` module in `QML_IMPORT_PATH`. Capture the desktop with the VM
skill; retain the process PID and stop only this comparison instance afterwards.

The fixture supplies a striped, colored background and 21 independent surfaces:

- Row 1: Gaussian sigma 0, 4, 8, 12, 16, 24, 32 logical px, no tint or scrim.
- Row 2: fixed sigma 12, tint opacity 0, .05, .1, .2, .35, .55, .8.
- Row 3: fixed sigma 12 and tint .08, complete-effect opacity 0 through 1.

The deliberately incorrect 1×1 legacy blur region must not clip v8 shapes.
Compare coarse color boundaries and fine stripes separately. The second row
should retain the first row's sigma-12 spatial filtering while changing color;
the third row intentionally mixes the sharp original background back in.

IPC target `glass-v8` exposes `sigma(real)` (-1 restores the matrix),
`hide(bool)`, `toast(bool)`, `rebuild()`, `animate()` and `quit()`. Use the instance's config path with
`quickshell ipc --path tests/glass-v8 call glass-v8 ...`.

Also exercise the real wallpaper preview (expanded/collapsed, toast hidden/shown),
Dock hover, notifications and fixed capture. Read the Quickshell and KWin logs.
A screenshot is visual evidence, not proof of animation timing or performance.

For negotiated legacy versions, set `KOS_SURFACE_SHAPE_MAX_VERSION` to 1..7 on
the comparison process; v8-only requests must disappear from WAYLAND_DEBUG logs.
Legacy clients retain Kawase filtering and the old explicit-region contract.
Do not expect the deliberately wrong region in this v8 fixture to work on v7.
