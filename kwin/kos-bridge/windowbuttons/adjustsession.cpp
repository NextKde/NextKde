#include "adjustsession.h"

#include <effect/effectwindow.h>

#include <QDebug>

#include "buttonrenderer.h"

namespace KOS
{

AdjustSession::AdjustSession(ButtonRenderer *renderer, Commit commit, Remove remove,
                             SiblingProbe siblingProbe)
    : m_renderer(renderer)
    , m_commit(std::move(commit))
    , m_remove(std::move(remove))
    , m_siblingProbe(std::move(siblingProbe))
{
}

bool AdjustSession::begin(KWin::EffectWindow *window, const WindowQuery &query,
                          const PanelGeometry &base,
                          std::optional<GeometryRule> existingRule)
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

    if (existingRule) {
        m_hasExistingRule = true;
        m_existingMatcher = existingRule->matcher;
        m_baseOverlayMode = existingRule->overlayMode;
        m_overlayMode = existingRule->overlayMode;
        m_baseScope = (existingRule->matcher.title.isEmpty()
                       && existingRule->matcher.titleRegex.isEmpty()
                       && existingRule->matcher.role.isEmpty())
            ? MatchScope::App : MatchScope::Window;
        m_scope = m_baseScope;
    } else {
        m_hasExistingRule = false;
        m_existingMatcher = WindowMatcher{};
        m_baseOverlayMode = OverlayMode::Cover;
        m_overlayMode = OverlayMode::Cover;
        m_baseScope = canToggleScope() ? MatchScope::Window : MatchScope::App;
        m_scope = m_baseScope;
    }

    syncOptions();
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

bool AdjustSession::canToggleScope() const
{
    return !m_query.role.isEmpty() || !m_query.caption.isEmpty();
}

void AdjustSession::setOverlayMode(OverlayMode mode)
{
    if (!m_window || m_overlayMode == mode) {
        return;
    }
    m_overlayMode = mode;
    syncOptions();
}

void AdjustSession::setMatchScope(MatchScope scope)
{
    if (!m_window || !canToggleScope() || m_scope == scope) {
        return;
    }
    m_scope = scope;
    syncOptions();
}

WindowMatcher AdjustSession::targetMatcher() const
{
    if (m_scope == MatchScope::App) {
        if (m_hasExistingRule && m_baseScope == MatchScope::App && !m_existingMatcher.isEmpty()) {
            return m_existingMatcher;
        }
        return appMatcher(m_query);
    }
    if (m_hasExistingRule && m_baseScope == MatchScope::Window
        && !m_existingMatcher.titleRegex.isEmpty()) {
        return m_existingMatcher;
    }
    // A roleless window with no distinct open sibling of the same class and
    // type commits as class+type so changing document or tab captions keep
    // the cover. A user who wants the caption honoured despite that can
    // hand-write a titleRegex rule, which the branch above preserves.
    if (m_query.role.isEmpty() && !m_siblingProbe(m_query)) {
        return appMatcher(m_query);
    }
    return adjustmentMatcher(m_query);
}

void AdjustSession::syncOptions()
{
    if (m_window && m_renderer) {
        m_renderer->setAdjustOptions(m_window, m_overlayMode, m_scope,
                                     canToggleScope(), !m_query.role.isEmpty(),
                                     m_hasExistingRule);
    }
}

bool AdjustSession::commit()
{
    if (!m_window) {
        return false;
    }

    const PanelGeometry geometry = m_geometry;
    const OverlayMode overlayMode = m_overlayMode;
    const WindowMatcher matcher = targetMatcher();
    const WindowMatcher previous = m_hasExistingRule ? m_existingMatcher : WindowMatcher{};
    const bool scopeChanged = m_hasExistingRule
        && matcher.canonicalKey() != m_existingMatcher.canonicalKey();
    const bool changed = !sameGeometry(m_base, geometry)
        || overlayMode != m_baseOverlayMode || scopeChanged;

    // Ended before the write, so that a write that fails leaves the panel
    // visibly back where the configuration puts it instead of showing an
    // adjustment that is not on disk.
    endSession();

    if (!changed) {
        // Nothing was moved. A rule storing the geometry that was already in
        // effect would be a second place the same answer is written down, and
        // it would take the panel out of the user's configuration for nothing.
        // A changed scope or overlay mode counts as a change even when the
        // geometry is identical, so a legacy caption-locked rule still gets
        // promoted to class+type by re-saving it here.
        qInfo() << "KOS: the panel for" << m_query.windowClass
                << "was not changed; nothing written";
        return true;
    }

    return m_commit ? m_commit(previous, matcher, geometry, overlayMode) : false;
}

bool AdjustSession::reset()
{
    if (!m_window) {
        return false;
    }
    const WindowMatcher toRemove = m_hasExistingRule ? m_existingMatcher : WindowMatcher{};
    const bool hadRule = m_hasExistingRule;
    endSession();
    if (!hadRule || !m_remove) {
        return true;
    }
    return m_remove(toRemove);
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
    m_hasExistingRule = false;
    m_existingMatcher = WindowMatcher{};
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
    m_hasExistingRule = false;
    m_existingMatcher = WindowMatcher{};
}

} // namespace KOS
