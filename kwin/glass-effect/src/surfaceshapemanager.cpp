#include "surfaceshapemanager.h"

#include "wayland-kos-surface-shape-v1-server-protocol.h"
#include "wayland/display.h"
#include "wayland/surface.h"

#include <algorithm>
#include <wayland-server-core.h>

namespace KWin
{
struct SurfaceShapeManager::ShapeResource
{
    SurfaceShapeManager *manager = nullptr;
    SurfaceInterface *surface = nullptr;
    wl_resource *resource = nullptr;
    SurfaceShape value;
    QMetaObject::Connection surfaceDestroyed;
    bool revealEnabled = false;
    bool revealOpened = false;
    bool revealRunning = false;
    qreal progress = 0;
    qreal startProgress = 0;
    qint64 startTime = 0;
    uint32_t duration = 320;
    uint32_t serial = 0;
};

static const struct kos_surface_shape_manager_v1_interface s_managerImplementation{
    SurfaceShapeManager::getShape,
    SurfaceShapeManager::destroyManagerResource,
};

static const struct kos_surface_shape_v1_interface s_shapeImplementation{
    SurfaceShapeManager::setGeometry,
    SurfaceShapeManager::setCorner,
    SurfaceShapeManager::setEnabled,
    SurfaceShapeManager::setRole,
    SurfaceShapeManager::destroyShape,
    SurfaceShapeManager::setScrim,
    SurfaceShapeManager::setBlur,
    SurfaceShapeManager::setCaptureGeometry,
    SurfaceShapeManager::setMaterialOpacity,
    SurfaceShapeManager::setReveal,
};

SurfaceShapeManager::SurfaceShapeManager(Display *display, QObject *parent)
    : QObject(parent)
{
    m_clock.start();
    // Must advertise the interface version the protocol declares, or a
    // conformant client binds at 1 and can never send the since=3 set_scrim
    // or the since=4/5/6/7 material and reveal requests. Shape resource versions follow
    // the actual negotiated manager version below.
    m_global = wl_global_create(*display, &kos_surface_shape_manager_v1_interface,
                                7, this, bindManager);
}

SurfaceShapeManager::~SurfaceShapeManager()
{
    if (m_global) {
        wl_global_destroy(m_global);
    }
    // Client-owned shape resources OUTLIVE us. Destroying them here would drop
    // their ids from the client's object map, and the `destroy` the client is
    // about to send for the vanished global would come back as "invalid object"
    // -- a fatal protocol error that kills the whole connection. Detach instead:
    // the resource stays dispatachable, every callback turns into a no-op, and
    // the heap ShapeResource is freed by the client's own destroy. If the client
    // disconnects first, wl_resource's destructor does it.
    const auto lists = m_shapes;
    m_shapes.clear();
    for (const auto &list : lists) {
        for (ShapeResource *shape : list) {
            shape->manager = nullptr;
            shape->surface = nullptr;
            disconnect(shape->surfaceDestroyed);
        }
    }
}

QVector<SurfaceShape> SurfaceShapeManager::shapesFor(const SurfaceInterface *surface) const
{
    QVector<SurfaceShape> result;
    for (const ShapeResource *shape : m_shapes.value(surface)) {
        // Retain a zero-opacity declaration through the client's final hide
        // commit, so a stale blur region cannot fall back to a full glass slab.
        const bool closedReveal = shape->revealEnabled && shape->progress == 0;
        if ((shape->value.enabled || closedReveal) && shape->value.geometry.width() > 0
            && shape->value.geometry.height() > 0) {
            SurfaceShape value = shape->value;
            if (shape->revealEnabled) {
                value.enabled = true;
                const QRectF finalRect = value.geometry;
                // The allocation remains constant, including the fully closed pose.
                value.captureGeometry = surfaceCaptureBounds(value);
                const SurfaceReveal reveal{finalRect, shape->progress};
                // Glass and client content share the same bottom-center transform.
                // Closed geometry is still 80% sized; opacity retires the panel.
                value.geometry = reveal.visibleGeometry();
                value.radius *= reveal.scale();
                value.materialOpacity *= reveal.progress;
            }
            result.append(value);
        }
    }
    return result;
}

std::optional<SurfaceReveal> SurfaceShapeManager::revealFor(const SurfaceInterface *surface) const
{
    for (const ShapeResource *shape : m_shapes.value(surface)) {
        if (shape->revealEnabled) {
            return SurfaceReveal{shape->value.geometry, shape->progress};
        }
    }
    return std::nullopt;
}

void SurfaceShapeManager::advanceAnimations()
{
    const qint64 now = m_clock.elapsed();
    for (const auto &list : std::as_const(m_shapes)) {
        for (ShapeResource *shape : list) {
            if (!shape->revealRunning) continue;
            const qreal t = std::clamp(qreal(now - shape->startTime) / shape->duration, 0.0, 1.0);
            const qreal eased = 1 - (1 - t) * (1 - t) * (1 - t);
            shape->progress = shape->startProgress
                + ((shape->revealOpened ? 1.0 : 0.0) - shape->startProgress) * eased;
            Q_EMIT revealFrameChanged(shape->surface, surfaceCaptureBounds(shape->value));
            if (t >= 1) {
                shape->revealRunning = false;
                kos_surface_shape_v1_send_reveal_finished(shape->resource,
                    shape->revealOpened, shape->serial);
            }
        }
    }
}

void SurfaceShapeManager::bindManager(wl_client *client, void *data,
                                      uint32_t version, uint32_t id)
{
    wl_resource *resource = wl_resource_create(client,
        &kos_surface_shape_manager_v1_interface, std::min(version, 7u), id);
    wl_resource_set_implementation(resource, &s_managerImplementation, data, nullptr);
}

void SurfaceShapeManager::destroyManagerResource(wl_client *, wl_resource *resource)
{
    wl_resource_destroy(resource);
}

void SurfaceShapeManager::getShape(wl_client *client, wl_resource *resource,
                                   uint32_t id, wl_resource *surfaceResource)
{
    auto *manager = static_cast<SurfaceShapeManager *>(wl_resource_get_user_data(resource));
    SurfaceInterface *surface = SurfaceInterface::get(surfaceResource);
    if (!surface) {
        wl_resource_post_error(resource, 0, "invalid wl_surface");
        return;
    }
    auto *shape = new ShapeResource;
    shape->manager = manager;
    shape->surface = surface;
    shape->value.id = manager->m_nextId++;
    // shape 资源版本跟随 manager 资源的实际协商版本（bind 侧已 min(version,7)）
    // ——写死 4 会让 v1 客户端拿到标成 v4 的资源，将来按版本门控全失真
    shape->resource = wl_resource_create(client, &kos_surface_shape_v1_interface,
                                          wl_resource_get_version(resource), id);
    wl_resource_set_implementation(shape->resource, &s_shapeImplementation, shape,
                                   destroyShapeResource);
    shape->surfaceDestroyed = connect(surface, &QObject::destroyed, manager,
        [shape] {
            // remove() reads shape->surface back out of the hash key, so it must
            // NOT be cleared here -- doing so would leave the bucket holding a
            // freed ShapeResource. The disconnect inside remove() also makes
            // sure this lambda can never run after the shape is gone.
            if (shape->resource) {
                wl_resource_destroy(shape->resource);
            }
        });
    manager->m_shapes[surface].append(shape);
    Q_EMIT manager->surfaceShapesChanged(surface);
}

void SurfaceShapeManager::destroyShapeResource(wl_resource *resource)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape) {
        return;
    }
    shape->resource = nullptr;
    if (shape->manager) {
        shape->manager->remove(shape);
    } else {
        // Orphaned by the manager's teardown; the resource was kept alive on
        // purpose so this client-side destroy could reclaim it.
        delete shape;
    }
}

void SurfaceShapeManager::setGeometry(wl_client *, wl_resource *resource,
                                      int32_t x, int32_t y, int32_t width, int32_t height)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape->manager) {
        return;
    }
    shape->value.geometry = QRectF(x, y, std::max(width, 0), std::max(height, 0));
    shape->manager->changed(shape);
}

void SurfaceShapeManager::setCorner(wl_client *, wl_resource *resource,
                                    wl_fixed_t radius, wl_fixed_t exponent)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape->manager) {
        return;
    }
    shape->value.radius = std::clamp(wl_fixed_to_double(radius), 0.0, 4096.0);
    shape->value.exponent = std::clamp(wl_fixed_to_double(exponent), 2.0, 8.0);
    shape->manager->changed(shape);
}

void SurfaceShapeManager::setCaptureGeometry(wl_client *, wl_resource *resource,
                                            int32_t x, int32_t y, int32_t width, int32_t height)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape->manager) return;
    const QRectF capture(x, y, std::max(width, 0), std::max(height, 0));
    if (shape->value.captureGeometry == capture) return;
    shape->value.captureGeometry = capture;
    shape->manager->changed(shape);
}

void SurfaceShapeManager::setMaterialOpacity(wl_client *, wl_resource *resource, wl_fixed_t opacity)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape->manager) return;
    const qreal value = std::clamp(wl_fixed_to_double(opacity), 0.0, 1.0);
    if (shape->value.materialOpacity == value) return;
    shape->value.materialOpacity = value;
    shape->manager->changed(shape);
}

void SurfaceShapeManager::setReveal(wl_client *, wl_resource *resource,
                                    uint32_t enabled, uint32_t opened, uint32_t duration, uint32_t serial)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape->manager) return;
    // Sample the old transition before reversing; never reset its visible pose.
    shape->manager->advanceAnimations();
    const bool wasEnabled = shape->revealEnabled;
    shape->revealEnabled = enabled != 0;
    shape->revealOpened = opened != 0;
    shape->serial = serial;
    if (!wasEnabled) shape->progress = 0;
    shape->startProgress = shape->progress;
    shape->startTime = shape->manager->m_clock.elapsed();
    shape->duration = std::clamp(duration, 1u, 2000u);
    shape->revealRunning = shape->revealEnabled
        && shape->progress != (shape->revealOpened ? 1.0 : 0.0);
    shape->manager->changed(shape);
    if (shape->revealEnabled && !shape->revealRunning) {
        kos_surface_shape_v1_send_reveal_finished(resource, shape->revealOpened, serial);
    }
}

void SurfaceShapeManager::setEnabled(wl_client *, wl_resource *resource, uint32_t enabled)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape->manager) {
        return;
    }
    shape->value.enabled = enabled != 0;
    shape->manager->changed(shape);
}

void SurfaceShapeManager::setRole(wl_client *, wl_resource *, uint32_t)
{
    // Compatibility for KOS clients built while roles existed. Roles never
    // affected rendering, so intentionally discard the obsolete request.
}

void SurfaceShapeManager::setScrim(wl_client *, wl_resource *resource,
                                   uint32_t enabled, uint32_t tint,
                                   wl_fixed_t cap, wl_fixed_t decay)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape->manager) {
        return;
    }
    shape->value.scrimEnabled = enabled != 0;
    shape->value.scrimTint = (tint == 1) ? 1 : 0;
    shape->value.scrimCap = std::clamp(wl_fixed_to_double(cap), 0.0, 1.0);
    shape->value.scrimDecay = std::clamp(wl_fixed_to_double(decay), 0.0, 4.0);
    shape->manager->changed(shape);
}

void SurfaceShapeManager::setBlur(wl_client *, wl_resource *resource,
                                  uint32_t enabled, uint32_t level)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape->manager) {
        return;
    }
    shape->value.blurEnabled = enabled != 0;
    // The compositor blur table is 15 steps. The precise clamp against the
    // table length happens at consumption (blur.cpp); this only rejects
    // nonsense so a hostile value cannot reach far.
    shape->value.blurLevel = std::clamp<uint>(level, 1, 15);
    shape->manager->changed(shape);
}

void SurfaceShapeManager::destroyShape(wl_client *, wl_resource *resource)
{
    wl_resource_destroy(resource);
}

void SurfaceShapeManager::changed(ShapeResource *shape)
{
    if (shape->surface) {
        Q_EMIT surfaceShapesChanged(shape->surface);
    }
}

void SurfaceShapeManager::remove(ShapeResource *shape)
{
    // When this runs from the surface's destroyed() handler, `surface` is
    // already dangling. It is only ever used as a hash key and as an opaque
    // token for the repaint signal, both of which compare the pointer value
    // without dereferencing it, so that is safe -- but do not start using it
    // as an object in here.
    SurfaceInterface *surface = shape->surface;
    if (surface) {
        auto it = m_shapes.find(surface);
        if (it != m_shapes.end()) {
            it->removeOne(shape);
            if (it->isEmpty()) {
                m_shapes.erase(it);
            }
        }
    }
    disconnect(shape->surfaceDestroyed);
    delete shape;
    if (surface) {
        Q_EMIT surfaceShapesChanged(surface);
    }
}
}
