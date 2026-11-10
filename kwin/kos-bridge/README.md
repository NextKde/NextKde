# KOS Bridge — KWin window button overlay

A KWin effect that covers the window controls of client-side decorated
windows with an iPadOS-style rounded panel containing three macOS traffic
lights, so applications that draw their own title bar get consistent KOS
chrome. KOS server-side decorations own native KDecoration buttons and are
never covered by this panel. Cooperative applications and qualified GTK/Firefox
controls use their respective native paths instead.

## How it works

- **Placed from configuration, tinted from the window.** The panel is pinned to
  a corner by `position` and `offset`, the same way on every window, so it
  never lands somewhere arbitrary. Its tint is read from the title bar under
  it, because that is the one thing configuration cannot know.
- **Adjustable in place.** A right press on a fallback CSD panel starts an adjust session:
  drag it, wheel it larger or smaller, and the geometry it ends at is written to
  a rules file the plugin owns. See **Adjusting a panel**.
- **Separate ownership.** KOS server-side decorations paint and handle their own
  controls through KDecoration. Bridge recognizes their capability marker,
  drops legacy hit regions/tint timers and skips overlay painting even when a
  legacy rule requests `always`. Undeclared client-side windows still use the
  fallback overlay; cooperative clients supply their own layout.
- **Why the position is not measured.** A compositor cannot ask a client-side
  decorated window where it put its controls: `xdg-decoration` carries only a
  mode, `_GTK_FRAME_EXTENTS` carries shadow margins (and only on X11), and
  `GtkHeaderBar` lives inside the client process. `EffectWindow::decoration()`
  is null for these windows. Guessing from the pixels is possible but not
  reliable — the left end of a self-drawn bar is usually the application's own
  logo, which is a *stronger* cluster than its controls are, and the controls
  themselves can be thin widely spaced glyphs with almost nothing in common
  with a filled button. A fixed offset is right far more often, and right in
  the same way for every window — and where it is not, dragging it is.
- Hooks `drawWindow`: lets the window paint itself first, then stamps the
  panel clipped to that window's **visible region** — its frame minus every
  opaque window stacked above it. Because the clip excludes everything above,
  a lower window's panel can never be drawn over an upper window.
- Draws a single **opaque rounded panel**. Being opaque is what lets it
  *cover* the application's own controls rather than float above them.
- Client-side decorated windows take their tint from the title bar's own
  pixels. Native KOS decorations are excluded before sampling begins.
- **Same-frame tint, without a guessed first color.** A fully visible titlebar
  gutter is copied and reduced to a median color on the GPU before drawing the
  panel in that same paint. The first cover need not wait for CPU readback.
  Unusable pixels hide both layers unless a previously validated fallback exists;
  input stays with the client until CPU confirmation, avoiding invisible hit areas.
- Skips screen-space panels and sampling while the window is transformed,
  faded, dimmed or desaturated: those pixels are not its unmodified title bar.
  Neutral offscreen source captures still include the controls during animations.
  Only touches normal windows / dialogs.
  Popups, context menus, tooltips, OSDs, notifications, docks, the Quickshell
  bar, the Plasma desktop and input-method surfaces are ignored.
- **Skips internal windows**, which is every window KWin makes for itself: its
  OSD (the desktop-change pill, for one), the outline, the tab switcher, the
  tile editor. They have no client process behind them — no application whose
  title bar could be underneath — but they otherwise look exactly like an
  undecorated normal window, so nothing above would have rejected them.

## The tint

`windowbuttons/titlebarmetrics.cpp` samples the title bar's rendered pixels for
legacy overlay windows (excluding native KOS decorations):

- **Top-anchored background gutter.** RGB comes from a narrow strip immediately
  beside the cover, starting two logical pixels below the window top. It does
  not follow the controls' vertical offset into avatars or lower toolbars. The
  preferred RGB strip is at most 32 device pixels wide; the fallback is at the
  opposite end outside the caption's middle third, at most 160 pixels wide.
  Neither includes the cover's own columns.
- **GPU visual tint.** `titlebargputint.cpp` copies only a fully visible gutter
  (at most 160 × 8 pixels) into separate scratch storage, then computes the same
  integer luma histogram/median cluster as the CPU sampler into one RGBA texel.
  The panel samples that texel immediately; GPU ordering replaces the former
  first-frame wait without `glReadPixels`, fence polling or a CPU/GPU stall.
  Copying first avoids sampling from the framebuffer being painted. Output
  rotations only reorder the histogram's pixels. This also follows late titlebar
  changes beyond the five-second CPU warm-up, rather than switching back to an
  older tint after an arbitrary deadline. It adds one bounded copy and one
  single-pixel reduction per eligible paint, not another scheduled repaint.
  Incomplete/integer targets, partial gutter visibility and shader/allocation
  failures retain the asynchronous path. Invalid alpha yields transparent output,
  never an uninitialized black fallback. GPU storage is one reusable 100 KiB
  scratch texture plus a color texel for the renderer, not per window.
- **Per-window vertical boundary.** One asynchronous read captures a strip of
  at most **160 × 192 device pixels** (120 KiB), shared by RGB and boundary
  detection. Eight horizontal groups form robust row profiles. Median colors
  above and below a candidate edge are compared against their local median
  deviation, rather than a fixed 12-level RGB threshold: coherent flat steps
  as small as two channel levels can qualify. At least 3/4 of the columns must
  support the direction of the change. The strongest local row step places
  the edge, and two consistent observations confirm it before trimming.
  Icons, isolated lines and gradual gradients do not trim it. The controls retain their
  configured positions. Boundary detection requires a completely visible
  probe; unavailable evidence leaves the configured cover extent in place.
- **Non-blocking readback.** Transfer into a per-window pixel-pack buffer and
  inspect its fence on a later paint. Only signalled buffers are mapped; paint
  hooks never wait on a GPU fence. Preserve the read framebuffer, source read-buffer selection, pixel-pack
  buffer and pack layout. Reject incomplete/missing-color targets and initialize
  orphaned transfer storage to transparent zeros: a failed read cannot turn
  undefined buffer bytes into an opaque black panel. Preserve the render target's content transform
  (including DRM FlipY and output rotation), then normalize the completed
  pixels to top-down viewport coordinates. Failed/occluded reads count against the sampling
  cadence, and a busy transfer is abandoned after 250 ms rather than keeping a
  fast retry loop alive indefinitely.
- RGB sampling stays near the window top, while exclusion uses the entire
  expanded cover. Enlarging it cannot sample the cover itself.
  Require at least 75% visible strip coverage and 75% near-opaque pixel coverage;
  sparse damaged glyphs cannot stand in for an undrawn/occluded background.
  Both CPU and GPU accept alpha 254–255: some CSD clients, such as WeChat,
  render a nominally opaque titlebar at 254/255. That one-level loss is
  unpremultiplied before luma and RGB accumulation, with fully opaque RGB
  unchanged. Alpha 253 or lower is still rejected rather than mistaking a
  client-side fade-in for a darker titlebar.
- **A median, not a mean.** A fixed 256-bin luma histogram averages RGB within
  ±3 of the median, rejecting transparent pixels, glyphs and antialiased edges
  without allocating, copying and sorting per-pixel sample vectors.
- **CPU fallback confirmation.** Cached fallback RGB and initial input readiness
  require two consistent usable captures at least 32 ms apart. The GPU visual
  path does not wait for this confirmation. The interval is measured at capture rather
  than GPU completion so polling jitter cannot force an unnecessary third read.
  Startup/change confirmation polls the fence every 4 ms for the first 32 ms of
  a transfer, then returns to the regular 16 ms poll; neither path waits on the GPU.
  Four warm-up attempts run at 32 ms intervals; steady active-window checks back
  off from 125 ms through 250/500 ms to 1000 ms as observations stay unchanged.
  During the first five seconds after sampling starts, client damage restarts
  warm-up even with a known tint: a cold-start placeholder is not evidence that
  the application's titlebar has finished loading. This deadline is not extended
  by damage, focus or resize. Afterwards, known windows retain their document/video
  backoff; observed RGB changes still return to 32 ms confirmation. Before the
  first tint, client damage also restarts warm-up after failed reads. Damage does
  not reset the last-attempt time, and a static startup window still backs off;
  this is not unconditional 32 ms polling for five seconds. New damage during a
  transfer requests a newer capture without discarding every usable observation,
  which would starve confirmation in a continuously repainting startup window.
  Failed observations also back off after warm-up. These are scheduling intervals,
  not measured end-to-end latency. Focus changes
  restart the fast phase for both windows while retaining validated RGB. Client
  damage also requests a throttled refresh for inactive windows; damage during
  an in-flight transfer remains outstanding until a newer capture completes.
  Invalid observations break confirmation, and failed inactive refreshes stop
  after the bounded warm-up budget. Near-equal readings (up to two levels per
  RGB channel) do not change the cached color.
- **Bounded reusable storage.** The scan uses fixed stack arrays, without
  per-pixel heap allocations. CPU pixel arrays are reused. The common GL row
  flip normalizes in place, avoiding a second full pixel array; rotated/mirrored
  outputs retain a reusable scratch array. A signalled, consumed PBO is reused;
  canceled or timed-out transfers orphan storage to avoid GPU waits. The RGBA
  payload is capped at 120 KiB per buffer (360 KiB for three CPU buffers and
  120 KiB for one PBO in the general transform path, excluding driver overhead).
  Minimized windows stop scheduled sampling and release sample caches after
  a 500 ms animation grace period; closing windows releases them immediately.
  Periodic repaint requests cover the bounded probe instead of the whole
  window-width band after the first observation.
- **No texture upload on RGB changes.** A cached white rounded background mask
  is tinted by the GPU color texel, or a premultiplied uniform on the fallback
  path; buttons, hover rings and adjustment marks live in a separate reusable
  transparent texture. New RGB
  values do not churn the panel texture cache. Explicit `dark`, `light` and
  custom-color settings still bypass sampling.
- Legacy server decorations without the native capability marker retain their palette fallback for upgrade compatibility.

The effect's `window-controls` debug payload includes `tintSameFrame`,
`tintStartingUp`, `tintIntervalMs`, `tintReadbackPending` and `tintChangePending`
alongside the CPU-validated fallback RGB. These distinguish the GPU visual path
from startup backoff, a busy readback or a fallback color awaiting confirmation;
the GPU color itself is not synchronously read for diagnostics.

Optional CPU-only maximum-probe microbenchmark (excludes GPU/readback/repaint):
`./.build/kos-bridge/titlebar_tint_test --benchmark`.

Offline regressions (no plugin installation or compositor restart):

```bash
cmake -S kwin/kos-bridge -B .build/kos-bridge -DKOS_BRIDGE_BUILD_TESTS=ON
cmake --build .build/kos-bridge --parallel 4
ctest --test-dir .build/kos-bridge --output-on-failure
```

`titlebar_tint_test` checks histogram equivalence, bounded sampling geometry,
neighboring filled toolbar widgets on both sides, noise rejection and confirmation
timing. `titlebar_readback_test` exercises the
real PBO/fence path, row orientation, buffer reuse and GL-state restoration on
an offscreen context; CTest reports it as skipped if no GL context is available.
With `-DKOS_BRIDGE_BUILD_GPU_TESTS=ON`, `titlebar_pixels_gpu_test` also covers
the asynchronous path across all eight output transforms, fractional scale,
non-zero viewport origins and target clipping, plus incomplete/integer-target
failures, transparent failure pixels, valid black titlebars and source read-buffer
restoration (no pre-read `glFinish`). `titlebar_gpu_tint_test` draws the final
panel in the same command stream as changing titlebar content, before any CPU
read or additional frame. It checks CPU/GPU histogram equivalence across all
output transforms, gutter visibility, GL-state restoration, valid black,
transparent failure, premultiplied mask edges and fallback compositing.
These tests do not replace checking the installed effect's appearance in a new
KWin session; do not hot-load a replaced plugin into the running compositor.

## Configuration

Two files, and the split between them is the point:

| File | Written by | Holds |
| --- | --- | --- |
| `~/.config/kos/window-buttons.json` | you | every key below, plus the `rules` you write by hand |
| `~/.local/share/kos/window-buttons-rules.json` | the plugin | the geometry a panel was dragged into, one rule per window |

The plugin never writes the first file — it is your statement of what you want,
and it is edited by hand — and the second holds nothing but geometry, is written
only by an adjustment, and is ignored if you delete it (which undoes every
adjustment at once).

### window-buttons.json

```json
{
    "default": {
        "position": "right",
        "offset": { "x": 10, "y": 6 },
        "buttonSize": 14,
        "buttonSpacing": 14,
        "panelPadding": 4.5,
        "panelPaddingX": 10,
        "interceptMargin": 5,
        "background": "auto",
        "drawOnDecoratedWindows": "auto"
    },
    "apps": {
        "firefox": { "background": "dark" },
        "google-chrome": { "background": "#202124" },
        "org.gnome.TextEditor": { "showButtons": false }
    },
    "rules": [
        { "match": { "class": "org.kde.dolphin", "type": "dialog" },
          "showButtons": false },
        { "match": { "titleRegex": "^Picture-in-Picture" },
          "position": "left", "offset": { "x": 4, "y": 4 } }
    ]
}
```

| Key | Values | Meaning |
| --- | --- | --- |
| `showButtons` | bool | Disable the panel for this app |
| `nativeGtkControls` | bool | Legacy manual qualification for native GTK CSD controls; defaults to false. Standard GTK 3 controls declare ownership automatically through the installed GTK module. Suppresses painting and input interception only without a server-side decoration. Native KOS SSD uses decoration buttons. See [GTK integration](../../docs/GtkWindowButtons.md) |
| `position` | `left` / `right` | Which edge the panel is pinned to. Anything else falls back to `right`, the layout these applications follow |
| `offset` | `{ "x": n, "y": n }` | Distance in logical pixels from that edge to the panel's outer edge (`x`), and from the window's top to the panel's top (`y`) |
| `buttonSize` | number | Traffic light diameter |
| `buttonSpacing` | number | Gap between the lights |
| `panelPadding` | number | Vertical padding between the panel edge and the lights |
| `panelPaddingX` | number | Horizontal padding; omit it to reuse `panelPadding` |
| `interceptMargin` | number | Logical pixels around the panel where the pointer is taken by it as well (default 5). Raise it for an application whose own controls still highlight around the panel's edge; `0` takes the panel only |
| `background` | `auto` / `dark` / `light` / `#hex` | Panel tint; `auto` follows the title bar's own pixels (exact RGB) or window palette, `dark`/`light` uses fixed theme tones, or specify an explicit hex color (e.g. `"#202124"`) |
| `drawOnDecoratedWindows` | `auto` / `always` / `never` | How far the panel goes on windows KWin decorates itself. `auto` means "when the decoration in use is ours" — see below |

The panel is exactly the `buttonSize` / `buttonSpacing` layout grown by the
padding, so it is the same size on every window.

Every value is bounded — `buttonSize` 6…40, `buttonSpacing` 0…40, `panelPadding`
0…20, `panelPaddingX` 0…60 — and the file and the gesture are clamped the same
way, so a hand edit cannot produce a panel a drag could not. The vertical padding
is the tight one because it is the panel's height on every window; the horizontal
one has to fit whatever width an application's own controls turn out to have.

`offset` is the key that has to be tuned per application, and the only one that
depends on the application's own title bar. Rather than editing it, adjust the
panel on the window: see **Adjusting a panel** below.

App keys match the window class exactly, or its first whitespace-separated token
(`"code code"` matches `"code"`).

Qualified Forma/Mayonnaise CSD apps retain their own OpenGL controls, without
overlay painting, input interception or tint sampling. Saved overlay geometry
and forced-paint rules cannot add a duplicate cluster. This policy uses verified
desktop IDs and leaves SSD controls and cooperative surface negotiation intact;
see [control ownership](../../docs/NativeWindowDecoration.md).

### Which configuration a window gets

1. `default` — every key.
2. `apps[class]` — merged key by key over the default.
3. The first matching entry of the hand-written `rules` — merged key by key.
4. The first matching entry of the machine-written
   `~/.local/share/kos/window-buttons-rules.json` — **replaces the six geometry
   keys** (`position`, `offset`, `buttonSize`, `buttonSpacing`, `panelPadding`,
   `panelPaddingX`) and touches nothing else.

So `showButtons`, `background`, `interceptMargin` and `drawOnDecoratedWindows`
always come from what you wrote, and an adjustment can never be undone by a
`offset` you left behind in step 1 or 2. Within a list, a rule that names more
things about a window wins over one that names fewer; ties keep the order the
file is written in, and the machine-written file is written newest first.

A machine rule stores the whole geometry, not a patch: once a window has been
adjusted, the hand-written geometry no longer reaches it. Deleting its entry —
or the whole file — gives it back.

### Matching

A `rules` entry matches on any of these, and all of the ones it names have to
hold:

| Matcher | Matches |
| --- | --- |
| `"class"` | The window class exactly, or any whitespace-separated token of it |
| `"title"` | The caption exactly |
| `"titleRegex"` | The caption, as a `QRegularExpression`. A key of its own, so a title containing a bracket cannot silently become a broken pattern |
| `"role"` | The window role. **Empty on Wayland**, where KWin has no role to report: a rule that sets one never matches there. Kept for X11 |
| `"type"` | One of `normal`, `desktop`, `dock`, `toolbar`, `menu`, `dialog`, `utility`, `splash`, `dropdownmenu`, `popupmenu`, `tooltip`, `notification`, `combobox`, `dndicon`, `onscreendisplay`, `criticalnotification`, `appletpopup` |

A rule that names nothing matches **nothing**, not everything, and is dropped
with a warning.

### Which decoration the panel belongs to

The common KOS appearance switch controls the selected decoration and CSD
integration. Fallback CSD overlays normally require KOS decoration selection;
`drawOnDecoratedWindows: always` retains the explicit legacy override.

### Server-side decorated windows

The current KOS decoration advertises `_kos_native_decoration_controls` and
owns its KDecoration buttons, including layout and input. This capability takes
precedence over all overlay rules. Native controls use the common glyph mode
and KDE's left/right button layout, not overlay geometry or background settings.
They cannot enter Bridge's right-click adjustment mode. See
[native decoration controls](../../docs/NativeWindowDecoration.md).

For older decorations without that marker, `auto` / `always` / `never` retain
legacy behavior so updating Bridge before the decoration does not remove the
window's only buttons. Update both plugins together and log in again to load them.

Reload without restarting KWin:

```bash
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect kos_bridge
```

## Adjusting a panel

Settings' **Resize button background separately** switch locks all fallback overlay circles
and gaps to 14 logical pixels. In that mode the edge grips change separately
saved cover margins without moving the buttons; plain/Shift wheel size changes
are disabled, and Ctrl+wheel changes only the cover. Turning it off restores the
original button geometry. See [ownership, persistence and validation](../../docs/WindowAppearance.md#independent-window-button-cover).

Right-click a panel. A blue ring appears around it, a grip appears on each of its
four edges, and the panel is now being positioned:

| Gesture | Effect |
| --- | --- |
| Left-press on the panel and drag | Move it. Clamped to the window |
| Drag the left or right grip | Width: `panelPaddingX` |
| Drag the top or bottom grip | Height: `panelPadding` |
| Wheel | `buttonSize` ± 1 per notch |
| Shift + wheel | `buttonSpacing` ± 1 |
| Ctrl + wheel | `panelPadding` ± 1 |
| Arrows / Shift + arrows | Nudge 1 px / 10 px |
| Enter | Save |
| Esc | Discard |
| Right press | Save — and adjust the panel it landed on, if it landed on one |
| Left-press off the panel | Save, and the click goes where it was aimed |

The grips are what makes the width and the height reachable on their own: the
width is `panelPaddingX` — how much of the panel is not lights — and the height is
`panelPadding`, while the wheel's three values are the lights themselves, which is
what a panel is normally tuned for. A grip drags the edge it is on and leaves the
opposite edge where it is, and a value that was following the other dimension (a
`panelPaddingX` left at the "same as `panelPadding`" default) is pinned to what it
resolves to, so only the edge that was dragged moves. Every bound is absolute
rather than relative to the window, so an edge dragged outwards stops at the edge
of the window rather than pushing the panel's other edge out.

Which side the panel is on is derived rather than dragged: `position` becomes
`left` when the panel's middle is left of the window's middle, and the two meet
continuously there, so dragging across the middle of a window changes the side
without a jump. The wheel leaves `offset` alone, so the panel grows away from the
edge it is pinned to rather than away from its own middle.

Saving matches the **window class and type**, plus the window role when one
is available. Without a role (including Wayland), the exact caption is used as
a fallback, so a QQ image viewer need not inherit the main window's cover size.
A caption-based adjustment must be saved again if the caption changes; use a
hand-written `titleRegex` for changing document titles when appropriate. Old
class-only rules remain compatible as fallbacks; adjust and save the secondary
window once to override them. A window with no class cannot be adjusted.

Every session ends in a line in the journal, because the file is the only readout
an adjustment has:

```
KOS: saved the panel adjustment for "code code" to "/home/…/window-buttons-rules.json"
KOS: discarded the panel adjustment for "code code"
KOS: the panel for "code code" was not changed; nothing written
```

Watch it with `journalctl --user -b -u plasma-kwin_wayland -f | grep KOS`.

## Interaction

- Left-clicking a light performs that light's action. From left to right the
  panel is **minimize** (yellow), **zoom** (green), **close** (red): the zoom
  light toggles between maximized and restored, the minimize light minimizes,
  the close light closes. The order lives in one table in `typeAt()`; the
  colours, the glyphs, the hit testing and the actions all follow it.
- A press anywhere else on the panel is swallowed, so it never reaches the
  application's own controls underneath. The matching release is swallowed
  too, so the application does not see a stray button-up. Presses of other
  buttons are swallowed as well but perform nothing, so a right-click cannot
  close a window on its way to a context menu — it starts an adjustment
  instead (above).
- Motion over the panel is swallowed too. The controls the panel covers are
  still there, and an application that keeps receiving motion over them goes on
  highlighting them — visibly, where they are larger than the panel. The margin
  named by `interceptMargin` is taken with the panel for the same reason. The
  cursor and window activation are unaffected: KWin has already moved the
  pointer and decided the window under it before this runs. Motion that carries
  a button pressed somewhere else — the application's own selection or slider
  drag — is passed through, so such a drag does not stall while it crosses the
  panel.
- The wheel is left alone on a client-side decorated window: the panel sits over
  the application's own content there — a tab strip, a page, a list — and the
  pointer happening to be on the panel is no reason for that to stop scrolling.
  On a window KWin decorates there is nothing under the panel but the
  decoration's own title bar, which KWin turns a wheel over into *shading the
  window*; the panel takes the wheel there so a wheel over it does nothing
  rather than something none of the panel's buttons do.
- Neither the panel nor its margin takes the pointer where something is
  stacked above them: a click there belongs to the upper window, not to the one
  whose panel is hidden behind it.
- Hovering a dot draws a contrasting ring around it.
- The zoom light's glyph follows the window: two wedges pointing out of the
  button while the window is not maximized, and the same two wedges pointing at
  each other once it is. The test is the one the click itself makes
  (`maximizeMode() == MaximizeFull`), so the mark cannot end up promising the
  state the window is already in. Maximized in one direction only counts as not
  maximized, because clicking there does maximize.
- The close light's cross is drawn a little smaller than the other two glyphs —
  a cross that fills its circle has no room around it and reads as the largest
  of the three.

## The tiling menu

Hold **Alt** and move the pointer onto the zoom light. A grid of tiling presets
drops out below the panel. It is four columns by two rows, and there are no
words in it: every cell is a picture of where the window would end up, which is
what a 30-pixel cell has room for.

| Cell | What it does |
| --- | --- |
| Fill | Maximize: the whole work area |
| Left half, right half | KWin's own tiling |
| Restore | Leave the whole-window state and go back to the size the window had |
| Left ⅓, left ⅔, right ⅔, right ⅓ | This effect places the window on that part of the work area |

The halves are KWin's tiling rather than a placement of this effect's own, so
the menu and the keyboard are one state rather than two: a window tiled from
here is one that `Meta`+`→` will put a neighbour beside, and one that a drag
pulls back out to the size it had before. It also means the halves follow the
user's tile layout — where that layout has been customized, "left half" is the
left tile *of that layout*. KWin refuses to tile a window it cannot resize, so
the menu is not offered at all on such a window: every cell but Restore is a
size the window would take on, and seven cells that do nothing are worse than
none.

The thirds are placements this effect makes, because KWin has no tile for them.
Two things follow. The first is that a placement is computed from the window's
maximize area, so a third of the screen is a third of what a maximized window
covers: struts (panels, docks) excluded, on the screen the window is on. The
second is that nobody else remembers the rectangle a placement replaced, so this
effect does — Restore puts it back, and does so only while the window is still
where the placement left it, since a window that has been moved or resized since
is not one whose previous size is still what "back to how it was" means. The
complementary cells are exact: left ⅓ and right ⅔ tile the work area with no
seam and no overlap, so two windows placed that way fit together.

| Gesture | Effect |
| --- | --- |
| Alt + hover the zoom light | Open the menu |
| Hover a cell | Highlight it |
| Left-click a cell | Place the window there |
| Left-click anywhere else | Close the menu, and nothing else — the press is swallowed |
| Move off the menu and its panel | Close the menu |
| Esc | Close the menu |
| Wheel | Taken over the menu on a window KWin decorates, as over the panel |

A press while the menu is open belongs to the menu wherever it lands, which is
how a menu behaves everywhere and is also what stops an Alt+click on the light
that opened it from closing the window on the way to putting the menu away.

The menu is drawn inside the window and clipped to it, like the panel: a window
stacked above covers it. It is not drawn at all where it would not fit — a
window too short to hold it under the panel, or too narrow to hold it at all,
has no menu — and it is recomputed from the panel and the window on every frame,
so a window that moves or resizes under an open menu takes it along rather than
leaving it behind. It is not configurable: there is nothing to set about it, and
turning it off would be a new key rather than a value.

The panel and the menu are each clipped to the part of the frame being repainted
— the two rectangles are different, and one of them routinely has nothing to
paint while the other has plenty, as when an application repaints its content
under an open menu. Neither is allowed to decide whether the other is drawn: a
single early return on the panel's clip is what once left the menu's pixels to be
painted over by the window's own content, so that the menu flicked out and the
application showed through it once per repaint underneath.

Alt over a window is already KWin's "move this window with the pointer", so the
cursor turns into a move cursor while the menu is open. Nothing comes of it: the
press that would begin that move is swallowed by the panel, as every press on
the panel is.

## Notes

- Server-decorated KOS windows use native KDecoration controls; Bridge still
  supplies their shared corner/shadow appearance, without a button overlay.
- Only the macOS traffic-light look is implemented.
- A KWin window rule cannot help here. Since Plasma 6.6, `noborder` = Force: No
  makes KWin draw a decoration for a CSD window, but it does not stop the
  client drawing its own — for GTK, Firefox and Chromium that produces *two*
  title bars. It is only clean for clients that yield, which Qt already does
  by default.
- `windowbuttons/titlebarscan.*`, with its harness in `tests/scan_titlebar.cpp`,
  is the pixel-scan placement this replaced. It is no longer part of the
  plugin — a logo, a toolbar and a half-painted frame are all indistinguishable
  from a control cluster — but it is still built by
  `cmake -S . -B build -DKOS_BRIDGE_BUILD_TESTS=ON` so it stays compilable, and
  `KOS_SCAN_DEBUG=1` prints each of its heuristics' votes.
- The same flag builds `tests/rules_test.cpp`, which covers the geometry the
  adjust gesture works in, the matcher and the four-step resolution, and the
  rules file (round trip, dedupe, clamping, and that a store that changes
  nothing rewrites nothing). None of those touch a compositor — `panelgeometry`
  and `windowrules` keep KWin headers out on purpose — so they run under
  `ctest`. `windowbuttons/panelgeometry.h` is the one definition of where a
  panel is; the renderer, the adjust session and the test all go through it.

## Unified window appearance

Window chrome is resolved by `windowappearance/`: an inner physical-pixel
outline, a narrow contact shadow and a broad ambient shadow. Continuous corners
are the default, with a longer tangent transition and zero curvature at the
straight-edge joins. One compositor shader clips SSD/CSD content and draws all
three layers against the same contour. Arc mode retains native scene outlines,
shared decoration shadows and the CSD eight-tile fallback.

Continuous mode uses a damage-driven offscreen window-content cache, with
a 256 MiB texture budget and GPU size checks; unsupported/excess windows fall
back to native arcs. It adds GPU rendering work for changing content and resize.
It does not capture the background. Fullscreen always uses square corners and
hides KOS outlines, frames, shadows and traffic-light controls, regardless of
appearance overrides. Leaving fullscreen restores the normal window appearance.
Glass honors the unified geometry property to avoid applying a cached arc again.

The draw chain is Glass (20), Dock/Stage animations (50), then Bridge (100).
Dock consumes Bridge's shared source through a synchronous in-process interface:
one texture contains client content, native decoration and the KOS button panel.
Dock deforms its mesh while Bridge applies the contour in source UV coordinates,
so buttons and continuous corners follow the same animation without a second
Dock texture. Stage retains its outer capture of the already-rounded source.
Bridge must not cache the animation output: doing so skips downstream animation
draw calls on undamaged frames. Continuous shadow bounds reserve the larger of
the active and inactive extents, so a focus change does not resize the source FBO.
CI builds/links Bridge, Dock and Glass with complete KWin 6.6/6.7/6.8 SDKs and runs
offline/API checks. Live compositor coverage is separately recorded per Release;
see [release policy](../../docs/Releasing.md).

Dock allocates its legacy cache only when the provider is unavailable or declines
the window. That capture includes the KOS controls in arc mode too. Allocation
failures restore native arcs and are retried after geometry/scale/configuration
or budget changes. Animated button/menu hit regions are cleared; the final normal
paint restores them. Source damage, panel hover/focus changes and configuration
updates invalidate the shared content; unchanged content reuses the texture.

Hidden scene items release the continuous content texture after animation
visibility references end. Configuration notifications are coalesced and
unchanged/invalid files keep existing textures. Stacking updates share a single
snapshot per notification burst; resolved app settings retain only configured
rules. Native shadow atlases still held by windows survive LRU eviction through
a weak lookup, avoiding repeated generation. See the
[resource and performance review](../../docs/WindowAppearance.md)
for remaining costs and manual acceptance steps.

Configuration: `~/.config/kos/window-appearance.json`. See
[the version 2 example](windowappearance/window-appearance.example.json) and
[implementation limits and user verification steps](../../docs/WindowAppearance.md).
Version 1 is accepted; explicitly configured widths without a unit remain logical
pixels. Version 2 defaults to one physical pixel. Bridge, decoration and Glass require matching builds
for the KWin installation that will load them. Run acceptance only in a VM.

For repeatable API checks against another KWin source checkout:

```sh
python3 tools/ci/check-kwin-api.py --build-dir .build/kosctl --kwin-headers /path/to/kwin/src
```

Bridge detects the installed paint-hook signature rather than assuming a version
number, retaining `presentTime` on 6.6.x. Shader validation uses the `link()` result
available on both APIs; drawing keeps a local copy of non-assignable paint data.
On 6.6.x, which lacks the base shader resources, Bridge supplies the equivalent
texture/saturation/modulation stages and uses KWin's own color-management GLSL.
The continuous-contour stages pass offline GLSL linking for desktop GL and GLES
against both tested 6.6 versions; GPU execution remains unverified.

### GPU title-bar readback regression test

The title-bar sampler maps through the render target's content transform before
reading its framebuffer. Readback pixels are normalized to top-down viewport
coordinates, including flipped and rotated targets, so panel exclusions and
visibility clipping refer to the correct pixels.

The opt-in GPU test renders coordinate-coded pixels using the installed KWin
projection matrix and exercises the production readback helper. It covers all
eight output transforms, 100% and 125% scaling, out-of-bounds clipping, and read
framebuffer restoration. Run it in an environment with an EGL/OpenGL context:

```sh
cmake -S kwin/kos-bridge -B .build/titlebar-gpu -G Ninja \
  -DKOS_BRIDGE_BUILD_GPU_TESTS=ON
cmake --build .build/titlebar-gpu --target titlebar_pixels_gpu_test
ctest --test-dir .build/titlebar-gpu -R '^titlebar_pixels_gpu_test$' -V
```

CTest reports a skipped test (exit 77) when an EGL context is unavailable.

## Cooperative application controls

Custom Wayland apps can declare a surface-local controls slot. Bridge draws only
the three buttons without a background or title-bar sampling, independently of
the selected window decoration. The shared appearance switch controls takeover;
declared surfaces never fall through to the legacy overlay. See the
[integration contract](../../docs/CooperativeWindowControls.md) and
[VM test](../../tests/cooperative-controls/README.md).
