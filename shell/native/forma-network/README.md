# Native Forma network panel

`NetworkTrafficPanel.qml` is the production Quickshell popup host. Its content
is `Kos.FormaNetwork.NetworkTrafficView`, a C++ `QQuickRhiItem` containing the
original Forma controls, linked from the pinned Forma library. This is not a
QML restyling or a screenshot texture.

## Components and ownership

`networkscene.cpp` uses Forma `VStack`, `HStack`, `Spacer`, `Divider`, `FormRow`,
`ScrollView`, `Label`, `Image` and `Button`. All layout, native scroll physics, pointer
capture, focus and button animations come from that library. Only the traffic
graph, connectivity grid and small color indicators use custom native
`Widget`/`Canvas` drawing. The outer card has no native background; NextKde's
existing `LiquidGlassPanel`/KWin protocol remains the material owner.

Layout metrics follow Stats' `Kit/constants.swift`, `Kit/helpers.swift` and
`Modules/Net/popup.swift`: 264-point content, 8-point margins, 42-point header,
30-point section headers and 22-point data/process rows. Upload is red above
the graph baseline; download is blue below it, with independent maxima. The
layout reference is Stats commit `573145558badb690728e39f3b2dcdb490e2ea731`.
Stats is MIT licensed; its copyright/license is retained in `Stats-LICENSE`.
No Swift source or Apple artwork/font is compiled into this module. Forma
supplies its own original components and embedded Inter font under its GPL/OFL
licenses. Glyph/spacing differences from macOS remain possible.

## Rendering and clarity

The old experimental FBO was a fixed 253×820 texture displayed on a 1.5× screen.
This module leaves QQuickRhiItem's pixel buffer sizing automatic: a 280×900
logical view on that screen renders to 420×1350 physical pixels. Moving or
resizing the item regenerates its target and glyphs at the effective DPR.
There is no fixed-resolution capture texture, CPU readback, or a second QML
offscreen mask resampling the text during normal rendering.

`qrhidevice.cpp` adapts Forma's existing rendering-hardware interface to Qt's
QRhi device/command buffer. Its instanced SDF drawing, Painter, FreeType atlas,
text system and shader formulas are reused. Frames render into GPU textures
and copy to the Qt-owned color buffer without filtering or CPU readback.
`prepare.py` generates only the small window/frame embedding API and converts
uniform declarations to Qt shader packs; it checks the expected upstream API
and leaves the dependency source unchanged.

Both OpenGL 3.3 and Vulkan use the same code. The QML plugin requests a suitable
desktop GL format before creating popup windows, without selecting a backend.
Qt's threaded render loop is supported: the native tree lives on the render
side; GUI snapshots/input cross only at synchronization, actions return through
queued calls. GPU devices/themes are thread-local, and the shared native font
cache is protected across windows. Idle frames stop after animations settle.
Qt's software scenegraph is unsupported by QQuickRhiItem.

## Frame cost

The scene is only updated when something it draws actually changed:

- `NetworkView` bumps a revision once per changed snapshot; the render side
  re-applies data on that revision instead of deep-comparing the whole snapshot
  (decoded icons included) on every frame.
- Theme colours are applied separately, so a data tick no longer marks the
  whole tree for re-measure.
- Process rows are reused by `name+iconSource`. The list is ranked by rate, so
  its order changes on most refreshes; reordering and retitling existing nodes
  keeps their glyph layout and icon textures.
- Chart peak labels and connectivity states are resolved with the data, not
  inside `draw()`.
- The layout publishes the rectangles that actually react to hover (controls
  and the overlay scrollbar track) to the GUI thread. Pointer movement elsewhere
  does not request a frame, because it cannot change the scene; entering or
  leaving a control still repaints, so hover feedback is unchanged.

`KOS_FORMA_BENCH=1` makes the check binary print per-30-frame synchronize and
render CPU time plus the draw-call count.

## Data

The existing `NetworkService`, `network.traffic`, `network.details` and
`network.applications` provide real data. Lifetime interface counters and a
local reset baseline provide displayed totals; resetting does not alter the
network or system counters. Unknown connectivity cells stay neutral. Latency,
jitter and public IP remain unavailable (an em dash) until a platform provider
actually supplies them. There are no fabricated UP states or sample network
values in the production panel. Application rates retain their existing
visible-TCP scope, including the proxy double-counting caveat.

## Build and verification

The normal root build includes the module and `kosctl` deploys its plugin.
Dependencies include Qt 6.7+ Quick/GuiPrivate/ShaderTools, SDL3, FreeType and GL.
The source override is optional; a developer checkout in `$HOME/Projects/Forma`
is detected locally, otherwise CMake fetches pinned Forma commit
`5bdb550a3d42535ea026ee04070bc0dd97774ef3`.

```sh
cmake -S . -B .build/kosctl -DBUILD_TESTING=ON -DKOS_FORMA_SOURCE_DIR=/path/to/Forma
cmake --build .build/kosctl --target kos_forma_network kos-forma-network-check kos-platform -j4
QSG_RENDER_LOOP=threaded .build/kosctl/shell/native/forma-network/kos-forma-network-check
QSG_RENDER_LOOP=threaded .build/kosctl/shell/native/forma-network/kos-forma-network-check --vulkan
QSG_RENDER_LOOP=threaded .build/kosctl/shell/native/forma-network/kos-forma-network-check --vulkan --scroll
ctest --test-dir .build/kosctl -R 'kos-ui.status-panels' --output-on-failure
```

Frame cost and regressions:

```sh
# 24 process rows, 10 reordering updates per second, per-frame CPU time.
KOS_FORMA_BENCH=1 QSG_RENDER_LOOP=threaded \
  .build/kosctl/shell/native/forma-network/kos-forma-network-check --many 24 --churn --reorder
# Hover gating: inert movement must not repaint, a control must.
QSG_RENDER_LOOP=threaded .build/kosctl/shell/native/forma-network/kos-forma-network-check --hover
```

The standalone check uses explicit sample data to test the same production
native view. It verifies the physical DPR target, construction of over 100
native component nodes, a Qt-to-native button callback, scroll delivery,
idle convergence and, with `--hover`, that only hover targets request a repaint. `KOS_FORMA_CAPTURE=/absolute/path.png` saves a GPU screenshot.
It also asserts that both colored graph halves survive the later native-image
batch, covering Vulkan render-pass preservation rather than just file creation.
The status-panel tests load the shipping QML popup on isolated virtual KWin
outputs and check actual rendered summary/details/collapse, the fixed Wayland
envelope, data delivery and second-screen anchoring. Their item captures do not
include compositor-generated glass; those effects need a composited screenshot
for visual inspection. No installation or desktop restart is required to test.
