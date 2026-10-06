/*
    KWin - the KDE window manager. Minimize/restore animation for Stage 侧栏.
    Uniform scale + translate + end fade: the window shrinks into its own
    sidebar card and grows back out of it (macOS Stage Manager style — no
    content warping, aspect-preserving).

    Derived from KWin MagicLamp (Martin Gräßlin, GPL-2.0-or-later).

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "stageanim.h"
#include "effect/effecthandler.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QUuid>

#include <algorithm>
#include <cmath>

using namespace std::chrono_literals;

namespace KWin
{

// Categorized logging so target resolution is verifiable from the journal
// (uncategorized qWarnings from KWin plugins never reach it).
Q_LOGGING_CATEGORY(STAGEANIM_LOG, "kwin.effects.stageanim", QtInfoMsg)

// 目标解析日志：card / card-flat 是正常路径（后者 = 中心拖放的直长动画），
// 仅在 kwinrc [Effect-stageanim] TraceTargets=true 时输出（调参/验证用，
// reconfigureEffect 即时生效）；global/fallback 是异常路径（没查到卡片
// 矩形），始终 warning 提醒。
static void logTarget(bool trace, const char *source, const QString &id,
                      const QRect &rect, qreal scale)
{
    if (trace || (qstrcmp(source, "card") != 0
                  && qstrcmp(source, "card-flat") != 0))
        qCWarning(STAGEANIM_LOG) << "target=" << source << "id=" << id
                                 << "rect=" << rect << "scale=" << scale;
}

// ── 调参常量（与 shell/desktop/modules/stage/stage-geometry.mjs 对应项
// 保持一致——改一处必须同步另一处）──
static constexpr qreal kPerspectiveFocal = 900.0;   // 针孔透视焦距
static constexpr qreal kFadeTailFraction = 0.3;     // 末段淡出占比
static constexpr qreal kCardMinEndScale = 0.08;     // 装卡缩放下限
static constexpr qreal kCardMaxEndScale = 0.5;      // 装卡缩放上限
static constexpr qreal kGlobalMinScale = 0.10;      // 全局矩形缩放下限
static constexpr qreal kGlobalMaxScale = 0.40;      // 全局矩形缩放上限
static constexpr qreal kDefaultGlassOpacity = 0.65; // 飞行玻璃透明度默认

// shell（StageSidebarWindow.publishTargets）按窗口 KWin internalId 发布的
// 卡片矩形。动画起止点 = 那扇窗口自己的卡片位置与尺寸（macOS 式连续交换）。
struct StageTarget
{
    QString id; // KWin internalId（无花括号），与 shell windowId 逐字一致
    QRect rect;
    bool flat = false; // shell 标记：从"正视卡片"直长/直收（中心拖放），
                       // 动画不带倾斜分量
};

// 目标文件路径：$XDG_STATE_HOME/quickshell/kos/fg-sched/stage-targets.json
//（由 shell 的 JsonConfigStore → platform state.write 原子写入）
static QString stageTargetsPath()
{
    const QString stateHome = qEnvironmentVariable("XDG_STATE_HOME",
        QStandardPaths::writableLocation(QStandardPaths::HomeLocation)
            + QStringLiteral("/.local/state"));
    return stateHome + QStringLiteral(
        "/quickshell/kos/fg-sched/stage-targets.json");
}

// targets 文件的完整快照：卡片矩形 + suppress 名单。每次动画触发只读
// 一次（旧实现 isSuppressed 与 resolveTarget 各开一遍文件——两次解析
// 之间 shell 改写会产生撕裂读，且白白翻倍文件 IO）
struct StageTargetsFile
{
    QVector<StageTarget> targets;
    QSet<QString> suppress;
};

static StageTargetsFile loadStageTargets()
{
    StageTargetsFile out;
    QFile f(stageTargetsPath());
    if (!f.open(QIODevice::ReadOnly))
        return out;
    const auto doc = QJsonDocument::fromJson(f.readAll());
    if (doc.isNull()) {
        // 坏 JSON（半截写入/磁盘问题）与"shell 未运行（文件不存在）"要
        // 区分得开：前者是故障信号，静默回落会掩盖排障线索。只告警一次
        // ——本函数逐事件调用，坏文件常驻时不能刷屏
        static bool warnedBadJson = false;
        if (!warnedBadJson) {
            warnedBadJson = true;
            qCWarning(STAGEANIM_LOG,
                "stage-targets.json exists but is not valid JSON");
        }
        return out;
    }
    const auto obj = doc.object();
    const auto arr = obj.value(QStringLiteral("targets")).toArray();
    out.targets.reserve(arr.size());
    for (const auto &v : arr) {
        const auto o = v.toObject();
        const QRect r(o.value(QStringLiteral("x")).toInt(),
                      o.value(QStringLiteral("y")).toInt(),
                      o.value(QStringLiteral("width")).toInt(),
                      o.value(QStringLiteral("height")).toInt());
        if (!r.isValid())
            continue;
        StageTarget t;
        t.id = o.value(QStringLiteral("id")).toString();
        t.rect = r;
        t.flat = o.value(QStringLiteral("flat")).toInt(0) == 1;
        out.targets.append(t);
    }
    // suppress 名单内的窗口最小化/还原**跳过动画**（瞬间完成）——实时
    // 卡片模式的静默收放全靠它（悬停预备静默最小化、实时恢复静默还原
    // +keepBelow 压底都不能打扰视觉）。恒空：伪实时已删，保留解析仅为
    // 文件格式兼容
    const auto sup = obj.value(QStringLiteral("suppress")).toArray();
    for (const auto &v : sup)
        out.suppress.insert(v.toString());
    return out;
}

// suppress 名单命中判定（名单语义见 loadStageTargets 内注释）
static bool isSuppressed(const QSet<QString> &suppress, const EffectWindow *w)
{
    return suppress.contains(w->internalId().toString(QUuid::WithoutBraces));
}

StageAnimEffect::StageAnimEffect()
{
    reconfigure(ReconfigureAll);
    connect(effects, &EffectsHandler::windowAdded, this, &StageAnimEffect::slotWindowAdded);
    connect(effects, &EffectsHandler::windowDeleted, this, &StageAnimEffect::slotWindowDeleted);

    // windowAdded 只对"加载之后"新建的窗口发——dbus loadEffect 落在会话
    // 中段，开机就存在的窗口不会补发信号，连接必须自己对 stackingOrder
    // 全量补建（否则那批窗口永远没有最小化/还原动画）。QSet 防重连。
    const QList<EffectWindow *> windows = effects->stackingOrder();
    for (EffectWindow *w : windows)
        slotWindowAdded(w);

    setVertexSnappingMode(RenderGeometry::VertexSnappingMode::None);
}

bool StageAnimEffect::supported()
{
    return OffscreenEffect::supported() && effects->animationsSupported();
}

void StageAnimEffect::reconfigure(ReconfigureFlags)
{
    const KConfigGroup grp = effects->config()->group(QStringLiteral("Effect-stageanim"));
    const std::chrono::milliseconds d(grp.readEntry<int>("AnimationDuration", 420));
#ifdef KOS_KWIN_PAINT_TIME_API
    m_duration = std::chrono::milliseconds(static_cast<int>(animationTime(d)));
#else
    m_duration = animationTime(d);
#endif

    const int x = grp.readEntry<int>("TargetX", -1);
    const int y = grp.readEntry<int>("TargetY", -1);
    const int w = grp.readEntry<int>("TargetWidth", -1);
    const int h = grp.readEntry<int>("TargetHeight", -1);
    m_target = (x >= 0 && y >= 0 && w > 0 && h > 0)
        ? QRect(x, y, w, h)
        : QRect();

    // 倾角钳位（对比下方 GlassOpacity）：透视深度 depth = (pivotX − sx)
    // ·sinR 随角变大，k = focal / (focal − depth)——大屏宽 × 45° 时 depth
    // ≈900 恰好触焦，>45° 远缘 focal−depth 变负、k 翻负号，顶点镜像翻转
    // 窗口绘制炸裂。40° 封顶时 1272px 半宽 depth≈818 < focal(900) 恒安全。
    m_tiltAngle = std::clamp(grp.readEntry<double>("TiltAngle", 22.0),
                             0.0, 40.0);

    // 飞行玻璃透明度：1.0 = 关闭（全程不透明），越低越"玻璃"
    //（飞行途中透见桌面，落地/装卡端由 fade 尾巴收掉）
    m_glassOpacity = std::clamp(grp.readEntry<double>("GlassOpacity",
                                                      kDefaultGlassOpacity),
                                0.10, 1.0);

    m_trace = grp.readEntry<bool>("TraceTargets", false);

    // 右侧常驻（shell 的 StageModeService 投影）：装卡姿态镜像——卡片
    // 倾斜在右侧取反（右缘近大），动画终点姿态须与卡片一致
    m_mirrorTargets = grp.readEntry<bool>("TargetMirror", false);

    // 缓动曲线可配（kwinrc EasingCurve，默认 OutCubic 无阻尼）
    const QString curve = grp.readEntry<QString>("EasingCurve", QStringLiteral("OutCubic"));
    if (curve == QLatin1String("InOutCubic"))
        m_easing.setType(QEasingCurve::InOutCubic);
    else if (curve == QLatin1String("OutBack"))
        m_easing.setType(QEasingCurve::OutBack);
    else if (curve == QLatin1String("OutQuad"))
        m_easing.setType(QEasingCurve::OutQuad);
    else if (curve == QLatin1String("InOutQuad"))
        m_easing.setType(QEasingCurve::InOutQuad);
    else if (curve == QLatin1String("Linear"))
        m_easing.setType(QEasingCurve::Linear);
    else
        m_easing.setType(QEasingCurve::OutCubic);
}

#ifdef KOS_KWIN_PAINT_TIME_API
void StageAnimEffect::prePaintScreen(ScreenPrePaintData &data, std::chrono::milliseconds presentTime)
#else
void StageAnimEffect::prePaintScreen(ScreenPrePaintData &data)
#endif
{
    // Mark the screen as transformed so the moving window is repainted fully.
    data.mask |= PAINT_SCREEN_WITH_TRANSFORMED_WINDOWS;

#ifdef KOS_KWIN_PAINT_TIME_API
    effects->prePaintScreen(data, presentTime);
#else
    effects->prePaintScreen(data);
#endif
}

#ifdef KOS_KWIN_PAINT_TIME_API
void StageAnimEffect::prePaintWindow(RenderView *view, EffectWindow *w, WindowPrePaintData &data, std::chrono::milliseconds presentTime)
#else
void StageAnimEffect::prePaintWindow(RenderView *view, EffectWindow *w, WindowPrePaintData &data)
#endif
{
    auto animationIt = m_animations.find(w);
    if (animationIt != m_animations.end()) {
#ifdef KOS_KWIN_PAINT_TIME_API
        (*animationIt).timeLine.advance(presentTime);
#else
        (*animationIt).timeLine.advance(view);
#endif
        data.setTransformed();
    }

#ifdef KOS_KWIN_PAINT_TIME_API
    effects->prePaintWindow(view, w, data, presentTime);
#else
    effects->prePaintWindow(view, w, data);
#endif
}

// 触发时解析该窗口的目标矩形，优先级：
// ① shell 发布的按窗口 id 卡片矩形（窗口从自己的卡片原地长出/收回）
// ② 全局侧栏矩形（kwinrc [Effect-stageanim] Target*）
// ③ 都没有时保持无效，apply() 走原版回落（任务栏图标几何/光标）。
void StageAnimEffect::resolveTarget(EffectWindow *w, StageAnimAnimation &anim,
                                    const QVector<StageTarget> &targets)
{
    anim.target = QRect();
    anim.endScale = -1.0;
    anim.flat = false;

    const QRect geo = w->frameGeometry().toRect();
    if (!targets.isEmpty() && geo.width() > 0) {
        const QString selfId = w->internalId().toString(QUuid::WithoutBraces);
        for (const auto &t : targets) {
            if (t.id != selfId || !t.rect.isValid())
                continue;
            // 等比缩放装进卡片（两轴取小，不拉伸内容——比例失调是红线）
            anim.target = t.rect;
            anim.flat = t.flat;
            anim.endScale = std::clamp(
                std::min(qreal(t.rect.width()) / geo.width(),
                         qreal(t.rect.height()) / geo.height()),
                kCardMinEndScale, kCardMaxEndScale);
            logTarget(m_trace, t.flat ? "card-flat" : "card", selfId, t.rect,
                anim.endScale);
            return;
        }
    }

    anim.target = QRect();
    if (m_target.isValid() && geo.width() > 0) {
        anim.target = m_target;
        anim.endScale = std::clamp(
            qreal(anim.target.width()) / std::max(1, geo.width()),
            kGlobalMinScale, kGlobalMaxScale);
        logTarget(m_trace, "global", w->internalId().toString(QUuid::WithoutBraces),
                  anim.target, anim.endScale);
        return;
    }
    logTarget(m_trace, "fallback", w->internalId().toString(QUuid::WithoutBraces),
              QRect(), -1.0);
}

void StageAnimEffect::apply(EffectWindow *w, int mask, WindowPaintData &data, WindowQuadList &quads)
{
    Q_UNUSED(mask)
    auto animationIt = m_animations.constFind(w);
    if (animationIt == m_animations.constEnd())
        return;

    // 0 = not minimized, 1 = fully minimized
    const qreal progress = (*animationIt).timeLine.value();
    const qreal t = m_easing.valueForProgress(progress);

    const QRect geo = w->frameGeometry().toRect();

    // 目标矩形与终态缩放比例
    QRectF target;
    qreal endScale = 0.15;
    const bool haveTarget = (*animationIt).endScale > 0
        && (*animationIt).target.isValid();
    if (haveTarget) {
        target = (*animationIt).target;
        endScale = (*animationIt).endScale;
    } else {
        // 原版回落：任务栏图标几何 / 光标最近边缘
        QRect icon = w->iconGeometry().toRect();
        if (icon.isValid() && icon.width() > 0) {
            target = icon;
            endScale = std::clamp(qreal(icon.width()) / std::max(1, geo.width()),
                                  kGlobalMinScale, kGlobalMaxScale);
        } else {
            QPoint pt = cursorPos().toPoint();
            const QRect extG = geo;
            if (extG.contains(pt)) {
                const int d[4] = {pt.x() - extG.x(), extG.right() - pt.x(),
                                  pt.y() - extG.y(), extG.bottom() - pt.y()};
                int di = d[0];
                int which = 0;
                for (int i = 1; i < 4; ++i) {
                    if (d[i] < di) {
                        di = d[i];
                        which = i;
                    }
                }
                switch (which) {
                case 0:
                    pt.setX(extG.x());
                    break;
                case 1:
                    pt.setX(extG.right());
                    break;
                case 2:
                    pt.setY(extG.y());
                    break;
                default:
                    pt.setY(extG.bottom());
                    break;
                }
            } else {
                pt.setX(std::clamp(pt.x(), extG.x(), extG.right()));
                pt.setY(std::clamp(pt.y(), extG.y(), extG.bottom()));
            }
            target = QRect(pt, QSize(0, 0));
        }
    }

    // 窗口中心从自身滑向目标中心；等比缩放；末段 30% 淡出（还原时间线倒放
    // 即先淡入）。在此之上叠加旋转分量：t=1（卡片态）带卡片的 3D 倾斜姿态、
    // t=0 平铺——窗口"从倾斜卡片旋转展开"，而不是生硬的等比放大。
    // WindowVertex 只有 2D 顶点，倾斜用针孔透视投影模拟：绕缩放矩形中心
    // 垂直轴（pivot 与卡片 origin.x = width/2 对齐）转 angleDeg，顶点按
    // 深度 k = focal/(focal−z) 缩放。⚠️ Qt 的 Y 轴朝下，QML 正角绕 Y 旋转时
    // 卡片是"左缘近大、右缘远小"（右缘 z<0 远离观察者），特效必须同向。
    const QPointF fromC = QRectF(geo).center();
    const QPointF toC = target.center();
    const QPointF c = fromC + (toC - fromC) * t;
    const qreal s = 1.0 + (endScale - 1.0) * t;
    // 右侧常驻（m_mirrorTargets）时装卡倾斜取反：镜像后右缘近大，与
    // 卡片的右侧镜像角同姿态（StageCard 的 angleRad 同源取反）
    const qreal tiltSign = m_mirrorTargets ? -1.0 : 1.0;
    const qreal angleDeg = (haveTarget && !(*animationIt).flat)
        ? tiltSign * m_tiltAngle * t : 0.0;
    const qreal rad = qDegreesToRadians(angleDeg);
    const qreal cosR = std::cos(rad);
    const qreal sinR = std::sin(rad);
    const qreal focal = kPerspectiveFocal;
    const qreal pivotX = c.x(); // 中心垂直轴（与卡片 origin.x = width/2 对齐）
    const qreal cy = c.y();

    for (WindowQuad &quad : quads) {
        for (int j = 0; j < 4; ++j) {
            WindowVertex &v = quad[j];
            const qreal gx = geo.x() + v.x();
            const qreal gy = geo.y() + v.y();
            qreal sx = (gx - fromC.x()) * s + c.x();
            qreal sy = (gy - fromC.y()) * s + c.y();
            if (std::abs(angleDeg) > 0.01) {
                const qreal depth = (pivotX - sx) * sinR; // 正角左缘近大，负角（镜像）右缘近大
                const qreal k = focal / (focal - depth);
                sx = pivotX + (sx - pivotX) * cosR * k;
                sy = cy + (sy - cy) * k;
            }
            v.setX(sx - geo.x());
            v.setY(sy - geo.y());
        }
    }

    // 玻璃透明感：透明度从 1（平铺态）全程渐变到 glassOpacity（卡片态）
    // ——飞行途中窗口呈半透明、能透见桌面；restore 时间线倒放即"从玻璃
    // 姿态逐渐凝实"。末段 fade 尾巴在其上收尾（装卡端淡没，防残影）。
    // glassOpacity = 1.0 时该乘子恒为 1，行为与纯淡出版一致。
    const qreal glassMix = 1.0 + (m_glassOpacity - 1.0) * t;
    const qreal fade = std::clamp((1.0 - t) / kFadeTailFraction, 0.0, 1.0);
    data.setOpacity(data.opacity() * glassMix * fade);
}

void StageAnimEffect::postPaintScreen()
{
    auto animationIt = m_animations.begin();
    while (animationIt != m_animations.end()) {
        if ((*animationIt).timeLine.done()) {
            unredirect(animationIt.key());
            animationIt = m_animations.erase(animationIt);
        } else {
            ++animationIt;
        }
    }

    effects->addRepaintFull();

    // Call the next effect.
    effects->postPaintScreen();
}

void StageAnimEffect::slotWindowAdded(EffectWindow *w)
{
    if (m_connected.contains(w))
        return;
    m_connected.insert(w);
    connect(w, &EffectWindow::minimizedChanged, this, [this, w]() {
        if (w->isMinimized()) {
            slotWindowMinimized(w);
        } else {
            slotWindowUnminimized(w);
        }
    });
}

void StageAnimEffect::slotWindowDeleted(EffectWindow *w)
{
    m_animations.remove(w);
    m_connected.remove(w);
}

void StageAnimEffect::slotWindowMinimized(EffectWindow *w)
{
    if (effects->activeFullScreenEffect()) {
        return;
    }

    // targets 文件每触发只读一次（suppress 判定 + 卡片矩形共用同一快照）
    const StageTargetsFile snap = loadStageTargets();
    // suppress 名单 = 实时模式的静默收放（悬停预备/实时恢复）：不建动画，
    // 窗口瞬间消失——视觉上"没发生过"，实时内容与显式动画由此共存
    if (isSuppressed(snap.suppress, w)) {
        return;
    }

    StageAnimAnimation &animation = m_animations[w];
    resolveTarget(w, animation, snap.targets);

    if (animation.timeLine.running()) {
        animation.timeLine.toggleDirection();
    } else {
        animation.visibleRef = EffectWindowVisibleRef(w, EffectWindow::PAINT_DISABLED_BY_MINIMIZE);
        animation.timeLine.setDirection(TimeLine::Forward);
        animation.timeLine.setDuration(m_duration);
        animation.timeLine.setEasingCurve(QEasingCurve::Linear);
    }

    redirect(w);
    effects->addRepaintFull();
}

void StageAnimEffect::slotWindowUnminimized(EffectWindow *w)
{
    if (effects->activeFullScreenEffect()) {
        return;
    }

    const StageTargetsFile snap = loadStageTargets();
    // 同上：suppress 名单内的还原瞬间完成（不播翻转动画）——engage 前由
    // shell 先把目标窗移出名单，翻转动画才可见
    if (isSuppressed(snap.suppress, w)) {
        return;
    }

    StageAnimAnimation &animation = m_animations[w];
    resolveTarget(w, animation, snap.targets);

    if (animation.timeLine.running()) {
        animation.timeLine.toggleDirection();
    } else {
        animation.visibleRef = EffectWindowVisibleRef(w, EffectWindow::PAINT_DISABLED_BY_MINIMIZE);
        animation.timeLine.setDirection(TimeLine::Backward);
        animation.timeLine.setDuration(m_duration);
        animation.timeLine.setEasingCurve(QEasingCurve::Linear);
    }

    redirect(w);
    effects->addRepaintFull();
}

bool StageAnimEffect::isActive() const
{
    return !m_animations.isEmpty();
}

} // namespace
