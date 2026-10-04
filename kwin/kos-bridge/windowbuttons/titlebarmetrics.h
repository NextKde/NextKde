#pragma once

#include <QRectF>

#include "buttonconfig.h"

namespace KWin
{
class EffectWindow;
class RenderTarget;
class RenderViewport;
class Region;
}

namespace KOS
{

// Read the tint of the title bar the panel is about to cover.
//
// This is the only thing the effect still measures. Where the panel goes is
// configured -- see AppConfig::offset -- because a compositor cannot reliably
// work out where a client-side decorated window put its controls: nothing
// exposes it (`xdg-decoration` carries only a mode, `_GTK_FRAME_EXTENTS`
// carries shadow margins and only on X11, `GtkHeaderBar` lives inside the
// client process, and `EffectWindow::decoration()` is null for these windows),
// and guessing from pixels mistakes logos, toolbars and half-painted frames
// for controls. The tint is different: it is a property of the whole bar, not
// of a feature inside it, so a median over the bar is right even when nothing
// in it is understood.
//
// `panelRect` is the panel in window-local logical pixels. The sample is taken
// from the band the panel occupies, across the window's whole width, minus the
// panel itself and the caption's middle third.
//
// Returns false when the band could not be read or held too few visible
// pixels, which means "not yet" -- the window has not painted, or is covered.
// The caller is expected to retry on a later frame.
bool sampleTitlebarTint(const KWin::RenderTarget &renderTarget,
                        const KWin::RenderViewport &viewport,
                        KWin::EffectWindow *window,
                        const KWin::Region &deviceClip,
                        const QRectF &panelRect,
                        bool *dark);

} // namespace KOS
