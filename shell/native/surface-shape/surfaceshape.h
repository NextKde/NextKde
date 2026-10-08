#pragma once

#include <QList>
#include <QMetaObject>
#include <QObject>
#include <QPointer>
#include <QQuickItem>
#include <QRectF>

class QQuickWindow;
struct kos_surface_shape_v1;
struct wl_surface;

class SurfaceShape : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QQuickItem *target READ target WRITE setTarget NOTIFY targetChanged)
    Q_PROPERTY(qreal radius READ radius WRITE setRadius NOTIFY radiusChanged)
    Q_PROPERTY(qreal exponent READ exponent WRITE setExponent NOTIFY exponentChanged)
    Q_PROPERTY(bool enabled READ isEnabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(bool active READ isActive NOTIFY activeChanged)
    Q_PROPERTY(QRectF captureGeometry READ captureGeometry WRITE setCaptureGeometry NOTIFY captureGeometryChanged)
    Q_PROPERTY(bool fixedCaptureSupported READ fixedCaptureSupported NOTIFY activeChanged)
    // Contrast scrim sent over protocol v3. scrimTint 0/1 = black/white;
    // scrimDecay > 1 selects fixed mode.
    Q_PROPERTY(bool scrimEnabled READ scrimEnabled WRITE setScrimEnabled NOTIFY scrimEnabledChanged)
    Q_PROPERTY(int scrimTint READ scrimTint WRITE setScrimTint NOTIFY scrimTintChanged)
    Q_PROPERTY(qreal scrimCap READ scrimCap WRITE setScrimCap NOTIFY scrimCapChanged)
    Q_PROPERTY(qreal scrimDecay READ scrimDecay WRITE setScrimDecay NOTIFY scrimDecayChanged)
    // Blur strength override sent over protocol v4. blurEnabled=false keeps the
    // shape on the window's default blur pipeline; blurLevel is the compositor
    // blur level 1..15 (the global kwinrc BlurStrength scale).
    Q_PROPERTY(bool blurEnabled READ blurEnabled WRITE setBlurEnabled NOTIFY blurEnabledChanged)
    Q_PROPERTY(int blurLevel READ blurLevel WRITE setBlurLevel NOTIFY blurLevelChanged)

public:
    explicit SurfaceShape(QObject *parent = nullptr);
    ~SurfaceShape() override;

    QQuickItem *target() const { return m_target; }
    void setTarget(QQuickItem *target);
    qreal radius() const { return m_radius; }
    void setRadius(qreal radius);
    qreal exponent() const { return m_exponent; }
    void setExponent(qreal exponent);
    bool isEnabled() const { return m_enabled; }
    void setEnabled(bool enabled);
    bool isActive() const { return m_shape != nullptr; }
    QRectF captureGeometry() const { return m_captureGeometry; }
    void setCaptureGeometry(const QRectF &geometry);
    bool fixedCaptureSupported() const;
    bool scrimEnabled() const { return m_scrimEnabled; }
    void setScrimEnabled(bool enabled);
    int scrimTint() const { return m_scrimTint; }
    void setScrimTint(int tint);
    qreal scrimCap() const { return m_scrimCap; }
    void setScrimCap(qreal cap);
    qreal scrimDecay() const { return m_scrimDecay; }
    void setScrimDecay(qreal decay);
    bool blurEnabled() const { return m_blurEnabled; }
    void setBlurEnabled(bool enabled);
    int blurLevel() const { return m_blurLevel; }
    void setBlurLevel(int level);

Q_SIGNALS:
    void targetChanged();
    void radiusChanged();
    void exponentChanged();
    void enabledChanged();
    void activeChanged();
    void captureGeometryChanged();
    void scrimEnabledChanged();
    void scrimTintChanged();
    void scrimCapChanged();
    void scrimDecayChanged();
    void blurEnabledChanged();
    void blurLevelChanged();

private Q_SLOTS:
    void scheduleSync();
    void sync();
    void handleWindowChanged(QQuickWindow *window);
    void rewireAncestors();

private:
    friend class SurfaceShapeSyncItem;
    bool eventFilter(QObject *watched, QEvent *event) override;
    void releaseShape();
    void disconnectAncestors();
    wl_surface *nativeSurface() const;

    QPointer<QQuickItem> m_target;
    QPointer<QQuickWindow> m_window;
    QPointer<QQuickItem> m_syncItem;
    kos_surface_shape_v1 *m_shape = nullptr;
    wl_surface *m_surface = nullptr;
    qreal m_radius = 0.0;
    QRectF m_captureGeometry;
    qreal m_exponent = 2.0;
    bool m_enabled = true;
    bool m_scrimEnabled = false;
    int m_scrimTint = 0;
    qreal m_scrimCap = 0.0;
    qreal m_scrimDecay = 1.0;
    bool m_blurEnabled = false;
    int m_blurLevel = 1;
    bool m_syncPending = false;
    // The published geometry is a scene rectangle, so it also moves when an
    // ancestor does -- a change the target's own x/y signals cannot see.
    QList<QMetaObject::Connection> m_ancestorConnections;
};
