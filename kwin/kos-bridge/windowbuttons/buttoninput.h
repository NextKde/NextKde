#pragma once

#include <QHash>
#include <QSet>
#include <QRectF>

#include <memory>

#include <input.h>

#include "buttonrenderer.h"
#include "tilemenu.h"

namespace KWin
{
struct KeyboardKeyEvent;
struct PointerAxisEvent;
struct PointerButtonEvent;
struct PointerMotionEvent;
class EffectWindow;
}

namespace KOS
{

class AdjustSession;
class ButtonConfig;

// Intercepts pointer and key events that belong to one of our panels: the press
// performs the window action and is consumed so it never reaches the
// application's own buttons underneath, and motion is consumed so those buttons
// are not hovered either -- a panel that covered the controls but let the
// pointer through would have them light up around its edge.
//
// It is also where the adjust gesture lives: a right press on a panel starts an
// adjust session, and while one is running the presses, motion, wheel and keys
// that the session needs are taken here before anything else can see them.
//
// This filter is installed at InputFilterOrder::Decoration, and KWin installs
// its own DecorationEventFilter at the same weight. A later install at equal
// weight runs first (InputRedirection::installInputEventFilter inserts by
// std::lower_bound over ascending weight), so this one sees these events before
// the decoration does and returning true swallows them for good.
class ButtonInput final : public KWin::InputEventFilter
{
public:
    ButtonInput(ButtonRenderer *renderer, ButtonConfig *config);
    ~ButtonInput() override;

    bool pointerButton(KWin::PointerButtonEvent *event) override;
    bool pointerMotion(KWin::PointerMotionEvent *event) override;
    bool pointerAxis(KWin::PointerAxisEvent *event) override;
    bool keyboardKey(KWin::KeyboardKeyEvent *event) override;

    // The window is going away: an adjust session on it is over.
    void forgetWindow(KWin::EffectWindow *window);

private:
    void performAction(KWin::EffectWindow *window, ButtonRenderer::Action action);
    // Applies one cell of the tiling menu: KWin's own tiling and maximizing for
    // the halves and the whole area, and a placement this effect makes for the
    // thirds, which KWin has no notion of.
    void performTilePreset(KWin::EffectWindow *window, TilePreset preset);

    // Starts an adjust session on a window. A window that cannot be keyed by a
    // rule is refused, with a warning: the adjustment could not be saved.
    void startSession(KWin::EffectWindow *window);
    // Ends the running session, writing what was adjusted.
    void finishSession();
    // A press while a session is running.
    bool sessionPress(KWin::PointerButtonEvent *event, KWin::EffectWindow *window,
                      bool insidePanel);

    ButtonRenderer *m_renderer;
    ButtonConfig *m_config;
    std::unique_ptr<AdjustSession> m_session;

    // The button whose press was swallowed, and whose release therefore has to
    // be swallowed too: an application that receives a button-up for a
    // button-down it never saw is left with a stuck button.
    Qt::MouseButton m_consumedButton = Qt::NoButton;
    // The keys whose press was consumed while adjusting, for the same reason.
    QSet<int> m_consumedKeys;

    // What a third replaced, for the one preset that has to put it back.
    //
    // A half is a KWin tile and the whole area is a maximize, so KWin itself
    // remembers the geometry to return to and Restore only has to take the
    // window out of that state. A third is a placement this effect made, so
    // there is nobody else to remember: this is that memory, and it is used
    // only while the window is still where the placement left it -- a window
    // the user has moved or resized since is a window whose previous geometry
    // is no longer what "back to how it was" means.
    struct PlacementUndo {
        QRectF before;
        QRectF placed;
    };
    QHash<KWin::EffectWindow *, PlacementUndo> m_placements;
};

} // namespace KOS
