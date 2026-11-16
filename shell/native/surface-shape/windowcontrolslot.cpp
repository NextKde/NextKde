#include "windowcontrolslot.h"
#include "wayland-kos-window-controls-v1-client-protocol.h"
#include <QGuiApplication>
#include <QQuickWindow>
#include <QPlatformSurfaceEvent>
#include <QtGui/qguiapplication_platform.h>
#include <QtGui/qpa/qplatformwindow_p.h>
#include <wayland-client-core.h>
#include <cmath>
#include <algorithm>
#include <array>

class ControlsProtocol : public QObject {
    Q_OBJECT
public:
    static ControlsProtocol &instance() { static ControlsProtocol value; return value; }
    kos_window_controls_manager_v1 *manager = nullptr;
Q_SIGNALS:
    void available();
    void unavailable();
private:
    wl_registry *registry = nullptr;
    uint32_t globalName = 0;
    ControlsProtocol() {
        auto *native = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>();
        if (!native) return;
        registry = wl_display_get_registry(native->display());
        static const wl_registry_listener listener{global, removed};
        wl_registry_add_listener(registry, &listener, this);
        wl_display_flush(native->display());
    }
    ~ControlsProtocol() override {
        auto *native = qGuiApp ? qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>() : nullptr;
        if (!native || !native->display()) return;
        if (manager) kos_window_controls_manager_v1_destroy(manager);
        if (registry) wl_registry_destroy(registry);
    }
    static void global(void *data, wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
        auto *self = static_cast<ControlsProtocol *>(data);
        if (qstrcmp(interface, kos_window_controls_manager_v1_interface.name) || self->manager) return;
        self->manager = static_cast<kos_window_controls_manager_v1 *>(wl_registry_bind(registry, name, &kos_window_controls_manager_v1_interface, std::min(version, 2u)));
        self->globalName = name;
        Q_EMIT self->available();
    }
    static void removed(void *data, wl_registry *, uint32_t name) {
        auto *self = static_cast<ControlsProtocol *>(data);
        if (name != self->globalName) return;
        Q_EMIT self->unavailable();
        wl_proxy_destroy(reinterpret_cast<wl_proxy *>(self->manager));
        self->manager = nullptr; self->globalName = 0;
    }
};

WindowControlSlot::WindowControlSlot(QQuickItem *parent) : QQuickItem(parent) {
    setFlag(ItemHasContents, false);
    auto &protocol = ControlsProtocol::instance();
    connect(&protocol, &ControlsProtocol::available, this, &WindowControlSlot::schedule);
    connect(&protocol, &ControlsProtocol::unavailable, this, [this] { release(true); });
    connect(this, &QQuickItem::enabledChanged, this, &WindowControlSlot::schedule);
}
WindowControlSlot::~WindowControlSlot() { release(); }
void WindowControlSlot::setTarget(QQuickItem *item) {
    if (item == m_target) return;
    release();
    m_target = item;
    watchTarget();
    Q_EMIT targetChanged();
}
void WindowControlSlot::setButtons(const QVariantList &value) {
    if (m_buttons == value) return;
    m_buttons = value; Q_EMIT metricsChanged(); schedule();
}
void WindowControlSlot::watchTarget() {
    for (const auto &connection : std::as_const(m_connections)) disconnect(connection);
    m_connections.clear();
    for (auto *item = m_target.data(); item; item = item->parentItem()) {
        for (auto signal : {&QQuickItem::xChanged, &QQuickItem::yChanged, &QQuickItem::widthChanged,
                            &QQuickItem::heightChanged, &QQuickItem::scaleChanged, &QQuickItem::rotationChanged,
                            &QQuickItem::visibleChanged, &QQuickItem::opacityChanged})
            m_connections.append(connect(item, signal, this, &WindowControlSlot::schedule));
        m_connections.append(connect(item, &QQuickItem::parentChanged, this, [this] { watchTarget(); }));
    }
    if (m_target) {
        m_connections.append(connect(m_target, &QQuickItem::windowChanged, this, [this] { attachWindow(); }));
        m_connections.append(connect(m_target, &QObject::destroyed, this, [this] { release(); m_target = nullptr; }));
    }
    attachWindow();
}
void WindowControlSlot::attachWindow() {
    auto *window = m_target ? m_target->window() : nullptr;
    if (window != m_window) {
        release();
        if (m_window) m_window->removeEventFilter(this);
        m_window = window;
        if (m_window) m_window->installEventFilter(this);
    }
    schedule();
}
bool WindowControlSlot::eventFilter(QObject *object, QEvent *event) {
    if (object == m_window && event->type() == QEvent::PlatformSurface) {
        auto *surfaceEvent = static_cast<QPlatformSurfaceEvent *>(event);
        if (surfaceEvent->surfaceEventType() == QPlatformSurfaceEvent::SurfaceAboutToBeDestroyed) release();
        else schedule();
    }
    if (object == m_window && (event->type() == QEvent::Show || event->type() == QEvent::WindowStateChange)) schedule();
    return false;
}
void WindowControlSlot::release(bool serverGone) {
    auto *native = qGuiApp ? qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>() : nullptr;
    if (m_controls && native && native->display()) {
        if (serverGone) wl_proxy_destroy(reinterpret_cast<wl_proxy *>(m_controls));
        else kos_window_controls_v1_destroy(m_controls);
    }
    m_controls = nullptr; m_surface = nullptr; m_active = false; m_ack = 0; m_haveRegion = false;
    Q_EMIT activeChanged();
    if (m_window) m_window->update();
}
void WindowControlSlot::schedule() {
    if (!m_target || !m_window) return;
    polish();
    m_window->update();
}
void WindowControlSlot::configured(void *data, kos_window_controls_v1 *, uint32_t serial, uint32_t active, uint32_t glyph) {
    auto *self = static_cast<WindowControlSlot *>(data);
    self->m_active = active == 1;
    self->m_hoverGlyphs = glyph == 1;
    self->m_ack = serial;
    Q_EMIT self->activeChanged();
    self->schedule();
}
void WindowControlSlot::updatePolish() {
    if (!m_target || !m_window || !m_window->handle()) return;
    auto *native = m_window->nativeInterface<QNativeInterface::Private::QWaylandWindow>();
    auto *surface = native ? native->surface() : nullptr;
    auto *manager = ControlsProtocol::instance().manager;
    if (!surface || !manager) return;
    if (m_surface != surface) {
        release();
        m_surface = surface;
        m_controls = kos_window_controls_manager_v1_get_controls(manager, surface);
        static const kos_window_controls_v1_listener listener{configured};
        kos_window_controls_v1_add_listener(m_controls, &listener, this);
        Q_EMIT activeChanged();
    }
    const QPointF origin = m_target->mapToScene(QPointF());
    const QPointF xAxis = m_target->mapToScene(QPointF(1, 0)) - origin;
    const QPointF yAxis = m_target->mapToScene(QPointF(0, 1)) - origin;
    // Nonuniform scaling/rotation cannot be represented by circular controls;
    // keep the application's own transformed controls in that case.
    bool enabled = isEnabled() && m_target->isVisible() && m_window->isVisible()
        && m_window->visibility() != QWindow::FullScreen
        && std::abs(xAxis.y()) < .001 && std::abs(yAxis.x()) < .001
        && xAxis.x() > 0 && std::abs(xAxis.x() - yAxis.y()) < .001;
    for (auto *item = m_target.data(); item; item = item->parentItem())
        enabled = enabled && item->opacity() >= 1.0;
    const qreal scale = xAxis.x();
    QByteArray bytes;
    bool valid = m_buttons.size() <= 3;
    std::array<bool, 3> seen{};
    for (const auto &button : m_buttons) {
        const auto fields = button.toMap();
        const int action = QStringList{"maximize", "minimize", "close"}.indexOf(fields.value("action").toString());
        const QPointF position = origin + QPointF(fields.value("x").toDouble()*scale, fields.value("y").toDouble()*scale);
        const qreal width = fields.value("width").toDouble()*scale, height = fields.value("height").toDouble()*scale;
        const bool itemValid = action >= 0 && !seen[action] && std::isfinite(position.x()) && std::isfinite(position.y())
            && std::isfinite(width) && std::isfinite(height) && position.x() >= 0 && position.y() >= 0
            && position.x() < 65536 && position.y() < 65536 && width >= 6 && width <= 40 && width == height;
        valid = valid && itemValid;
        if (!itemValid) continue;
        seen[action] = true;
        const int32_t words[]{action, wl_fixed_from_double(position.x()), wl_fixed_from_double(position.y()),
                              wl_fixed_from_double(width), wl_fixed_from_double(height)};
        bytes.append(reinterpret_cast<const char *>(words), sizeof(words));
    }
    enabled = enabled && valid;
    if (!enabled) bytes.clear();
    if (!m_haveRegion || bytes != m_lastButtons || enabled != m_lastEnabled) {
        if (kos_window_controls_v1_get_version(m_controls) >= 2) {
            wl_array array{size_t(bytes.size()), size_t(bytes.size()), bytes.data()};
            kos_window_controls_v1_set_buttons(m_controls, &array, enabled);
        } else {
            // Keep legacy overlays suppressed, but never give a v1 compositor
            // an arbitrary button list it cannot represent.
            kos_window_controls_v1_set_region(m_controls, 0, 0, 0, 0, 0, 0, 0);
        }
        m_lastButtons = bytes; m_lastEnabled = enabled; m_haveRegion = true;
    }
    if (m_ack) { kos_window_controls_v1_ack_configure(m_controls, m_ack); m_ack = 0; }
    // No timers, frame polling or readbacks. Polish requests are scheduled only
    // by layout, visibility, surface lifecycle and configure events.
}
#include "windowcontrolslot.moc"
