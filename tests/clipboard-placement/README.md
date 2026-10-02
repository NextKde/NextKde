# Clipboard placement

Super+V takes one position snapshot before the panel takes keyboard focus.
The KWin input effect prefers an enabled text-input-v3/v2 caret belonging to
the original window, otherwise the current pointer. The shell selects the
containing output, opens below the anchor, flips above it at the bottom edge,
and clamps to that output's placement area with a 12 logical-pixel margin.
Application/window search keeps its existing centered placement.

This requires the updated shell, platform daemon and KWin input effect.
An absent/older effect or daemon preserves centered placement with a bounded
180 ms shell fallback. Apps using XWayland or a direct input-method integration
may not supply Wayland caret geometry; they use pointer placement. The feature
does not read text, change input-method settings, or poll cursor movement.

## Tests

Pure geometry (no graphical session needed):

```sh
node tests/clipboard-placement/test_geometry.mjs
```

Real QML controller/window, with a fake platform on a private bus and a
headless virtual KWin (requires Quickshell, kwin_wayland and dbus-run-session):

```sh
python3 tests/clipboard-placement/run.py
```

It checks caret and edge placement, unchanged window-search placement, fresh
reopening snapshots, repeated toggles, mode changes, missing/slow responses,
late replies, output loss, reserved-bar coordinates and guarded paste. Neither the user's clipboard nor session
configuration is used. Geometry and QML tests are also registered with CTest.

To exercise real Wayland text-input geometry and the built KWin effect, add
`KOS_TEST_INPUT_EFFECT`. This optional probe additionally requires Python
`dbus` and `gi`; its editor explicitly selects Qt's Wayland input context only
inside the test session. Add `KOS_TEST_PLATFORM_BINARY` to verify the actual
daemon's JSONL-to-D-Bus forwarding and uncached pointer fallback as well:

```sh
KOS_TEST_INPUT_EFFECT="$PWD/.build/input/kos_context_menu_input.so" \
KOS_TEST_PLATFORM_BINARY="$PWD/.build/tests/platform/kos-platform" \
python3 tests/clipboard-placement/run.py
```

Build the effect separately with
`cmake -S integrations/kwin/context-menu-input -B .build/input -G Ninja`
and `cmake --build .build/input --parallel 1`. The normal root build supplies
the platform executable. These tests load the effect only into the private
compositor; they do not install or reload any plugin in the running desktop.
