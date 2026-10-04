# KOS Bridge — KWin window button overlay

A KWin effect that covers the window controls of client-side decorated
windows with an iPadOS-style rounded panel containing three macOS traffic
lights, so applications that draw their own title bar get consistent KOS
chrome. The same panel is drawn over windows KWin decorates itself, where the
KOS decoration draws a frame and no buttons at all. It is drawn only while the
KOS decoration is selected — see **Which decoration the panel belongs to**.

## How it works

- **Placed from configuration, tinted from the window.** The panel is pinned to
  a corner by `position` and `offset`, the same way on every window, so it
  never lands somewhere arbitrary. Its tint is read from the title bar under
  it, because that is the one thing configuration cannot know.
- **Adjustable in place.** A right press on a panel starts an adjust session:
  drag it, wheel it larger or smaller, and the geometry it ends at is written to
  a rules file the plugin owns. See **Adjusting a panel**.
- **One panel for both kinds of window.** An effect is the only place this can
  live. KWin paints a decoration *below* the client surface and instantiates
  none at all for a client-side decorated window, so a decoration can never draw
  over one; this effect paints after the window — decoration included — has been
  rendered, so it can cover either. The price is that an effect cannot *remove*
  a decoration: every server-side decorated window gets one, whichever is
  selected. That is what the KOS decoration is for — it draws a frame and no
  buttons, so the panel over it is the window's only controls — and why the
  panel follows the decoration selection rather than standing alone.
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
- Picks the tint from the title bar's own pixels, rather than from a colour
  scheme. KWin's window palette follows `kdeglobals`, which a GTK or
  self-drawn title bar has nothing to do with.
- **Fails closed, on the tint only.** If the title bar cannot be read yet —
  the window has not painted, or it is covered — no panel is drawn on that
  frame and the read is retried. The panel never appears with a guessed tint.
- Skips frames where the window is being animated
  (`PAINT_WINDOW_TRANSFORMED`), and only touches normal windows / dialogs.
  Popups, context menus, tooltips, OSDs, notifications, docks, the Quickshell
  bar, the Plasma desktop and input-method surfaces are ignored.
- **Skips internal windows**, which is every window KWin makes for itself: its
  OSD (the desktop-change pill, for one), the outline, the tab switcher, the
  tile editor. They have no client process behind them — no application whose
  title bar could be underneath — but they otherwise look exactly like an
  undecorated normal window, so nothing above would have rejected them.
- Draws a single **opaque rounded panel**. Being opaque is what lets it
  *cover* the application's own controls rather than float above them.
- Picks the tint from the title bar's own pixels, rather than from a colour
  scheme. KWin's window palette follows `kdeglobals`, which a GTK or
  self-drawn title bar has nothing to do with.
- **Fails closed, on the tint only.** If the title bar cannot be read yet —
  the window has not painted, or it is covered — no panel is drawn on that
  frame and the read is retried. The panel never appears with a guessed tint.
- Skips frames where the window is being animated
  (`PAINT_WINDOW_TRANSFORMED`), and only touches normal windows / dialogs
  using client-side decorations. Popups, context menus, tooltips, OSDs,
  notifications, docks, the Quickshell bar, the Plasma desktop and
  input-method surfaces are ignored.
- **Skips internal windows**, which is every window KWin makes for itself: its
  OSD (the desktop-change pill, for one), the outline, the tab switcher, the
  tile editor. They have no client process behind them — no application whose
  title bar could be underneath — but they otherwise look exactly like an
  undecorated normal window, so nothing above would have rejected them.

## The tint

The only thing read from the window. `windowbuttons/titlebarmetrics.cpp` takes
a band of the composited frame at the panel's own rows, across the window's
whole width, and takes the **median luma**:

- **A median, not a mean.** The caption and the application's controls sit
  inside that band and are far higher contrast than the bar behind them. A
  mean would be dragged around by however much of them happens to be there,
  and by how bright they are; the median is the background as long as the
  background is the majority, which it is.
- The **panel's own columns and the caption's middle third are excluded** —
  the first because it is about to be covered, the second because it is
  glyphs rather than background.
- Pixels outside the window's **visible region are excluded**: they belong to
  whatever is stacked above, and tinting from another window would be worse
  than not tinting at all. A partly covered window is still tinted from the
  part of its bar that is visible.

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
| `position` | `left` / `right` | Which edge the panel is pinned to. Anything else falls back to `right`, the layout these applications follow |
| `offset` | `{ "x": n, "y": n }` | Distance in logical pixels from that edge to the panel's outer edge (`x`), and from the window's top to the panel's top (`y`) |
| `buttonSize` | number | Traffic light diameter |
| `buttonSpacing` | number | Gap between the lights |
| `panelPadding` | number | Vertical padding between the panel edge and the lights |
| `panelPaddingX` | number | Horizontal padding; omit it to reuse `panelPadding` |
| `interceptMargin` | number | Logical pixels around the panel where the pointer is taken by it as well (default 5). Raise it for an application whose own controls still highlight around the panel's edge; `0` takes the panel only |
| `background` | `auto` / `dark` / `light` | Panel tint; `auto` follows the title bar's own pixels |
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

The panel *is* the KOS decoration's window controls, so it is drawn only while
that decoration is selected in System Settings. `kosctl install` installs the
decoration and never selects it: the choice is the user's, and until it is made
the panel is drawn nowhere — `always` in the user's own file is the one
exception, below. Selecting Breeze, or anything else, takes the panel off every
window again — the client-side decorated ones included, because an application
that draws its own title bar draws its own controls in it and a KOS panel in
the corner of that is a panel nobody asked for.

KWin does not report the decoration to effects, so the configuration reads
`[org.kde.kdecoration2] library` out of `kwinrc` and watches that file; when it
changes, every cached decision is dropped and the screen is repainted.

### Server-side decorated windows

On windows KWin decorates itself, `drawOnDecoratedWindows` decides how far the
panel goes. `auto`, the default, means "when the decoration in use is ours" —
that decoration draws a frame and no buttons at all, so the panel is the only
controls such a window has. `never` leaves those windows to the decoration
entirely.

`always` is the one way to ask for the panel without the decoration: it draws it
over another decoration's buttons as well, and it is the only thing that
survives that decoration being selected. Only a hand-written file can set it —
the rules this plugin writes never carry the key.

Reload without restarting KWin:

```bash
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect kos_bridge
```

## Adjusting a panel

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

Saving writes a rule matched on the **window class** alone — the one thing about
a window that is the same now and the next time the application starts — so a
window with no class cannot be adjusted at all. A `title`, `titleRegex` or `type`
matcher is something to write in `rules` by hand.

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
  panel is **zoom** (green), **minimize** (yellow), **close** (red): the zoom
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

- Windows KWin decorates itself are handled too — the panel is the same panel,
  drawn by this effect in both cases, and the decoration
  (`kwin/kos-decoration/`) draws a frame and no buttons. There is
  no way around the decoration for the task switcher, the resize grips and the
  shadow to come from KWin; the effect is what draws the controls over it.
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
