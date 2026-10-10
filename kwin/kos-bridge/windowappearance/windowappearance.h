#pragma once

#include "appearanceconfig.h"
#include "sceneshadow.h"
#include "continuousclip.h"

#include <QElapsedTimer>
#include <QHash>
#include <QMetaObject>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QVariant>
#include <QVector4D>

namespace KWin
{
class EffectWindow;
class ShadowItem;
class OutlinedBorderItem;
class Item;
}

namespace KOS
{

// Resolves policy once. Arcs use native scene items; continuous corners use
// a mask on cached window content. No framebuffer/background patching.
class WindowAppearanceManager : public QObject
{
    Q_OBJECT
public:
    explicit WindowAppearanceManager(QObject *parent = nullptr);
    ~WindowAppearanceManager() override;
    void reconfigure();
    void prepare(KWin::EffectWindow *window, bool continuousAvailable = false);
    std::optional<WindowAppearance::ContinuousStyle> continuousStyle(KWin::EffectWindow *window) const;
    void forget(KWin::EffectWindow *window);
    void focusChanged(KWin::EffectWindow *gained);
    void restoreAll();

Q_SIGNALS:
    void configurationChanged();

private:
    struct WindowState
    {
        QVector4D declaredRadius;
        QVariant declaredGeometryProperty;
        QVariant declaredVisualRadiiProperty;
        QVariant declaredExponentProperty;
        QVector4D appliedRadius;
        WindowAppearance::CornerRadii radii;
        bool initialized = false;
        bool toneDirty = true;
        bool windowDark = true;
        bool tierDirty = true;
        int tier = 1;
        QPointer<QObject> decoration;
        QVariant declaredDecorationRadii;
        QVariant declaredDecorationShadow;
        QPointer<WindowAppearance::SceneShadowItem> sceneShadow;
        QPointer<KWin::ShadowItem> nativeShadow;
        qreal declaredNativeShadowOpacity = 1.0;
        bool usesDecorationShadow = false;
        std::shared_ptr<const WindowAppearance::ShadowAtlas> shadowAtlas;
        bool appearanceDropped = false;
        QPointer<KWin::OutlinedBorderItem> outline;
        QPointer<KWin::OutlinedBorderItem> frame;
        QPointer<KWin::Item> continuousBounds;
        std::optional<WindowAppearance::ContinuousStyle> continuous;
        QList<QMetaObject::Connection> connections;
        qreal shadowOpacity = 0.0;
        qreal shadowTarget = 0.0;
        qreal edgeOpacity = 0.0;
        qreal edgeTarget = 0.0;
        qreal shadowStart = 0.0;
        qreal edgeStart = 0.0;
        qint64 animationStarted = 0;
        int transitionMs = 180;
    };

    int tierFor(KWin::EffectWindow *window) const;
    void dirtyTiers();
    void updateTiers();
    void retarget(KWin::EffectWindow *window, WindowState &state,
                  const WindowAppearance::EffectiveAppearance &appearance,
                  bool dropped);
    void applyOpacities(WindowState &state);
    void restore(KWin::EffectWindow *window, WindowState &state);
    void animate();

    WindowAppearance::AppearanceConfig m_config;
    WindowAppearance::ShadowAtlasCache m_shadowCache;
    QHash<KWin::EffectWindow *, WindowState> m_windows;
    QElapsedTimer m_clock;
    QTimer m_animTimer;
    QTimer m_tierTimer;
};

} // namespace KOS
