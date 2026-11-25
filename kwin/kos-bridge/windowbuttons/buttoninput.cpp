#include "buttoninput.h"

#include "adjustsession.h"
#include "buttonconfig.h"
#include "windowquery.h"

#include <input_event.h>
#include <effect/effecthandler.h>
#include <effect/effectwindow.h>
#include <window.h>

#include <QDebug>

#include <limits>

namespace KOS
{

namespace
{

// Arrow keys, in logical pixels. A plain arrow moves the panel by one pixel,
// which is the point of the arrows -- they are for the last pixel or two after
// a drag -- and the shift of one follows the same 1/10 convention the arrows
// have everywhere else.
constexpr qreal NudgeStep = 1.0;
constexpr qreal NudgeStepLarge = 10.0;

// How many notches of a wheel one call carries.
//
// 120 is one notch in both fields: `deltaV120` is the platform's own
// 120-per-notch count, and the logical delta is handed on to Qt as an angle
// delta, which counts in the same 120. A mouse wheel fills both; a touchpad
// leaves `deltaV120` at zero and scrolls smoothly, so the logical delta is used
// and a resize then follows the fingers.
qreal axisSteps(const KWin::PointerAxisEvent *event)
{
    if (event->orientation != Qt::Orientation::Vertical) {
        return 0.0;
    }
    if (event->deltaV120 != 0) {
        return event->deltaV120 / 120.0;
    }
    return event->delta / 120.0;
}

// KWin's rectangles and Qt's are the same four numbers. These two carry one
// across at the points where the two meet -- KWin's RectF takes a QRectF by
// itself, so only this direction needs writing down.
QRectF toQt(const KWin::RectF &rect)
{
    return QRectF(rect.x(), rect.y(), rect.width(), rect.height());
}

// Whether two rectangles are the same place, to within the sub-pixel jitter a
// fractional scale leaves behind (KWin reports a restored width of
// 1345.9999999999998).
bool sameRect(const QRectF &a, const QRectF &b)
{
    constexpr qreal Tolerance = 0.5;
    return qAbs(a.x() - b.x()) <= Tolerance && qAbs(a.y() - b.y()) <= Tolerance
        && qAbs(a.width() - b.width()) <= Tolerance
        && qAbs(a.height() - b.height()) <= Tolerance;
}

// The area a window on this screen may occupy: the one maximizing it would use,
// so that a third of the screen is a third of what a maximized window covers --
// struts (a panel, a dock) excluded, on the screen the window is on rather than
// the one the pointer is on.
QRectF clientAreaFor(const KWin::EffectWindow *window)
{
    if (!KWin::effects) {
        return QRectF();
    }
    return toQt(KWin::effects->clientArea(KWin::MaximizeArea, window));
}

// Takes the window out of both of the whole-window states -- tiled and
// maximized -- that a placement has to leave before it can be made. Nothing
// here restores a geometry of its own: what KWin puts back on the way out is
// where Restore, and a drag, expect the window to be.
void leaveWholeWindowState(KWin::Window *window)
{
    if (window->requestedQuickTileMode()
        != KWin::QuickTileMode(KWin::QuickTileFlag::None)) {
        window->setQuickTileMode(KWin::QuickTileFlag::None,
                                 window->frameGeometry().center());
    }
    if (window->maximizeMode() != KWin::MaximizeRestore) {
        window->maximize(KWin::MaximizeRestore);
    }
}

bool isManagedPanelWindow(const KWin::EffectWindow *window)
{
    if (!window || window->isDeleted() || !window->isManaged()) {
        return false;
    }
    if (!window->isNormalWindow() && !window->isDialog()) {
        return false;
    }
    if (window->isSkipSwitcher() || window->isSpecialWindow()) {
        return false;
    }
    if (const KWin::Window *native = window->window(); native && native->isInternal()) {
        return false;
    }
    return true;
}

} // namespace

ButtonInput::ButtonInput(ButtonRenderer *renderer, ButtonConfig *config)
    : KWin::InputEventFilter(KWin::InputFilterOrder::Decoration)
    , m_renderer(renderer)
    , m_config(config)
    , m_session(std::make_unique<AdjustSession>(
          renderer,
          [this, config](const WindowMatcher &previous,
                         const WindowMatcher &target,
                         const PanelGeometry &geometry,
                         OverlayMode mode) {
              const bool ok = config && config->replaceRule(previous, target, geometry, mode);
              if (ok && m_pendingActionWindow) {
                  if (auto it = m_windowStates.find(m_pendingActionWindow);
                      it != m_windowStates.end()) {
                      it->pinnedRule.reset();
                  }
              }
              return ok;
          },
          [this, config](const WindowMatcher &matcher) {
              const bool ok = config && config->removeRule(matcher);
              if (ok && m_pendingActionWindow) {
                  if (auto it = m_windowStates.find(m_pendingActionWindow);
                      it != m_windowStates.end()) {
                      it->pinnedRule.reset();
                  }
              }
              return ok;
          },
          // Collects open-sibling and caption-history context for roleless
          // windows so secondary windows default to title scope (without
          // overwriting the primary app rule) while primary windows default
          // to app scope and structured titles generalize cleanly.
          [this](KWin::EffectWindow *window, const WindowQuery &query) {
              return scopeContextFor(window, query);
          }))
{
}

ButtonInput::~ButtonInput() = default;

void ButtonInput::fullscreenChanged(KWin::EffectWindow *window)
{
    if (!window || !window->isFullScreen() || !m_renderer) {
        return;
    }
    if (m_session->window() == window) {
        m_session->cancel();
    }
    // Also clears source-capture hits and closes this window's tiling menu.
    m_renderer->clearHits(window, true);
    // Keep consumed press bookkeeping until its matching release arrives.
}

void ButtonInput::clearFullscreenState()
{
    // Check only the two transient owners, without walking the window stack.
    // This also protects input arriving before the state-change callback.
    fullscreenChanged(m_session->window());
    fullscreenChanged(m_renderer->tileMenuWindow());
}

bool ButtonInput::pointerMotion(KWin::PointerMotionEvent *event)
{
    if (!event || !m_renderer) {
        return false;
    }
    clearFullscreenState();

    // A drag of a panel is this filter's own, and stays swallowed wherever the
    // pointer goes. It is tested before the pass-through below, which would
    // otherwise end the drag the moment it left the panel: the button it
    // carries was consumed here and never reached an application, so the test
    // for "a button held from somewhere else" does not apply to it.
    if (m_session->dragging()) {
        m_session->dragTo(event->position);
        return true;
    }

    // A drag that began elsewhere -- a text selection, a slider -- has to keep
    // its motion even where it passes over a panel, or the application's drag
    // freezes for as long as the pointer is there.
    if (event->buttons != Qt::NoButton && m_consumedButtons == Qt::NoButton) {
        return false;
    }

    if (m_session->active()) {
        if (m_renderer->adjustBarContains(event->position)) {
            m_renderer->setAdjustBarHovered(event->position);
            return true;
        }
        m_renderer->setAdjustBarHovered(QPointF(-1e9, -1e9));
    }

    KWin::EffectWindow *window = nullptr;
    bool insidePanel = false;
    bool nearLights = false;
    const ButtonRenderer::Action action =
        m_renderer->hitTest(event->position, &window, &insidePanel, &nearLights);

    // An open menu takes the pointer before the panel does. It hangs from the
    // panel's bottom edge, and the first few rows of it are inside the panel's
    // intercept margin: those pixels belong to the menu, or a click on the top
    // row of cells would be swallowed by the panel and do nothing.
    //
    // Leaving the menu and the panel it hangs from closes it, and that motion
    // then goes on to be handled as if it had never been open.
    if (m_renderer->tileMenuWindow()) {
        if (m_renderer->tileMenuRegionContains(event->position)) {
            m_renderer->setTileMenuHovered(event->position);
            if (!m_session->active()) {
                m_renderer->setHovered(
                    (action == ButtonRenderer::Action::None && !insidePanel) ? nullptr : window,
                    action, insidePanel, nearLights);
            }
            return true;
        }
        m_renderer->closeTileMenu();
    }

    // No hover while a session is running: the renderer draws the adjust ring
    // instead, and tracking a hover over a panel that is being positioned would
    // only repaint it for nothing.
    if (!m_session->active()) {
        m_renderer->setHovered(
            (action == ButtonRenderer::Action::None && !insidePanel) ? nullptr : window,
            action, insidePanel, nearLights);

        // Alt over the zoom light opens the tiling menu. Alt is already KWin's
        // "this window is about to be moved with the pointer" modifier, so it
        // means something to this window anyway -- and the press that would
        // follow is swallowed by the panel, so nothing else comes of it.
        //
        // There is no need to check whether this window's menu is already open:
        // the light is inside the panel, the panel is inside the menu's own
        // region, and a pointer in that region returned above.
        if ((event->modifiers & Qt::AltModifier)
            && action == ButtonRenderer::Action::Maximize && window && !m_renderer->cooperativeControls(window)) {
            m_renderer->openTileMenu(window);
        }
    }

    // Swallowing the motion is the point of the panel as far as the pointer is
    // concerned: the controls it covers are still there and the application
    // goes on highlighting them -- visibly, around the edge of a panel that is
    // not quite as large as they are -- as long as it keeps receiving motion
    // over them.
    //
    // Motion only. KWin has already moved the cursor and decided the window
    // under the pointer before any filter runs (see
    // PointerInputRedirection::processMotionInternal), and delivery to the
    // application happens in the last filter of the chain, so consuming this
    // stops the application from seeing the pointer and nothing else.
    return insidePanel;
}

bool ButtonInput::pointerButton(KWin::PointerButtonEvent *event)
{
    if (!event || !m_renderer) {
        return false;
    }
    clearFullscreenState();

    if (event->state == KWin::PointerButtonState::Released) {
        if (m_session->dragging() && event->button == Qt::LeftButton) {
            m_session->endDrag();
        }
        // Swallow the release that belongs to a press we already swallowed so
        // the application does not see a stray button-up.
        if (m_consumedButtons.testFlag(event->button)) {
            m_consumedButtons &= ~Qt::MouseButtons(event->button);
            return true;
        }
        return false;
    }

    if (event->state != KWin::PointerButtonState::Pressed) {
        return false;
    }

    // A press while the tiling menu is open belongs to the menu, wherever it
    // lands. On a cell, that is the cell's work; anywhere else -- on the panel,
    // on the window, on nothing -- the press only dismisses it, and does not
    // also become a press on whatever was under it. That is how a menu behaves
    // everywhere, and here it is also what stops an Alt+click on the light that
    // opened the menu from closing the window on the way to putting the menu
    // away.
    if (KWin::EffectWindow *menuWindow = m_renderer->tileMenuWindow()) {
        m_consumedButtons |= event->button;
        const std::optional<TilePreset> preset =
            event->button == Qt::LeftButton
                && m_renderer->tileMenuRegionContains(event->position)
            ? m_renderer->tileMenuPresetAt(event->position)
            : std::nullopt;
        m_renderer->closeTileMenu();
        if (preset) {
            performTilePreset(menuWindow, *preset);
        }
        return true;
    }

    KWin::EffectWindow *window = nullptr;
    bool insidePanel = false;
    const ButtonRenderer::Action action =
        m_renderer->hitTest(event->position, &window, &insidePanel);

    if (m_session->active()) {
        return sessionPress(event, window, insidePanel);
    }

    // A right press on a panel is how an adjustment starts. It is swallowed
    // whether or not a session begins, as every press on the panel is -- an
    // application's context menu must not open through the panel.
    if (event->button == Qt::RightButton && insidePanel && window && !window->hasDecoration() && !m_renderer->cooperativeControls(window)) {
        m_consumedButtons |= event->button;
        startSession(window);
        return true;
    }

    if (!insidePanel || !window) {
        return false;
    }

    // Anywhere on the panel is swallowed, whatever the button, so that nothing
    // lands on the controls underneath; only the left button acts, so a
    // right-click meant to open the application's own context menu cannot
    // close the window instead.
    m_consumedButtons |= event->button;
    if (event->button == Qt::LeftButton) {
        performAction(window, action);
    }
    return true;
}

bool ButtonInput::sessionPress(KWin::PointerButtonEvent *event,
                               KWin::EffectWindow *window, bool insidePanel)
{
    if (event->button == Qt::RightButton) {
        // A right press means "done", wherever it lands -- on the panel being
        // adjusted, on another panel (which is then the one being adjusted
        // instead, so moving from one window to the next needs no trip through
        // cancelling first), or on anything else. It is the gesture that started
        // the session, so it is the one that ends it, and it saves: Esc is there
        // for anyone who wants the draft dropped, and a right press that quietly
        // threw the work away would make the gesture that opens this mode the
        // one that loses what was done in it.
        const bool elsewhere =
            insidePanel && window && window != m_session->window();
        m_consumedButtons |= event->button;
        finishSession();
        if (elsewhere) {
            startSession(window);
        }
        return true;
    }

    if (event->button == Qt::LeftButton) {
        if (m_renderer->adjustBarContains(event->position)) {
            m_consumedButtons |= event->button;
            if (const auto barAction = m_renderer->adjustBarActionAt(event->position)) {
                switch (*barAction) {
                case AdjustAction::ModeCover:
                    m_session->setOverlayMode(OverlayMode::Cover);
                    break;
                case AdjustAction::ModeTransparent:
                    m_session->setOverlayMode(OverlayMode::Transparent);
                    break;
                case AdjustAction::ModeHidden:
                    m_session->setOverlayMode(OverlayMode::Hidden);
                    finishSession();
                    break;
                case AdjustAction::ScopeWindow:
                    m_session->setMatchScope(MatchScope::Window);
                    break;
                case AdjustAction::ScopeApp:
                    m_session->setMatchScope(MatchScope::App);
                    break;
                case AdjustAction::Reset:
                    resetSession();
                    break;
                case AdjustAction::Done:
                    finishSession();
                    break;
                case AdjustAction::None:
                    break;
                }
            }
            return true;
        }
        if (insidePanel && window == m_session->window()) {
            // Pressed on the panel: the edge under the pointer is dragged, or --
            // anywhere else on it -- the panel as a whole follows the pointer.
            m_consumedButtons |= event->button;
            const std::optional<PanelEdge> edge =
                m_session->edgeAt(event->position);
            if (edge) {
                m_session->beginResize(event->position, *edge);
            } else {
                m_session->beginDrag(event->position);
            }
            return true;
        }
        // Pressed anywhere else: the adjustment is over and this press goes on
        // to do what it was aimed at. It is not swallowed.
        finishSession();
        return pointerButton(event);
    }

    // Every other button: swallowed, as it is when no session is running, and
    // the session goes on. A scroll-wheel click in the middle of positioning a
    // panel is not a decision about the panel.
    m_consumedButtons |= event->button;
    return true;
}

void ButtonInput::cancelAdjustment()
{
    m_session->cancel();
    m_renderer->closeTileMenu();
}

bool ButtonInput::pointerAxis(KWin::PointerAxisEvent *event)
{
    if (!event || !m_renderer) {
        return false;
    }
    clearFullscreenState();

    // While adjusting, the wheel resizes the panel, and it is taken whether or
    // not the pointer is still on it: the pointer is free to leave the panel
    // mid-drag, and a wheel that reached KWin from there would shade the window
    // out from under the resize.
    if (m_session->active()) {
        const qreal steps = axisSteps(event);
        if (steps != 0.0) {
            if (event->modifiers & Qt::ControlModifier) {
                m_session->resize(GeometryField::Padding, steps);
            } else if (event->modifiers & Qt::ShiftModifier) {
                m_session->resize(GeometryField::Spacing, steps);
            } else {
                m_session->resize(GeometryField::DotSize, steps);
            }
        }
        return true;
    }

    KWin::EffectWindow *window = nullptr;
    bool insidePanel = false;
    m_renderer->hitTest(event->position, &window, &insidePanel);

    // A wheel over the open menu is taken on a window KWin decorates itself,
    // for the same reason it is taken over the panel: there it would shade the
    // window. On a client-side decorated window it is left alone, and scrolls
    // the content behind the menu -- which is what the menu is over.
    if (KWin::EffectWindow *menuWindow = m_renderer->tileMenuWindow()) {
        if (m_renderer->tileMenuRegionContains(event->position)
            && menuWindow->hasDecoration()) {
            return true;
        }
    }

    // A server-side decorated window has nothing under the panel but the
    // decoration's own title bar, which KWin turns a wheel over into shading
    // the window. The panel takes the wheel there, so that a wheel over it does
    // nothing rather than something none of the panel's own buttons do.
    if (insidePanel && window && window->hasDecoration()) {
        return true;
    }

    // Client-side decorated: the wheel is left alone. There the panel sits over
    // the application's own content -- a tab strip, a page, a list -- and the
    // pointer happening to be on the panel is no reason for that to stop
    // scrolling.
    return false;
}

bool ButtonInput::keyboardKey(KWin::KeyboardKeyEvent *event)
{
    if (!event || !m_renderer) {
        return false;
    }
    clearFullscreenState();

    if (event->state == KWin::KeyboardKeyState::Released) {
        if (m_consumedKeys.remove(event->key)) {
            return true;
        }
        return false;
    }

    // Escape closes the tiling menu, and belongs to it: while one is open it is
    // the thing that key is about.
    if (event->key == Qt::Key_Escape && m_renderer->tileMenuWindow()) {
        m_consumedKeys.insert(event->key);
        m_renderer->closeTileMenu();
        return true;
    }

    // A terminating key can repeat after closing the menu or session. Its
    // repeats belong to the same consumed press until the matching release.
    if (!m_session->active()) {
        return m_consumedKeys.contains(event->key);
    }

    switch (event->key) {
    case Qt::Key_Escape:
        m_consumedKeys.insert(event->key);
        m_session->cancel();
        return true;
    case Qt::Key_Return:
    case Qt::Key_Enter:
        m_consumedKeys.insert(event->key);
        finishSession();
        return true;
    case Qt::Key_Left:
    case Qt::Key_Right:
    case Qt::Key_Up:
    case Qt::Key_Down: {
        const qreal step = (event->modifiers & Qt::ShiftModifier) ? NudgeStepLarge
                                                                 : NudgeStep;
        QPointF delta;
        switch (event->key) {
        case Qt::Key_Left:
            delta = QPointF(-step, 0);
            break;
        case Qt::Key_Right:
            delta = QPointF(step, 0);
            break;
        case Qt::Key_Up:
            delta = QPointF(0, -step);
            break;
        default:
            delta = QPointF(0, step);
            break;
        }
        m_consumedKeys.insert(event->key);
        m_session->nudge(delta);
        return true;
    }
    case Qt::Key_M:
    case Qt::Key_C:
        m_consumedKeys.insert(event->key);
        m_session->setOverlayMode(OverlayMode::Cover);
        return true;
    case Qt::Key_T:
        m_consumedKeys.insert(event->key);
        m_session->setOverlayMode(m_session->overlayMode() == OverlayMode::Transparent
                                      ? OverlayMode::Cover
                                      : OverlayMode::Transparent);
        return true;
    case Qt::Key_H:
        m_consumedKeys.insert(event->key);
        m_session->setOverlayMode(OverlayMode::Hidden);
        finishSession();
        return true;
    case Qt::Key_S:
        if (m_session->canToggleScope()) {
            m_consumedKeys.insert(event->key);
            m_session->setMatchScope(m_session->matchScope() == MatchScope::App
                                          ? MatchScope::Window
                                          : MatchScope::App);
            return true;
        }
        break;
    case Qt::Key_Backspace:
    case Qt::Key_Delete:
        m_consumedKeys.insert(event->key);
        resetSession();
        return true;
    default:
        break;
    }

    return false;
}

void ButtonInput::forgetWindow(KWin::EffectWindow *window)
{
    m_session->forgetWindow(window);
    if (m_pendingActionWindow == window) {
        m_pendingActionWindow = nullptr;
    }
    m_windowStates.remove(window);
    // A placement is about a window that no longer exists, and there is nothing
    // left to put back.
    m_placements.remove(window);
}

void ButtonInput::trackWindow(KWin::EffectWindow *window)
{
    if (!isManagedPanelWindow(window) || m_windowStates.contains(window)) {
        return;
    }
    m_windowStates.insert(window, WindowTrackState{
        .order = ++m_windowOrderSeq,
        .lastCaption = window->caption(),
        .dynamicCaption = false,
        .pinnedRule = std::nullopt,
    });
}

void ButtonInput::reconfigured()
{
    cancelAdjustment();
    for (auto it = m_windowStates.begin(); it != m_windowStates.end(); ++it) {
        it->pinnedRule.reset();
    }
}

AppConfig ButtonInput::configForWindow(KWin::EffectWindow *window) const
{
    if (!m_config) {
        return AppConfig{};
    }
    const auto it = m_windowStates.constFind(window);
    const std::optional<GeometryRule> pinned =
        (it != m_windowStates.constEnd()) ? it->pinnedRule : std::nullopt;
    return m_config->getAppConfig(windowQueryFor(window), pinned);
}

WindowScopeContext ButtonInput::scopeContextFor(KWin::EffectWindow *window,
                                                const WindowQuery &query) const
{
    WindowScopeContext ctx;
    const auto selfIt = m_windowStates.constFind(window);
    ctx.dynamicCaption = selfIt != m_windowStates.constEnd() && selfIt->dynamicCaption;
    const quint64 selfOrder = selfIt != m_windowStates.constEnd()
        ? selfIt->order
        : std::numeric_limits<quint64>::max();

    if (!KWin::effects || query.windowClass.isEmpty()) {
        return ctx;
    }

    const auto windows = KWin::effects->stackingOrder();
    for (KWin::EffectWindow *other : windows) {
        if (!other || other == window || !isManagedPanelWindow(other)) {
            continue;
        }
        if (other->windowClass() != query.windowClass
            || other->windowTypeInt() != query.type) {
            continue;
        }
        const QString otherCaption = other->caption();
        if (otherCaption.isEmpty() || otherCaption == query.caption) {
            continue;
        }
        if (!ctx.siblingCaptions.contains(otherCaption)) {
            ctx.siblingCaptions.append(otherCaption);
        }

        const auto otherIt = m_windowStates.constFind(other);
        if (otherIt != m_windowStates.constEnd()) {
            if (otherIt->order < selfOrder) {
                ctx.hasOlderSibling = true;
            }
            if (otherIt->dynamicCaption) {
                ctx.hasDynamicSibling = true;
            }
        }

        bool otherHasWindowRule =
            otherIt != m_windowStates.constEnd() && otherIt->pinnedRule.has_value();
        if (!otherHasWindowRule && m_config) {
            GeometryRule otherRule;
            if (m_config->findStoredRule(windowQueryFor(other), &otherRule)
                && matcherScope(otherRule.matcher) == MatchScope::Window) {
                otherHasWindowRule = true;
            }
        }
        if (!otherHasWindowRule) {
            ctx.hasUnscopedSibling = true;
        }
    }
    return ctx;
}

void ButtonInput::captionChanged(KWin::EffectWindow *window)
{
    if (!isManagedPanelWindow(window) || m_session->window() == window) {
        return;
    }
    trackWindow(window);
    auto stateIt = m_windowStates.find(window);
    if (stateIt == m_windowStates.end()) {
        return;
    }
    WindowTrackState &state = stateIt.value();
    const QString oldCaption = state.lastCaption;
    const QString newCaption = window->caption();
    if (oldCaption == newCaption) {
        return;
    }

    const WindowQuery currentQuery = windowQueryFor(window);
    WindowQuery previousQuery = currentQuery;
    previousQuery.caption = oldCaption;

    std::optional<GeometryRule> activePrevWindowRule;
    if (state.pinnedRule) {
        activePrevWindowRule = *state.pinnedRule;
    } else if (m_config && !oldCaption.isEmpty()) {
        GeometryRule stored;
        if (m_config->findStoredRule(previousQuery, &stored)
            && matcherScope(stored.matcher) == MatchScope::Window) {
            activePrevWindowRule = stored;
        }
    }

    state.lastCaption = newCaption;
    if (!state.dynamicCaption) {
        const CaptionTransition transition = classifyCaptionTransition(
            currentQuery.windowClass, oldCaption, newCaption);
        if (transition != CaptionTransition::Unchanged
            && transition != CaptionTransition::StartupPlaceholder) {
            state.dynamicCaption = true;
        }
    }

    if (!activePrevWindowRule || !m_config) {
        return;
    }

    GeometryRule currentMatched;
    const std::optional<GeometryRule> currentMatchedOpt =
        m_config->findStoredRule(currentQuery, &currentMatched)
            ? std::optional<GeometryRule>(currentMatched)
            : std::nullopt;
    const WindowScopeContext ctx = scopeContextFor(window, currentQuery);
    const CaptionAdaptation adaptation = adaptRuleForCaptionChange(
        previousQuery, currentQuery, *activePrevWindowRule, currentMatchedOpt, ctx);

    switch (adaptation.kind) {
    case CaptionAdaptation::Kind::None:
        if (activePrevWindowRule->matcher.matches(currentQuery)
            || (currentMatchedOpt
                && matcherScope(currentMatchedOpt->matcher) == MatchScope::Window)) {
            state.pinnedRule.reset();
        }
        break;
    case CaptionAdaptation::Kind::UpgradeToPrefixRegex:
        if (m_config->replaceRule(activePrevWindowRule->matcher,
                                  adaptation.targetMatcher,
                                  activePrevWindowRule->geometry,
                                  activePrevWindowRule->overlayMode)) {
            state.pinnedRule.reset();
            qInfo() << "KOS: generalized title rule for" << currentQuery.windowClass
                    << "to" << adaptation.targetMatcher.titleRegex;
        } else {
            state.pinnedRule = *activePrevWindowRule;
        }
        break;
    case CaptionAdaptation::Kind::PromoteToApp:
        if (m_config->replaceRule(activePrevWindowRule->matcher,
                                  adaptation.targetMatcher,
                                  activePrevWindowRule->geometry,
                                  activePrevWindowRule->overlayMode)) {
            state.pinnedRule.reset();
            qInfo() << "KOS: promoted title rule for" << currentQuery.windowClass
                    << "to app scope after caption change";
        } else {
            state.pinnedRule = *activePrevWindowRule;
        }
        break;
    case CaptionAdaptation::Kind::PinInSession:
        state.pinnedRule = *activePrevWindowRule;
        break;
    }
}

void ButtonInput::startSession(KWin::EffectWindow *window)
{
    if (!m_config) {
        return;
    }
    trackWindow(window);
    const WindowQuery query = windowQueryFor(window);
    const AppConfig config = configForWindow(window);
    GeometryRule existingRule;
    std::optional<GeometryRule> foundRule;
    if (m_config->findStoredRule(query, &existingRule)) {
        foundRule = existingRule;
    }
    if (!foundRule || matcherScope(foundRule->matcher) == MatchScope::App) {
        if (const auto it = m_windowStates.constFind(window);
            it != m_windowStates.constEnd() && it->pinnedRule) {
            foundRule = *it->pinnedRule;
        }
    }
    if (!m_session->begin(window, query, config.geometry, foundRule)) {
        qWarning() << "KOS: not adjusting the panel on this window: it has no"
                   << "window class to write a rule against, or no area to put a"
                   << "panel in";
    }
}

void ButtonInput::finishSession()
{
    if (!m_session->active()) {
        return;
    }
    const QString windowClass = m_session->windowClass();
    m_pendingActionWindow = m_session->window();
    const bool committed = m_session->commit();
    m_pendingActionWindow = nullptr;
    if (committed) {
        // The file is the readout -- there is no on-screen one -- so the line
        // that says an adjustment was saved is how anyone can tell a save from a
        // discard without opening the file.
        qInfo() << "KOS: saved the panel adjustment for" << windowClass << "to"
                << (m_config ? m_config->rulesPath() : QString());
    } else if (m_config) {
        qWarning() << "KOS: could not write" << m_config->rulesPath()
                   << "- the panel adjustment for" << windowClass
                   << "was not saved";
    }
}

void ButtonInput::resetSession()
{
    if (!m_session->active()) {
        return;
    }
    m_pendingActionWindow = m_session->window();
    m_session->reset();
    m_pendingActionWindow = nullptr;
}

void ButtonInput::performAction(KWin::EffectWindow *window, ButtonRenderer::Action action)
{
    switch (action) {
    case ButtonRenderer::Action::Close:
        m_renderer->setHovered(nullptr, ButtonRenderer::Action::None);
        window->closeWindow();
        break;
    case ButtonRenderer::Action::Minimize:
        m_renderer->setHovered(nullptr, ButtonRenderer::Action::None);
        window->minimize();
        break;
    case ButtonRenderer::Action::Maximize:
        if (KWin::Window *w = window->window()) {
            w->maximize(w->maximizeMode() == KWin::MaximizeFull
                            ? KWin::MaximizeRestore
                            : KWin::MaximizeFull);
        }
        break;
    case ButtonRenderer::Action::None:
        break;
    }
}

void ButtonInput::performTilePreset(KWin::EffectWindow *window, TilePreset preset)
{
    KWin::Window *w = window ? window->window() : nullptr;
    if (!w) {
        return;
    }

    switch (preset) {
    case TilePreset::Fill:
        w->maximize(KWin::MaximizeFull);
        return;

    case TilePreset::LeftHalf:
    case TilePreset::RightHalf:
        // KWin's own tiling, so that this menu and the keyboard are one state
        // rather than two: a window tiled from here is one that Meta+Right can
        // put a neighbour beside, and one that drags back out to the size it
        // had before it was tiled.
        //
        // The point the tile is taken at is the window's own centre. KWin uses
        // it to decide which screen the tile belongs to, and the screen the
        // window is on is the one that matters -- not wherever the pointer
        // happens to be when the menu is clicked. (KWin's own
        // setQuickTileModeAtCurrentPosition does the same thing.)
        w->setQuickTileMode(preset == TilePreset::LeftHalf
                                ? KWin::QuickTileFlag::Left
                                : KWin::QuickTileFlag::Right,
                            w->frameGeometry().center());
        return;

    case TilePreset::Restore:
        // Out of whatever whole-window state the window is in. Both of these
        // are KWin's own, and KWin remembers what to put back for both.
        leaveWholeWindowState(w);
        // And back to what a placement replaced, if a placement is what put the
        // window where it is: that one is this effect's own doing and nobody
        // else remembers it. Only while the window is still exactly where the
        // placement left it -- a window the user has moved since would
        // otherwise jump to somewhere it has not been for a while.
        if (const auto undo = m_placements.constFind(window);
            undo != m_placements.constEnd()
            && sameRect(toQt(w->moveResizeGeometry()), undo->placed)) {
            w->moveResize(undo->before);
        }
        return;

    case TilePreset::LeftThird:
    case TilePreset::LeftTwoThirds:
    case TilePreset::RightTwoThirds:
    case TilePreset::RightThird: {
        // KWin has no tile for these -- there is nothing for setQuickTileMode
        // to ask for -- so the window is placed instead: taken out of any
        // whole-window state, and then given the rectangle.
        //
        // The order is the whole of why it works. Maximizing, tiling and
        // moveResize all apply their geometry when the client has acknowledged
        // it, so what a window ends up with is the last request sent -- and a
        // request sent before the window was taken out of the state would be
        // overruled by the geometry that leaving it puts back.
        const QRectF target = tilePresetRect(preset, clientAreaFor(window));
        if (target.isEmpty()) {
            return;
        }
        // What the placement replaces, read before the window is taken out of
        // its state: a maximized window replaced the maximized rectangle, and
        // that -- not the geometry the maximize was hiding -- is where Restore
        // should put it back.
        const QRectF before = toQt(w->moveResizeGeometry());
        leaveWholeWindowState(w);
        m_placements[window] = PlacementUndo{before, target};
        w->moveResize(target);
        return;
    }

    case TilePreset::Count:
        break;
    }
}

} // namespace KOS
