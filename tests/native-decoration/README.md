# Native KDecoration controls acceptance (VM only)

Requires Konsole, KWin, qdbus6, Python/Pillow and the VM outer X11 session.
No host tests or application launches.

```sh
XDG_RUNTIME_DIR=/run/user/1000 DISPLAY=:0 XAUTHORITY=/path/to/vm/xauthority \
python3 tests/native-decoration/run-vm.py \
  --bridge .build/cooperative-bridge/kos_bridge.so \
  --decoration .build/native-decoration/kos_decoration.so \
  --output /tmp/native-decoration-acceptance
```

The output must not exist. Candidate plugins run in an isolated nested compositor,
configuration/data directory and DBus session. A separate Konsole uses an already
finished command so testing close cannot interrupt a user's terminal work.

Assertions cover native button ownership despite forced legacy overlay rules,
zero overlay painting/sampling, actual maximize/restore/minimize/close clicks,
right-click exclusion from overlay adjustment, KDE left/right layout changes,
shared always/hover glyph mode, and controls remaining visible with Bridge
unloaded. Screenshots are captured from only the nested compositor output and
wait for presented pixels. Native input/geometry diagnostics and screenshots
are saved alongside the passed marker.
