/*
    SPDX-FileCopyrightText: 2026 NextKDE contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "surfaceshapemanager.h"

#include "wayland-kos-surface-shape-v1-server-protocol.h"

#include <wayland/display.h>
#include <wayland/surface.h>

#include <algorithm>
#include <utility>
#include <wayland-server-core.h>

namespace KWin
{

struct SurfaceShapeManager::ShapeResource
{
    struct RevealCommand
    {
        uint32_t enabled;
        uint32_t opened;
        uint32_t duration;
        uint32_t serial;
    };

    SurfaceShapeManager *manager = nullptr;
    SurfaceInterface *surface = nullptr;
    wl_resource *resource = nullptr;
    GlassShape value;
    GlassShape pending;
    bool transactional = false;
    bool sealed = false;
    // The reveal command is not part of the immutable GlassShape snapshot:
    // applying it starts a timeline rather than publishing one state.
    std::optional<RevealCommand> pendingReveal;
    std::optional<RevealCommand> sealedReveal;
    bool revealEnabled = false;
    bool revealOpened = false;
    bool revealRunning = false;
    bool revealCompletionPending = false;
    qreal progress = 0;
    qreal startProgress = 0;
    qint64 startTime = 0;
    uint32_t duration = 320;
    uint32_t serial = 0;
    QMetaObject::Connection surfaceDestroyed;
    QMetaObject::Connection surfaceCommitted;

    GlassShape &edit()
    {
        return transactional ? pending : value;
    }
};

static const struct kos_surface_shape_manager_v1_interface s_managerImplementation{
    SurfaceShapeManager::getShape,
    SurfaceShapeManager::destroyManagerResource,
    SurfaceShapeManager::commit,
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
    SurfaceShapeManager::setMaterial,
    SurfaceShapeManager::setBlurSigma,
    SurfaceShapeManager::setTint,
    SurfaceShapeManager::setPointerEffects,
};

SurfaceShapeManager::SurfaceShapeManager(Display *display, QObject *parent)
    : QObject(parent)
{
    m_clock.start();
    if (display) {
        m_global = wl_global_create(*display, &kos_surface_shape_manager_v1_interface,
                                    9, this, bindManager);
    }
}

SurfaceShapeManager::~SurfaceShapeManager()
{
    if (m_global) {
        wl_global_destroy(m_global);
        m_global = nullptr;
    }

    for (wl_resource *resource : std::as_const(m_managerResources)) {
        wl_resource_set_user_data(resource, nullptr);
    }
    m_managerResources.clear();

    const auto lists = m_shapes;
    m_shapes.clear();
    for (const auto &list : lists) {
        for (ShapeResource *shape : list) {
            shape->manager = nullptr;
            shape->surface = nullptr;
            QObject::disconnect(shape->surfaceDestroyed);
            QObject::disconnect(shape->surfaceCommitted);
            // The wl_resource may outlive the manager. Null its user data so a
            // later destroy callback cannot touch freed memory; the resource's
            // own destroy function only reads user data and returns when null.
            if (shape->resource) {
                wl_resource_set_user_data(shape->resource, nullptr);
            }
            delete shape;
        }
    }
}

QVector<GlassShape> SurfaceShapeManager::shapesFor(const SurfaceInterface *surface) const
{
    QVector<GlassShape> result;
    for (const ShapeResource *shape : m_shapes.value(surface)) {
        // Keep a fully closed reveal in the list so the surface never falls
        // back to the legacy full-window region during its final hide frame.
        const bool closedReveal = shape->revealEnabled && shape->progress == 0;
        GlassShape value = shape->value;
        if (shape->revealEnabled) {
            const QRectF finalRect = value.geometry;
            // The allocation must not shrink with the animation, or every
            // frame would reallocate the capture and rerun the blur chain.
            if (value.captureGeometry.isEmpty()) {
                value.captureGeometry = finalRect;
            } else {
                value.captureGeometry = value.captureGeometry.united(finalRect);
            }
            const SurfaceReveal reveal{finalRect, shape->progress};
            value.geometry = reveal.visibleGeometry();
            value.radius *= reveal.scale();
            value.materialOpacity *= reveal.progress;
        }
        if (value.hasArea() || closedReveal) {
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
            if (!shape->revealRunning || !shape->surface) {
                continue;
            }
            const qreal t = std::clamp(qreal(now - shape->startTime) / shape->duration, 0.0, 1.0);
            const qreal eased = 1 - (1 - t) * (1 - t) * (1 - t);
            shape->progress = shape->startProgress
                + ((shape->revealOpened ? 1.0 : 0.0) - shape->startProgress) * eased;
            const QRectF bounds = shape->value.captureGeometry.isEmpty()
                ? shape->value.geometry
                : shape->value.captureGeometry.united(shape->value.geometry);
            Q_EMIT revealFrameChanged(shape->surface, bounds);
            if (t >= 1) {
                shape->revealRunning = false;
                // Notify only after the endpoint frame has been drawn.
                shape->revealCompletionPending = true;
            }
        }
    }
}

void SurfaceShapeManager::completeAnimations()
{
    for (const auto &list : std::as_const(m_shapes)) {
        for (ShapeResource *shape : list) {
            if (!shape->revealCompletionPending) {
                continue;
            }
            shape->revealCompletionPending = false;
            if (shape->resource) {
                kos_surface_shape_v1_send_reveal_finished(shape->resource,
                                                          shape->revealOpened, shape->serial);
            }
        }
    }
}

void SurfaceShapeManager::bindManager(wl_client *client, void *data, uint32_t version, uint32_t id)
{
    auto *manager = static_cast<SurfaceShapeManager *>(data);
    wl_resource *resource = wl_resource_create(client, &kos_surface_shape_manager_v1_interface,
                                                std::min(version, uint32_t(kos_surface_shape_manager_v1_interface.version)), id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &s_managerImplementation, manager, nullptr);
    manager->m_managerResources.insert(resource);
}

void SurfaceShapeManager::destroyManagerResource(wl_client *, wl_resource *resource)
{
    auto *manager = static_cast<SurfaceShapeManager *>(wl_resource_get_user_data(resource));
    if (manager) {
        manager->m_managerResources.remove(resource);
    }
    wl_resource_destroy(resource);
}

void SurfaceShapeManager::getShape(wl_client *client, wl_resource *resource, uint32_t id,
                                   wl_resource *surfaceResource)
{
    auto *manager = static_cast<SurfaceShapeManager *>(wl_resource_get_user_data(resource));
    if (!manager) {
        return;
    }
    SurfaceInterface *surface = SurfaceInterface::get(surfaceResource);
    if (!surface) {
        wl_resource_post_error(resource, WL_DISPLAY_ERROR_INVALID_OBJECT,
                               "surface object is not a wl_surface");
        return;
    }

    auto *shape = new ShapeResource;
    shape->manager = manager;
    shape->surface = surface;
    shape->transactional = wl_resource_get_version(resource) >= 8;
    // A transactional shape starts disabled and becomes visible with its first
    // committed transaction. Legacy resources retain the old enabled default.
    shape->value.enabled = !shape->transactional;
    shape->pending = shape->value;

    shape->resource = wl_resource_create(client, &kos_surface_shape_v1_interface,
                                         wl_resource_get_version(resource), id);
    if (!shape->resource) {
        delete shape;
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(shape->resource, &s_shapeImplementation, shape,
                                   destroyShapeResource);

    shape->surfaceDestroyed = QObject::connect(surface, &QObject::destroyed, manager,
        [shape] {
            if (shape->surface) {
                shape->manager->m_shapes[shape->surface].removeAll(shape);
                if (shape->manager->m_shapes.value(shape->surface).isEmpty()) {
                    shape->manager->m_shapes.remove(shape->surface);
                }
            }
            shape->surface = nullptr;
            if (shape->resource) {
                wl_resource_set_user_data(shape->resource, nullptr);
                wl_resource_destroy(shape->resource);
                shape->resource = nullptr;
            }
            delete shape;
        });
    shape->surfaceCommitted = QObject::connect(surface, &SurfaceInterface::committed, manager,
        [manager, surface] { manager->applyCommit(surface); });

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
        if (shape->surface) {
            shape->manager->m_shapes[shape->surface].removeAll(shape);
            if (shape->manager->m_shapes.value(shape->surface).isEmpty()) {
                shape->manager->m_shapes.remove(shape->surface);
            }
        }
        QObject::disconnect(shape->surfaceDestroyed);
        QObject::disconnect(shape->surfaceCommitted);
        if (shape->surface) {
            Q_EMIT shape->manager->surfaceShapesChanged(shape->surface);
        }
    }
    delete shape;
}

void SurfaceShapeManager::destroyShape(wl_client *, wl_resource *resource)
{
    wl_resource_destroy(resource);
}

void SurfaceShapeManager::commit(wl_client *, wl_resource *resource, wl_resource *surfaceResource)
{
    auto *manager = static_cast<SurfaceShapeManager *>(wl_resource_get_user_data(resource));
    if (!manager) {
        return;
    }
    SurfaceInterface *surface = SurfaceInterface::get(surfaceResource);
    if (!surface) {
        return;
    }
    // The client publishes the batch during polish and then commits the
    // surface. Sealing here is enough; applyCommit() runs on the surface
    // commit and is the only place that publishes new values.
    for (ShapeResource *shape : manager->m_shapes.value(surface)) {
        if (shape->transactional) {
            shape->sealed = true;
            // The reveal timeline is sealed with the same surface commit but
            // must be applied after the shape snapshot, not as part of it.
            if (shape->pendingReveal) {
                shape->sealedReveal = shape->pendingReveal;
                shape->pendingReveal.reset();
            }
        }
    }
}

void SurfaceShapeManager::applyCommit(SurfaceInterface *surface)
{
    bool dirty = false;
    const auto list = m_shapes.value(surface);
    for (ShapeResource *shape : list) {
        if (!shape->transactional || !shape->sealed) {
            continue;
        }
        shape->value = shape->pending;
        shape->sealed = false;
        if (shape->sealedReveal) {
            const ShapeResource::RevealCommand command = *shape->sealedReveal;
            shape->sealedReveal.reset();
            applyReveal(shape, command.enabled, command.opened,
                        command.duration, command.serial);
        }
        dirty = true;
    }
    if (dirty) {
        Q_EMIT surfaceShapesChanged(surface);
    }
}

void SurfaceShapeManager::setGeometry(wl_client *, wl_resource *resource,
                                      int32_t x, int32_t y, int32_t width, int32_t height)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape || !shape->manager) {
        return;
    }
    const QRectF geometry(x, y, std::max(width, 0), std::max(height, 0));
    if (shape->edit().geometry == geometry) {
        return;
    }
    shape->edit().geometry = geometry;
    if (!shape->transactional && shape->surface) {
        Q_EMIT shape->manager->surfaceShapesChanged(shape->surface);
    }
}

void SurfaceShapeManager::setCorner(wl_client *, wl_resource *resource,
                                    wl_fixed_t radius, wl_fixed_t exponent)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape || !shape->manager) {
        return;
    }
    const qreal r = std::clamp(wl_fixed_to_double(radius), 0.0, 4096.0);
    const qreal e = std::clamp(wl_fixed_to_double(exponent), 2.0, 8.0);
    if (shape->edit().radius == r && shape->edit().exponent == e) {
        return;
    }
    shape->edit().radius = r;
    shape->edit().exponent = e;
    if (!shape->transactional && shape->surface) {
        Q_EMIT shape->manager->surfaceShapesChanged(shape->surface);
    }
}

void SurfaceShapeManager::setEnabled(wl_client *, wl_resource *resource, uint32_t enabled)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape || !shape->manager) {
        return;
    }
    shape->edit().enabled = enabled != 0;
    if (!shape->transactional && shape->surface) {
        Q_EMIT shape->manager->surfaceShapesChanged(shape->surface);
    }
}

void SurfaceShapeManager::setRole(wl_client *, wl_resource *, uint32_t)
{
    // Retained as a no-op so the destructor opcode never moves.
}

void SurfaceShapeManager::setScrim(wl_client *, wl_resource *resource, uint32_t enabled,
                                   uint32_t tint, wl_fixed_t cap, wl_fixed_t decay)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape || !shape->manager) {
        return;
    }
    shape->edit().scrimEnabled = enabled != 0;
    shape->edit().scrimTint = tint;
    shape->edit().scrimCap = std::clamp(wl_fixed_to_double(cap), 0.0, 1.0);
    shape->edit().scrimDecay = wl_fixed_to_double(decay);
}

void SurfaceShapeManager::setBlur(wl_client *, wl_resource *resource, uint32_t enabled,
                                  uint32_t level)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape || !shape->manager) {
        return;
    }
    shape->edit().blurEnabled = enabled != 0;
    shape->edit().blurLevel = std::clamp(level, 0u, 15u);
}

void SurfaceShapeManager::setCaptureGeometry(wl_client *, wl_resource *resource,
                                             int32_t x, int32_t y, int32_t width, int32_t height)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape || !shape->manager) {
        return;
    }
    const QRectF capture(x, y, std::max(width, 0), std::max(height, 0));
    if (shape->edit().captureGeometry == capture) {
        return;
    }
    shape->edit().captureGeometry = capture;
    if (!shape->transactional && shape->surface) {
        Q_EMIT shape->manager->surfaceShapesChanged(shape->surface);
    }
}

void SurfaceShapeManager::setMaterialOpacity(wl_client *, wl_resource *resource,
                                             wl_fixed_t opacity)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape || !shape->manager) {
        return;
    }
    shape->edit().materialOpacity = std::clamp(wl_fixed_to_double(opacity), 0.0, 1.0);
    if (!shape->transactional && shape->surface) {
        Q_EMIT shape->manager->surfaceShapesChanged(shape->surface);
    }
}

void SurfaceShapeManager::setReveal(wl_client *, wl_resource *resource,
                                    uint32_t enabled, uint32_t opened,
                                    uint32_t duration, uint32_t serial)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape || !shape->manager) {
        return;
    }
    if (shape->transactional) {
        shape->pendingReveal = ShapeResource::RevealCommand{enabled, opened, duration, serial};
        return;
    }
    shape->manager->applyReveal(shape, enabled, opened, duration, serial);
}

void SurfaceShapeManager::applyReveal(ShapeResource *shape, uint32_t enabled,
                                      uint32_t opened, uint32_t duration, uint32_t serial)
{
    // Fold any elapsed timeline time into every running shape before starting
    // a new one, so the frame that carries this request uses consistent
    // progress values.
    advanceAnimations();
    const bool wasEnabled = shape->revealEnabled;
    shape->revealEnabled = enabled != 0;
    shape->revealOpened = opened != 0;
    shape->serial = serial;
    shape->revealCompletionPending = false;
    if (!wasEnabled) {
        shape->progress = 0;
    }
    shape->startProgress = shape->progress;
    shape->startTime = m_clock.elapsed();
    shape->duration = std::clamp(duration, 1u, 2000u);
    shape->revealRunning = shape->revealEnabled
        && shape->progress != (shape->revealOpened ? 1.0 : 0.0);
    if (!shape->transactional && shape->surface) {
        Q_EMIT surfaceShapesChanged(shape->surface);
    }
    if (shape->revealEnabled && !shape->revealRunning && shape->resource) {
        kos_surface_shape_v1_send_reveal_finished(shape->resource, shape->revealOpened, serial);
    }
}

void SurfaceShapeManager::setMaterial(wl_client *, wl_resource *resource, uint32_t effect,
                                      uint32_t profile)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape || !shape->manager) {
        return;
    }
    shape->edit().effect = std::min(effect, 1u);
    shape->edit().material = std::min(profile, 2u);
}

void SurfaceShapeManager::setBlurSigma(wl_client *, wl_resource *resource, wl_fixed_t sigma)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape || !shape->manager) {
        return;
    }
    shape->edit().blurSigmaSet = true;
    shape->edit().blurSigma = std::clamp(wl_fixed_to_double(sigma), 0.0, 32.0);
}

void SurfaceShapeManager::setTint(wl_client *, wl_resource *resource, uint32_t mode,
                                  wl_fixed_t red, wl_fixed_t green, wl_fixed_t blue,
                                  wl_fixed_t opacity)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape || !shape->manager) {
        return;
    }
    shape->edit().tintMode = std::min(mode, 3u);
    shape->edit().tint = QColor::fromRgbF(
        std::clamp(wl_fixed_to_double(red), 0.0, 1.0),
        std::clamp(wl_fixed_to_double(green), 0.0, 1.0),
        std::clamp(wl_fixed_to_double(blue), 0.0, 1.0));
    shape->edit().tintOpacity = std::clamp(wl_fixed_to_double(opacity), 0.0, 1.0);
}

void SurfaceShapeManager::setPointerEffects(wl_client *, wl_resource *resource,
                                            uint32_t flags)
{
    auto *shape = static_cast<ShapeResource *>(wl_resource_get_user_data(resource));
    if (!shape || !shape->manager) {
        return;
    }
    shape->edit().pointerEffects = flags & 0x7u;
}

} // namespace KWin
