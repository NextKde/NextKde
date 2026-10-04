#include "adjustsession.h"

#include <effect/effectwindow.h>

#include <QDebug>

#include "buttonrenderer.h"

namespace KOS
{

AdjustSession::AdjustSession(ButtonRenderer *renderer, Commit commit)
    : m_renderer(renderer)
    , m_commit(std::move(commit))
{
}

bool AdjustSession::begin(KWin::EffectWindow *window, const WindowQuery &query,
                          const PanelGeometry &base)
{
    cancel();

    if (!window || !m_renderer) {
        return false;
    }
    // The rule is matched on the window class, so a window without one could
    // never be matched again: the adjustment would be lost the moment it was
    // made. Windows like that exist -- KWin's own surfaces, a client that has
    // not set a class yet -- and they simply cannot be tuned.
    if (query.windowClass.isEmpty()) {
        return false;
    }
    const QSizeF size = window->frameGeometry().size();
    if (size.width() <= 0 || size.height() <= 0) {
        return false;
    }

    m_window = window;
    m_query = query;
    m_base = base;
    m_geometry = base;
    m_dragging = false;
    m_resizeEdge.reset();

    m_renderer->setAdjusting(window, true);
    // The draft starts as the geometry already on screen, so a session that is
    // entered and left again changes nothing and writes nothing.
    m_renderer->setPendingGeometry(window, m_geometry);
    return true;
}

void AdjustSession::beginDrag(const QPointF &globalPos)
{
    if (!m_window) {
        return;
    }
    // The panel's unclipped origin: on a window too small for the panel the
    // drawn rect is cut down to the window, and grabbing by the clipped corner
    // would make the panel jump the moment the pointer moved.
    const QRectF frame = m_window->frameGeometry();
    const QPointF origin =
        frame.topLeft() + panelOrigin(m_geometry, frame.size());
    m_grabOffset = globalPos - origin;
    m_resizeEdge.reset();
    m_dragging = true;
}

void AdjustSession::beginResize(const QPointF &globalPos, PanelEdge edge)
{
    if (!m_window) {
        return;
    }
    m_resizeBase = m_geometry;
    m_dragStart = globalPos;
    m_resizeEdge = edge;
    m_dragging = true;
}

void AdjustSession::dragTo(const QPointF &globalPos)
{
    if (!m_window || !m_dragging) {
        return;
    }

    if (m_resizeEdge) {
        apply(clamped(resizedByEdge(m_resizeBase, *m_resizeEdge,
                                    globalPos - m_dragStart)));
        return;
    }

    const QRectF frame = m_window->frameGeometry();
    apply(panelGeometryFromTopLeft(m_geometry, frame.size(),
                                   globalPos - m_grabOffset - frame.topLeft()));
}

std::optional<PanelEdge> AdjustSession::edgeAt(const QPointF &globalPos) const
{
    if (!m_window) {
        return std::nullopt;
    }
    // Panel-local, and deliberately against the *unclipped* origin: the grips
    // are drawn there, and on a window too small for the panel it is the part
    // that is drawn that is being pulled at.
    const QRectF frame = m_window->frameGeometry();
    return gripAt(m_geometry,
                  globalPos - frame.topLeft() - panelOrigin(m_geometry, frame.size()));
}

void AdjustSession::endDrag()
{
    m_dragging = false;
    m_resizeEdge.reset();
}

void AdjustSession::resize(GeometryField field, qreal steps)
{
    if (!m_window) {
        return;
    }
    apply(resized(m_geometry, field, steps));
}

void AdjustSession::nudge(const QPointF &delta)
{
    if (!m_window) {
        return;
    }
    apply(nudged(m_geometry, m_window->frameGeometry().size(), delta));
}

bool AdjustSession::commit()
{
    if (!m_window) {
        return false;
    }

    const QString windowClass = m_query.windowClass;
    const PanelGeometry geometry = m_geometry;
    const bool changed = !sameGeometry(m_base, geometry);

    // Ended before the write, so that a write that fails leaves the panel
    // visibly back where the configuration puts it instead of showing an
    // adjustment that is not on disk.
    endSession();

    if (!changed) {
        // Nothing was moved. A rule storing the geometry that was already in
        // effect would be a second place the same answer is written down, and
        // it would take the panel out of the user's configuration for nothing.
        qInfo() << "KOS: the panel for" << windowClass
                << "was not changed; nothing written";
        return true;
    }

    WindowMatcher matcher;
    // The class alone. A title changes as the window is used, a role does not
    // exist on Wayland, and the type would only be a second way of saying what
    // the class already says -- while the class is the one thing about a window
    // that is the same now and the next time the application starts.
    matcher.className = windowClass;
    return m_commit(matcher, geometry);
}

void AdjustSession::cancel()
{
    if (m_window) {
        qInfo() << "KOS: discarded the panel adjustment for"
                << m_query.windowClass;
        endSession();
    }
}

void AdjustSession::forgetWindow(KWin::EffectWindow *window)
{
    if (m_window != window) {
        return;
    }
    // Deliberately no renderer calls: the window is being destroyed, and the
    // renderer has already dropped the draft and the adjust ring it held for it.
    m_window = nullptr;
    m_dragging = false;
    m_resizeEdge.reset();
}

void AdjustSession::apply(const PanelGeometry &geometry)
{
    if (!m_window || sameGeometry(m_geometry, geometry)) {
        return;
    }
    m_geometry = geometry;
    m_renderer->setPendingGeometry(m_window, m_geometry);
}

void AdjustSession::endSession()
{
    m_renderer->setAdjusting(m_window, false);
    m_renderer->clearPendingGeometry(m_window, m_base);
    m_window = nullptr;
    m_dragging = false;
    m_resizeEdge.reset();
}

} // namespace KOS
