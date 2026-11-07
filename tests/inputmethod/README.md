# Input method popup motion

The candidate panel and language tip use `InputMethodPresentation.qml` to
retain their last complete content and caret anchor until exit finishes.
Same-turn Kimpanel updates are coalesced; content updates while open do not
restart the entrance. The shared `PopupMotion` reverses from the current
progress when the user switches again during exit.

Candidates enter in 150 ms and exit in 120 ms with a 2.5% contraction.
Language tips enter in 180 ms and exit in 140 ms with an 8% contraction.
Text, shadow and compositor material share the reveal progress. Candidate
size changes settle over 100 ms, with text anchored at the padded top left.
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
```

The fixture exercises the production QML presentation and animation, including
exit snapshots, reversal, coalescing, screen handoff and empty payloads.
It does not verify KWin glass rendering. Real VM acceptance must also check
typing and committing, rapid Chinese/English switches, horizontal/vertical
candidate layouts, and screen-edge placement with the installed Shell.

The dedicated `input method motion` workflow runs these checks on candidate
branches. CTest also registers them in the logic and headless groups.
For application compatibility patterns and troubleshooting (e.g. Wayland text-input requirements and bundled toolkit workarounds), see the [Input Method Integration Guide](../../docs/InputMethodIntegration.md).

[中文](README.zh-CN.md)
