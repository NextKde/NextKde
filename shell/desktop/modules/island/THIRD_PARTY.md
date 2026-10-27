# Third-party code in the island module

## Islet — https://github.com/Claritys11/islet

Licence: MIT (see the upstream project's `LICENSE` for the full terms).

What was taken:

- `NotchIsland.qml` — the *notch* silhouette: a rectangle whose top edge is a
  straight cut with only the bottom corners rounded, plus the two quarter-disc
  "ears" that blend the cut into the screen edge. The ear geometry (the
  `ShapePath` with a `PathArc` of radius 12) is reproduced in
  `IslandWindow.qml`.
- `NotchIsland.qml` / `SweepText.qml` — the idea of the karaoke fill: the
  current lyric line drawn twice, the bright copy clipped to how far into the
  line the playback position is. `IslandLyricsWidget.qml` reproduces it against
  the shell's own MPRIS service and `TimedLyrics.mjs`.
- The idea of a per-corner radius in the island's own outline. The mask itself
  is this project's (`shaders/squircle.frag`); it gained an optional top/bottom
  radius split so the notch can be drawn with the same SDF the rest of the
  shell uses.

What was **not** taken: Islet's services and views that depend on subprocesses
(`fd`, `fzf`, `cava`), on Spicetify/Spotify, on Notion, on Google Calendar, or
on DankMaterialShell. NextKde's architecture forbids running external
commands from QML, so those parts would have to be rebuilt against the
platform contract rather than copied.

## Notchy — https://github.com/MrKai77/Notchy

**Notchy is closed source.** Its `Resources/LICENSE.txt` states: "This software
is proprietary. The source code in this repository is not licensed for
redistribution, modification, or derivative works."

So nothing was copied from it. What was done instead is a **clean-room
implementation from observation**: the installed application's own settings
(`defaults read dev.notchy.app`) and the identifiers in its binary were read to
learn *what* the product does and *how big* its parts are, and the equivalent
behaviour was written from scratch here. The shape vocabulary itself comes from
Islet (MIT, above), which uses the same "notch" design.

Observed facts used as the specification (not code):

- `settings.pillDesign = notch` -- the pill design is a notch, which is why
  this module's "notch" shape preset exists at all.
- `settings.pillSizeScale = 1.05`, `settings.closedPillHeightOffset = 2`.
- `settings.panelWidth = 820`, `settings.panelHeight = 250` -- the expanded
  panel is 3.28:1. (NookX's, measured from its own screenshot, is 4.27:1.)
- `settings.home.cardWidth = 366.6`, `settings.home.cardHeight = 170`, and
  `settings.home.cards = "screenTime,launcher,quickActions,displays"` -- the
  expanded panel is a grid of four cards.
- Identifier families in the binary: `NotchEarsView`, `NotchBodyShape`,
  `NotchSurface`, `NotchWallpaperMask`, `NotchyGlassMaterial`,
  `NotchyLiquidGlassBackground`, `NotchIdleRingsView`, `NotchyWidget*`.

What was implemented here from that specification: the "screen time" card
(`IslandUsageWidget.qml`), reading the shell's own activity snapshot.
