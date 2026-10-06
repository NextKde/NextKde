#pragma once

#include <QPointF>
#include <QSizeF>
#include <QString>

#include <functional>

#include "panelgeometry.h"
#include "windowrules.h"

namespace KWin
{
class EffectWindow;
}

namespace KOS
{

class ButtonRenderer;

// One window's panel being positioned by hand.
//
// The session *is* the draft: it holds the geometry the panel is being dragged
// into and pushes it to the renderer, which draws it in place of the geometry
// the configuration resolves to. Committing turns the draft into a rule,
// cancelling drops it, and either way the panel is back on the configuration
// immediately afterwards.
//
// Nothing here reads the configuration or the compositor beyond the window's
// own frame geometry. All of the arithmetic is in panelgeometry.h, which the
// tests exercise without a compositor or a session.
class AdjustSession
{
public:
    // Writes a committed geometry. False when the file could not be written.
    using Commit =
        std::function<bool(const WindowMatcher &, const PanelGeometry &)>;

    AdjustSession(ButtonRenderer *renderer, Commit commit);

    bool active() const { return m_window != nullptr; }
    KWin::EffectWindow *window() const { return m_window; }
    // The class a commit would be written against. For the log line that says
    // what was saved, which is the only readout of a commit there is.
    QString windowClass() const { return m_query.windowClass; }
    bool dragging() const { return m_dragging; }

    // Starts a session with the panel where it already is. False -- with
    // nothing changed -- for a window that cannot be keyed by a rule, or one
    // with no area to put a panel in.
    bool begin(KWin::EffectWindow *, const WindowQuery &,
               const PanelGeometry &base);

    // The panel follows the pointer, keeping the point that was grabbed under
    // it. `globalPos` is in global logical pixels.
    void beginDrag(const QPointF &globalPos);
    // One edge of the panel follows the pointer instead, and the opposite edge
    // stays where it is: the width grip changes how wide the panel is, the
    // height grip how tall, and neither touches the lights.
    void beginResize(const QPointF &globalPos, PanelEdge);
    void dragTo(const QPointF &globalPos);
    void endDrag();

    // The resize grip under a global position, if any. A press inside a panel
    // picks between moving it and sizing it with this.
    std::optional<PanelEdge> edgeAt(const QPointF &globalPos) const;

    // Wheel steps: one call is one notch, positive towards a larger value.
    void resize(GeometryField, qreal steps);
    // Arrow keys, in logical pixels.
    void nudge(const QPointF &delta);

    // Writes the draft as a rule. False when the write failed -- the draft is
    // dropped either way, so a failed commit leaves the panel visibly back where
    // the configuration puts it rather than looking saved and not being.
    bool commit();
    // Drops the draft. The panel returns to the configuration's geometry.
    void cancel();

    // The window is going away. Ends the session without touching the renderer,
    // which has already dropped everything it held for the window.
    void forgetWindow(KWin::EffectWindow *);

private:
    void apply(const PanelGeometry &);
    void endSession();

    ButtonRenderer *m_renderer;
    Commit m_commit;

    KWin::EffectWindow *m_window = nullptr;
    WindowQuery m_query;
    // The geometry the configuration resolved to when the session started, for
    // the repaint when the draft is dropped and for deciding whether the draft
    // is worth writing at all.
    PanelGeometry m_base;
    PanelGeometry m_geometry;
    // A drag of either kind is in progress. Which kind it is hangs on
    // `m_resizeEdge`: no edge means the panel as a whole is following the
    // pointer.
    bool m_dragging = false;
    std::optional<PanelEdge> m_resizeEdge;
    // The geometry the resize started from, and where the pointer was then.
    // Deltas are measured against these rather than accumulated per event, so a
    // drag that runs into one of the bounds and comes back out resumes from
    // where the pointer is instead of drifting away from it.
    PanelGeometry m_resizeBase;
    QPointF m_dragStart;
    // Pointer position minus the panel's top-left at the moment of the grab, so
    // the panel does not jump to centre itself under the pointer.
    QPointF m_grabOffset;
};

} // namespace KOS
