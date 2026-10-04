#include "kosovervieweffect.h"

#include <kwin/effect/effecthandler.h>
#include <kwin/input.h>
#include <kwin/input_event.h>

#include <KConfigGroup>
#include <KSharedConfig>

#include <QKeyEvent>
#include <QVector2D>

#include <algorithm>
#include <cmath>

namespace KWin
{

namespace
{

// 快甩判开的速度阈值(progress/s;1.0 = 一秒滑满整个行程)
constexpr qreal kFlickVelocity = 1.1;
// 松手时的进度判定线
constexpr qreal kOpenThreshold = 0.5;
// 横向让位守卫:开始跟踪后,横向位移达到该值即让位给左右切工作区(不再要求
// 横向显著大于纵向 —— 那会让误触先"黑一下"再退出)
constexpr qreal kHorizontalMinPx = 24.0;
// 纵向进度超过该值后,才要求横向同时占优(kHorizontalGuard)才让位;
// 低进度阶段横向位移到 kHorizontalMinPx 就让位,避免误触泛黑
constexpr qreal kCommittedProgress = 0.15;
// 横向/纵向位移比超过该值让位(仅在进度已超过 kCommittedProgress 时生效)
constexpr qreal kHorizontalGuard = 1.25;

qreal eased(qreal t)
{
    t = std::clamp(t, 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

} // namespace

KosOverviewEffect::KosOverviewEffect()
    : QuickSceneEffect()
    , m_spy(this)
{
    setSource(QUrl(QStringLiteral("qrc:/kos-overview/qml/Main.qml")));
    reconfigure(ReconfigureAll);
    input()->installInputEventSpy(&m_spy);

    // 概览打开期间保持模型新鲜(增删窗口、切 space 都会触发重算)
    connect(effects, &EffectsHandler::windowAdded, this, &KosOverviewEffect::refreshModel);
    connect(effects, &EffectsHandler::windowDeleted, this, &KosOverviewEffect::refreshModel);
    connect(effects, &EffectsHandler::desktopChanged, this, [this](VirtualDesktop *, VirtualDesktop *,
                                                                   EffectWindow *, LogicalOutput *) {
        refreshModel();
    });
}

KosOverviewEffect::~KosOverviewEffect()
{
    input()->uninstallInputEventSpy(&m_spy);
}

void KosOverviewEffect::refreshModel()
{
    // windows()/desktopCount()/currentDesktopIndex() 都是惰性求值,
    // 这里只需通知 QML 重新读取。
    if (isRunning()) {
        Q_EMIT windowsChanged();
    }
}

QVariantList KosOverviewEffect::filterWindows(VirtualDesktop *desktop) const
{
    QVariantList list;
    if (!desktop) {
        return list;
    }
    auto *output = effects->activeScreen();
    const auto order = effects->stackingOrder();
    for (auto it = order.rbegin(); it != order.rend(); ++it) { // 从上到下
        EffectWindow *w = *it;
        if (output && w->screen() && w->screen() != output) {
            continue;
        }
        if (w->isDesktop() || w->isDock() || w->isSpecialWindow() || !w->isNormalWindow()) {
            continue;
        }
        if (!w->isOnAllDesktops() && !w->desktops().contains(desktop)) {
            continue;
        }
        list << QVariant::fromValue(w);
    }
    return list;
}

VirtualDesktop *KosOverviewEffect::spaceAt(int index) const
{
    const auto desks = effects->desktops();
    if (index < 0 || index >= desks.size()) {
        return nullptr;
    }
    return desks.at(index);
}

QVariantList KosOverviewEffect::windows() const
{
    return filterWindows(effects->currentDesktop());
}

int KosOverviewEffect::desktopCount() const
{
    return effects->desktops().size();
}

int KosOverviewEffect::currentDesktopIndex() const
{
    const auto desks = effects->desktops();
    const int idx = desks.indexOf(effects->currentDesktop());
    return idx < 0 ? 0 : idx;
}

QVariantList KosOverviewEffect::windowsForSpace(int index) const
{
    return filterWindows(spaceAt(index));
}

void KosOverviewEffect::switchSpace(int delta)
{
    const auto desks = effects->desktops();
    if (desks.isEmpty() || delta == 0) {
        return;
    }
    int idx = desks.indexOf(effects->currentDesktop());
    if (idx < 0) {
        idx = 0;
    }
    const int next = std::clamp(idx + delta, 0, int(desks.size()) - 1);
    if (next != idx) {
        effects->setCurrentDesktop(desks.at(next));
    }
}

void KosOverviewEffect::activateWindow(QObject *window)
{
    auto *w = qobject_cast<EffectWindow *>(window);
    if (!w) {
        return;
    }
    if (w->isMinimized()) {
        w->setMinimized(false);
    }
    effects->activateWindow(w);
    startSpring(0.0);
}

void KosOverviewEffect::reconfigure(ReconfigureFlags flags)
{
    Q_UNUSED(flags)
    const KConfigGroup group =
        KConfigGroup(KSharedConfig::openConfig(QStringLiteral("kwinrc")),
                     QStringLiteral("Effect-kos_overview"));
    m_travelScale = group.readEntry(QStringLiteral("TravelScale"), 0.33);
    m_shrink = group.readEntry(QStringLiteral("ShrinkAmount"), 0.35);
    m_dim = group.readEntry(QStringLiteral("DimAmount"), 0.5);
    m_stiffness = group.readEntry(QStringLiteral("SpringStiffness"), 170.0);
    m_damping = group.readEntry(QStringLiteral("SpringDamping"), 20.0);
}

void KosOverviewEffect::setProgress(qreal value)
{
    const qreal clamped = std::clamp(value, 0.0, 1.0);
    if (clamped == m_progress) {
        return;
    }
    m_progress = clamped;
    Q_EMIT progressChanged();
}

void KosOverviewEffect::refreshTravel()
{
    qreal height = 0;
    if (auto *out = effects->activeScreen()) {
        const auto geometry = out->geometryF();
        height = geometry.y() + geometry.height();
    }
    if (height <= 0) {
        height = 1000;
    }
    m_travel = std::max(height * m_travelScale, 200.0);
}

void KosOverviewEffect::startSpring(qreal target)
{
    m_springTarget = std::clamp(target, 0.0, 1.0);
    m_springVelocity = m_velocity;
    m_springActive = true;
    m_phase = Phase::Spring;
    m_frameTimer.restart();
    if (!isRunning()) {
        setRunning(true);
    }
}

void KosOverviewEffect::settleSpring()
{
    // 半隐式欧拉;单帧步长钳制,避免卡顿后过冲
    const qreal dt = std::min(m_frameTimer.restart() / 1000.0, 0.033);
    m_springVelocity +=
        (-m_stiffness * (m_progress - m_springTarget) - m_damping * m_springVelocity) * dt;
    setProgress(m_progress + m_springVelocity * dt);

    if (std::fabs(m_progress - m_springTarget) < 0.0015
        && std::fabs(m_springVelocity) < 0.02) {
        setProgress(m_springTarget);
        m_springActive = false;
        if (m_progress >= 1.0) {
            m_phase = Phase::Open;
        } else {
            m_phase = Phase::Closed;
            setRunning(false);
        }
    }
}

void KosOverviewEffect::prePaintScreen(ScreenPrePaintData &data)
{
    if (m_springActive) {
        refreshTravel();
        settleSpring();
    }
    QuickSceneEffect::prePaintScreen(data);
}

void KosOverviewEffect::postPaintScreen()
{
    if (m_springActive || m_phase == Phase::Gesture) {
        effects->addRepaintFull();
    }
    Effect::postPaintScreen();
}

void KosOverviewEffect::paintWindow(const RenderTarget &renderTarget, const RenderViewport &viewport,
                                    EffectWindow *w, int mask, const Region &deviceRegion,
                                    WindowPaintData &data)
{
    if (m_progress > 0.0005) {
        const qreal e = eased(m_progress);
        const qreal s = 1.0 - m_shrink * e;

        const auto geo = w->frameGeometry();
        const QPointF windowCenter(geo.x() + geo.width() / 2.0, geo.y() + geo.height() / 2.0);

        auto *output = w->screen() ? w->screen() : effects->activeScreen();
        const auto og = output ? output->geometryF() : KWin::RectF();
        const QPointF screenCenter(og.x() + og.width() / 2.0, og.y() + og.height() / 2.0);

        // 假设:WindowPaintData::setScale 以窗口中心为锚。
        // 把窗口中心向屏幕中心收拢 (1-s) 比例,形成整层桌面缩向屏幕中心的观感。
        data.setScale(QVector2D(s, s));
        data.translate((screenCenter.x() - windowCenter.x()) * (1.0 - s),
                       (screenCenter.y() - windowCenter.y()) * (1.0 - s));
        data.setBrightness(1.0 - m_dim * e);
    }
    Effect::paintWindow(renderTarget, viewport, w, mask, deviceRegion, data);
}

void KosOverviewEffect::grabbedKeyboardEvent(QKeyEvent *e)
{
    if (e->type() == QEvent::KeyPress && e->key() == Qt::Key_Escape) {
        startSpring(0.0);
        e->accept();
        return;
    }
    QuickSceneEffect::grabbedKeyboardEvent(e);
}

void KosOverviewEffect::requestClose()
{
    if (isRunning()) {
        startSpring(0.0);
    }
}

QVariantMap KosOverviewEffect::initialProperties(LogicalOutput *screen)
{
    auto map = QuickSceneEffect::initialProperties(screen);
    map.insert(QStringLiteral("effect"), QVariant::fromValue(this));
    return map;
}

// ── GestureSpy ──────────────────────────────────────────────────────────────

void KosOverviewEffect::GestureSpy::swipeGestureBegin(PointerSwipeGestureBeginEvent *event)
{
    if (event->fingerCount != 4) {
        return;
    }
    auto *effect = m_effect;
    if (effect->m_phase == Phase::Gesture) {
        return;
    }
    effect->m_tracking = true;
    effect->m_phase = Phase::Gesture;
    effect->m_springActive = false;
    effect->m_accum = QPointF();
    effect->m_gestureBase = effect->m_progress;
    effect->m_velocity = 0;
    effect->m_lastEventTime = event->time;
    effect->refreshTravel();
    if (!effect->isRunning()) {
        effect->setRunning(true);
    }
    effect->refreshModel();
    // 确保 wheel/pointer 输入会转发到概览场景(双指滚动翻页依赖这个)
    if (auto *view = effect->viewForScreen(effects->activeScreen())) {
        effect->activateView(view);
    }
}

void KosOverviewEffect::GestureSpy::swipeGestureUpdate(PointerSwipeGestureUpdateEvent *event)
{
    auto *effect = m_effect;
    if (!effect->m_tracking || effect->m_phase != Phase::Gesture) {
        return;
    }

    const QPointF delta = event->delta;
    effect->m_accum += delta;

    const auto dtUs =
        std::chrono::duration_cast<std::chrono::microseconds>(event->time - effect->m_lastEventTime)
            .count();
    effect->m_lastEventTime = event->time;
    if (dtUs > 0) {
        const qreal dt = dtUs / 1e6;
        // 上滑时 dy < 0,打开方向为正
        const qreal instant = (-delta.y() / effect->m_travel) / dt;
        effect->m_velocity = 0.6 * effect->m_velocity + 0.4 * instant;
    }

    // 横向让位守卫(两级):
    //  1) 进度还没越过 kCommittedProgress:横向位移一到 kHorizontalMinPx 立即让位
    //     —— 此时纵向只是噪声,不该"先黑一下"
    //  2) 进度已较深:要求横向同时显著占优(kHorizontalGuard)才让位,
    //     避免斜着滑到一半被误判成横向
    const bool committed = effect->m_progress > kCommittedProgress;
    if (std::fabs(effect->m_accum.x()) > kHorizontalMinPx
        && (!committed
            || std::fabs(effect->m_accum.x()) > kHorizontalGuard * std::fabs(effect->m_accum.y()))) {
        effect->m_tracking = false;
        effect->startSpring(effect->m_progress >= kOpenThreshold ? 1.0 : 0.0);
        return;
    }

    effect->setProgress(effect->m_gestureBase + (-effect->m_accum.y()) / effect->m_travel);
}

void KosOverviewEffect::GestureSpy::swipeGestureEnd(PointerSwipeGestureEndEvent *event)
{
    Q_UNUSED(event)
    auto *effect = m_effect;
    if (!effect->m_tracking) {
        return;
    }
    effect->m_tracking = false;
    const bool open = effect->m_progress >= kOpenThreshold
        || (effect->m_velocity > kFlickVelocity && effect->m_progress > 0.2);
    effect->startSpring(open ? 1.0 : 0.0);
}

void KosOverviewEffect::GestureSpy::swipeGestureCancelled(PointerSwipeGestureCancelEvent *event)
{
    Q_UNUSED(event)
    auto *effect = m_effect;
    if (!effect->m_tracking) {
        return;
    }
    effect->m_tracking = false;
    effect->startSpring(effect->m_progress >= kOpenThreshold ? 1.0 : 0.0);
}

} // namespace KWin
