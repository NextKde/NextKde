#pragma once

#include <QHash>
#include <QImage>
#include <QObject>
#include <QPointer>
#include <QRectF>
#include <QSet>
#include <QSizeF>
#include <QString>
#include <chrono>
#include <map>
#include <memory>
#include <optional>

#include "buttonglyph.h"
#include "titlebarmetrics.h"
#include "tilemenu.h"

namespace KWin
{
class EffectWindow;
class RenderTarget;
class RenderViewport;
class Region;
class GLTexture;
}

namespace KOS
{

// Animation state copied from the window's WindowPaintData, so the panel moves,
// scales and fades together with the window instead of appearing at its final
// place before the window gets there.
struct PaintTransform {
    qreal xScale = 1.0;
    qreal yScale = 1.0;
    qreal xTranslate = 0.0;
    qreal yTranslate = 0.0;
    qreal opacity = 1.0;
};

// Draws an iPadOS-style rounded panel behind three traffic-light buttons,
// covering the window controls that a client-side decorated application drew
// for itself. The panel is opaque so it covers them rather than floating
// transparently above them.
//
// Where it goes is configured, not measured: see AppConfig::offset. Only its
// tint is read from the window, because a bar's colour is a property of the
// whole bar and a median over it is right even where nothing in it is
// understood -- see titlebarmetrics.h.
class ButtonRenderer : public QObject
{
public:
    ButtonRenderer();
    ~ButtonRenderer() override;

    void paint(const KWin::RenderTarget &renderTarget,
               const KWin::RenderViewport &viewport,
               KWin::EffectWindow *window,
               const AppConfig &config,
               const KWin::Region &deviceRegion,
               const PaintTransform &transform);

    enum class Action { None, Close, Minimize, Maximize };

    // Hit-test a global logical pointer position against the panels currently
    // on screen. Returns the action and, via `window`, the owning window.
    // `insidePanel` (optional) is set to true whenever the point is anywhere
    // the panel takes the pointer, even between the dots or in the margin
    // around it, so the caller can swallow the event instead of letting it
    // reach the application's own controls underneath.
    //
    // The point has to be over a part of the window that is not covered by
    // anything above it, and the topmost window wins where two panels overlap.
    Action hitTest(const QPointF &logicalPos, KWin::EffectWindow **window,
                   bool *insidePanel = nullptr) const;

    // Update which dot is hovered. Repaints the affected window when it changes.
    void setHovered(KWin::EffectWindow *window, Action action);

    // Damage the panels of two windows: the one that just stopped being the
    // active window and the one that just became it (`b` may be `a`). The lights
    // are coloured by which window is active, and the focus moving damages
    // nothing on its own -- an application may redraw its own title bar and a
    // decoration may follow the state, but neither is promised -- so without
    // this a panel shows the colours of the window that used to be active until
    // something else happens to repaint it.
    void repaintPanels(KWin::EffectWindow *a, KWin::EffectWindow *b);

    // ---- the tiling menu --------------------------------------------------
    //
    // A menu of tiling presets that hangs from the panel's bottom edge, opened
    // by the input filter when the pointer is over the zoom light with Alt
    // held. Only one is open at a time, so the state below is a single menu
    // rather than one per window.
    //
    // It is drawn in the same pass as the panel, clipped to the same region, so
    // it is inside the window it belongs to: a window stacked above covers the
    // menu exactly as it would cover the window's own content.

    // Opens the menu under the window's zoom light -- the light whose action is
    // Action::Maximize, wherever the order puts it. False when the window has
    // no panel on screen this frame (nothing for the menu to hang from) or no
    // room under it, in which case nothing is drawn and nothing takes the
    // pointer.
    bool openTileMenu(KWin::EffectWindow *window);
    void closeTileMenu();
    // The window the open menu belongs to, or null when there is none.
    KWin::EffectWindow *tileMenuWindow() const;

    // Whether a point belongs to the open menu: the menu box, the panel it
    // hangs from, or the column of window between them. That region is what
    // keeps the walk from the light down into the menu unbroken -- it is wider
    // than the menu itself, because the menu is centred on the light and then
    // slid back inside the window, and the two ends of that walk do not always
    // line up.
    //
    // The region is where the menu *is*, worked out from the panel and the
    // window, and not from what the last frame happened to draw: a frame that
    // repaints the window's content damages none of the menu, and the menu is
    // still there. What is left is the one thing geometry cannot answer, whether
    // something is stacked over the menu, which is asked about the point the
    // same way the panel's own hit test asks it.
    bool tileMenuRegionContains(const QPointF &logicalPos) const;
    // The preset of the cell under a point, if it is in one.
    std::optional<TilePreset> tileMenuPresetAt(const QPointF &logicalPos) const;
    // Update which cell is highlighted, repainting the menu when it changes.
    void setTileMenuHovered(const QPointF &logicalPos);

    // ---- the adjust draft -------------------------------------------------
    //
    // A window being adjusted draws the draft geometry instead of the one the
    // configuration resolved to. It is kept here rather than in the session so
    // that everything downstream of the config in paint() -- the drawn panel,
    // the hit rects, the tint band, hitTest() -- follows it without knowing
    // about it.

    // Draw the window's panel with this geometry from now on, and repaint both
    // the panel that is on screen and the one that will be. The two are
    // different rectangles and both have to be damaged, or the panel leaves a
    // copy of itself behind at every step of a drag.
    void setPendingGeometry(KWin::EffectWindow *, const PanelGeometry &draft);
    // Back to the resolved configuration. `base` is the geometry the
    // configuration resolves to for this window, which is what the frame after
    // this one will draw -- this class does not know it, and the caller does.
    void clearPendingGeometry(KWin::EffectWindow *, const PanelGeometry &base);
    bool hasPendingGeometry(KWin::EffectWindow *) const;
    PanelGeometry pendingGeometry(KWin::EffectWindow *) const;

    // Whether the window is the one being adjusted, which draws the panel with
    // the adjust ring and suppresses the hover ring.
    void setAdjusting(KWin::EffectWindow *, bool adjusting);
    bool adjusting(KWin::EffectWindow *) const;

    // Drop cached geometry for a window that has gone away.
    void forget(KWin::EffectWindow *window);

    // Drop the hit rects of a window whose panel is not on screen this frame,
    // keeping its cached tint. A panel that is not drawn must not take the
    // pointer: the window is being animated, or it is not one this effect
    // draws a panel for at all.
    void clearHits(KWin::EffectWindow *window);

    // Drop every cached tint. Called when the configuration changes, since the
    // configuration decides which band is sampled.
    void invalidateAll();

private:
    // The light drawn in each of the three positions, left to right. `Type` is
    // what a light *is* -- its colour, its glyph, the action it performs -- and
    // where it sits is a separate decision, so the order lives in this one
    // function and nowhere else: the same three lights can be laid out in any
    // order without touching the colours, the glyphs, the hit-testing or the
    // actions. The lights themselves are drawn by buttonglyph.h, which owns
    // everything about one light and nothing about where it goes.
    static Type typeAt(int index);
    // The action a light performs. The inverse of nothing: `typeAt` says where a
    // light is, this says what it does.
    static Action actionFor(Type type);

    // Read the active window's title bar and reuse the last tint while it is
    // inactive. Returns false until the first successful reading.
    //
    // Reading is easy; deciding when a reading is the bar rather than something
    // that happens to be under the panel for a moment is not, and is what most
    // of the state below is for.
    bool tintFor(const KWin::RenderTarget &renderTarget,
                 const KWin::RenderViewport &viewport,
                 KWin::EffectWindow *window,
                 const QRectF &panel,
                 const KWin::Region &deviceRegion,
                 bool *dark);

    // Schedule one repaint at the next sampling deadline. The timer is
    // cancelled with this renderer; inactive or deleted windows are skipped.
    void scheduleSample(KWin::EffectWindow *window);
    static void requestSample(KWin::EffectWindow *window, const QRectF &panel);

    // The geometry the window's panel is drawn with: the draft while one is
    // being adjusted, otherwise the configuration's.
    PanelGeometry effectiveGeometry(KWin::EffectWindow *window,
                                    const AppConfig &config) const;

    // The panel's rectangle on screen in global logical pixels for a given
    // geometry, exactly as paint() draws it.
    QRectF panelRectFor(KWin::EffectWindow *, const PanelGeometry &) const;
    // The same for the geometry the panel currently has: the draft if there is
    // one, otherwise the rectangle it was last drawn at. Empty for a window
    // with no panel on screen.
    QRectF currentRect(KWin::EffectWindow *) const;

    // Damage one rectangle of the composited frame. Everything here repaints
    // through this: EffectWindow::addRepaintFull() called from a pointer
    // handler has been crashing KWin, and a panel is a small fixed rectangle.
    static void repaintRect(const QRectF &globalRect);

    KWin::GLTexture *panelTexture(const QSizeF &panelSize, bool active, bool dark,
                                  const PanelGeometry &geometry, Action hovered,
                                  bool adjusting, bool maximized);
    KWin::GLTexture *cacheTexture(const QString &key, QImage image);
    QImage buildPanel(const QSizeF &panelSize, bool active, bool dark,
                      const PanelGeometry &geometry, Action hovered,
                      bool adjusting, bool maximized) const;

    KWin::GLTexture *tileMenuTexture(bool dark, std::optional<TilePreset> hovered);
    QImage buildTileMenu(bool dark, std::optional<TilePreset> hovered) const;

    // Blit one of this effect's textures over a rectangle of the frame, clipped
    // to the part of the window that is actually being painted. The panel and
    // the tile menu both come through here, so the shader setup, the blend
    // state and its restoration exist once.
    static void blit(const KWin::RenderViewport &viewport, const KWin::Region &clip,
                     const QRectF &logicalRect, KWin::GLTexture *texture);

    // The light that opens the tiling menu: the one that performs Action::Maximize.
    // Found through typeAt() so that reordering the panel moves the menu's
    // anchor with the light it belongs to.
    static int zoomDotIndex();

    std::map<QString, std::unique_ptr<KWin::GLTexture>> m_textures;
    qsizetype m_textureBytes = 0;

    // Times are read against this clock, which does not jump when the wall
    // clock does.
    using Clock = std::chrono::steady_clock;

    struct CacheEntry {
        // The tint the panel is drawn with. A window whose title bar has never
        // been read has no tint and gets no panel for now.
        bool known = false;
        bool dark = true;
        // A changed tint takes over only when another reading confirms it
        // after ConfirmTime.
        bool pending = false;
        bool pendingDark = false;
        Clock::time_point pendingSince{};
        // Initial reads are close together; later reads are three seconds
        // apart, including when the application paints continuously.
        Clock::time_point lastRead{};
        int warmupReads = 0;
        bool sampleScheduled = false;
        quint64 sampleToken = 0;
        // Latest geometry for the timer's repaint. A resize updates these
        // without restarting the fast sampling phase.
        QSizeF windowSize;
        QRectF panel;
    };
    QHash<KWin::EffectWindow *, CacheEntry> m_cache;
    quint64 m_nextSampleToken = 0;

    struct HitRects {
        // The drawn panel, and the pointer area it claims: the panel expanded
        // by the intercept margin, never beyond the window's own edge.
        QRectF panelRect;
        QRectF interceptRect;
        // The three lights, by position rather than by action: which action a
        // position means is typeAt()'s business, and asking it here is what
        // keeps a reordered panel clickable at the position it is drawn in.
        QRectF dots[TypeCount];
    };
    QHash<KWin::EffectWindow *, HitRects> m_hits;

    // The tiling menu, if one is open. Its rectangle is recomputed from the
    // current panel and window rectangles on every frame that draws the panel
    // and cleared on the frames that do not -- so a window that moves under an
    // open menu takes the menu with it instead of leaving it behind, and a
    // window whose panel goes away takes the menu with it too. It is what the
    // input filter hit-tests, and it is deliberately not a record of which
    // pixels the last frame painted: those are two different questions, and
    // answering the second one here is what once left the menu on screen taking
    // no clicks.
    struct TileMenuState {
        KWin::EffectWindow *window = nullptr;
        QRectF rect;
        std::optional<TilePreset> hovered;
        bool dark = true;
    };
    TileMenuState m_menu;

    // The geometry an adjust session has dragged into place but not yet
    // committed. Survives invalidateAll(): it belongs to a session that is still
    // running, and a configuration reload is not a reason to throw away what
    // the user is in the middle of doing.
    QHash<KWin::EffectWindow *, PanelGeometry> m_pending;
    QSet<KWin::EffectWindow *> m_adjusting;

    KWin::EffectWindow *m_hoverWindow = nullptr;
    Action m_hovered = Action::None;
};

} // namespace KOS
