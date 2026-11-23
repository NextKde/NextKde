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
    // Drop only KOS additions on a live window; keep the client's own appearance.
    void restoreWindow(KWin::EffectWindow *window);
    void focusChanged(KWin::EffectWindow *gained);
    void restoreAll();

Q_SIGNALS:
    void configurationChanged();

private:
    friend class WindowAppearanceLifecycleTest;
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
        bool fullscreen = false;
        QPointer<KWin::OutlinedBorderItem> outline;
        QPointer<KWin::OutlinedBorderItem> frame;
        QPointer<KWin::Item> continuousBounds;
        std::optional<WindowAppearance::ContinuousStyle> continuous;
        // Everything outside WindowState that prepare() reads. When it is
        // unchanged (and no dirty flag is raised) the body is a no-op, so the
        // call is skipped: prepare() runs for every window on every paint pass.
        struct PrepareInputs
        {
            QSizeF size;
            qreal scale = 0;
            QPointer<QObject> decoration;
            QPointer<KWin::ShadowItem> shadowItem;
            QString windowClass;
            QString desktopFileName;
            QString resourceClass;
            QVector4D borderRadius;
            int tier = 1;
            bool maximized = false;
            bool fullscreen = false;
            bool continuousAvailable = false;
            bool decorationSupportsAppearance = false;
            bool wantsDecorationShadow = false;
            bool operator==(const PrepareInputs &) const = default;
        };
        PrepareInputs prepareInputs;
        bool prepared = false;
        // Direct prepare() calls that must run the body even when the inputs
        // above compare equal (updateTiers() recomputes the tier itself).
        bool prepareDirty = true;
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
    bool m_restoring = false;
};

} // namespace KOS
