#include "surfaceshape.h"

#include "wayland-kos-surface-shape-v1-client-protocol.h"

#include <QEvent>
#include <QGuiApplication>
#include <QtGui/qguiapplication_platform.h>
#include <QQuickItem>
#include <QQuickWindow>
#include <QtGui/qpa/qplatformwindow_p.h>
#include <algorithm>
#include <wayland-client-core.h>

// Polish runs on the GUI thread after animations/layout and before the scene
// graph is synchronized. A zero-timeout callback can run after that frame's
// wl_surface.commit, leaving Glass with the previous geometry and scrim while
// the new blur region/content is already on screen.
class SurfaceShapeSyncItem : public QQuickItem
{
public:
    SurfaceShapeSyncItem(SurfaceShape *shape, QQuickItem *parent)
        : QQuickItem(parent), m_shape(shape) {}

protected:
    void updatePolish() override { m_shape->sync(); }

private:
    SurfaceShape *m_shape;
};

namespace
{
// QQuickItem::isVisible() already folds in the whole ancestor chain, but its
// opacity does not. A panel faded out by an ancestor -- the Dock's reveal
// handle cross-fades its pill to 0 -- is still "visible" and would keep
// claiming a compositor shape, and the compositor cannot tell a transparent
// panel from a missing one: it would paint glass for something the user cannot
// see. So the gate has to follow effective opacity too, and the window's own
// visibility, since a hidden surface has nothing on screen either.
bool effectivelyShown(const QQuickItem *item)
{
    for (const QQuickItem *ancestor = item; ancestor;
         ancestor = ancestor->parentItem()) {
        if (!ancestor->isVisible() || ancestor->opacity() <= 0.0) {
            return false;
        }
    }
    QQuickWindow *window = item ? item->window() : nullptr;
    return !window || window->isVisible();
}

// One warning per process: whether set_scrim may be sent is a property of the
// compositor this client is bound to, not of any single shape.
bool warnedScrimUnavailable = false;
bool warnedBlurUnavailable = false;

class ShapeProtocol : public QObject
{
public:
    static ShapeProtocol &instance()
    {
        static ShapeProtocol protocol;
        return protocol;
    }

    kos_surface_shape_manager_v1 *manager() const { return m_manager; }

private:
    ShapeProtocol()
    {
        auto *native = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>();
        if (!native) {
            return;
        }
        m_registry = wl_display_get_registry(native->display());
        static const wl_registry_listener listener{global, globalRemove};
        wl_registry_add_listener(m_registry, &listener, this);
        wl_display_flush(native->display());
    }

    ~ShapeProtocol() override
    {
        // 应用程序退出时底层 Wayland 连接往往已先行销毁，必须验证连接有效性，防止调用已失效指针导致崩溃弹窗
        auto *native = qGuiApp ? qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>() : nullptr;
        if (!native || !native->display()) {
            return;
        }
        if (m_manager) {
            kos_surface_shape_manager_v1_destroy(m_manager);
            m_manager = nullptr;
        }
        if (m_registry) {
            wl_registry_destroy(m_registry);
            m_registry = nullptr;
        }
    }

    static void global(void *data, wl_registry *registry, uint32_t name,
                       const char *interface, uint32_t version)
    {
        auto *self = static_cast<ShapeProtocol *>(data);
        if (qstrcmp(interface, kos_surface_shape_manager_v1_interface.name) == 0) {
            self->m_manager = static_cast<kos_surface_shape_manager_v1 *>(
                wl_registry_bind(registry, name,
                    &kos_surface_shape_manager_v1_interface, std::min(version, 7u)));
            self->m_globalName = name;
            Q_EMIT self->available();
        }
    }

    static void globalRemove(void *data, wl_registry *, uint32_t name)
    {
        auto *self = static_cast<ShapeProtocol *>(data);
        if (name != self->m_globalName) {
            return;
        }
        // Release the children first: their destroy still has to reach the
        // manager resource before we let go of it.
        Q_EMIT self->unavailable();
        if (self->m_manager) {
            // The compositor blanked the server-side implementation on its way
            // out, so a `destroy` request would dispatch against null. Drop the
            // proxy locally instead; the next `global` event binds a fresh one
            // and every SurfaceShape re-attaches through available().
            wl_proxy_destroy(reinterpret_cast<wl_proxy *>(self->m_manager));
        }
        self->m_manager = nullptr;
        self->m_globalName = 0;
    }

Q_SIGNALS:
    void available();
    void unavailable();

private:
    Q_OBJECT
    wl_registry *m_registry = nullptr;
    kos_surface_shape_manager_v1 *m_manager = nullptr;
    uint32_t m_globalName = 0;
};
}

SurfaceShape::SurfaceShape(QObject *parent)
    : QObject(parent)
{
    connect(&ShapeProtocol::instance(), &ShapeProtocol::available,
            this, &SurfaceShape::scheduleSync);
    connect(&ShapeProtocol::instance(), &ShapeProtocol::unavailable,
            this, [this] { releaseShape(); });
}

SurfaceShape::~SurfaceShape()
{
    delete m_syncItem;
    releaseShape();
    disconnectAncestors();
}

void SurfaceShape::setTarget(QQuickItem *target)
{
    if (m_target == target) return;
    if (m_target) disconnect(m_target, nullptr, this, nullptr);
    m_target = target;
    if (m_target) {
        connect(m_target, &QQuickItem::windowChanged,
                this, &SurfaceShape::handleWindowChanged);
        connect(m_target, &QQuickItem::xChanged, this, &SurfaceShape::scheduleSync);
        connect(m_target, &QQuickItem::yChanged, this, &SurfaceShape::scheduleSync);
        connect(m_target, &QQuickItem::widthChanged, this, &SurfaceShape::scheduleSync);
        connect(m_target, &QQuickItem::heightChanged, this, &SurfaceShape::scheduleSync);
        // The gate above reads effective visibility and opacity, so those have
        // to re-run the sync the same way a geometry change does.
        connect(m_target, &QQuickItem::visibleChanged, this, &SurfaceShape::scheduleSync);
        connect(m_target, &QQuickItem::opacityChanged, this, &SurfaceShape::scheduleSync);
        // Re-parenting moves the item without touching any of its own
        // properties, so the ancestor chain has to be rewired first.
        connect(m_target, &QQuickItem::parentChanged,
                this, &SurfaceShape::rewireAncestors);
        // handleWindowChanged short-circuits when the window is unchanged, so
        // a target swap inside one window still needs the chain rebuilt here.
        rewireAncestors();
        handleWindowChanged(m_target->window());
    } else {
        disconnectAncestors();
        handleWindowChanged(nullptr);
    }
    Q_EMIT targetChanged();
}

void SurfaceShape::rewireAncestors()
{
    disconnectAncestors();
    for (QQuickItem *item = m_target ? m_target->parentItem() : nullptr;
         item; item = item->parentItem()) {
        m_ancestorConnections.append(connect(item, &QQuickItem::xChanged,
                                             this, &SurfaceShape::scheduleSync));
        m_ancestorConnections.append(connect(item, &QQuickItem::yChanged,
                                             this, &SurfaceShape::scheduleSync));
        m_ancestorConnections.append(connect(item, &QQuickItem::visibleChanged,
                                             this, &SurfaceShape::scheduleSync));
        m_ancestorConnections.append(connect(item, &QQuickItem::opacityChanged,
                                             this, &SurfaceShape::scheduleSync));
    }
    scheduleSync();
}

void SurfaceShape::disconnectAncestors()
{
    for (const QMetaObject::Connection &connection : m_ancestorConnections) {
        disconnect(connection);
    }
    m_ancestorConnections.clear();
}

void SurfaceShape::setRadius(qreal radius)
{
    radius = std::max<qreal>(0.0, radius);
    if (qFuzzyCompare(m_radius, radius)) return;
    m_radius = radius; Q_EMIT radiusChanged(); scheduleSync();
}

void SurfaceShape::setExponent(qreal exponent)
{
    exponent = std::clamp(exponent, 2.0, 8.0);
    if (qFuzzyCompare(m_exponent, exponent)) return;
    m_exponent = exponent; Q_EMIT exponentChanged(); scheduleSync();
}

void SurfaceShape::setEnabled(bool enabled)
{
    if (m_enabled == enabled) return;
    m_enabled = enabled; Q_EMIT enabledChanged(); scheduleSync();
}

void SurfaceShape::setCaptureGeometry(const QRectF &geometry)
{
    if (m_captureGeometry == geometry) return;
    m_captureGeometry = geometry;
    Q_EMIT captureGeometryChanged();
    scheduleSync();
}

bool SurfaceShape::fixedCaptureSupported() const
{
    return m_shape && wl_proxy_get_version(reinterpret_cast<wl_proxy *>(m_shape))
        >= KOS_SURFACE_SHAPE_V1_SET_CAPTURE_GEOMETRY_SINCE_VERSION;
}

void SurfaceShape::setMaterialOpacity(qreal opacity)
{
    opacity = std::clamp(opacity, 0.0, 1.0);
    if (m_materialOpacity == opacity) return;
    m_materialOpacity = opacity;
    Q_EMIT materialOpacityChanged();
    scheduleSync();
}

bool SurfaceShape::materialOpacitySupported() const
{
    return m_shape && wl_proxy_get_version(reinterpret_cast<wl_proxy *>(m_shape))
        >= KOS_SURFACE_SHAPE_V1_SET_MATERIAL_OPACITY_SINCE_VERSION;
}

void SurfaceShape::setRevealEnabled(bool enabled)
{
    if (m_revealEnabled == enabled) return;
    m_revealEnabled = enabled; m_revealDirty = true;
    Q_EMIT revealChanged(); scheduleSync();
}

void SurfaceShape::setRevealOpened(bool opened)
{
    if (m_revealOpened == opened) return;
    m_revealOpened = opened; m_revealDirty = true;
    Q_EMIT revealChanged(); scheduleSync();
}

void SurfaceShape::setRevealDuration(int duration)
{
    duration = std::clamp(duration, 1, 2000);
    if (m_revealDuration == duration) return;
    m_revealDuration = duration; m_revealDirty = true;
    Q_EMIT revealChanged(); scheduleSync();
}

bool SurfaceShape::revealSupported() const
{
    return m_shape && wl_proxy_get_version(reinterpret_cast<wl_proxy *>(m_shape))
        >= KOS_SURFACE_SHAPE_V1_SET_REVEAL_SINCE_VERSION;
}

void SurfaceShape::setScrimEnabled(bool enabled)
{
    if (m_scrimEnabled == enabled) return;
    m_scrimEnabled = enabled; Q_EMIT scrimEnabledChanged(); scheduleSync();
}

void SurfaceShape::setScrimTint(int tint)
{
    tint = (tint == 1) ? 1 : 0;
    if (m_scrimTint == tint) return;
    m_scrimTint = tint; Q_EMIT scrimTintChanged(); scheduleSync();
}

void SurfaceShape::setScrimCap(qreal cap)
{
    cap = std::clamp(cap, 0.0, 1.0);
    if (qFuzzyCompare(m_scrimCap, cap)) return;
    m_scrimCap = cap; Q_EMIT scrimCapChanged(); scheduleSync();
}

void SurfaceShape::setScrimDecay(qreal decay)
{
    // 0..1 is adaptive decay. Values above 1 encode fixed mode while keeping
    // the v3 wire request backward-compatible with old compositors.
    decay = std::clamp(decay, 0.0, 4.0);
    if (qFuzzyCompare(m_scrimDecay, decay)) return;
    m_scrimDecay = decay; Q_EMIT scrimDecayChanged(); scheduleSync();
}

void SurfaceShape::setBlurEnabled(bool enabled)
{
    if (m_blurEnabled == enabled) return;
    m_blurEnabled = enabled; Q_EMIT blurEnabledChanged(); scheduleSync();
}

void SurfaceShape::setBlurLevel(int level)
{
    // The compositor blur table is 15 steps; the global path writes 1..15
    // through the same scale, so clamp here rather than trusting the caller.
    level = std::clamp(level, 1, 15);
    if (m_blurLevel == level) return;
    m_blurLevel = level; Q_EMIT blurLevelChanged(); scheduleSync();
}

void SurfaceShape::handleWindowChanged(QQuickWindow *window)
{
    if (m_window == window) { scheduleSync(); return; }
    if (m_window) m_window->removeEventFilter(this);
    delete m_syncItem;
    m_syncPending = false;
    releaseShape();
    m_window = window;
    if (m_window) {
        m_window->installEventFilter(this);
        m_syncItem = new SurfaceShapeSyncItem(this, m_window->contentItem());
    }
    rewireAncestors();
}

bool SurfaceShape::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == m_window && event->type() == QEvent::PlatformSurface)
        scheduleSync();
    return QObject::eventFilter(watched, event);
}

wl_surface *SurfaceShape::nativeSurface() const
{
    if (!m_window || !m_window->handle()) return nullptr;
    auto *native = m_window->nativeInterface<QNativeInterface::Private::QWaylandWindow>();
    return native ? native->surface() : nullptr;
}

void SurfaceShape::scheduleSync()
{
    if (m_syncPending || !m_syncItem) return;
    m_syncPending = true;
    m_syncItem->polish();
}

void SurfaceShape::sync()
{
    m_syncPending = false;
    if (!m_target || !m_window) { releaseShape(); return; }
    wl_surface *surface = nativeSurface();
    auto *manager = ShapeProtocol::instance().manager();
    // 早退也要释放旧 shape 代理：窗口销毁中途 surface 变 null 时它仍指向
    // 旧 surface（active 属性也保持与实际不符），到下次变更才被释放
    if (!surface) {
        releaseShape();
        return;
    }
    if (!manager) return;
    if (surface != m_surface) {
        releaseShape();
        m_surface = surface;
        m_shape = kos_surface_shape_manager_v1_get_shape(manager, surface);
        static const kos_surface_shape_v1_listener listener{
            [](void *data, kos_surface_shape_v1 *, uint32_t opened, uint32_t serial) {
                auto *self = static_cast<SurfaceShape *>(data);
                // A new request invalidates any completion still in flight.
                if (serial == self->m_revealSerial && !self->m_revealDirty)
                    Q_EMIT self->revealFinished(opened != 0);
            }
        };
        kos_surface_shape_v1_add_listener(m_shape, &listener, this);
        Q_EMIT activeChanged();
    }
    const QRectF geometry = m_target->mapRectToScene(
        QRectF(0, 0, m_target->width(), m_target->height()));
    kos_surface_shape_v1_set_geometry(m_shape,
        qRound(geometry.x()), qRound(geometry.y()),
        qRound(geometry.width()), qRound(geometry.height()));
    if (fixedCaptureSupported()) {
        const QRect capture = m_captureGeometry.toAlignedRect();
        kos_surface_shape_v1_set_capture_geometry(m_shape,
            capture.x(), capture.y(), std::max(0, capture.width()), std::max(0, capture.height()));
    }
    if (materialOpacitySupported()) {
        kos_surface_shape_v1_set_material_opacity(m_shape,
            wl_fixed_from_double(m_materialOpacity));
    }
    kos_surface_shape_v1_set_corner(m_shape,
        wl_fixed_from_double(m_radius), wl_fixed_from_double(m_exponent));
    kos_surface_shape_v1_set_enabled(m_shape,
        (m_enabled && effectivelyShown(m_target)) ? 1 : 0);
    if (revealSupported() && m_revealDirty) {
        m_revealDirty = false;
        kos_surface_shape_v1_set_reveal(m_shape, m_revealEnabled, m_revealOpened,
            m_revealDuration, ++m_revealSerial);
    }
    // set_scrim is since=3, and libwayland-client does not range-check the
    // opcode: sending it on a proxy bound at an older version is a protocol
    // error that takes the whole Wayland connection down. Bind-time version is
    // the compositor's advertised one, so honour it here rather than relying on
    // the server having created the resource at 3.
    if (wl_proxy_get_version(reinterpret_cast<struct wl_proxy *>(m_shape))
        >= KOS_SURFACE_SHAPE_V1_SET_SCRIM_SINCE_VERSION) {
        kos_surface_shape_v1_set_scrim(m_shape,
            (m_scrimEnabled && effectivelyShown(m_target)) ? 1 : 0,
            m_scrimTint,
            wl_fixed_from_double(m_scrimCap),
            wl_fixed_from_double(m_scrimDecay));
    } else if (!warnedScrimUnavailable) {
        warnedScrimUnavailable = true;
        qWarning() << "kos-surface-shape: compositor bound below protocol version 3;"
                   << "the contrast scrim is unavailable";
    }
    // set_blur is since=4, guarded the same way as set_scrim above: the
    // opcode check protects the connection against an older compositor.
    if (wl_proxy_get_version(reinterpret_cast<struct wl_proxy *>(m_shape))
        >= KOS_SURFACE_SHAPE_V1_SET_BLUR_SINCE_VERSION) {
        kos_surface_shape_v1_set_blur(m_shape, m_blurEnabled ? 1 : 0, m_blurLevel);
    } else if (m_blurEnabled && !warnedBlurUnavailable) {
        warnedBlurUnavailable = true;
        qWarning() << "kos-surface-shape: compositor bound below protocol version 4;"
                   << "the per-shape blur override is unavailable";
    }
}

void SurfaceShape::releaseShape()
{
    if (m_shape) kos_surface_shape_v1_destroy(m_shape);
    const bool wasActive = m_shape != nullptr;
    m_shape = nullptr;
    m_surface = nullptr;
    m_revealDirty = true;
    if (wasActive) Q_EMIT activeChanged();
}

#include "surfaceshape.moc"
