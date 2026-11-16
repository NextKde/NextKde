# Input method popup motion

The candidate panel and language tip use `InputMethodPresentation.qml` to
retain their last complete content and caret anchor until exit finishes.
Same-turn Kimpanel updates are coalesced; content updates while open do not
restart the entrance. The shared `PopupMotion` reverses from the current
progress when the user switches again during exit.

Candidates enter in 210 ms and exit in 160 ms with a 4% contraction.
Language tips enter in 190 ms and exit in 140 ms with a 10% contraction.
Text, shadow and compositor material share the reveal progress. Candidate
size changes blend over 160 ms and the selection plate follows smoothly,
with text anchored at the padded top left.
Caret tracking remains immediate and the input region closes as soon as exit
starts. Screen handoff fades the old panel at its previous anchor.

The empty full-screen layer surface stays mapped with an empty input region;
only the card is revealed. This prevents window-map effects from moving the
whole surface. Each opening resolves a fresh compositor caret before revealing
content, with a 180 ms upper bound and cancellation of late replies. Missing
spot coordinates use the pointer/window fallback rather than absolute `(0, 0)`.

Run **only in a dedicated VM or hosted CI**:

```sh
node tests/inputmethod/run.mjs /usr/lib/qt6/bin/qmltestrunner
node shell/desktop/modules/inputmethod/test_inputmethod_placement.mjs
node shell/desktop/modules/inputmethod/test_inputmethod_status_dismissal.mjs
python3 tools/tests/test_fcitx_panel_install.py
```

The fixture exercises the production QML presentation and animation, including
exit snapshots, reversal, coalescing, screen handoff and empty payloads.
It does not verify KWin glass rendering. Real VM acceptance must also check
typing and committing, rapid Chinese/English switches, horizontal/vertical
candidate layouts, and screen-edge placement with the installed Shell.

Unified-panel acceptance must retain `QT_IM_MODULE=fcitx` in Kate/Qt and
`GTK_IM_MODULE=fcitx` in GTK 3/4, on Wayland and (where supported) XWayland.
Enable once, type `nihao`, select by keyboard and pointer, and confirm Chinese
commits without a second client-side candidate window. Disable takeover while
the application remains open and confirm the original candidate UI and input
still work. Stop the frontend and check `org.nextkde.FcitxPanel1.Active` becomes
false and `ContextCount` returns zero. The bridge test additionally covers
missing/incompatible adapters, backup failures and durable crash recovery.
No test should rewrite the application's input-module environment to make the
panel pass. Applications with no Fcitx input connection are outside this check.

The same runner also exercises presentation preferences: loading and saving
NextKde-only state, rejecting engine/configuration keys, reporting save
failures, adaptive layout, unchanged click indices, annotation visibility,
font sizing, contrast, bounded long lists and reduced motion. VM acceptance
should change these options while composing and confirm the Fcitx config
file is unchanged and the selected candidate still commits normally.

Launcher acceptance must start the real Shell with an inherited
`QT_IM_MODULE=fcitx QT_IM_MODULES=fcitx` environment. Its entrypoint pragmas
must still select the native Wayland input context. With takeover enabled,
type `nihao` in launcher search: the liquid glass panel must appear at the
search caret and Space must commit `你好`. Repeat with takeover disabled to
check native Fcitx fallback. Run the same check in source/dev and installed
launch modes; hot reload is insufficient for input-context changes. Capture
the candidate panel without opening a screenshot selection overlay, which
can steal the launcher's keyboard focus.

The dedicated `input method motion` workflow runs these checks on candidate
branches. CTest also registers them in the logic and headless groups.
For application compatibility patterns and troubleshooting (e.g. Wayland text-input requirements and bundled toolkit workarounds), see the [Input Method Integration Guide](../../docs/InputMethodIntegration.md).

[中文](README.zh-CN.md)
