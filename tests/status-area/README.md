# Status area regression tests

`logic.mjs` exercises the production editor layout and traffic-history helpers:
logical widths from 320 to 1280 pixels, cross-row reordering, the pinned final
card, bounded history, invalid rates, and interface changes. CTest registers it
as `kos-shell.status-area-state` with the `logic` label, and the CI inventory
requires it.

`run.mjs` requires Quickshell, QtTest and a Wayland session. It loads production
components in a real window, isolates configuration/state/runtime directories,
and replaces platform transport with read-only fixture responses. It exercises
ordering and visibility, the mapped narrow editor, a pointer drag between rows,
the mapped traffic popup, Escape and outside-press dismissal, baseline/accepted
sample callbacks, late responses after an interface change, and disconnection.
It never calls the user's installed platform daemon. CTest registers it as
`kos-shell.status-area` with the `ui` label; the compositor-independent CI job
does not claim to cover this Wayland test.

```sh
cmake -S . -B .build/status-area -G Ninja \
  -DKOS_BUILD_PLATFORM=OFF -DKOS_BUILD_KWIN_PLUGINS=OFF -DKOS_BUILD_SPATIAL=OFF
ctest --test-dir .build/status-area -R '^kos-shell.status-area-state$' -V
# In the authorized graphical validation environment:
ctest --test-dir .build/status-area -R '^kos-shell.status-area$' -V
```

The service emits `trafficSampled` only after completing a valid rate calculation.
The panel records those events while open, retaining at most 60 samples for the
current device. Opening it starts a fresh history; disconnecting closes it.
