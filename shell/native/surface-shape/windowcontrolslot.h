#pragma once
#include <QQuickItem>
#include <QPointer>
#include <QVector>
#include <QVariantList>
struct kos_window_controls_v1;
struct wl_surface;

// Renderless, event-driven adapter. The application owns the slot layout and
// keeps its fallback visible until the compositor grants this specific surface.
class WindowControlSlot : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(QQuickItem *target READ target WRITE setTarget NOTIFY targetChanged)
    Q_PROPERTY(QVariantList buttons READ buttons WRITE setButtons NOTIFY metricsChanged)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(bool supported READ supported NOTIFY activeChanged)
    Q_PROPERTY(bool hoverGlyphs READ hoverGlyphs NOTIFY activeChanged)
public:
    explicit WindowControlSlot(QQuickItem *parent = nullptr);
    ~WindowControlSlot() override;
    QQuickItem *target() const { return m_target; }
    void setTarget(QQuickItem *);
    QVariantList buttons() const { return m_buttons; }
    void setButtons(const QVariantList &);
    bool active() const { return m_active; }
    bool supported() const { return m_controls != nullptr; }
    bool hoverGlyphs() const { return m_hoverGlyphs; }
Q_SIGNALS:
    void targetChanged();
    void metricsChanged();
    void activeChanged();
protected:
    void updatePolish() override;
    bool eventFilter(QObject *, QEvent *) override;
private:
    void watchTarget();
    void schedule();
    void release(bool serverGone = false);
    void attachWindow();
    static void configured(void *, kos_window_controls_v1 *, uint32_t, uint32_t, uint32_t);
    QPointer<QQuickItem> m_target;
    QPointer<QQuickWindow> m_window;
    QVector<QMetaObject::Connection> m_connections;
    kos_window_controls_v1 *m_controls = nullptr;
    wl_surface *m_surface = nullptr;
    QVariantList m_buttons;
    QByteArray m_lastButtons;
    bool m_lastEnabled = false, m_haveRegion = false;
    bool m_active = false, m_hoverGlyphs = false;
    uint32_t m_ack = 0;
};
