#include "buttoninput.h"

#include "adjustsession.h"
#include "buttonconfig.h"
#include "windowquery.h"

#include <input_event.h>
#include <effect/effecthandler.h>
#include <effect/effectwindow.h>
#include <window.h>

#include <QDebug>

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

} // namespace

ButtonInput::ButtonInput(ButtonRenderer *renderer, ButtonConfig *config)
    : KWin::InputEventFilter(KWin::InputFilterOrder::Decoration)
    , m_renderer(renderer)
    , m_config(config)
    , m_session(std::make_unique<AdjustSession>(
          renderer, [config](const WindowMatcher &matcher,
                             const PanelGeometry &geometry) {
              return config && config->storeGeometry(matcher, geometry);
          }))
{
}

ButtonInput::~ButtonInput() = default;

bool ButtonInput::pointerMotion(KWin::PointerMotionEvent *event)
{
    if (!event || !m_renderer) {
        return false;
    }

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

    KWin::EffectWindow *window = nullptr;
    bool insidePanel = false;
    const ButtonRenderer::Action action =
        m_renderer->hitTest(event->position, &window, &insidePanel);

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
                    action == ButtonRenderer::Action::None ? nullptr : window,
                    action);
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
            action == ButtonRenderer::Action::None ? nullptr : window, action);

        // Alt over the zoom light opens the tiling menu. Alt is already KWin's
        // "this window is about to be moved with the pointer" modifier, so it
        // means something to this window anyway -- and the press that would
        // follow is swallowed by the panel, so nothing else comes of it.
        //
        // There is no need to check whether this window's menu is already open:
        // the light is inside the panel, the panel is inside the menu's own
        // region, and a pointer in that region returned above.
        if ((event->modifiers & Qt::AltModifier)
            && action == ButtonRenderer::Action::Maximize && window) {
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
    if (event->button == Qt::RightButton && insidePanel && window) {
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

bool ButtonInput::pointerAxis(KWin::PointerAxisEvent *event)
{
    if (!event || !m_renderer) {
        return false;
    }

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
    default:
        break;
    }

    return false;
}

void ButtonInput::forgetWindow(KWin::EffectWindow *window)
{
    m_session->forgetWindow(window);
    // A placement is about a window that no longer exists, and there is nothing
    // left to put back.
    m_placements.remove(window);
}

void ButtonInput::startSession(KWin::EffectWindow *window)
{
    if (!m_config) {
        return;
    }
    const WindowQuery query = windowQueryFor(window);
    const AppConfig config = m_config->getAppConfig(query);
    if (!m_session->begin(window, query, config.geometry)) {
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
    if (m_session->commit()) {
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

void ButtonInput::performAction(KWin::EffectWindow *window, ButtonRenderer::Action action)
{
    switch (action) {
    case ButtonRenderer::Action::Close:
        window->closeWindow();
        break;
    case ButtonRenderer::Action::Minimize:
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
