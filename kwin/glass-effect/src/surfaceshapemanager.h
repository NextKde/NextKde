#pragma once

#include <QHash>
#include <QObject>
#include <QRectF>
#include <QVector>
#include <wayland-server-core.h>

struct wl_global;
struct wl_resource;

namespace KWin
{
class Display;
class SurfaceInterface;

struct SurfaceShape
{
    quint64 id = 0;
    QRectF geometry;
    qreal radius = 0.0;
    qreal exponent = 2.0;
    bool enabled = true;
    // Contrast scrim transported by set_scrim (protocol v3). Tint 0/1 selects
    // black/white; decay > 1 selects fixed rather than adaptive opacity.
    bool scrimEnabled = false;
    int scrimTint = 0;
    qreal scrimCap = 0.0;
    qreal scrimDecay = 1.0;
    // Per-shape blur override transported by set_blur (protocol v4). Disabled
    // keeps the shape on the window's default blur pipeline; blurLevel is the
    // compositor blur level 1..15, the same scale as the global kwinrc
    // BlurStrength.
    bool blurEnabled = false;
    uint blurLevel = 1;
};

class SurfaceShapeManager : public QObject
{
    Q_OBJECT

public:
    explicit SurfaceShapeManager(Display *display, QObject *parent = nullptr);
    ~SurfaceShapeManager() override;

    QVector<SurfaceShape> shapesFor(const SurfaceInterface *surface) const;

Q_SIGNALS:
    void surfaceShapesChanged(KWin::SurfaceInterface *surface);

private:
    struct ShapeResource;

public: // Wayland C dispatch table callbacks.
    static void bindManager(wl_client *client, void *data, uint32_t version, uint32_t id);
    static void destroyManagerResource(wl_client *client, wl_resource *resource);
    static void getShape(wl_client *client, wl_resource *resource, uint32_t id,
                         wl_resource *surfaceResource);
    static void destroyShapeResource(wl_resource *resource);
    static void setGeometry(wl_client *client, wl_resource *resource,
                            int32_t x, int32_t y, int32_t width, int32_t height);
    static void setCorner(wl_client *client, wl_resource *resource,
                          wl_fixed_t radius, wl_fixed_t exponent);
    static void setEnabled(wl_client *client, wl_resource *resource, uint32_t enabled);
    static void setRole(wl_client *client, wl_resource *resource, uint32_t role);
    static void setScrim(wl_client *client, wl_resource *resource,
                         uint32_t enabled, uint32_t tint,
                         wl_fixed_t cap, wl_fixed_t decay);
    static void setBlur(wl_client *client, wl_resource *resource,
                        uint32_t enabled, uint32_t level);
    static void destroyShape(wl_client *client, wl_resource *resource);

private:
    void changed(ShapeResource *shape);
    void remove(ShapeResource *shape);

    wl_global *m_global = nullptr;
    quint64 m_nextId = 1;
    QHash<const SurfaceInterface *, QVector<ShapeResource *>> m_shapes;
};
}
