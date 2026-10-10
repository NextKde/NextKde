#include "windowappearance.h"
#include "appearanceprotocol.h"
#include "geometryprotocol.h"

#include <effect/effecthandler.h>
#include <effect/effectwindow.h>
#include <scene/outlinedborderitem.h>
#include <scene/shadowitem.h>
#include <scene/windowitem.h>
#include <window.h>
#include <KDecoration3/Decoration>
#include <QPalette>
#include <algorithm>
#include <cmath>

namespace KOS
{
using namespace WindowAppearance;
namespace
{
KWin::BorderRadius nativeRadii(const CornerRadii &radii, qreal inset = 0.0)
{
    return KWin::BorderRadius(std::max(0.0, radii.topLeft - inset),
        std::max(0.0, radii.topRight - inset),
        std::max(0.0, radii.bottomRight - inset),
        std::max(0.0, radii.bottomLeft - inset));
}
}

WindowAppearanceManager::WindowAppearanceManager(QObject *parent)
    : QObject(parent)
{
    m_clock.start();
    m_animTimer.setInterval(16);
    m_animTimer.setTimerType(Qt::PreciseTimer);
    connect(&m_animTimer, &QTimer::timeout, this, [this] { animate(); });
    m_tierTimer.setSingleShot(true);
    m_tierTimer.setInterval(0);
    connect(&m_tierTimer, &QTimer::timeout, this, &WindowAppearanceManager::updateTiers);
    connect(&m_config, &AppearanceConfig::changed, this, [this] {
        m_shadowCache.clear();
        if (!m_config.enabled()) {
            restoreAll();
        } else {
            for (auto it = m_windows.begin(); it != m_windows.end(); ++it) {
                it.value().toneDirty = true;
                it.value().tierDirty = true;
            }
        }
        if (KWin::effects) {
            KWin::effects->addRepaintFull();
        }
        Q_EMIT configurationChanged();
    });
    if (KWin::effects) {
        connect(KWin::effects, &KWin::EffectsHandler::stackingOrderChanged,
                this, [this] { dirtyTiers(); });
    }
}

WindowAppearanceManager::~WindowAppearanceManager()
{
    restoreAll();
}

void WindowAppearanceManager::reconfigure()
{
    m_config.load();
}

void WindowAppearanceManager::dirtyTiers()
{
    // Geometry signals can arrive many times before the compositor paints.
    // Coalesce a burst instead of walking the whole stack in every signal.
    if (!m_windows.isEmpty() && !m_tierTimer.isActive()) {
        m_tierTimer.start();
    }
}

void WindowAppearanceManager::updateTiers()
{
    if (!KWin::effects || !m_config.enabled()) {
        return;
    }
    const auto windows = KWin::effects->stackingOrder();
    const auto *active = KWin::effects->activeWindow();
    QList<QRectF> aboveFrames;
    QList<KWin::EffectWindow *> changed;
    // Read/filter each candidate once and share the same stack snapshot.
    // Stop after two overlaps; deeper tiers have the same configured alpha.
    for (auto it = windows.crbegin(); it != windows.crend(); ++it) {
        auto *window = *it;
        if (!window) {
            continue;
        }
        if (auto state = m_windows.find(window); state != m_windows.end()) {
            int overlaps = 0;
            if (active != window) {
                const QRectF frame = window->frameGeometry();
                for (const QRectF &above : aboveFrames) {
                    if (above.intersects(frame) && ++overlaps == 2) {
                        break;
                    }
                }
            }
            const int tier = active == window ? 0 : overlaps + 1;
            state->tierDirty = false;
            if (state->tier != tier) {
                state->tier = tier;
                changed.append(window);
            }
        }
        if (window->isVisible() && window->isOnCurrentDesktop()
            && window->isOnCurrentActivity() && !window->isSkipSwitcher()
            && (window->isNormalWindow() || window->isDialog())
            && !window->isSpecialWindow() && !window->isPopupWindow()) {
            aboveFrames.append(window->frameGeometry());
        }
    }
    for (auto *window : changed) {
        if (auto state = m_windows.find(window); state != m_windows.end()) {
            // Preserve the result of texture admission; do not retry a
            // rejected continuous texture merely because its tier changed.
            prepare(window, state->continuous.has_value());
        }
    }
}

int WindowAppearanceManager::tierFor(KWin::EffectWindow *window) const
{
    if (KWin::effects->activeWindow() == window) {
        return 0;
    }
    const auto windows = KWin::effects->stackingOrder();
    const int index = windows.indexOf(window);
    if (index < 0) {
        return 1;
    }
    int overlaps = 0;
    for (int i = index + 1; i < windows.size(); ++i) {
        const auto *above = windows[i];
        if (!above || !above->isVisible() || !above->isOnCurrentDesktop()
            || !above->isOnCurrentActivity() || above->isSkipSwitcher()
            || (!above->isNormalWindow() && !above->isDialog())
            || above->isSpecialWindow() || above->isPopupWindow()) {
            continue;
        }
        if (above->frameGeometry().intersects(window->frameGeometry())
            && ++overlaps >= 2) {
            return 3;
        }
    }
    return overlaps == 0 ? 1 : 2;
}

void WindowAppearanceManager::prepare(KWin::EffectWindow *window, bool continuousAvailable)
{
    if (!window || !m_config.enabled() || !KWin::effects
        || !window->window() || !window->windowItem()) {
        return;
    }
    auto *native = window->window();
    auto *item = window->windowItem();
    const QSizeF size = window->frameGeometry().size();
    if (size.isEmpty()) {
        return;
    }
    auto &state = m_windows[window];
    if (!state.initialized) {
        state.initialized = true;
        state.declaredRadius = native->borderRadius().toVector();
        state.declaredGeometryProperty = native->property(WindowRadiiProperty);
        state.declaredVisualRadiiProperty = native->property(VisualRadiiProperty);
        state.declaredExponentProperty = native->property(CurveExponentProperty);
        state.appliedRadius = state.declaredRadius;
        state.connections.append(connect(window,
            &KWin::EffectWindow::windowFrameGeometryChanged, this,
            [this] { dirtyTiers(); }));
        state.connections.append(connect(native, &KWin::Window::paletteChanged,
            this, [this, window] {
                if (auto it = m_windows.find(window); it != m_windows.end()) {
                    it.value().toneDirty = true;
                    window->windowItem()->scheduleRepaint(window->windowItem()->boundingRect());
                }
            }));
    }
    const EffectiveAppearance eff = m_config.effectiveFor(window->windowClass(),
        {native->desktopFileName(), native->resourceClass()});
    const bool maximized = native->maximizeMode() == KWin::MaximizeFull;
    const auto policy = window->isFullScreen() ? eff.states.fullscreen
        : maximized ? eff.states.maximized : StateSettings::Policy::Inherit;
    const bool dropped = policy == StateSettings::Policy::Off;
    state.appearanceDropped = dropped;
    const qreal scale = std::max<qreal>(0.01, native->targetScale());
    // Match KWin's pixel-snapped native corner radius; use the same value in
    // the decoration, inner outline, outer frame and both shadow layers.
    const qreal arcRadius = policy == StateSettings::Policy::Inherit
        ? std::round(clampedRadius(size, eff.corners.radius) * scale) / scale : 0.0;
    const bool continuous = !dropped && arcRadius > 0 && continuousAvailable
        && eff.corners.profile == CornerProfile::Continuous && eff.corners.smoothness > 0;
    const qreal radius = continuous
        ? clampedRadius(size, cornerExtent(arcRadius, eff.corners.smoothness)) : arcRadius;
    state.radii = CornerRadii{radius, radius, radius, radius};
    // Continuous mode clips the complete SSD/CSD frame in the compositor.
    // Keep its input sharp: native circular clipping would remove pixels
    // which the continuous contour still needs, or apply antialiasing twice.
    const QVector4D target = dropped ? state.declaredRadius
        : continuous ? QVector4D() : state.radii.toVector();
    const QVariant geometry = dropped ? state.declaredGeometryProperty : QVariant::fromValue(target);
    if (native->property(WindowRadiiProperty) != geometry) {
        native->setProperty(WindowRadiiProperty, geometry);
    }
    const QVariant visualRadii = dropped ? state.declaredVisualRadiiProperty
        : QVariant::fromValue(state.radii.toVector());
    const QVariant exponent = dropped ? state.declaredExponentProperty
        : QVariant::fromValue(continuous ? curveExponent(eff.corners.smoothness) : 2.0);
    if (native->property(VisualRadiiProperty) != visualRadii) {
        native->setProperty(VisualRadiiProperty, visualRadii);
    }
    if (native->property(CurveExponentProperty) != exponent) {
        native->setProperty(CurveExponentProperty, exponent);
    }
    if (native->borderRadius().toVector() != target) {
        native->setBorderRadius(KWin::BorderRadius(target.x(), target.y(), target.z(), target.w()));
    }
    state.appliedRadius = target;

    QObject *decoration = native->decoration();
    if (state.decoration != decoration) {
        if (state.decoration) {
            state.decoration->setProperty(DecorationRadiiProperty, state.declaredDecorationRadii);
            state.decoration->setProperty(DecorationShadowProperty, state.declaredDecorationShadow);
        }
        state.decoration = decoration;
        state.declaredDecorationRadii = decoration ? decoration->property(DecorationRadiiProperty) : QVariant();
        state.declaredDecorationShadow = decoration ? decoration->property(DecorationShadowProperty) : QVariant();
    }
    if (decoration && decoration->property(DecorationRadiiProperty) != QVariant::fromValue(target)) {
        decoration->setProperty(DecorationRadiiProperty, QVariant::fromValue(target));
    }

    if (state.toneDirty) {
        const QColor color = native->palette().color(QPalette::Window);
        state.windowDark = 0.2126 * color.redF() + 0.7152 * color.greenF()
            + 0.0722 * color.blueF() < 0.5;
        state.toneDirty = false;
    }
    const bool dark = eff.outline.appearance == WindowTone::Dark
        || (eff.outline.appearance == WindowTone::Auto && state.windowDark);
    const qreal requestedStroke = eff.outline.width
        * (eff.outline.widthUnit == OutlineSettings::WidthUnit::Physical ? 1.0 : scale);
    const qreal strokePixels = requestedStroke > 0
        ? (continuous ? requestedStroke : std::max<qreal>(1.0, std::round(requestedStroke))) : 0;
    const qreal stroke = strokePixels / scale;
    const KWin::RectF frameRect(QPointF(), size);
    if (!state.outline) {
        state.outline = new KWin::OutlinedBorderItem(frameRect, KWin::BorderOutline(), item);
        state.outline->setParent(item);
        state.outline->setZ(1);
    }
    const qreal innerStroke = std::min(stroke, std::min(size.width(), size.height()) / 2.0);
    // OutlinedBorderItem grows outward from its innerRect. Deflate the rect
    // AND radius so the outer edge stays exactly on the native window contour.
    state.outline->setOutline(KWin::BorderOutline(innerStroke,
        eff.outline.colorFor(dark), nativeRadii(state.radii, innerStroke)));
    state.outline->setInnerRect(KWin::RectF(innerStroke, innerStroke,
        std::max(0.0, size.width() - 2 * innerStroke),
        std::max(0.0, size.height() - 2 * innerStroke)));
    state.outline->setVisible(!dropped && !continuous && innerStroke > 0);
    const qreal frameWidth = std::round(eff.frame.width() * scale) / scale;
    if (!state.frame) {
        state.frame = new KWin::OutlinedBorderItem(frameRect, KWin::BorderOutline(), item);
        state.frame->setParent(item);
        state.frame->setZ(-1);
    }
    state.frame->setOutline(KWin::BorderOutline(frameWidth,
        eff.fill.colorFor(dark), nativeRadii(state.radii)));
    state.frame->setInnerRect(frameRect);
    state.frame->setVisible(!dropped && !continuous && frameWidth > 0);
    if (state.tierDirty) {
        state.tier = tierFor(window);
        state.tierDirty = false;
    }
    retarget(window, state, eff, dropped);

    if (continuous) {
        state.continuous = ContinuousStyle{size, radius, eff.corners.smoothness,
            innerStroke, frameWidth, dark, !eff.shadow.dynamic || state.tier == 0,
            state.edgeOpacity, state.shadowOpacity, eff.outline, eff.fill, eff.shadow};
        // Geometry only. KWin includes it in expandedGeometry, while the
        // shader paints the two shadows/frame. It has no texture or contents.
        // Reserve the widest dynamic shadow once. Focus changes only update
        // shader sigma/opacity; changing expandedGeometry here would resize
        // both this content FBO and an enclosing Dock-animation FBO, and
        // invalidate that animation's source bounds/grid at the handoff.
        const qreal blur = eff.shadow.dynamic
            ? std::max(eff.shadow.activeBlur, eff.shadow.inactiveBlur)
            : eff.shadow.activeBlur;
        const qreal padding = frameWidth + (eff.shadow.enabled
            ? 3 * std::max(blur, eff.shadow.contactBlur) : 0) + 1 / scale;
        if (!state.continuousBounds) {
            state.continuousBounds = new KWin::Item(item);
            state.continuousBounds->setParent(item);
        }
        state.continuousBounds->setGeometry(KWin::RectF(-padding, -padding,
            size.width() + 2 * padding, size.height() + 2 * padding));
    } else {
        state.continuous.reset();
        delete state.continuousBounds.data();
    }

    // DecorationShadow is preferred whenever the selected decoration exposes
    // the KOS relay and KWin permits native shadows in this window state.
    state.usesDecorationShadow = !continuous && decoration
        && decoration->property(DecorationAppearanceSupportedProperty).toBool()
        && native->wantsShadowToBeRendered();
    const bool hasShadow = !dropped && !continuous && eff.shadow.enabled;
    const bool wide = !eff.shadow.dynamic || state.tier == 0;
    const auto atlas = hasShadow ? m_shadowCache.get(state.radii, frameWidth,
        scale, eff.shadow, wide, state.usesDecorationShadow) : nullptr;
    // Keep the currently used atlas alive for SSD as well as CSD. A cache
    // eviction must not regenerate the same atlas on every paint pass.
    state.shadowAtlas = atlas;
    if (decoration && decoration->property(DecorationAppearanceSupportedProperty).toBool()) {
        const auto shadow = state.usesDecorationShadow && atlas
            ? atlas->decorationShadow : std::shared_ptr<KDecoration3::DecorationShadow>();
        const QVariant value = dropped ? state.declaredDecorationShadow : QVariant::fromValue(shadow);
        if (decoration->property(DecorationShadowProperty) != value) {
            decoration->setProperty(DecorationShadowProperty, value);
        }
    }
    auto *nativeShadow = item->shadowItem();
    if (state.nativeShadow != nativeShadow) {
        if (state.nativeShadow) {
            state.nativeShadow->setOpacity(state.declaredNativeShadowOpacity);
        }
        state.nativeShadow = nativeShadow;
        state.declaredNativeShadowOpacity = nativeShadow ? nativeShadow->opacity() : 1.0;
    }
    if (!state.usesDecorationShadow && hasShadow && atlas) {
        if (!state.sceneShadow) {
            state.sceneShadow = new SceneShadowItem(item);
            state.sceneShadow->setZ(-2);
        }
        state.sceneShadow->setAtlas(atlas);
        state.sceneShadow->setWindowSize(size);
        state.sceneShadow->setVisible(true);
    } else if (state.sceneShadow) {
        // Detach the unused fallback, so it no longer enlarges window bounds.
        delete state.sceneShadow.data();
    }
    if (dropped && state.nativeShadow) {
        state.nativeShadow->setOpacity(state.declaredNativeShadowOpacity);
    } else {
        applyOpacities(state);
    }
}

std::optional<ContinuousStyle> WindowAppearanceManager::continuousStyle(KWin::EffectWindow *window) const
{
    const auto it = m_windows.constFind(window);
    if (it == m_windows.cend() || !it.value().continuous) {
        return std::nullopt;
    }
    auto style = it.value().continuous;
    style->edgeOpacity = it.value().edgeOpacity;
    style->shadowOpacity = it.value().shadowOpacity;
    return style;
}

void WindowAppearanceManager::retarget(KWin::EffectWindow *window, WindowState &state,
    const EffectiveAppearance &eff, bool dropped)
{
    Q_UNUSED(window)
    const qreal shadow = !dropped && eff.shadow.enabled ? eff.shadow.tierAlpha(state.tier) : 0.0;
    const bool hasEdge = eff.outline.width > 0 || eff.frame.width() > 0;
    const qreal edge = !dropped && hasEdge
        ? (state.tier == 0 ? eff.outline.activeOpacity : eff.outline.inactiveOpacity) : 0.0;
    if (state.shadowTarget == shadow && state.edgeTarget == edge
        && state.transitionMs == eff.shadow.transitionMs) {
        return;
    }
    state.shadowStart = state.shadowOpacity;
    state.edgeStart = state.edgeOpacity;
    state.shadowTarget = shadow;
    state.edgeTarget = edge;
    state.transitionMs = eff.shadow.transitionMs;
    state.animationStarted = m_clock.elapsed();
    if (state.transitionMs == 0) {
        state.shadowOpacity = shadow;
        state.edgeOpacity = edge;
    } else if (!m_animTimer.isActive()) {
        m_animTimer.start();
    }
}

void WindowAppearanceManager::applyOpacities(WindowState &state)
{
    if (state.outline) {
        state.outline->setOpacity(state.edgeOpacity);
    }
    if (state.frame) {
        state.frame->setOpacity(state.edgeOpacity);
    }
    if (state.sceneShadow) {
        state.sceneShadow->setOpacity(state.shadowOpacity);
    }
    if (state.nativeShadow) {
        // Affect only the shadow node. Window/surface opacity is untouched.
        state.nativeShadow->setOpacity(state.appearanceDropped
            ? state.declaredNativeShadowOpacity
            : state.usesDecorationShadow ? state.shadowOpacity : 0.0);
    }
}

void WindowAppearanceManager::focusChanged(KWin::EffectWindow *gained)
{
    Q_UNUSED(gained)
    dirtyTiers();
}

void WindowAppearanceManager::animate()
{
    bool running = false;
    const qint64 now = m_clock.elapsed();
    for (auto it = m_windows.begin(); it != m_windows.end(); ++it) {
        auto &state = it.value();
        if (state.shadowOpacity == state.shadowTarget && state.edgeOpacity == state.edgeTarget) {
            continue;
        }
        const qreal progress = state.transitionMs > 0
            ? std::clamp(qreal(now - state.animationStarted) / state.transitionMs, 0.0, 1.0) : 1.0;
        const qreal eased = progress * progress * (3.0 - 2.0 * progress);
        state.shadowOpacity = state.shadowStart + (state.shadowTarget - state.shadowStart) * eased;
        state.edgeOpacity = state.edgeStart + (state.edgeTarget - state.edgeStart) * eased;
        if (progress >= 1.0) {
            state.shadowOpacity = state.shadowTarget;
            state.edgeOpacity = state.edgeTarget;
        } else {
            running = true;
        }
        // Item::setOpacity schedules only the affected item bounds, and does
        // nothing if unchanged. This timer stops at the configured deadline.
        applyOpacities(state);
        if (state.continuous && it.key()->windowItem()) {
            // Uniform-only animation: the cached window content stays intact.
            it.key()->windowItem()->scheduleRepaint(it.key()->windowItem()->boundingRect());
        }
    }
    if (!running) {
        m_animTimer.stop();
    }
}

void WindowAppearanceManager::restore(KWin::EffectWindow *window, WindowState &state)
{
    for (const auto &connection : state.connections) {
        disconnect(connection);
    }
    if (state.nativeShadow) {
        state.nativeShadow->setOpacity(state.declaredNativeShadowOpacity);
    }
    if (state.decoration) {
        state.decoration->setProperty(DecorationRadiiProperty, state.declaredDecorationRadii);
        state.decoration->setProperty(DecorationShadowProperty, state.declaredDecorationShadow);
    }
    delete state.sceneShadow.data();
    delete state.outline.data();
    delete state.frame.data();
    delete state.continuousBounds.data();
    if (window && window->window() && state.initialized) {
        auto *native = window->window();
        const QVector4D r = state.declaredRadius;
        native->setProperty(WindowRadiiProperty, state.declaredGeometryProperty);
        native->setProperty(VisualRadiiProperty, state.declaredVisualRadiiProperty);
        native->setProperty(CurveExponentProperty, state.declaredExponentProperty);
        native->setBorderRadius(KWin::BorderRadius(r.x(), r.y(), r.z(), r.w()));
    }
}

void WindowAppearanceManager::forget(KWin::EffectWindow *window)
{
    auto it = m_windows.find(window);
    if (it != m_windows.end()) {
        restore(window, it.value());
        m_windows.erase(it);
    }
}

void WindowAppearanceManager::restoreAll()
{
    m_animTimer.stop();
    m_tierTimer.stop();
    for (auto it = m_windows.begin(); it != m_windows.end(); ++it) {
        restore(it.key(), it.value());
    }
    m_windows.clear();
    m_shadowCache.clear();
}

} // namespace KOS
