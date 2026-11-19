#include "bridge.h"
#include "windowbuttons/cooperativecontrols.h"
#include <wayland_server.h>
#include <wayland/surface.h>
#ifdef KOS_KWIN_PAINT_RESULT_API
#include <opengl/eglcontext.h>
#endif
#include "windowbuttons/buttonrenderer.h"
#include "windowbuttons/buttonconfig.h"
#include "windowbuttons/buttoninput.h"
#include "windowbuttons/windowquery.h"
#include "windowappearance/windowappearance.h"
#include "windowappearance/appearanceprotocol.h"
#include <KDecoration3/Decoration>

#include <effect/effecthandler.h>
#include <effect/effectwindow.h>
#include <core/rendertarget.h>
#include <core/renderviewport.h>
#include <scene/windowitem.h>
#include <input.h>
#include <window.h>
#include <scene/decorationitem.h>
#include <scene/surfaceitem.h>
#include <scene/windowitem.h>
#include <algorithm>
#include <cmath>
#include <type_traits>
#include <QJsonArray>
#include <QJsonDocument>
#include <QTimer>
#include <xcb/xcb.h>
#include <cstring>

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

// KWin 6.7 changed scene regions from integer to floating point. Keep the
// mapping inside a template so each build only compiles its own overload.
template<typename RegionT>
KWin::Region mapOpaqueToDevice(KWin::Item *item, const RegionT &opaque,
                               const KWin::RenderViewport &viewport)
{
    if constexpr (std::is_same_v<RegionT, KWin::Region>) {
        return viewport.mapToDeviceCoordinatesAligned(item->mapToScene(opaque));
    } else {
        return viewport.mapToDeviceCoordinatesAligned(item->mapToScene(opaque).rounded());
    }
}

// Device-coordinate region a window's own content actually paints solid.
// Client surfaces and server-side decorations each expose their opaque
// region; shadow and outline items expose nothing, which is what we want:
// only an opaque pixel of the upper window may replace a lower one.
KWin::Region opaqueContentDeviceRegion(KWin::EffectWindow *window,
                                       const KWin::RenderViewport &viewport)
{
    auto *item = window->windowItem();
    if (!item) {
        return {};
    }
    KWin::Region region;
    const auto add = [&](KWin::Item *child) {
        if (!child || !child->isVisible()) {
            return;
        }
        const auto opaque = child->opaque();
        // Clients are free to declare a huge number of opaque rectangles.
        // Mapping all of them on the paint path is not worth it; such a
        // window simply does not occlude for us.
        if (opaque.isEmpty() || opaque.rects().size() > 128) {
            return;
        }
        region |= mapOpaqueToDevice(child, opaque, viewport);
    };
    add(item->surfaceItem());
    add(item->decorationItem());
    return region;
}

bool sameContour(const WindowAppearance::ContinuousStyle &a,
                 const WindowAppearance::ContinuousStyle &b)
{
    return qFuzzyCompare(a.radius + 1.0, b.radius + 1.0)
        && qFuzzyCompare(a.smoothness + 1.0, b.smoothness + 1.0)
        && qFuzzyCompare(a.size.width() + 1.0, b.size.width() + 1.0)
        && qFuzzyCompare(a.size.height() + 1.0, b.size.height() + 1.0);
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
#if KWIN_BUILD_X11
    const auto registerGtk = [this] {
        m_gtkNativeAtom = KWin::effects->announceSupportProperty("_KOS_GTK_NATIVE_CONTROLS_V1", this);
        for (auto *window : KWin::effects->stackingOrder()) refreshGtkNativeControls(window);
    };
    connect(KWin::effects, &KWin::EffectsHandler::xcbConnectionChanged, this, registerGtk);
    connect(KWin::effects, &KWin::EffectsHandler::propertyNotify, this,
        [this](KWin::EffectWindow *window, long atom) {
            if (atom == m_gtkNativeAtom) refreshGtkNativeControls(window);
        });
    connect(KWin::effects, &KWin::EffectsHandler::windowAdded, this,
        [this](KWin::EffectWindow *window) { refreshGtkNativeControls(window); });
    connect(KWin::effects, &KWin::EffectsHandler::windowDeleted, this,
        [this](KWin::EffectWindow *window) { m_gtkNativeWindows.remove(window); });
    if (KWin::effects->xcbConnection()) registerGtk();
#endif
    m_cooperative = std::make_unique<CooperativeControls>(
        KWin::waylandServer() ? KWin::waylandServer()->display() : nullptr,
        [this](KWin::EffectWindow *window) { return m_config->getAppConfig(windowQueryFor(window)); }, this);
    connect(m_cooperative.get(), &CooperativeControls::changed, this, [this](KWin::SurfaceInterface *surface) {
        for (auto *window : KWin::effects->stackingOrder()) {
            if (!window->window() || (surface && window->window()->surface() != surface)) continue;
            m_input->forgetWindow(window);
            m_renderer->forget(window); // Drops pending tint timers/readbacks on handoff.
            m_continuousClip->invalidate(window);
            window->addRepaintFull();
        }
    });

    const auto watchWindowState = [this](KWin::EffectWindow *window) {
        connect(window, &KWin::EffectWindow::windowDamaged, this,
                [this, window] { m_renderer->contentChanged(window); });
        if (auto *native = window->window()) {
            const QPointer<KWin::EffectWindow> guarded(window);
            connect(native, &KWin::Window::captionChanged, this,
                    [this, guarded] {
                        // Captions change at frame rate in a terminal, and
                        // resolving a configuration walks the rule lists. Only
                        // a window the renderer has panel state for can need
                        // anything from that walk: for the rest, the paint
                        // path resolves the configuration when it draws.
                        if (guarded && m_renderer && m_config
                            && m_renderer->tracksWindow(guarded)) {
                            m_renderer->captionChanged(guarded, m_config->getAppConfig(windowQueryFor(guarded)));
                        }
                    });
        }
        if (window->windowItem()) {
            const QPointer<KWin::EffectWindow> guarded(window);
            connect(window->windowItem(), &KWin::Item::visibleChanged, this,
                    [this, guarded] {
                        if (guarded && guarded->isMinimized()
                            && (!guarded->windowItem() || !guarded->windowItem()->isVisible())) {
                            m_renderer->dropSamplingCache(guarded);
                        }
                    }, Qt::QueuedConnection);
        }
        connect(window, &KWin::EffectWindow::minimizedChanged, this,
                [this, window] {
                    // Let the minimize animation keep its validated controls until
                    // all animation visibility references end, then release sample buffers.
                    QTimer::singleShot(500, this, [this, guarded = QPointer<KWin::EffectWindow>(window)] {
                        if (guarded && guarded->isMinimized()
                            && (!guarded->windowItem() || !guarded->windowItem()->isVisible())) {
                            m_renderer->dropSamplingCache(guarded);
                        }
                    });
                });
        connect(window, &KWin::EffectWindow::windowFullScreenChanged,
                this, [this](KWin::EffectWindow *changed) {
                    m_input->fullscreenChanged(changed);
                });
    };
    connect(KWin::effects, &KWin::EffectsHandler::windowAdded,
            this, watchWindowState);
    for (auto *window : KWin::effects->stackingOrder()) {
        watchWindowState(window);
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
    connect(KWin::effects, &KWin::EffectsHandler::activeFullScreenEffectChanged,
            this, &BridgeEffect::updateNativeThumbnails);
    connect(KWin::effects, &KWin::EffectsHandler::activeFullScreenEffectChanged,
            this, &BridgeEffect::preserveDesktopStack);
    // Slide elevates all Dock windows while preparing a switch. Run after
    // its signal handlers too: another output, a gesture, or a newly mapped
    // surface can be elevated without changing the active effect.
    connect(KWin::effects, &KWin::EffectsHandler::desktopChanged,
            this, &BridgeEffect::preserveDesktopStack, Qt::QueuedConnection);
    connect(KWin::effects, &KWin::EffectsHandler::desktopChanging,
            this, &BridgeEffect::preserveDesktopStack, Qt::QueuedConnection);
    connect(KWin::effects, &KWin::EffectsHandler::windowAdded,
            this, &BridgeEffect::preserveDesktopStack, Qt::QueuedConnection);
    updateNativeThumbnails();
    preserveDesktopStack();
}

BridgeEffect::~BridgeEffect()
{
    if (m_cooperative) disconnect(m_cooperative.get(), nullptr, this, nullptr);
    m_cooperative.reset();
    if (KWin::effects->property(SharedWindowSourceProperty).value<QObject *>() == this)
        KWin::effects->setProperty(SharedWindowSourceProperty, QVariant());
    // QObject disconnects receiver connections only after members have been
    // destroyed. Appearance restoration can emit scene signals synchronously;
    // stop our callbacks first and restore while all sibling members are live.
    disconnect(KWin::effects, nullptr, this, nullptr);
    disconnect(m_renderer.get(), nullptr, this, nullptr);
    disconnect(m_appearance.get(), nullptr, this, nullptr);
    m_appearance->restoreAll();
}

void BridgeEffect::reconfigure(ReconfigureFlags flags)
{
    Q_UNUSED(flags)
    // An in-flight draft must not retain the previous geometry policy.
    if (m_input) m_input->cancelAdjustment();
    if (m_config) {
        m_config->load();
    }
    if (m_cooperative) m_cooperative->refresh();
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

QString BridgeEffect::debug(const QString &parameter) const
{
    if (parameter != QLatin1String("window-controls")) return {};
    QJsonArray windows;
    for (auto *window : KWin::effects->stackingOrder()) {
        if (!window->window()) continue;
        AppConfig config = m_config->getAppConfig(windowQueryFor(window));
        const bool declared = m_cooperative && m_cooperative->configureWindow(window, config);
        auto entry = m_renderer->controlDiagnostics(window);
        entry.insert("declared", declared);
        entry.insert("nativeControls", config.usesClientControls(window->hasDecoration())
            || (!window->hasDecoration() && !config.cooperativeControls && m_gtkNativeWindows.contains(window)));
        entry.insert("windowClass", window->windowClass());
        entry.insert("decorated", window->hasDecoration());
        auto *decoration = window->window()->decoration();
        const bool nativeDecoration = decoration && decoration->property(WindowAppearance::DecorationControlsProperty).toBool();
        entry.insert("decorationControls", nativeDecoration);
        QJsonArray nativeButtons;
        if (nativeDecoration) for (auto *button : decoration->findChildren<QObject *>()) {
            if (!button->inherits("KDecoration3::DecorationButton") || !button->property("visible").toBool()) continue;
            const QRectF rect = button->property("geometry").toRectF().translated(window->frameGeometry().topLeft());
            nativeButtons.append(QJsonObject{{"action",button->objectName()}, {"rect",QJsonArray{rect.x(),rect.y(),rect.width(),rect.height()}}});
        }
        entry.insert("decorationButtons", nativeButtons);
        entry.insert("maximized", window->window()->maximizeMode() == KWin::MaximizeFull);
        entry.insert("active", config.cooperativeControls);
        entry.insert("id", window->window()->internalId().toString());
        entry.insert("minimized", window->isMinimized());
        entry.insert("caption", window->caption());
        entry.insert("role", window->windowRole());
        entry.insert("type", window->windowTypeInt());
        windows.append(entry);
    }
    return QString::fromUtf8(QJsonDocument(QJsonObject{{"windows", windows},
        {"samplingWindows", m_renderer->samplingWindowCount()},
        {"cursor", QJsonArray{KWin::effects->cursorPos().x(), KWin::effects->cursorPos().y()}}}).toJson(QJsonDocument::Compact));
}

void BridgeEffect::preserveDesktopStack()
{
    const auto *effect = KWin::effects->activeFullScreenEffect();
    if (!effect || !effect->inherits("KWin::SlideEffect")) return;
    for (auto *window : KWin::effects->stackingOrder()) {
        const auto *native = window->window();
        if (native && native->isDock() && native->layer() == KWin::BelowLayer
            && (native->resourceClass() == QLatin1String("quickshell")
                || native->resourceClass() == QLatin1String("org.quickshell"))) {
            // DeskCenter is a Dock for Overview/shortcut protection, but it
            // remains desktop content even while Slide elevates real panels.
            KWin::effects->setElevatedWindow(window, false);
        }
    }
}

void BridgeEffect::updateNativeThumbnails()
{
    const auto *effect = KWin::effects->activeFullScreenEffect();
    const bool nativeThumbnails = effect && (effect->inherits("KWin::OverviewEffect")
        || effect->inherits("KWin::WindowViewEffect"));
    if (m_nativeThumbnails == nativeThumbnails) {
        return;
    }
    m_nativeThumbnails = nativeThumbnails;
    if (nativeThumbnails) {
        // KWin thumbnails render scene items directly, bypassing drawWindow.
        // Restore native rounding before their first capture, including hidden windows.
        m_continuousClip->clear();
        for (auto *window : KWin::effects->stackingOrder()) {
            if (appearanceEligible(window) || m_appearance->continuousStyle(window)) {
                m_appearance->prepare(window, false);
            }
        }
    }
    KWin::effects->addRepaintFull();
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
        m_appearance->prepare(window, !m_nativeThumbnails && m_continuousClip->availableFor(window));
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

#ifdef KOS_KWIN_PAINT_RESULT_API
bool
#else
void
#endif
BridgeEffect::paintWindow(const KWin::RenderTarget &renderTarget,
                          const KWin::RenderViewport &viewport,
                          KWin::EffectWindow *window, int mask,
                          const KWin::Region &deviceRegion,
                          KWin::WindowPaintData &data)
{
    auto *previousScreenFramebuffer = m_screenFramebuffer;
    m_screenFramebuffer = renderTarget.framebuffer();
#ifdef KOS_KWIN_PAINT_RESULT_API
    const bool painted = Effect::paintWindow(renderTarget, viewport, window, mask, deviceRegion, data);
    m_screenFramebuffer = previousScreenFramebuffer;
    return painted;
#else
    Effect::paintWindow(renderTarget, viewport, window, mask, deviceRegion, data);
    m_screenFramebuffer = previousScreenFramebuffer;
#endif
}

#ifdef KOS_KWIN_PAINT_RESULT_API
bool
#else
void
#endif
BridgeEffect::drawWindow(const KWin::RenderTarget &renderTarget,
                        const KWin::RenderViewport &viewport,
                        KWin::EffectWindow *window, int mask,
                        const KWin::Region &deviceRegion,
                        KWin::WindowPaintData &data)
{
    if (window->data(WindowSourceCaptureRole).toBool()) {
        return Effect::drawWindow(renderTarget, viewport, window, mask, deviceRegion, data);
    }
    const bool legacyCapture = window->data(LegacyWindowSourceCaptureRole).toBool();
    // A continuous window is marked translucent so the scene paints the
    // background under its clipped corners. That also disables KWin's own
    // occlusion culling for it, so windows completely behind other opaque
    // windows keep being captured and drawn. Skip those here instead: the
    // covering windows paint later in this same pass, so their pixels are
    // still written. Anything transformed (morphs, animations, slide) keeps
    // the normal path, because its geometry no longer describes the screen.
    if (!legacyCapture && !(mask & PAINT_WINDOW_TRANSFORMED)
        && !window->data(DockSourceAnimationRole).toBool()
        && fullyOccluded(window, viewport)) {
        m_renderer->clearHits(window);
#ifdef KOS_KWIN_PAINT_RESULT_API
        return true;
#else
        return;
#endif
    }
    if (!legacyCapture && drawSharedWindow(renderTarget, viewport, window, mask, deviceRegion, data, {})) {
#ifdef KOS_KWIN_PAINT_RESULT_API
        return true;
#else
        return;
#endif
    }
    const PaintTransform neutralCheck{
        .xScale = data.xScale(),
        .yScale = data.yScale(),
        .zScale = data.zScale(),
        .xTranslate = data.xTranslation(),
        .yTranslate = data.yTranslation(),
        .zTranslate = data.zTranslation(),
        .rotationAngle = data.rotationAngle(),
        .opacity = data.opacity(),
        .brightness = data.brightness(),
        .saturation = data.saturation(),
    };
    // Built-in KWin OffscreenEffects (such as Magic Lamp) redirect windows into
    // their own FBO with infinite region and neutral WindowPaintData without
    // setting LegacyWindowSourceCaptureRole. Include KOS controls in those
    // captures even when continuous corners are disabled (e.g. square maximized).
    const bool offscreenCapture = renderTarget.framebuffer()
        && renderTarget.framebuffer() != m_screenFramebuffer
        && deviceRegion == KWin::Region::infinite()
        && neutralCheck.isNeutral();
    const bool capture = legacyCapture || offscreenCapture;
#ifdef KOS_KWIN_PAINT_RESULT_API
    if (KWin::EglContext::currentContext() != KWin::effects->openglContext())
        return false;
    const bool painted = Effect::drawWindow(renderTarget, viewport, window, mask, deviceRegion, data);
    if (!painted)
        return false;
#else
    Effect::drawWindow(renderTarget, viewport, window, mask, deviceRegion, data);
#endif
    paintButtons(renderTarget, viewport, window, mask, deviceRegion, data, capture);
    if (capture)
        m_renderer->clearHits(window);
#ifdef KOS_KWIN_PAINT_RESULT_API
    return painted;
#endif
}

bool BridgeEffect::drawSharedWindow(const KWin::RenderTarget &target,
    const KWin::RenderViewport &viewport, KWin::EffectWindow *window, int mask,
    const KWin::Region &region, KWin::WindowPaintData &data, const WindowSourceMorph &morph)
{
    if (m_nativeThumbnails) return false;
    const auto style = m_appearance->continuousStyle(window);
    if (!style) return false;
    if (!m_continuousClip->configure(window, style)) {
        m_appearance->prepare(window, false);
        return false;
    }
    // An animated consumer deforms the captured texture, so its controls have
    // to be part of the source. A stationary frame keeps them out: the panel
    // and its tint are then drawn as an overlay above the finished window.
    // Hover, menu and tint changes repaint only the panel instead of
    // invalidating the whole-window source, and the source itself changes only
    // when the window content is damaged.
    const bool morphing = static_cast<bool>(morph);
    const bool result = m_continuousClip->paint(target, viewport, window, mask, region, data,
        *style, [this, window, morphing](const auto &sourceTarget, const auto &sourceViewport,
                                        const auto &sourceRegion) {
            const QVariant previous = window->data(WindowSourceCaptureRole);
            window->setData(WindowSourceCaptureRole, true);
            KWin::WindowPaintData sourceData;
            sourceData.setOpacity(1.0);
#ifdef KOS_KWIN_PAINT_RESULT_API
            const bool painted =
#endif
            KWin::effects->drawWindow(sourceTarget, sourceViewport, window,
                PAINT_WINDOW_TRANSFORMED | PAINT_WINDOW_TRANSLUCENT,
                sourceRegion, sourceData);
#ifdef KOS_KWIN_PAINT_RESULT_API
            if (painted && morphing)
#else
            if (morphing)
#endif
                paintButtons(sourceTarget, sourceViewport, window, 0, KWin::Region::infinite(), sourceData, true);
            window->setData(WindowSourceCaptureRole, previous);
#ifdef KOS_KWIN_PAINT_RESULT_API
            return painted;
#else
            return true;
#endif
        }, morph);
    if (!result) {
        // The source could not be allocated/uploaded. Restore native rounding
        // before the downstream scene (or legacy Dock capture) paints it,
        // which also paints the controls through the ordinary path.
        m_appearance->prepare(window, false);
    } else if (!morphing) {
        // The window is on screen now; draw its controls above it, clipped to
        // the part of the panel this frame repaints.
        paintButtons(target, viewport, window, mask, region, data, false);
    }
    if (window->data(DockSourceAnimationRole).toBool() || (mask & PAINT_WINDOW_TRANSFORMED)
        || !window->isVisible() || window->isDeleted())
        m_renderer->clearHits(window);
    else if (result)
        m_renderer->syncHits(window);
    return result;
}

void BridgeEffect::refreshGtkNativeControls(KWin::EffectWindow *window)
{
#if KWIN_BUILD_X11
    if (!window) return;
    bool native = false;
    auto *connection = KWin::effects->xcbConnection();
    if (connection && m_gtkNativeAtom && window->windowId()) {
        const auto cookie = xcb_get_property(connection, false, window->windowId(),
            m_gtkNativeAtom, XCB_ATOM_CARDINAL, 0, 1);
        auto *reply = xcb_get_property_reply(connection, cookie, nullptr);
        if (reply && reply->type == XCB_ATOM_CARDINAL && reply->format == 32
            && reply->value_len == 1 && reply->bytes_after == 0) {
            uint32_t value = 0;
            std::memcpy(&value, xcb_get_property_value(reply), sizeof(value));
            native = value == 1;
        }
        free(reply);
    }
    const bool previous = m_gtkNativeWindows.contains(window);
    if (native) m_gtkNativeWindows.insert(window); else m_gtkNativeWindows.remove(window);
    if (previous != native) {
        m_input->forgetWindow(window);
        m_renderer->forget(window);
        m_continuousClip->invalidate(window);
        window->addRepaintFull();
    }
#endif
}

void BridgeEffect::paintButtons(const KWin::RenderTarget &renderTarget,
    const KWin::RenderViewport &viewport, KWin::EffectWindow *window, int mask,
    const KWin::Region &deviceRegion, const KWin::WindowPaintData &data, bool sourceCapture)
{
    if (!window || !m_config || !m_renderer) {
        return;
    }

    // A native decoration owns both pixels and input. Never sample or cover
    // its controls, even when a legacy per-app rule forces overlay rendering.
    if (auto *native = window->window(); native && native->decoration()
        && native->decoration()->property(WindowAppearance::DecorationControlsProperty).toBool()) {
        m_input->forgetWindow(window);
        m_renderer->forget(window); // Also stop tint timers inherited from an older decoration.
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
    // Hidden/minimized windows only enter drawWindow while an animation holds
    // a visibility or deleted reference; let them keep their cached controls.
    if (window->isFullScreen() || !window->isManaged()
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
    AppConfig config = m_config->getAppConfig(windowQueryFor(window));
    if (m_cooperative) m_cooperative->configureWindow(window, config);
    if (config.usesClientControls(window->hasDecoration())
        || (!window->hasDecoration() && !config.cooperativeControls && m_gtkNativeWindows.contains(window))) {
        // A previous overlay rule may still have live input/tint state. Give
        // ownership back completely, including the sampling timer and PBO.
        m_input->forgetWindow(window);
        m_renderer->forget(window);
        return;
    }
    if (!config.showButtons) {
        m_renderer->clearHits(window, sourceCapture);
        return;
    }

    const PaintTransform transform{
        .xScale = data.xScale(),
        .yScale = data.yScale(),
        .zScale = data.zScale(),
        .xTranslate = data.xTranslation(),
        .yTranslate = data.yTranslation(),
        .zTranslate = data.zTranslation(),
        .rotationAngle = data.rotationAngle(),
        .opacity = data.opacity(),
        .brightness = data.brightness(),
        .saturation = data.saturation(),
        // Captures deliberately set TRANSFORMED to draw the
        // raw source; their actual paint data must stay neutral.
        .transformed = !sourceCapture && (mask & PAINT_WINDOW_TRANSFORMED),
    };

    // Always intersect with our own occlusion-culled region for resting
    // windows. Offscreen source captures and geometrically moving windows use
    // deviceRegion directly (generic screen painting runs bottom-to-top).
    const KWin::Region clip = (sourceCapture || !transform.isIdentityGeometry())
        ? deviceRegion
        : visibleRegionFor(window, viewport, deviceRegion);
    if (clip.isEmpty()) {
        // Nothing of this window is on screen, so nothing of its panel is
        // either.
        m_renderer->clearHits(window, sourceCapture);
        return;
    }

    m_renderer->paint(renderTarget, viewport, window, config, clip,
                      transform, sourceCapture);
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

bool BridgeEffect::fullyOccluded(KWin::EffectWindow *window,
                                 const KWin::RenderViewport &viewport) const
{
    if (!window || !window->windowItem() || !window->isVisible() || !m_appearance) {
        return false;
    }
    // Native-rounded windows are not marked translucent, so KWin computes
    // their opaque region and culls this window itself. Only the continuous
    // path lost that and needs the check.
    const auto style = m_appearance->continuousStyle(window);
    if (!style) {
        return false;
    }
    // Fullscreen effects paint bottom-to-top with an infinite deviceRegion,
    // so geometry no longer says which pixels this pass covers.
    if (KWin::effects->activeFullScreenEffect()) {
        return false;
    }
    if (window->opacity() < 1.0 || window->windowItem()->opacity() < 1.0) {
        return false;
    }

    const auto windows = KWin::effects->stackingOrder();
    const int index = windows.indexOf(window);
    if (index < 0 || index + 1 >= windows.size()) {
        return false;
    }

    const KWin::Rect output = viewport.deviceRect();
    // Everything this window can paint: the shader quad is exactly
    // expandedGeometry, and both shadow layers live inside it. Clipping to
    // the output keeps off-screen shadow from demanding coverage.
    const KWin::Rect target =
        viewport.mapToDeviceCoordinatesAligned(window->expandedGeometry()) & output;
    if (target.isEmpty()) {
        return false;
    }
    const KWin::Rect targetFrame =
        viewport.mapToDeviceCoordinatesAligned(window->frameGeometry());
    const qreal scale = viewport.scale();
    const bool targetFillsOutput = targetFrame.x() <= output.x()
        && targetFrame.y() <= output.y() && targetFrame.right() >= output.right()
        && targetFrame.bottom() >= output.bottom();

    KWin::Region covered;
    for (int i = index + 1; i < windows.size(); ++i) {
        KWin::EffectWindow *above = windows[i];
        if (!above || !above->isVisible() || above->isMinimized()
            || !above->isOnCurrentDesktop() || !above->isOnCurrentActivity()
            || above->data(DockSourceAnimationRole).toBool()
            || above->opacity() < 1.0 || !above->windowItem()
            || above->windowItem()->opacity() < 1.0) {
            continue;
        }
        const auto aboveStyle = m_appearance->continuousStyle(above);
        if (!aboveStyle) {
            continue;
        }
        const KWin::Rect frame =
            viewport.mapToDeviceCoordinatesAligned(above->frameGeometry());
        // A window whose frame misses the target contributes nothing to the
        // coverage union; skip mapping its opaque regions.
        if (!frame.intersects(target)) {
            continue;
        }
        KWin::Region content = opaqueContentDeviceRegion(above, viewport);
        content &= KWin::Region(frame);
        if (content.isEmpty()) {
            continue;
        }
        // The contour paints every pixel of the frame except the corner
        // regions. Subtracting the whole corner squares under-approximates
        // that, which is the safe direction: never claim coverage the shader
        // does not actually provide.
        //
        // Two windows with the same frame and the same contour are the one
        // case where the corner slivers match exactly, so the upper window
        // paints every pixel the lower one would. That is the stacked
        // maximized/fullscreen case, where no shadow reaches the screen.
        const bool sameOutputContour = targetFillsOutput
            && frame == targetFrame && sameContour(*style, *aboveStyle);
        if (!sameOutputContour) {
            const int cut = qCeil(std::max<qreal>(0.0, aboveStyle->radius) * scale);
            if (cut > 0 && cut * 2 < frame.width() && cut * 2 < frame.height()) {
                content -= KWin::Region(frame.x(), frame.y(), cut, cut);
                content -= KWin::Region(frame.right() - cut, frame.y(), cut, cut);
                content -= KWin::Region(frame.x(), frame.bottom() - cut, cut, cut);
                content -= KWin::Region(frame.right() - cut, frame.bottom() - cut, cut, cut);
            }
        }
        covered |= content;
        if (covered.contains(target)) {
            return true;
        }
    }
    return false;
}

} // namespace KOS
