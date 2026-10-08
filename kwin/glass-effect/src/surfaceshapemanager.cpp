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
};

SurfaceShapeManager::SurfaceShapeManager(Display *display, QObject *parent)
    : QObject(parent)
{
    // Must advertise the interface version the protocol declares, or a
    // conformant client binds at 1 and can never send the since=3 set_scrim
    // or the since=4/5 blur/capture requests. Shape resource versions follow
    // the actual negotiated manager version below.
    m_global = wl_global_create(*display, &kos_surface_shape_manager_v1_interface,
                                5, this, bindManager);
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
        if (shape->value.enabled && shape->value.geometry.width() > 0
            && shape->value.geometry.height() > 0) {
            result.append(shape->value);
        }
    }
    return result;
}

void SurfaceShapeManager::bindManager(wl_client *client, void *data,
                                      uint32_t version, uint32_t id)
{
    wl_resource *resource = wl_resource_create(client,
        &kos_surface_shape_manager_v1_interface, std::min(version, 5u), id);
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
    // shape 资源版本跟随 manager 资源的实际协商版本（bind 侧已 min(version,5)）
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
