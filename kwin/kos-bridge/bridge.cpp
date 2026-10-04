#include "bridge.h"
#include "windowbuttons/buttonrenderer.h"
#include "windowbuttons/buttonconfig.h"
#include "windowbuttons/buttoninput.h"
#include "windowbuttons/windowquery.h"

#include <effect/effecthandler.h>
#include <effect/effectwindow.h>
#include <core/renderviewport.h>
#include <input.h>

namespace KOS
{

BridgeEffect::BridgeEffect()
    : Effect()
    , m_renderer(std::make_unique<ButtonRenderer>())
    , m_config(std::make_unique<ButtonConfig>())
    , m_input(std::make_unique<ButtonInput>(m_renderer.get(), m_config.get()))
{
    if (KWin::input()) {
        KWin::input()->installInputEventFilter(m_input.get());
    }

    connect(KWin::effects, &KWin::EffectsHandler::windowDeleted, this,
            [this](KWin::EffectWindow *window) {
                // The session first: it is the only one that could still be
                // holding the pointer, and it drops it without calling back
                // into the renderer, which is about to forget the window
                // anyway.
                if (m_input) {
                    m_input->forgetWindow(window);
                }
                if (m_renderer) {
                    m_renderer->forget(window);
                }
                if (m_lastActive == window) {
                    m_lastActive = nullptr;
                }
            });

    // A panel's lights are coloured by whether their window is the active one,
    // so the focus moving between two windows leaves two panels wrong: the one
    // that lost it and the one that gained it. Nothing damages a window for
    // that -- an application may redraw its own title bar and a decoration may
    // follow the state, but neither is promised, and an idle window repaints
    // for no reason at all. So the two panel rectangles are damaged here.
    connect(KWin::effects, &KWin::EffectsHandler::windowActivated, this,
            [this](KWin::EffectWindow *window) {
                if (!m_renderer) {
                    return;
                }
                KWin::EffectWindow *previous = m_lastActive;
                m_lastActive = window;
                m_renderer->repaintPanels(previous, window);
            });

    // KWin does not tell effects that the decoration changed. Selecting a
    // different one changes which windows have a decoration at all, and
    // therefore which of them get a panel -- so the whole screen is repainted
    // and every cached decision dropped.
    m_config->setOnDecorationChanged([this]() {
        if (m_renderer) {
            m_renderer->invalidateAll();
        }
        if (KWin::effects) {
            KWin::effects->addRepaintFull();
        }
    });
}

BridgeEffect::~BridgeEffect() = default;

void BridgeEffect::reconfigure(ReconfigureFlags flags)
{
    Q_UNUSED(flags)
    if (m_config) {
        m_config->load();
    }
    // The configuration feeds the title-bar scan (position, padding, tint
    // override), so every cached measurement is stale now.
    if (m_renderer) {
        m_renderer->invalidateAll();
    }
    // Repaint everything so a hot-reloaded config is visible immediately
    // instead of waiting for each window's next unrelated repaint.
    if (KWin::effects) {
        KWin::effects->addRepaintFull();
    }
}

bool BridgeEffect::isActive() const
{
    return true;
}

void BridgeEffect::drawWindow(const KWin::RenderTarget &renderTarget,
                               const KWin::RenderViewport &viewport,
                               KWin::EffectWindow *window, int mask,
                               const KWin::Region &deviceRegion,
                               KWin::WindowPaintData &data)
{
    // Let the window (and every effect after this one) paint itself first.
    Effect::drawWindow(renderTarget, viewport, window, mask, deviceRegion, data);

    if (!window || !m_config || !m_renderer) {
        return;
    }

    // While the window is being animated (for example the KOS dock open/close
    // morph) its geometry is transformed through quads, which this effect
    // cannot follow. Hiding the panel during the animation is better than
    // drawing it at the settled position before the window gets there -- and
    // the hidden panel must not take the pointer either.
    if (mask & PAINT_WINDOW_TRANSFORMED) {
        m_renderer->clearHits(window);
        return;
    }

    // These are already rejected by ButtonRenderer::paint. Skip the rule
    // lookup and stacking-order walk for them as well; shell and popup
    // surfaces can repaint frequently while never having a button panel.
    if (!window->isVisible() || !window->isManaged()
        || (!window->isNormalWindow() && !window->isDialog())
        || window->isSkipSwitcher() || window->isSpecialWindow()) {
        m_renderer->clearHits(window);
        return;
    }

    // `deviceRegion` is the part of this window that is actually visible: the
    // compositor has already subtracted every opaque window stacked above it
    // (see WorkspaceScene::paintSimpleScreen). Drawing the panel clipped to
    // that region is what keeps a lower window's panel from showing through an
    // upper window.
    // What this window is, for the rule list to be matched against: the class,
    // the caption, the role and the type. Read here rather than inside the
    // configuration so that the configuration stays a lookup and does not have
    // to know what an effect window is.
    const AppConfig config = m_config->getAppConfig(windowQueryFor(window));
    if (!config.showButtons) {
        m_renderer->clearHits(window);
        return;
    }

    // Always intersect with our own occlusion-culled region. The compositor
    // only culls on its optimised painting path; on the generic path (used
    // whenever any window is transformed) deviceRegion is the whole screen, so
    // relying on it alone lets a lower window's panel show through an upper one.
    const KWin::Region clip = visibleRegionFor(window, viewport, deviceRegion);
    if (clip.isEmpty()) {
        // Nothing of this window is on screen, so nothing of its panel is
        // either.
        m_renderer->clearHits(window);
        return;
    }

    m_renderer->paint(renderTarget, viewport, window, config, clip,
                      PaintTransform{
                          .xScale = data.xScale(),
                          .yScale = data.yScale(),
                          .xTranslate = data.xTranslation(),
                          .yTranslate = data.yTranslation(),
                          .opacity = data.opacity(),
                      });
}

KWin::Region BridgeEffect::visibleRegionFor(KWin::EffectWindow *window,
                                            const KWin::RenderViewport &viewport,
                                            const KWin::Region &deviceRegion) const
{
    const auto toRegion = [&](KWin::EffectWindow *w) {
        const KWin::Rect r = viewport.mapToDeviceCoordinatesAligned(w->frameGeometry());
        return KWin::Region(r.x(), r.y(), r.width(), r.height());
    };

    KWin::Region visible = toRegion(window);
    if (deviceRegion != KWin::Region::infinite()) {
        visible &= deviceRegion;
    }
    if (visible.isEmpty()) {
        return visible;
    }

    const auto windows = KWin::effects->stackingOrder();
    const int index = windows.indexOf(window);
    if (index < 0) {
        return KWin::Region();
    }
    for (int j = index + 1; j < windows.size() && !visible.isEmpty(); ++j) {
        KWin::EffectWindow *above = windows[j];
        if (!above || !above->isVisible()) {
            continue;
        }
        // Skip-switcher shell surfaces can have a large transparent frame.
        // Treating that whole frame as opaque hides every panel underneath.
        // Ordinary translucent application windows still occlude the panel.
        if (above->isSkipSwitcher() || above->isDesktop() || above->isDock()
            || above->isOnScreenDisplay() || above->isNotification()) {
            continue;
        }
        visible = visible.subtracted(toRegion(above));
    }
    return visible;
}

} // namespace KOS
