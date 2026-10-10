#include "bridge.h"
#include "windowbuttons/buttonrenderer.h"
#include "windowbuttons/buttonconfig.h"
#include "windowbuttons/buttoninput.h"
#include "windowbuttons/windowquery.h"
#include "windowappearance/windowappearance.h"

#include <effect/effecthandler.h>
#include <effect/effectwindow.h>
#include <core/renderviewport.h>
#include <input.h>
#include <window.h>

namespace KOS
{

namespace
{

// The window types the unified appearance applies to. The same filter the
// button panels use -- shell surfaces, docks, popups and notifications are
// other systems' surfaces and keep their own look.
bool appearanceEligible(const KWin::EffectWindow *window)
{
    if (!window || !window->isVisible() || !window->isManaged()) {
        return false;
    }
    if (!window->isNormalWindow() && !window->isDialog()) {
        return false;
    }
    if (window->isSkipSwitcher() || window->isSpecialWindow()) {
        return false;
    }
    // Reject every popup-like role explicitly. Transient surfaces such as
    // tooltips, menus and combo boxes can otherwise slip through as "normal"
    // on some backends and end up with their own shadow and outline.
    if (window->isPopupWindow() || window->isPopupMenu()
        || window->isDropdownMenu() || window->isComboBox()
        || window->isMenu() || window->isTooltip() || window->isAppletPopup()
        || window->isOnScreenDisplay() || window->isNotification()
        || window->isCriticalNotification() || window->isSplash()
        || window->isUtility() || window->isDock() || window->isDesktop()
        || window->isDNDIcon()) {
        return false;
    }
    // KWin's own user interface is not an application window. The OSD the
    // desktop-change script draws, the outline, the tab switcher: those are
    // internal windows that report themselves as managed, undecorated normal
    // windows -- without this they grow a shadow of their own.
    if (const KWin::Window *native = window->window();
        native && native->isInternal()) {
        return false;
    }
    // Input-method candidate windows behave like popups without declaring it.
    const QString appId = window->windowClass();
    if (appId.contains(QStringLiteral("fcitx"), Qt::CaseInsensitive)
        || appId.contains(QStringLiteral("ibus"), Qt::CaseInsensitive)
        || appId.contains(QStringLiteral("inputmethod"), Qt::CaseInsensitive)) {
        return false;
    }
    return true;
}

} // namespace

BridgeEffect::BridgeEffect()
    : Effect()
    , m_renderer(std::make_unique<ButtonRenderer>())
    , m_config(std::make_unique<ButtonConfig>())
    , m_input(std::make_unique<ButtonInput>(m_renderer.get(), m_config.get()))
    , m_appearance(std::make_unique<WindowAppearanceManager>())
    , m_continuousClip(std::make_unique<WindowAppearance::ContinuousClip>())
{
    KWin::effects->setProperty(SharedWindowSourceProperty,
        QVariant::fromValue(static_cast<QObject *>(this)));
    connect(m_renderer.get(), &ButtonRenderer::sourceRepaint, this,
        [this](const QRectF &rect) { m_continuousClip->invalidateRegion(rect); });
    connect(KWin::effects, &KWin::EffectsHandler::windowDataChanged, this,
        [this](KWin::EffectWindow *window, int role) {
            if (role == DockSourceAnimationRole) {
                m_renderer->clearHits(window);
                m_continuousClip->invalidate(window);
            }
        });
    connect(m_appearance.get(), &WindowAppearanceManager::configurationChanged,
            this, [this] { m_continuousClip->clear(); });
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
                if (m_appearance) {
                    m_continuousClip->forget(window);
                    m_appearance->forget(window);
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
    // The window appearance has the same dependency in the other direction:
    // the shadow tier and outline opacity follow the focus, and both move
    // animated, so the two windows are retargeted and damaged here as well.
    connect(KWin::effects, &KWin::EffectsHandler::windowActivated, this,
            [this](KWin::EffectWindow *window) {
                if (m_appearance) {
                    m_appearance->focusChanged(window);
                }
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
            m_continuousClip->invalidateAll();
        }
        if (KWin::effects) {
            KWin::effects->addRepaintFull();
        }
    });
}

BridgeEffect::~BridgeEffect()
{
    if (KWin::effects->property(SharedWindowSourceProperty).value<QObject *>() == this)
        KWin::effects->setProperty(SharedWindowSourceProperty, QVariant());
}

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
        m_continuousClip->invalidateAll();
    }
    if (m_appearance) {
        m_appearance->reconfigure();
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

void BridgeEffect::prePaintWindow(KWin::RenderView *view,
                                 KWin::EffectWindow *window,
                                 KWin::WindowPrePaintData &data
#ifdef KOS_KWIN_PAINT_TIME_API
                                 , std::chrono::milliseconds presentTime
#endif
                                 )
{
    // Radius and appearance bounds must exist before the scene computes its
    // opaque region and culls windows against the current damage.
    if (m_appearance && appearanceEligible(window)) {
        m_appearance->prepare(window, m_continuousClip->availableFor(window));
        const auto style = m_appearance->continuousStyle(window);
        if (m_continuousClip->configure(window, style)) {
            // The mask opens the corners. The scene must paint the actual
            // background under them before drawing this cached window.
            data.setTranslucent();
        } else if (style) {
            m_appearance->prepare(window, false);
        }
    } else if (m_continuousClip) {
        // Closing/minimizing animations can keep painting a window after
        // isVisible becomes false. Keep its existing contour for that time.
        if (m_continuousClip->configure(window, m_appearance->continuousStyle(window))) {
            data.setTranslucent();
        }
    }
    Effect::prePaintWindow(view, window, data
#ifdef KOS_KWIN_PAINT_TIME_API
                           , presentTime
#endif
                           );
}

void BridgeEffect::drawWindow(const KWin::RenderTarget &renderTarget,
                               const KWin::RenderViewport &viewport,
                               KWin::EffectWindow *window, int mask,
                               const KWin::Region &deviceRegion,
                               KWin::WindowPaintData &data)
{
    if (window->data(WindowSourceCaptureRole).toBool()) {
        // A shared source capture started before us in the effect chain.
        // The provider paints the button panel after this raw scene pass.
        Effect::drawWindow(renderTarget, viewport, window, mask, deviceRegion, data);
        return;
    }
    if (window->data(LegacyWindowSourceCaptureRole).toBool()) {
        Effect::drawWindow(renderTarget, viewport, window, mask, deviceRegion, data);
        paintButtons(renderTarget, viewport, window, deviceRegion, data, true);
        m_renderer->clearHits(window);
        return;
    }
    if (drawSharedWindow(renderTarget, viewport, window, mask, deviceRegion, data, {})) {
        return;
    }
    Effect::drawWindow(renderTarget, viewport, window, mask, deviceRegion, data);
    paintButtons(renderTarget, viewport, window, deviceRegion, data, false);
}

bool BridgeEffect::drawSharedWindow(const KWin::RenderTarget &target,
    const KWin::RenderViewport &viewport, KWin::EffectWindow *window, int mask,
    const KWin::Region &region, KWin::WindowPaintData &data, const WindowSourceMorph &morph)
{
    const auto style = m_appearance->continuousStyle(window);
    if (!style) return false;
    if (!m_continuousClip->configure(window, style)) {
        m_appearance->prepare(window, false);
        return false;
    }
    const bool result = m_continuousClip->paint(target, viewport, window, mask, region, data,
        *style, [this, window](const auto &sourceTarget, const auto &sourceViewport) {
            const QVariant previous = window->data(WindowSourceCaptureRole);
            window->setData(WindowSourceCaptureRole, true);
            KWin::WindowPaintData sourceData;
            sourceData.setOpacity(1.0);
            KWin::effects->drawWindow(sourceTarget, sourceViewport, window,
                PAINT_WINDOW_TRANSFORMED | PAINT_WINDOW_TRANSLUCENT,
                KWin::Region::infinite(), sourceData);
            paintButtons(sourceTarget, sourceViewport, window, KWin::Region::infinite(), sourceData, true);
            window->setData(WindowSourceCaptureRole, previous);
        }, morph);
    if (!result) {
        // The source could not be allocated/uploaded. Restore native rounding
        // before the downstream scene (or legacy Dock capture) paints it.
        m_appearance->prepare(window, false);
    }
    if (window->data(DockSourceAnimationRole).toBool() || (mask & PAINT_WINDOW_TRANSFORMED))
        m_renderer->clearHits(window);
    else if (result)
        m_renderer->syncHits(window);
    return result;
}

void BridgeEffect::paintButtons(const KWin::RenderTarget &renderTarget,
    const KWin::RenderViewport &viewport, KWin::EffectWindow *window,
    const KWin::Region &deviceRegion, const KWin::WindowPaintData &data, bool sourceCapture)
{
    if (!window || !m_config || !m_renderer) {
        return;
    }

    // Animated controls belong to the source capture, never a stationary
    // screen overlay. Only the capture may paint them during a Dock morph.
    if (!sourceCapture && window->data(DockSourceAnimationRole).toBool()) {
        m_renderer->clearHits(window, sourceCapture);
        return;
    }

    // These are already rejected by ButtonRenderer::paint. Skip the rule
    // lookup and stacking-order walk for them as well; shell and popup
    // surfaces can repaint frequently while never having a button panel.
    if ((!sourceCapture && !window->isVisible()) || !window->isManaged()
        || (!window->isNormalWindow() && !window->isDialog())
        || window->isSkipSwitcher() || window->isSpecialWindow()) {
        m_renderer->clearHits(window, sourceCapture);
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
        m_renderer->clearHits(window, sourceCapture);
        return;
    }

    // Always intersect with our own occlusion-culled region. The compositor
    // only culls on its optimised painting path; on the generic path (used
    // whenever any window is transformed) deviceRegion is the whole screen, so
    // relying on it alone lets a lower window's panel show through an upper one.
    const KWin::Region clip = sourceCapture ? deviceRegion : visibleRegionFor(window, viewport, deviceRegion);
    if (clip.isEmpty()) {
        // Nothing of this window is on screen, so nothing of its panel is
        // either.
        m_renderer->clearHits(window, sourceCapture);
        return;
    }

    m_renderer->paint(renderTarget, viewport, window, config, clip,
                      PaintTransform{
                          .xScale = data.xScale(),
                          .yScale = data.yScale(),
                          .xTranslate = data.xTranslation(),
                          .yTranslate = data.yTranslation(),
                          .opacity = data.opacity(),
                      }, sourceCapture);
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
