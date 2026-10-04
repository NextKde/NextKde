#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QPointF>
#include <QVariantMap>

#include <kwin/effect/quickeffect.h>
#include <kwin/input_event_spy.h>

#include <chrono>

namespace KWin
{

// 四指上/下滑打开的工作区概览(Phase 1 骨架)。
//
// 与官方 Overview 不同,手势不走 EffectTogglableGesture(其行程固定 200px,
// 会提前饱和),而是通过 InputEventSpy 直接观察触控板滑动的原始位移流:
//   progress = 手指累计位移 / 行程(默认屏幕高度, kwinrc 可调)
// 松手后由自实现的弹簧积分器收敛,初速取手势释放瞬间的速度,实现速度阻尼。
// Spy 只读不消费事件,不会影响 KWin 自身的左右切工作区手势。
class KosOverviewEffect : public QuickSceneEffect
{
    Q_OBJECT
    Q_PROPERTY(qreal progress READ progress NOTIFY progressChanged)

public:
    explicit KosOverviewEffect();
    ~KosOverviewEffect() override;

    qreal progress() const { return m_progress; }
    Q_INVOKABLE void requestClose();

    // ── 供 QML 概览场景使用 ──────────────────────────────────────────────
    // 当前 space 的可见窗口(从上到下)。QML 用 KWinComponents.WindowThumbnail
    // 按 internalId 渲染实时缩略图,点卡片走 activateWindow()。
    Q_PROPERTY(QVariantList windows READ windows NOTIFY windowsChanged)
    Q_PROPERTY(int desktopCount READ desktopCount NOTIFY windowsChanged)
    Q_PROPERTY(int currentDesktopIndex READ currentDesktopIndex NOTIFY windowsChanged)
    QVariantList windows() const;
    int desktopCount() const;
    int currentDesktopIndex() const;

    Q_INVOKABLE QVariantList windowsForSpace(int index) const;
    Q_INVOKABLE void switchSpace(int delta);
    Q_INVOKABLE void activateWindow(QObject *window);

    void reconfigure(ReconfigureFlags flags) override;
    void prePaintScreen(ScreenPrePaintData &data) override;
    void postPaintScreen() override;
    void paintWindow(const RenderTarget &renderTarget, const RenderViewport &viewport,
                     EffectWindow *w, int mask, const Region &deviceRegion,
                     WindowPaintData &data) override;
    void grabbedKeyboardEvent(QKeyEvent *e) override;

protected:
    QVariantMap initialProperties(LogicalOutput *screen) override;

Q_SIGNALS:
    void progressChanged();
    void windowsChanged();

private:
    enum class Phase {
        Closed,  // 完全关闭,progress == 0
        Gesture, // 手指按着,progress 跟手
        Spring,  // 松手,弹簧收敛中
        Open,    // 完全打开,progress == 1
    };

    // 观察者:只读跟踪四指滑动,不消费事件。
    class GestureSpy : public InputEventSpy
    {
    public:
        explicit GestureSpy(KosOverviewEffect *effect)
            : m_effect(effect)
        {
        }
        void swipeGestureBegin(PointerSwipeGestureBeginEvent *event) override;
        void swipeGestureUpdate(PointerSwipeGestureUpdateEvent *event) override;
        void swipeGestureEnd(PointerSwipeGestureEndEvent *event) override;
        void swipeGestureCancelled(PointerSwipeGestureCancelEvent *event) override;

    private:
        KosOverviewEffect *const m_effect;
    };

    void setProgress(qreal value);
    void startSpring(qreal target);
    void settleSpring();
    void refreshTravel();
    void refreshModel();
    QVariantList filterWindows(VirtualDesktop *desktop) const;
    VirtualDesktop *spaceAt(int index) const;

    GestureSpy m_spy;
    Phase m_phase = Phase::Closed;
    qreal m_progress = 0;         // 0..1,概览展开进度(跟手值/弹簧值)

    // 手势跟踪状态
    bool m_tracking = false;
    QPointF m_accum;              // 本次手势累计位移(px)
    qreal m_gestureBase = 0;      // begin 时的 progress
    qreal m_velocity = 0;         // progress/s,打开方向为正(EMA 平滑)
    std::chrono::microseconds m_lastEventTime{0};

    // 弹簧状态
    bool m_springActive = false;
    qreal m_springTarget = 0;
    qreal m_springVelocity = 0;   // progress/s
    QElapsedTimer m_frameTimer;

    // 参数(kwinrc [Effect-kos_overview])
    qreal m_travelScale = 1.0;    // 行程 = 输出逻辑高度 * TravelScale
    qreal m_travel = 1000;        // px,每次帧按当前输出刷新
    qreal m_shrink = 0.35;        // 打开时窗口层缩到 (1 - ShrinkAmount)
    qreal m_dim = 0.5;            // 打开时窗口层压暗量
    qreal m_stiffness = 170.0;    // 弹簧刚度
    qreal m_damping = 20.0;       // 弹簧阻尼
};

} // namespace KWin
