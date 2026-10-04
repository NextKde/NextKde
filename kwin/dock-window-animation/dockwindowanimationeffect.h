#pragma once

#include <effect/effectwindow.h>
#include <effect/offscreeneffect.h>
#include <effect/timeline.h>

#include <QHash>
#include <QList>
#include <QRectF>
#include <QString>
#include <QStringList>
#include <QVector>

namespace KWin
{

class DockWindowAnimationEffect final : public OffscreenEffect
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kos.KWin.DockWindowAnimation")

public:
    DockWindowAnimationEffect();
    ~DockWindowAnimationEffect() override;

    void reconfigure(ReconfigureFlags flags) override;
#ifdef KOS_KWIN_PAINT_TIME_API
    void prePaintScreen(ScreenPrePaintData &data, std::chrono::milliseconds presentTime) override;
    void prePaintWindow(RenderView *view, EffectWindow *window,
                        WindowPrePaintData &data,
                        std::chrono::milliseconds presentTime) override;
#else
    void prePaintScreen(ScreenPrePaintData &data) override;
    void prePaintWindow(RenderView *view, EffectWindow *window,
                        WindowPrePaintData &data) override;
#endif
    void postPaintScreen() override;
    bool isActive() const override;

    int requestedEffectChainPosition() const override
    {
        return 50;
    }

    static bool supported();

public Q_SLOTS:
    // Q_SCRIPTABLE：ExportScriptableSlots 只导业务槽（ExportAllSlots 会
    // 把继承的 QObject::deleteLater 一并导给会话总线）
    Q_SCRIPTABLE void updateTargets(const QString &payload);
    Q_SCRIPTABLE bool prepareLaunch(const QString &payload);
    Q_SCRIPTABLE QString status() const;

Q_SIGNALS:
    void animationStarted(const QString &appId, const QString &windowId,
                          const QString &transition, int durationMs);

protected:
    void drawWindow(const RenderTarget &renderTarget,
                    const RenderViewport &viewport, EffectWindow *window,
                    int mask, const Region &deviceRegion,
                    WindowPaintData &data) override;
    void apply(EffectWindow *window, int mask, WindowPaintData &data,
               WindowQuadList &quads) override;

private:
    enum class Transition {
        Open,
        Minimize,
        Restore,
    };

    enum class MorphStyle {
        Scale,
        Genie,
    };

    struct Target {
        QString appId;
        QString windowId;
        QRectF geometry;
    };

    struct WindowAnimation {
        EffectWindowVisibleRef visibleRef;
        TimeLine timeLine;
        Target target;
        Transition transition = Transition::Minimize;
        // CSD 客户端自绘阴影缓冲区相对于窗口 frameGeometry 的物理偏移量
        QPointF csdOffset = QPointF(0, 0);

        // Progress-independent per-vertex constants for the genie mesh.
        struct VertexConstants {
            qreal delay = 0.0;
            qreal phaseDenom = 1.0;
            qreal roundedX = 0.0;
            qreal roundedY = 0.0;
            qreal sinPiV = 0.0;
            qreal originalX = 0.0;
            qreal originalY = 0.0;
        };
        // Cache of the makeGrid(40) subdivision, the source quad bounds and
        // the per-vertex constants above. KWin rebuilds the incoming quad
        // list every frame but it is stable for a redirected window, so the
        // cache is rebuilt only when the quad count or the edge quad bounds
        // change (e.g. a resize mid-animation) or the morph target moves.
        // cachedQuadCount == -1 means uninitialised.
        int cachedQuadCount = -1;
        QRectF cachedFirstQuadBounds;
        QRectF cachedLastQuadBounds;
        QRectF cachedSourceBounds;
        QRectF cachedIcon;
        WindowQuadList cachedGrid;
        QVector<VertexConstants> cachedVertices;
    };

    struct PendingLaunch {
        Target target;
        QStringList aliases;
        qint64 expiresAt = 0;
    };

    void handleWindowAdded(EffectWindow *window);
    void watchWindow(EffectWindow *window);
    void updateWindowGeometryTracking(EffectWindow *window);
    void tryStartTicketedOpenAnimation(EffectWindow *window,
                                       int remainingAttempts);
    void handleMinimizedChanged(EffectWindow *window);
    void handleWindowDeleted(EffectWindow *window);
    bool eligibleWindow(EffectWindow *window) const;
    bool claim(EffectWindow *window, int role);
    void releaseClaim(EffectWindow *window);
    void finishAnimation(EffectWindow *window);
    void startAnimation(EffectWindow *window, const Target &target,
                        Transition transition);
    void addAnimationRepaint(EffectWindow *window,
                             const QRectF &targetGeometry);
    void applyDockMorph(EffectWindow *window, WindowAnimation &animation,
                        WindowQuadList &quads) const;
    void applyBottomGenie(EffectWindow *window, WindowAnimation &animation,
                          WindowQuadList &quads) const;
    std::optional<Target> targetForWindow(EffectWindow *window) const;
    std::optional<Target> takePendingLaunchForWindow(EffectWindow *window);
    QStringList windowIdentityCandidates(EffectWindow *window) const;
    QString normalizedId(const QString &value) const;

    QHash<QString, Target> m_targetsByApp;
    QHash<QString, Target> m_targetsByWindow;
    QList<PendingLaunch> m_pendingLaunches;
    QHash<EffectWindow *, WindowAnimation> m_animations;
    QHash<EffectWindow *, int> m_claimedRoles;
    // 跟踪各窗口在未最小化状态下的真实 CSD 阴影缓冲区偏移量
    QHash<EffectWindow *, QPointF> m_csdOffsets;

    int m_openDuration = 300;
    int m_minimizeDuration = 300;
    int m_restoreDuration = 200;
    MorphStyle m_morphStyle = MorphStyle::Scale;
    quint64 m_openAnimationCount = 0;
    quint64 m_minimizeAnimationCount = 0;
    quint64 m_restoreAnimationCount = 0;
    quint64 m_launchTicketCount = 0;
    quint64 m_launchTicketConsumedCount = 0;
    QString m_lastAnimatedAppId;
};

} // namespace KWin
