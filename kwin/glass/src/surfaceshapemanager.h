/*
    SPDX-FileCopyrightText: 2026 NextKDE contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "glassshape.h"

#include <QElapsedTimer>
#include <QHash>
#include <QObject>
#include <QRectF>
#include <QSet>
#include <QVector>

#include <cstdint>
#include <optional>
#include <wayland-server-core.h>

struct wl_client;
struct wl_global;
struct wl_resource;

namespace KWin
{

class Display;
class SurfaceInterface;

// Compositor-driven open/close timeline (protocol v7). The client states the
// endpoint and duration; the compositor owns the frames so the glass and the
// client content scale as one group without a round trip per frame.
struct SurfaceReveal
{
    QRectF geometry;
    qreal progress = 1.0;

    qreal scale() const { return 0.8 + 0.2 * progress; }
    QPointF anchor() const { return QPointF(geometry.center().x(), geometry.bottom()); }
    QRectF visibleGeometry() const
    {
        const qreal width = geometry.width() * scale();
        const qreal height = geometry.height() * scale();
        return QRectF(geometry.center().x() - width / 2,
                      geometry.bottom() - height, width, height);
    }
};

// Minimal v8 server for kos_surface_shape_v1. It owns committed shape state and
// emits one signal per surface transaction; rendering reads only committed
// values. Scrim evaluation lives in the effect; per-shape noise is not part of
// this milestone and is recorded in the rewrite debt ledger.
class SurfaceShapeManager : public QObject
{
    Q_OBJECT

public:
    explicit SurfaceShapeManager(Display *display, QObject *parent = nullptr);
    ~SurfaceShapeManager() override;

    QVector<GlassShape> shapesFor(const SurfaceInterface *surface) const;
    std::optional<SurfaceReveal> revealFor(const SurfaceInterface *surface) const;
    // Called once per frame by the effect: advance running timelines, then
    // notify clients after the endpoint frame has been drawn.
    void advanceAnimations();
    void completeAnimations();

    static void bindManager(wl_client *client, void *data, uint32_t version, uint32_t id);
    static void getShape(wl_client *client, wl_resource *resource, uint32_t id,
                         wl_resource *surfaceResource);
    static void destroyManagerResource(wl_client *client, wl_resource *resource);
    static void commit(wl_client *client, wl_resource *resource, wl_resource *surfaceResource);

    static void setGeometry(wl_client *client, wl_resource *resource,
                            int32_t x, int32_t y, int32_t width, int32_t height);
    static void setCorner(wl_client *client, wl_resource *resource,
                          wl_fixed_t radius, wl_fixed_t exponent);
    static void setEnabled(wl_client *client, wl_resource *resource, uint32_t enabled);
    static void setRole(wl_client *client, wl_resource *resource, uint32_t role);
    static void destroyShape(wl_client *client, wl_resource *resource);
    static void setScrim(wl_client *client, wl_resource *resource, uint32_t enabled,
                         uint32_t tint, wl_fixed_t cap, wl_fixed_t decay);
    static void setBlur(wl_client *client, wl_resource *resource, uint32_t enabled,
                        uint32_t level);
    static void setCaptureGeometry(wl_client *client, wl_resource *resource,
                                   int32_t x, int32_t y, int32_t width, int32_t height);
    static void setMaterialOpacity(wl_client *client, wl_resource *resource,
                                   wl_fixed_t opacity);
    static void setReveal(wl_client *client, wl_resource *resource, uint32_t enabled,
                          uint32_t opened, uint32_t duration, uint32_t serial);
    static void setMaterial(wl_client *client, wl_resource *resource, uint32_t effect,
                            uint32_t profile);
    static void setBlurSigma(wl_client *client, wl_resource *resource, wl_fixed_t sigma);
    static void setTint(wl_client *client, wl_resource *resource, uint32_t mode,
                        wl_fixed_t red, wl_fixed_t green, wl_fixed_t blue,
                        wl_fixed_t opacity);
    static void setPointerEffects(wl_client *client, wl_resource *resource,
                                  uint32_t flags);

Q_SIGNALS:
    void surfaceShapesChanged(KWin::SurfaceInterface *surface);
    // Timeline-only updates change the visible geometry and material opacity,
    // never the capture/blur allocation. Repaint the panel and its sampling
    // margin without invalidating the blur chain or the legacy region.
    void revealFrameChanged(KWin::SurfaceInterface *surface, const QRectF &captureBounds);

private:
    struct ShapeResource;

    void applyCommit(SurfaceInterface *surface);
    void applyReveal(ShapeResource *shape, uint32_t enabled, uint32_t opened,
                     uint32_t duration, uint32_t serial);
    static void destroyShapeResource(wl_resource *resource);

    wl_global *m_global = nullptr;
    QElapsedTimer m_clock;
    QHash<const SurfaceInterface *, QVector<ShapeResource *>> m_shapes;
    QSet<wl_resource *> m_managerResources;
};

} // namespace KWin
