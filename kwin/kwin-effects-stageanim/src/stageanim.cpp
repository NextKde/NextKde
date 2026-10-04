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
#include "opengl/glutils.h"
#include "compositor.h"
#include "scene/item.h"
#include "scene/itemrenderer.h"
#include "scene/scene.h"
#include "scene/workspacescene.h"
#include "scene/windowitem.h"
#include "window.h"
#include "opengl/glvertexbuffer.h"

#include <QDateTime>
#include <QImage>
#include <QPainter>
#include <QRegularExpression>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUuid>

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

// 活体卡描述文件（shell 的 StageSidebarWindow.publishLiveCards 原子写入）：
//   { "at": <ms>, "cards": [ { id, winId, x, y, w, h,
//     angle, yOff, focal, radius, …v3 卡面元数据 } ] }
// id = 组键（稳定身份，v3）；winId = 渲染窗口（rep 窗口）的 KWin
// internalId（无花括号）——rep 翻转时特效按它原地换窗重接。x/y/w/h =
// 终态卡面（plate）未倾斜屏幕矩形；angle 已含右侧镜像符号。hidden =
// 启动台等覆盖层期（QML 窗体已隐）：卡保持注册、绘制/投喂暂停。
static QString stageLivePath()
{
    const QString stateHome = qEnvironmentVariable("XDG_STATE_HOME",
        QStandardPaths::writableLocation(QStandardPaths::HomeLocation)
            + QStringLiteral("/.local/state"));
    return stateHome + QStringLiteral(
        "/quickshell/kos/fg-sched/stage-live.json");
}

// 特效回执（shell 据此把卡片快照让位给活体绘制；不新鲜则回退快照）：
//   { "at": <ms>, "active": bool, "cards": [id...] }
static QString stageLiveStatusPath()
{
    return stageLivePath() + QStringLiteral(".status");
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

    // ── 活体卡输入通道：目录 + 文件双 watch（JsonConfigStore 原子重写
    // 会换 inode 拆掉文件 watch，目录 watch 兜住创建/替换）。4ms 去抖
    // 折叠 shell 的发布连发。10s 周期 reload 兜 missed events + 文件里
    // 有但窗口还没出现的 pending 重试（windowAdded 也触发）。
    m_livePath = stageLivePath();
    m_liveStatusPath = stageLiveStatusPath();
    m_liveWatcher = new QFileSystemWatcher(this);
    const QString liveDir = QFileInfo(m_livePath).absolutePath();
    m_liveWatcher->addPath(liveDir);
    m_liveWatcher->addPath(m_livePath);
    connect(m_liveWatcher, &QFileSystemWatcher::fileChanged, this, [this]() {
        if (!m_liveWatcher->files().contains(m_livePath))
            m_liveWatcher->addPath(m_livePath);
        QTimer::singleShot(4, this, &StageAnimEffect::reloadLiveCards);
    });
    connect(m_liveWatcher, &QFileSystemWatcher::directoryChanged, this, [this]() {
        if (!m_liveWatcher->files().contains(m_livePath))
            m_liveWatcher->addPath(m_livePath);
        // 回执/status 文件与本文件同目录——8s 心跳回执会自触发这里。
        // 发布文件 mtime 未变＝不是我们的变更，跳过这轮 reload（4ms 后
        // 全文件读+解析+缺席评估是纯浪费，v87 审查）
        if (QFileInfo(m_livePath).lastModified() == m_lastLiveReadMtime)
            return;
        QTimer::singleShot(4, this, &StageAnimEffect::reloadLiveCards);
    });
    m_liveStaleTimer.setInterval(10000);
    connect(&m_liveStaleTimer, &QTimer::timeout, this, &StageAnimEffect::reloadLiveCards);
    m_liveStaleTimer.start();
    m_liveStatusTimer.setInterval(8000);
    connect(&m_liveStatusTimer, &QTimer::timeout, this, [this]() {
        if (m_liveCards.isEmpty())
            return;
        // 只刷回执；脏纹理重拍已由 33ms 帧预算调度器（scheduleLiveRenders）负责
        writeLiveStatus();
    });
    m_liveStatusTimer.start();
    // 自驱帧回调：KWin 内部 offscreen 计时器路径实测未给最小化窗送回调
    //（原因未明），直接周期调用公开的 WindowItem::framePainted——与
    // Window::maybeSendFrameCallback 同款调用。客户端有待决帧请求时被
    // 喂到 → 渲染 → 提交 → Window::damaged → dirty + addRepaint。
    m_liveFrameTimer.setInterval(33);
    connect(&m_liveFrameTimer, &QTimer::timeout, this, [this]() {
        // 帧投喂分级：悬停/拖拽/悬停动画中的卡每拍喂（30fps），其余卡
        // 轮流喂（~7.5fps）——每次投喂都会引发客户端渲染→损伤→重拍（整
        // 窗场景树渲进 FBO），全员 30fps 是帧率杀手；侧栏小卡 7.5fps 的
        // 活体感无肉眼差异
        // 动静自适应（用户方案）：近 800ms 有损伤 = 卡内容在播放动画 →
        // 全速喂（30fps）；静态内容损伤为零 → 低速轮询足够（无待决帧时
        // 投喂本就是 no-op，低速纯粹防偶发漏帧）
        ++m_liveFeedTick;
        const qint64 feedNow = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now().time_since_epoch()).count();
        for (auto it = m_liveCards.begin(); it != m_liveCards.end(); ++it) {
            LiveCard &card = **it;
            if (card.dying)
                continue; // 退场卡已撤源，framePainted 多为 no-op，白跑窗口查找
            const bool active = card.lastDamageMs > 0
                && feedNow - card.lastDamageMs < 800;
            const bool priority = card.hovered || card.dragging
                || card.hoverAnimating || card.engaging || active;
            if (!priority && (m_liveFeedTick + card.feedPhase) % 4 != 0)
                continue;
            if (!liveCardPaintable(card) || !card.window->windowItem())
                continue;
            const auto timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now().time_since_epoch());
            card.window->windowItem()->framePainted(nullptr,
                card.window->window() ? card.window->window()->output() : nullptr,
                nullptr, timestamp);
        }

        // ── 重拍预算：整窗场景树渲进 FBO 是合成器线程大头，总量必须有界
        //（损伤回调里即时重拍的旧路在客户端去节流后＝整机掉帧的根因）。
        // 每拍最多 2 张，优先卡（悬停/拖拽/engaging）先、其余最久未拍轮转
        //——所有卡都保证被刷新，只是排队，绝不淹没。
        scheduleLiveRenders();

        // 缺席踢除钟控入口：发布载荷去重后文件可长期静默（无 mtime 变化
        // ＝无 reload），迟滞到点必须由时钟推进——否则被吞卡满 alpha 卡屏
        expireAbsentLiveCards();
    });
    // 帧钟随卡启停（v87 审查）：构造即 start＝零卡/断路后仍 30Hz 空转
    // 唤醒（arm 平台常驻功耗负担）。首卡注册 start、全清 stop——reload
    // 到达性由 watcher + 10s stale timer 保证
    reloadLiveCards();
    updateLiveFrameTimer();

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
    m_duration = animationTime(d); // 6.7+ 直接返回 chrono
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

    // 活体卡总闸（默认开——shell 侧 thumbLiveEffect 才是用户开关，
    // 这里只是排障时的硬断路器）
    m_liveEnabled = grp.readEntry<bool>("LiveCards", true);
    if (!m_liveEnabled && !m_liveCards.isEmpty()) {
        // 硬断路器：必须逐卡撤引用再清表——裸 clear() 会把所有离屏渲染
        // 引用漏在窗口上（隐藏窗永久继续出帧＝排障时"莫名变卡"的陷阱）
        for (auto it = m_liveCards.begin(); it != m_liveCards.end(); ++it)
            releaseLiveCard(**it);
        m_liveCards.clear();
        updateLiveFrameTimer();
        writeLiveStatus();
    }

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

// addRepaint 统一走 4 参 int 重载：6.6/6.7 都存在且无歧义。6.7 只剩
// Rect/RectF/Region/int×4 四个重载（Qt 的 QRect/QRectF 重载被删），传
// QRect 或 QRectF 都会在两个用户转换间二义
static void addRepaintRectF(EffectsHandler *fx, const QRectF &r)
{
    fx->addRepaint(qFloor(r.left()), qFloor(r.top()),
                   qCeil(r.width()), qCeil(r.height()));
}

#ifdef KOS_KWIN_PAINT_TIME_API
void StageAnimEffect::prePaintScreen(ScreenPrePaintData &data, std::chrono::milliseconds presentTime)
#else
void StageAnimEffect::prePaintScreen(ScreenPrePaintData &data)
#endif
{
    // Mark the screen as transformed so the moving window is repainted fully.
    // 活体卡期间不动这个 mask（自有分区 addRepaint，不需要全屏重绘）。
    if (!m_animations.isEmpty())
        data.mask |= PAINT_SCREEN_WITH_TRANSFORMED_WINDOWS;

    // 帧去重键（多输出防双喂）：6.6 = presentTime 值；6.7 起签名移除
    // presentTime、帧时钟由 RenderView 携带 → 用 view 指针（同帧同
    // view 幂等）。活体状态机每帧只推进一次
#ifdef KOS_KWIN_PAINT_TIME_API
    const qint64 frameKey = presentTime.count();
#else
    const qint64 frameKey = reinterpret_cast<qint64>(data.view);
#endif
    // ── 悬停引擎（特效自驱）── 卡面视觉已整体由特效绘制（方案"卡进
    // 特效"），悬停放大/压平/展开淡出动画在本进程跑——与内容同管线、
    // 同一时钟，像素级同步（跨文件追赶的脱节就此根治）。命中判定 =
    // 静止矩形（与 QML 输入区同界）+ 悬停中放宽到放大矩形（QML 缩放
    // MouseArea 的语义等价，防边缘闪烁）。曲线对齐 QML：scale OutBack
    // overshoot 1.2、tilt OutCubic。
    if (!m_liveCards.isEmpty() && frameKey != m_lastLiveFrameKey) {
        // 多输出防双喂：prePaintScreen 每屏各调一次，同一帧的两次调用
        // 会让补间时间线 advance 两遍（动画约 2 倍速）。命中判定幂等，
        // 跳过无副作用。活体卡缓动（下方 ease 循环）也必须在闸内——
        // v87 审查：闸外＝双屏下姿态缓动按屏数倍速推进
        m_lastLiveFrameKey = frameKey;
        // 活体卡缓动推进（发布姿态变化 → 短缓动追上，抹平取整抖动）：
        // 未完 → 持续请求卡区重绘
        for (auto it = m_liveCards.begin(); it != m_liveCards.end(); ++it) {
            LiveCard &card = **it;
            if (!card.easing)
                continue;
#ifdef KOS_KWIN_PAINT_TIME_API
            card.ease.advance(presentTime);
#else
            card.ease.advance(data.view);
#endif
            if (card.ease.done())
                card.easing = false;
            const QRectF r = currentPose(card).rect;
            addRepaintRectF(effects, r.adjusted(-40, -40, 40, 40));
        }
        const QPointF cur = effects->cursorPos();
        // 拖拽期全员免悬停（老体系语义：拖拽中无 hover 放大/倾斜——候选
        // 预示由 dropHover/dwellHint 武装态视觉承担）
        bool anyDragging = false;
        for (auto it = m_liveCards.begin(); it != m_liveCards.end(); ++it)
            if ((*it)->dragging) { anyDragging = true; break; }
        QVector<LiveCard *> order;
        order.reserve(m_liveCards.size());
        for (auto it = m_liveCards.begin(); it != m_liveCards.end(); ++it)
            order.append(it.value().data());
        std::sort(order.begin(), order.end(),
                  [](const LiveCard *a, const LiveCard *b) { return a->z > b->z; });
        // 最高层独占（v87 审查）：z 降序遍历中上层卡命中后占位
        bool hoverTaken = false;
        bool anyAnim = false;
        for (LiveCard *cp : order) {
            LiveCard &card = *cp;
            // ── 入场起摆保持 ── 收编卡等窗口飞行**结束**（最小化已落地
            // 且不再有最小化动画）才凝实——与飞行同时起摆时 OutCubic 前
            // 快后慢，飞行到一半卡已六成显形＝"动画结束之前卡片就出现了"
            //（用户定稿编排：全程只有飞行的窗口，落位瞬间卡尾段凝实，
            // 与其他卡的让位合流）。撤销（undo）路径窗口永不最小化：卡
            // 保持 alpha 0，缺席踢除无闪；全局动画关闭时 m_animations
            // 恒不含该窗＝最小化即落位，直接凝实
            if (card.enterHold) {
                if (card.window && card.window->isMinimized()
                        && !m_animations.contains(card.window.data())) {
                    card.enterHold = false;
                    // 释放＝落位凝实：只淡入。注册时装配的非 enterInstant
                    // 入场（侧滑 ±70/0.86 长大）此时重放＝"落位后卡又从
                    // 侧边滑入一遍"——统一收敛为 enterInstant 语义（v82）
                    card.spawnAtMs = 0;
                    card.curScale = 1.0;
                    card.scaleFrom = card.scaleTo = 1.0;
                    card.tiltFrom = card.tiltTo = card.target.angleDeg;
                    card.curTiltDeg = card.target.angleDeg;
                    card.hoverAnimating = false;
                    card.alphaFrom = 0.0;
                    card.alphaTo = 1.0;
                    card.fadeTl = TimeLine(std::chrono::milliseconds(180));
                    card.fadeAnimating = true;
                    anyAnim = true;
                }
                continue; // 保持期不进下方状态机/悬停引擎（alpha 0 不可点）
            }
            // ── 透明度唯一状态机 ── 目标只由发布状态决定（engaging/dying
            // → 0，否则 → 1），补间从当前值单向趋近，目标翻转即重启。
            // ⚠️ 历史教训（v61~v63 三连补丁的总根因，已整体废除）：曾把
            // alpha 耦合 KWin 飞行进度（alpha=1-p）——换卡时旧卡的**最小化**
            // 飞行让 p 归零 → alpha 弹回 1 ＝"旧卡一闪而过"；看门狗又与它
            // 强制清除 fadeAnimating 交相互打＝无操作透明抽搐。展开淡出
            // 时长 = animMs（与窗口飞行同拍收束），视觉等价且零耦合。
            const qreal aTo = (card.engaging || card.dying) ? 0.0 : 1.0;
            if ((!card.fadeAnimating && card.alpha != aTo)
                || (card.fadeAnimating && card.alphaTo != aTo)) {
                card.alphaFrom = card.alpha;
                card.alphaTo = aTo;
                card.fadeTl = TimeLine(card.engaging
                    ? card.animMs
                    : (aTo == 0.0 ? std::chrono::milliseconds(150)
                                  : std::chrono::milliseconds(180)));
                card.fadeAnimating = true;
            }
            if (card.dragging || card.engaging || card.dying || anyDragging) {
                if (card.hovered && card.hoverAnimating) {
                    // 拖拽开始时优雅退场（不再瞬跳）
                    card.hovered = false;
                    card.scaleFrom = card.curScale;
                    card.tiltFrom = card.curTiltDeg;
                    card.scaleTo = 1.0;
                    card.tiltTo = card.target.angleDeg;
                    card.hoverBlendFrom = card.hoverBlend;
                    card.hoverBlendTo = 0.0;
                    card.hoverTl = TimeLine(card.tiltMs);
                    card.hoverAnimating = true;
                } else {
                    // 与 armed 分支同款退场补间：只置 false 不动画会把
                    // hoverBlend 卡死在 1.0（边框恒蓝/深度淡出锁死）
                    card.hovered = false;
                    if (card.hoverBlend > 0.01 || card.curScale != 1.0) {
                        card.scaleFrom = card.curScale;
                        card.tiltFrom = card.curTiltDeg;
                        card.scaleTo = 1.0;
                        card.tiltTo = card.target.angleDeg;
                        card.hoverBlendFrom = card.hoverBlend;
                        card.hoverBlendTo = 0.0;
                        card.hoverTl = TimeLine(card.tiltMs);
                        card.hoverAnimating = true;
                    }
                }
                if (card.dragging) {
                    card.curScale = card.dragScale; // 老语义净放大 1.06×hover
                    card.curTiltDeg = 0.0;
                    card.hoverBlend = 0.0;
                    card.hoverBlendFrom = 0.0;
                    card.hoverBlendTo = 0.0;
                }
            } else {
                const QRectF rest = card.target.rect;
                const QRectF grown(rest.topLeft(),
                                   rest.size() * card.hoverScale);
                // 最高层独占（v87 审查）：z 降序遍历，上层卡命中后下层
                // 卡不再悬停——重叠过渡期两张卡同时放大＝QML MouseArea
                // 语义（只给顶层）不符，order 排序此前是死权重
                const bool hit = !hoverTaken
                    && (rest.contains(cur)
                        || (card.hovered && grown.contains(cur)));
                if (hit)
                    hoverTaken = true;
                if (hit != card.hovered) {
                    qCInfo(STAGEANIM_LOG) << "live hover"
                        << (hit ? "IN " : "OUT") << card.id.left(10)
                        << "cur" << int(cur.x()) << int(cur.y())
                        << "rest" << card.target.rect;
                    card.hovered = hit;
                    card.scaleFrom = card.curScale;
                    card.tiltFrom = card.curTiltDeg;
                    card.scaleTo = hit ? card.hoverScale : 1.0;
                    card.tiltTo = hit ? card.hoverTiltDeg : card.target.angleDeg;
                    // hoverBlend 也从当前值起摆（v87 审查）：旧实现
                    // (hovered?1:0)*cubic 在翻转/打断瞬间单帧硬跳
                    card.hoverBlendFrom = card.hoverBlend;
                    card.hoverBlendTo = hit ? 1.0 : 0.0;
                    card.hoverTl = TimeLine(card.hoverMs);
                    card.hoverAnimating = true;
                }
            }
            if (card.hoverAnimating) {
#ifdef KOS_KWIN_PAINT_TIME_API
                card.hoverTl.advance(presentTime);
#else
                card.hoverTl.advance(data.view);
#endif
                const qreal t = qBound(0.0, card.hoverTl.value(), 1.0);
                // OutBack（Qt 语义：overshoot 值直用为 c1——旧版 ×1.70158
                // 过冲强 1.7 倍）；OutCubic 手工版
                const qreal c1 = 1.2, c3 = c1 + 1.0;
                const qreal tm1 = t - 1.0;
                const qreal back = 1.0 + c3 * tm1 * tm1 * tm1 + c1 * tm1 * tm1;
                const qreal cubic = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t);
                card.curScale = card.scaleFrom
                    + (card.scaleTo - card.scaleFrom) * back;
                card.curTiltDeg = card.tiltFrom
                    + (card.tiltTo - card.tiltFrom) * cubic;
                card.hoverBlend = card.hoverBlendFrom
                    + (card.hoverBlendTo - card.hoverBlendFrom) * cubic;
                if (card.hoverTl.done()) {
                    card.hoverAnimating = false;
                    // 入场侧滑播完清标记——残留会让后续悬停动画被误判为
                    // 入场中（卡先横跳 ±70 再滑回＝"悬停抽动"的真凶）
                    card.spawnAtMs = 0;
                }
                anyAnim = true;
            }
            if (card.fadeAnimating) {
#ifdef KOS_KWIN_PAINT_TIME_API
                card.fadeTl.advance(presentTime);
#else
                card.fadeTl.advance(data.view);
#endif
                const qreal t = qBound(0.0, card.fadeTl.value(), 1.0);
                const qreal cubic = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t);
                card.alpha = card.alphaFrom + (card.alphaTo - card.alphaFrom) * cubic;
                if (card.fadeTl.done()) {
                    card.fadeAnimating = false;
                    // 终点快照：浮点插值 1 ulp 差会让 != aTo 判定多跑
                    // 一整轮补间（每轮重新基线化，1-2 轮才收敛）
                    card.alpha = card.alphaTo;
                }
                anyAnim = true;
            }
            // 扇叠扩散补间：hover/武装(dropHover)/驻留(dwellHint)任一即扩，
            // 目标翻转从当前值起摆（150ms OutCubic）——武装/驻留瞬时满扩
            // ＝跳变"生硬"的根因；旧实现挂 hoverBlend 也与放大曲线耦合
            {
                const qreal fanTarget = (card.hovered || card.dropHover
                    || card.dwellHint) ? 1.0 : 0.0;
                if (fanTarget != card.fanTo) {
                    card.fanFrom = card.fanBlend;
                    card.fanTo = fanTarget;
                    card.fanTl = TimeLine(std::chrono::milliseconds(150));
                    card.fanAnimating = true;
                }
                if (card.fanAnimating) {
#ifdef KOS_KWIN_PAINT_TIME_API
                    card.fanTl.advance(presentTime);
#else
                    card.fanTl.advance(data.view);
#endif
                    const qreal ft = qBound(0.0, card.fanTl.value(), 1.0);
                    const qreal fcubic = 1.0 - (1.0 - ft) * (1.0 - ft) * (1.0 - ft);
                    card.fanBlend = card.fanFrom
                        + (card.fanTo - card.fanFrom) * fcubic;
                    if (card.fanTl.done()) {
                        card.fanAnimating = false;
                        card.fanBlend = card.fanTo;
                    }
                    anyAnim = true;
                }
            }
        }
        if (anyAnim) {
            // 动画卡区域并集重绘（全屏 addRepaintFull 在本机 GPU 是掉帧
            // 大头——卡列只占屏幕一角）。⚠️ 必须在清扫**之前**算——order
            // 里是裸指针，清扫 release 后再解引用＝UAF（每次退场必触发）
            for (LiveCard *cp2 : order) {
                const LiveCard &c2 = *cp2;
                const QRectF r(c2.target.rect.topLeft(),
                               QSizeF(c2.target.rect.width() * c2.hoverScale,
                                      c2.target.rect.height() * c2.hoverScale));
                // 横向余量 ≥ 入场侧滑 ±70（不够＝侧滑帧背景动态时残影）
                addRepaintRectF(effects, r.adjusted(-75, -30, 75, 30));
            }
        }
        // 退场收尾：dying 卡淡透（统一状态机推进）即释放。不再有独立
        // ghost 管线——dying 卡留在 m_liveCards 里走同一套绘制/重绘区域，
        // 发布流回心转意时还能原地复活（无缝回淡，不再"掉卡重入场"）。
        QList<QString> deadDone;
        for (auto it = m_liveCards.begin(); it != m_liveCards.end(); ++it) {
            LiveCard &card = **it;
            if (card.dying && card.alpha <= 0.01 && !card.fadeAnimating)
                deadDone.append(it.key());
        }
        for (const QString &id : deadDone) {
            qCInfo(STAGEANIM_LOG) << "live SWEEP released" << id.left(8);
            releaseLiveCard(*m_liveCards.value(id)); // value()：operator[] 缺键默认构造后解引用即崩（v82）
            m_liveCards.remove(id);
        }
        updateLiveFrameTimer();
        if (!deadDone.isEmpty()) {
            // 清扫后回执同步：QML 侧 _liveActiveIds 据此判定让位/回退，
            // 残留已释放 id 会让对应槽位多隐藏一拍
            writeLiveStatus();
        }
    }

#ifdef KOS_KWIN_PAINT_TIME_API
    effects->prePaintScreen(data, presentTime);
#else
    effects->prePaintScreen(data);
#endif
}

// 活体直绘走 paintScreen 后置通道（所有窗口画完之后）：不依赖宿主窗
// 判定与它的绘制时机（宿主方案实测会因条带区域无损伤而不重绘=内容
// 冻结）；代价是内容盖在条带 chrome 之上——内容矩形内缩于卡面，边框/
// 标题/图标排不受影响，仅失去背板色调/深度渐变的叠加（后续可在着色器
// 里补）。任何窗口动画播放期间整体让位（飞行窗口会横穿卡列，层序
// 不可与直绘混排）。
//（paintScreen 签名在 6.6 与 6.7 发行版一致＝void，无需守卫）
void StageAnimEffect::paintScreen(const RenderTarget &renderTarget, const RenderViewport &viewport,
                                  int mask, const Region &deviceRegion, LogicalOutput *screen)
{
    static quint32 s_psCalls = 0;
    if (++s_psCalls % 18000 == 1)
        qCInfo(STAGEANIM_LOG) << "live paintScreen called #" << s_psCalls
                                 << "cards=" << m_liveCards.size()
                                 << "anims=" << m_animations.size();
    effects->paintScreen(renderTarget, viewport, mask, deviceRegion, screen);

    // ⚠️ 不可再有 m_animations 全局让位闸：卡面视觉整体在特效手里，全局
    // 一让＝动画期间整列卡消失（旧架构只让内容、QML 卡面还在）。改为
    // 逐卡让位——飞行中窗口自己的卡跳过（liveCardPaintable 内判定），
    // 其余卡照画；飞行窗由合成器画在窗层级，交叠瞬间由 engage 淡出遮蔽。
    if (m_liveCards.isEmpty())
        return;
    if (effects->activeFullScreenEffect())
        return;
    drawLiveCards(renderTarget, viewport);
}

#ifdef KOS_KWIN_PAINT_TIME_API
void StageAnimEffect::prePaintWindow(RenderView *view, EffectWindow *w, WindowPrePaintData &data, std::chrono::milliseconds presentTime)
{
    auto animationIt = m_animations.find(w);
    if (animationIt != m_animations.end()) {
        // 多输出防双喂（逐窗守卫）：prePaintWindow 每屏各调一次，同帧
        // advance 两遍＝2 倍速；守卫必须挂条目——全局时间戳会饿死同帧
        // 的其余窗口（v82 引入的收起/退避卡顿，v83.1 修正）
        if (presentTime != (*animationIt).lastAdvance) {
            (*animationIt).lastAdvance = presentTime;
            (*animationIt).timeLine.advance(presentTime);
        }
        data.setTransformed();
    }

    effects->prePaintWindow(view, w, data, presentTime);
}
#else
void StageAnimEffect::prePaintWindow(RenderView *view, EffectWindow *w, WindowPrePaintData &data)
{
    auto animationIt = m_animations.find(w);
    if (animationIt != m_animations.end()) {
        (*animationIt).timeLine.advance(view);
        data.setTransformed();
    }

    effects->prePaintWindow(view, w, data);
}
#endif

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
    bool haveTarget = false;
    // 活体卡跟踪：飞行目标逐帧取发布流里该窗当前卡面矩形，
    // 不再锁死动画开始时的 targets 快照——抽屉收起（启动台/全屏/让位）
    // 时卡片滑出屏，飞行窗随卡同向出屏（旧实现缩向回落点＝任务栏图标
    // /光标边缘，观感"收进屏幕中心"）。匹配：卡已接上的渲染窗指针，或
    // winId 字符串（卡刚发布、EffectWindow 连接建立前的 ~50ms 窗口期）
    {
        const QString selfKey = w->internalId().toString(QUuid::WithoutBraces);
        for (auto cit = m_liveCards.constBegin(); cit != m_liveCards.constEnd(); ++cit) {
            const LiveCard &lc = *cit.value();
            if (lc.dying || lc.engaging || !lc.target.rect.isValid()
                || lc.target.rect.isEmpty())
                continue;
            if (lc.window.data() != w && lc.winId != selfKey)
                continue;
            target = lc.target.rect;
            endScale = std::clamp(
                std::min(target.width() / std::max(1, geo.width()),
                         target.height() / std::max(1, geo.height())),
                kCardMinEndScale, kCardMaxEndScale);
            haveTarget = true;
            break;
        }
    }
    if (!haveTarget && (*animationIt).endScale > 0
        && (*animationIt).target.isValid()) {
        target = (*animationIt).target;
        endScale = (*animationIt).endScale;
        haveTarget = true;
    }
    if (!haveTarget) {
        // 原版回落：任务栏图标几何 / 光标最近边缘
        QRect icon = w->iconGeometry().toRect();
        if (icon.isValid() && icon.width() > 0) {
            target = icon;
            endScale = std::clamp(qreal(icon.width()) / std::max(1, geo.width()),
                                  kGlobalMinScale, kGlobalMaxScale);
        } else {
            QPoint pt = cursorPos().toPoint();
            if (geo.contains(pt)) {
                const int d[4] = {pt.x() - geo.x(), geo.right() - pt.x(),
                                  pt.y() - geo.y(), geo.bottom() - pt.y()};
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
                    pt.setX(geo.x());
                    break;
                case 1:
                    pt.setX(geo.right());
                    break;
                case 2:
                    pt.setY(geo.y());
                    break;
                default:
                    pt.setY(geo.bottom());
                    break;
                }
            } else {
                pt.setX(std::clamp(pt.x(), geo.x(), geo.right()));
                pt.setY(std::clamp(pt.y(), geo.y(), geo.bottom()));
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

    // 全屏重绘仅窗口动画期需要（承袭 MagicLamp）；live 卡常驻时恒刷会
    // 让合成器永不息帧（90Hz 全屏重组），live 卡有自己的分区重绘
    if (!m_animations.isEmpty())
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
    // 文件里挂着但窗口此前不存在的活体卡，此刻补建（10s reload 也兜）
    if (!m_livePending.isEmpty())
        QTimer::singleShot(50, this, &StageAnimEffect::reloadLiveCards);
}

void StageAnimEffect::slotWindowDeleted(EffectWindow *w)
{
    m_animations.remove(w);
    m_connected.remove(w);

    // 活体卡生命周期：卡片窗口死亡 → 进 dying 统一淡出（150ms），冻结
    // 纹理/姿态由状态机走完后清扫（card.window 已空，release 的守卫安全）。
    // 旧版健康卡立即释放除名＝瞬消 pop（用户实测"点关闭钮卡片直接消失
    // 不丝滑"，v89 修复）——dying 路径本来就有：缺席踢除/交棒淡出全走它
    for (auto it = m_liveCards.begin(); it != m_liveCards.end(); ++it) {
        LiveCard &card = **it;
        if (card.dying)
            continue;
        if (card.window == w || card.window.isNull()) {
            detachLiveCard(card);
            card.dying = true;
            card.enterHold = false;
            card.fadeAnimating = false; // 状态机一次性起淡
        }
    }
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
    return !m_animations.isEmpty() || !m_liveCards.isEmpty();
}

// ── 活体卡（合成器直绘）──────────────────────────────────────────
// 通道：shell 发布 stage-live.json（每卡终态卡面矩形 + 透视参数）→
// 特效对每张卡的代表窗持 refOffscreenRendering（KWin 起刷新率定时器给
// 隐藏窗补发帧回调——客户端继续渲染，成本等同窗口可见在桌面；无离屏
// 渲染管线、无导出、无跨进程消费者）→ 窗口内容渲进卡面尺寸小 FBO
//（损伤驱动重拍，填充率可忽略）→ 侧栏浮层窗口的 paintWindow 钩子里、
// 条带自绘内容之前，用 QML stage_tilt/stage_round 的着色器孪生画到
// ── 卡面本体（方案"卡进特效"）：元数据 + 铭牌光栅 ──
// v2 协议元数据：QML 只发布静止几何与参数，悬停/展开动画由特效自驱。
struct CardMeta
{
    QString title;
    int count = 1;
    qreal z = 0;
    bool dragging = false, engaging = false, dropHover = false, dwellHint = false;
    // 默认值与 reload 解析回落一致（= StageConfigService._schema 的 def，
    // v87 审查收敛：三套默认漂移＝发布端漏字段时静默落到另一套视觉）
    qreal hoverScale = 1.05, hoverTiltDeg = 0;
    std::chrono::milliseconds hoverMs{280};
    qreal fanSpacing = 8, tintAlpha = 0.55, borderAlpha = 0.13;
    qreal fanHoverSpread = 1.4;
    qreal depthStrength = 0.38, topLight = 0.07;
    qreal fade = 1.0;   // QML slot.opacity（压暗 × 视口边缘渐隐）
    bool closeHot = false;
    QString winId;      // 渲染窗口（rep 窗口 id；id 本体=组键，rep 翻转
                        // 只换此字段 → 特效原地换窗重接，不销毁重注册）
    bool selfMergeHint = false; // 中心合并武装：被拖卡自身亮蓝边框
    bool rightSide = false;     // 右条镜像（扇叠/深度/图标方向）
    bool merged = false;        // 合并卡（拆分芯片；标题让位 50）
    bool showCardTitle = true;
    bool enterInstant = false;  // 收编落卡（淡入=飞行时长 420ms）
    bool chipHot = false;       // 拆分芯片点亮（isHovered||mergeGlow）
    QString iconsJson;          // 组内窗口图标排（file:/icon: URL 数组）
    qreal iconSize = 40;   // 图标排图标边长（payload，v88：原硬编码 24）
    int iconSlots = 4;     // 图标排并列上限（payload，v88：原仅按宽度封顶）
    qreal engagingTilt = 0;     // 交棒保持倾角（adaptive=tiltAngle 非 0）
    std::chrono::milliseconds tiltMs{250};
    std::chrono::milliseconds enterMs{240};
    std::chrono::milliseconds animMs{420};
    qreal dragScale = 1.0;      // 拖拽净放大（1.06×hover 叠加，老语义）
    // cardGlow 已删（v87 审查）：辉光 pass 在 v57 撤除后特效侧零消费，
    // 仅剩"解析→存储"死链；QML 静态模式的扇叠背板辉光直接读
    // StageConfigService.cardGlow，不经本协议
};

static void applyCardMeta(LiveCard &card, const CardMeta &m)
{
    card.title = m.title;
    card.winId = m.winId;
    card.count = m.count;
    card.z = m.z;
    card.dragging = m.dragging;
    card.engaging = m.engaging;
    card.dropHover = m.dropHover;
    card.dwellHint = m.dwellHint;
    card.hoverScale = m.hoverScale;
    card.hoverTiltDeg = m.hoverTiltDeg;
    card.hoverMs = m.hoverMs;
    card.fanSpacing = m.fanSpacing;
    card.fanHoverSpread = m.fanHoverSpread;
    card.depthStrength = m.depthStrength;
    card.topLight = m.topLight;
    // QML 同款色族：静置 rgba(0.05,0.07,0.12,tint)，悬停 ×1.3 提亮
    const qreal ta = qBound(0.05, m.tintAlpha, 0.95);
    const qreal th = qBound(0.05, qMin(0.95, m.tintAlpha * 1.3), 0.95);
    card.tint = QColor(13, 18, 31, int(ta * 255));
    card.tintHover = QColor(26, 33, 51, int(th * 255));
    card.border = QColor(255, 255, 255, int(qBound(0.0, m.borderAlpha, 1.0) * 255));
    card.fade = m.fade;
    card.closeHot = m.closeHot;
    card.selfMergeHint = m.selfMergeHint;
    card.rightSide = m.rightSide;
    card.merged = m.merged;
    card.showCardTitle = m.showCardTitle;
    card.chipHot = m.chipHot;
    card.iconsJson = m.iconsJson;
    card.iconSize = m.iconSize;
    card.iconSlots = m.iconSlots;
    card.engagingTilt = m.engagingTilt;
    card.tiltMs = m.tiltMs;
    card.enterMs = m.enterMs;
    card.animMs = m.animMs;
    card.dragScale = m.dragScale > 1.001 ? m.dragScale : 1.0;
    card.enterInstant = m.enterInstant;
}

// 铭牌（标题 + 关闭钮，QML cardHeader 同版式 ×2 超采样）光栅进纹理。
// QImage 行 0 = 顶部，stage-live 着色器按 FBO 朝向（行 0 = 底）采样——
// 上传前 Y 镜像即可复用同一着色器。键变才重绘（标题/计数/卡宽）。
// 分脏分张（v87 审查）：铭牌与覆盖层各按各的键独立重光栅——旧版任一
// 键变就两层全重画（关闭钮悬停高频翻转会把整个图标排也重传一遍）。
void StageAnimEffect::rasterChrome(LiveCard &card)
{
    const int w = std::max(2, qRound(card.target.rect.width()));
    const int h = std::max(2, qRound(card.target.rect.height()));
    const QString key = card.title + QLatin1Char('|')
        + QString::number(card.count) + QLatin1Char('|')
        + QString::number(w) + QLatin1Char('x') + QString::number(h)
        + QLatin1Char(card.closeHot ? '!' : '.')
        + QLatin1Char(card.merged ? 'M' : 'm')
        + QLatin1Char(card.showCardTitle ? 'T' : 't');
    const QString ovKey = card.iconsJson + QLatin1Char('|')
        + QString::number(card.count) + QLatin1Char('|')
        + QString::number(w) + QLatin1Char('x') + QString::number(h)
        + QLatin1Char(card.merged ? (card.chipHot ? 'C' : 'N') : 'c')
        + QLatin1Char(card.rightSide ? 'R' : 'l')
        + QStringLiteral("|i%1n%2").arg(qRound(card.iconSize))
            .arg(card.iconSlots);
    const bool chromeDirty = key != card.chromeKey || !card.chromeTex;
    const bool overlayDirty = ovKey != card.overlayKey || !card.overlayTex;
    if (!chromeDirty && !overlayDirty)
        return;
    card.chromeKey = key;
    card.overlayKey = ovKey;

    auto upload = [](const QImage &im) {
        auto tex = GLTexture::allocate(GL_RGBA8, im.size());
        if (tex) {
            tex->setFilter(GL_LINEAR);
            tex->setWrapMode(GL_CLAMP_TO_EDGE);
            tex->bind();
            glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, im.width(), im.height(),
                            GL_BGRA, GL_UNSIGNED_BYTE, im.constBits());
            tex->unbind();
        }
        return tex;
    };

    // ── 铭牌：标题 + 关闭钮 + 拆分芯片 + 图标排（+N 溢出）──
    if (chromeDirty) {
    QImage img(w * 2, h * 2, QImage::Format_ARGB32_Premultiplied);
    img.fill(Qt::transparent);
    QPainter p(&img);
    p.setRenderHint(QPainter::Antialiasing, true);
    p.setRenderHint(QPainter::TextAntialiasing, true);
    QFont f = p.font();
    f.setPixelSize(22); // QML pixelSize 11 ×2
    f.setWeight(QFont::Bold);
    p.setFont(f);
    const int titleMargin = card.merged ? 50 * 2 : 26 * 2; // merged 让位芯片
    if (card.showCardTitle) {
        const QRect tr(16, 16, w * 2 - 16 - titleMargin - 8, 48);
        p.setPen(QColor(0, 0, 0, 150));
        p.drawText(tr.translated(0, 2), Qt::AlignLeft | Qt::AlignVCenter, card.title);
        p.setPen(QColor(255, 255, 255, 235));
        p.drawText(tr, Qt::AlignLeft | Qt::AlignVCenter, card.title);
    }
    // 关闭钮：右上 20×20 热区。静置=柔和暗底圆 + 白 ×（无圈线——
    // "圆圈带叉"样式用户否决；暗底保证亮内容上也不隐身），悬停=
    // 红圆底 + 白 ×。与 QML cardClose 同款（两模式视觉统一）
    const int csize = 40; // 20 ×2
    const int cx = w * 2 - 16 - csize;
    const int cy = 8 * 2 + (48 - csize) / 2;
    const qreal cmx = cx + csize / 2.0, cmy = cy + csize / 2.0;
    if (card.closeHot) {
        p.setPen(Qt::NoPen);
        p.setBrush(QColor(239, 68, 68, 225));
        p.drawEllipse(QPointF(cmx, cmy), 15.0, 15.0);
        p.setPen(QPen(QColor(255, 255, 255, 245), 3.2,
                      Qt::SolidLine, Qt::RoundCap));
    } else {
        p.setPen(Qt::NoPen);
        p.setBrush(QColor(10, 14, 20, 115));
        p.drawEllipse(QPointF(cmx, cmy), 14.0, 14.0);
        p.setPen(QPen(QColor(255, 255, 255, 210), 2.8,
                      Qt::SolidLine, Qt::RoundCap));
    }
    p.drawLine(QPointF(cmx - 5.5, cmy - 5.5), QPointF(cmx + 5.5, cmy + 5.5));
    p.drawLine(QPointF(cmx + 5.5, cmy - 5.5), QPointF(cmx - 5.5, cmy + 5.5));
    p.end();
    card.chromeTex = upload(img.mirrored(false, true));
    } // chromeDirty

    //（图标排（左下/右条右下）+ "+N" 溢出 + 拆分芯片（右上，merged
    // 常显暗态/悬停点亮））。绘制侧随卡投影（v78 起废除 v52"正视压平"
    // ——全套特效直绘后，压平层在悬停缩放/压平动画里表现为钉死原地
    // 不跟卡动）
    if (overlayDirty) {
    QImage ov(w * 2, h * 2, QImage::Format_ARGB32_Premultiplied);
    ov.fill(Qt::transparent);
    QPainter op(&ov);
    op.setRenderHint(QPainter::Antialiasing, true);
    op.setRenderHint(QPainter::TextAntialiasing, true);
    QFont of = op.font();
    of.setPixelSize(22); // QML pixelSize 11 ×2
    of.setWeight(QFont::Bold);
    op.setFont(of);
    QStringList icons;
    {
        const auto doc = QJsonDocument::fromJson(card.iconsJson.toUtf8());
        if (doc.isArray())
            for (const auto &v : doc.array())
                icons.append(v.toString());
    }
    // 去重兜底：QML 侧 decorateGroups 已按图标源去重（同应用多窗一枚），
    // 这里再滤一次防御异常数据（重复图标是用户实测困惑点）
    {
        QSet<QString> seenIcons;
        for (int i = icons.size() - 1; i >= 0; --i) {
            if (seenIcons.contains(icons.at(i)))
                icons.removeAt(i);
            else
                seenIcons.insert(icons.at(i));
        }
    }
    // 图标排参数经载荷（v88）：尺寸＝stripIconSize 旋钮（原硬编码 24，
    // 与静态模式 40px 不一致），并列上限＝maxIconSlots 旋钮与卡宽取小
    const int isz = std::max(12, qRound(card.iconSize)) * 2,
              igap = std::max(6, isz / 5);
    const int maxFit = std::max(1, std::min(card.iconSlots,
        (w * 2 + igap) / (isz + igap)));
    const int visible = int(std::min<qsizetype>(icons.size(), maxFit));
    int rowW = visible > 0 ? visible * isz + (visible - 1) * igap : 0;
    const bool overflow = icons.size() > visible;
    if (overflow)
        rowW += igap + 56;
    int ix0 = card.rightSide ? w * 2 - 10 - rowW : 10;
    const int iy0 = h * 2 - isz - 8; // 完整收进卡内（用户定稿"直接上移"）
    for (int i = 0; i < visible; i++) {
        const QString &src = icons.at(i);
        QPixmap pm;
        if (src.startsWith(QLatin1String("file://")))
            pm.load(src.mid(7));
        if (pm.isNull()) {
            QString name = src;
            name.remove(QRegularExpression(QStringLiteral("^image://[^/]+/")));
            pm = QIcon::fromTheme(name).pixmap(isz, isz);
        }
        if (!pm.isNull()) {
            op.drawPixmap(ix0 + i * (isz + igap), iy0, isz, isz, pm);
        } else {
            op.setPen(Qt::NoPen);
            op.setBrush(QColor(255, 255, 255, 90));
            op.drawRoundedRect(QRect(ix0 + i * (isz + igap), iy0, isz, isz), 8, 8);
        }
    }
    if (overflow) {
        op.setPen(QColor(255, 255, 255, 200));
        op.drawText(QRect(ix0 + visible * (isz + igap), iy0, 56, isz),
                    Qt::AlignLeft | Qt::AlignVCenter,
                    QStringLiteral("+%1").arg(icons.size() - visible));
    }
    if (card.merged) {
        // 拆分芯片：**右上**，关闭钮左侧（与 QML splitHit 同位 rightMargin
        // 31/顶 7；铭牌 titleMargin=50 一直为它预留着）。合并卡**常显**暗态
        //（alpha 90——用户要知道这张卡能拆），悬停点亮（chipHot → 加亮）。
        // 旧版画在卡面正中＝盖住内容且用户在右上找不到（实测反馈）
        const int ccx = w * 2 - 84; // 芯片中心（×2 画布；QML 20px 视觉钮中心）
        const int ccy = 36;
        const int base = card.chipHot ? 235 : 90;
        op.setPen(QPen(QColor(120, 210, 255, card.chipHot ? 235 : 110), 2.8));
        op.setBrush(Qt::NoBrush);
        op.drawRoundedRect(QRect(ccx - 12, ccy - 12, 18, 18), 4, 4);
        op.setBrush(QColor(255, 255, 255, base));
        op.drawRoundedRect(QRect(ccx - 12 + 6, ccy - 12 + 6, 18, 18), 4, 4);
    }
    op.end();
    card.overlayTex = upload(ov.mirrored(false, true));
    } // overlayDirty
    // 辉光 pass 已撤（v57；再启用需重做投影对齐与键位重光栅联动）
}

void StageAnimEffect::reloadLiveCards()
{
    QSet<QString> wanted;
    QVector<std::tuple<QString, LiveCardPose, CardMeta>> entries;
    QFile f(m_livePath);
    const bool fileMissing = !QFileInfo::exists(m_livePath);
    if (f.open(QIODevice::ReadOnly)) {
        const auto doc = QJsonDocument::fromJson(f.readAll());
        // 撕裂/半写 → 保持现状直接返回（裸写无原子保证；掉卡只走空表/
        // mtime 陈旧/迟滞路径，绝不因 parse 失败而掉）——旧实现只是跳过
        // 解析块，落入空 wanted＝600ms 后全体掉卡（与注释承诺相反）
        if (doc.isNull())
            return;
        m_lastLiveReadMtime = QFileInfo(m_livePath).lastModified();
        {
            const auto obj = doc.object();
            const auto arr = obj.value(QStringLiteral("cards")).toArray();
            for (const auto &v : arr) {
                const auto o = v.toObject();
                LiveCardPose pose;
                pose.rect = QRectF(o.value(QStringLiteral("x")).toDouble(),
                                   o.value(QStringLiteral("y")).toDouble(),
                                   o.value(QStringLiteral("w")).toDouble(),
                                   o.value(QStringLiteral("h")).toDouble());
                pose.angleDeg = o.value(QStringLiteral("angle")).toDouble();
                pose.yOff = o.value(QStringLiteral("yOff")).toDouble();
                pose.focal = o.value(QStringLiteral("focal")).toDouble();
                pose.radius = o.value(QStringLiteral("radius")).toDouble();
                const QString id = o.value(QStringLiteral("id")).toString();
                // 坏数据钳制（v82）：合法 JSON 的畸形尺寸会让光栅 w*2×h*2
                // 巨量分配（w=50000 ≈ 20GB）打爆合成器——超 8× 屏幕量级弃
                // 条目；<2px 的退化矩形也弃（isValid 只查 w,h>0，1.0×1.5
                // 能过闸＝注册后 renderLiveTexture 永远走 tiny-content 早退，
                // v87 审查）
                static const qreal kMaxDim = 32768.0;
                if (id.isEmpty() || !pose.rect.isValid()
                        || pose.rect.width() < 2 || pose.rect.height() < 2
                        || pose.rect.width() > kMaxDim
                        || pose.rect.height() > kMaxDim)
                    continue;
                if (pose.focal < 100.0)
                    pose.focal = 2200.0;
                // v2 卡面元数据（chrome 由特效同管线绘制）
                CardMeta meta;
                meta.title = o.value(QStringLiteral("title")).toString();
                meta.count = std::max(1, o.value(QStringLiteral("count")).toInt(1));
                meta.z = o.value(QStringLiteral("z")).toDouble();
                meta.dragging = o.value(QStringLiteral("dragging")).toBool();
                meta.engaging = o.value(QStringLiteral("engaging")).toBool();
                meta.dropHover = o.value(QStringLiteral("dropHover")).toBool();
                meta.dwellHint = o.value(QStringLiteral("dwellHint")).toBool();
                // 缺省值全部对齐 StageConfigService._schema 的 def（漂移＝
                // 发布端漏字段/改名时静默落到另一套视觉）。⚠️ 不再做
                // hoverScale≤1.01 强制 1.18 的边界改写——用户设 1.0 关放大
                // 是合法配置，改写会造成 QML/特效观感分裂
                meta.hoverScale = qBound(1.0,
                    o.value(QStringLiteral("hoverScale")).toDouble(1.05), 2.0);
                meta.hoverTiltDeg = o.value(QStringLiteral("hoverTilt")).toDouble(0.0);
                meta.hoverMs = std::chrono::milliseconds(
                    std::max(80, o.value(QStringLiteral("hoverMs")).toInt(280)));
                meta.fanSpacing = o.value(QStringLiteral("fanSpacing")).toDouble(8.0);
                meta.fanHoverSpread = qBound(1.0,
                    o.value(QStringLiteral("fanHoverSpread")).toDouble(1.4), 2.0);
                meta.winId = o.value(QStringLiteral("winId")).toString();
                meta.tintAlpha = o.value(QStringLiteral("cardTint")).toDouble(0.55);
                meta.borderAlpha = o.value(QStringLiteral("cardBorder")).toDouble(0.13);
                meta.depthStrength = o.value(QStringLiteral("cardDepth")).toDouble(0.38);
                meta.topLight = o.value(QStringLiteral("cardTopLight")).toDouble(0.07);
                meta.fade = qBound(0.0, o.value(QStringLiteral("fade")).toDouble(1.0), 1.0);
                meta.closeHot = o.value(QStringLiteral("closeHover")).toBool();
                meta.selfMergeHint = o.value(QStringLiteral("selfMergeHint")).toBool();
                meta.rightSide = o.value(QStringLiteral("rightSide")).toBool();
                meta.merged = o.value(QStringLiteral("merged")).toBool();
                meta.showCardTitle = o.value(QStringLiteral("showCardTitle")).toBool(true);
                meta.enterInstant = o.value(QStringLiteral("enterInstant")).toBool();
                meta.chipHot = o.value(QStringLiteral("chipHot")).toBool();
                meta.iconsJson = o.value(QStringLiteral("iconsJson")).toString();
                meta.iconSize = qBound(12.0,
                    o.value(QStringLiteral("iconSize")).toDouble(40.0), 96.0);
                meta.iconSlots = std::max(1,
                    o.value(QStringLiteral("iconSlots")).toInt(4));
                meta.engagingTilt = o.value(QStringLiteral("engagingTilt")).toDouble();
                meta.tiltMs = std::chrono::milliseconds(
                    std::max(80, o.value(QStringLiteral("tiltMs")).toInt(250)));
                meta.enterMs = std::chrono::milliseconds(
                    std::max(80, o.value(QStringLiteral("enterMs")).toInt(240)));
                meta.animMs = std::chrono::milliseconds(
                    std::max(120, o.value(QStringLiteral("animMs")).toInt(420)));
                meta.dragScale = o.value(QStringLiteral("dragScale")).toDouble(1.0);
                entries.append({id, pose, meta});
                wanted.insert(id);
            }
        }
    }
    // 心跳超时（shell 死亡/停摆）：撤销全部引用，status 置 inactive。
    // 用文件 mtime 判活（'at' 字段实测间歇落进陈旧值；mtime 由内核在
    // writePath 落盘时盖章，可靠）。25s = 心跳 15s 的 1.7 倍容错
    {
        const QFileInfo info(m_livePath);
        if (!info.exists()
            || QDateTime::currentMSecsSinceEpoch()
                    - info.lastModified().toMSecsSinceEpoch()
                > 25000) {
            wanted.clear();
            entries.clear();
        }
    }
    // 文件在但 open 失败（权限抖动/EMFILE 等瞬时不可读）＝传输层毛病而
    // 非发布方意图，保持现状早退——落入空 wanted 会 600ms 后全体掉卡
    // 闪退一次（"绝不因读失败掉卡"契约，与 parse 失败同款语义）
    if (!fileMissing && !f.isOpen()) {
        qCWarning(STAGEANIM_LOG) << "live reload: open failed, keep state"
                                 << m_livePath;
        return;
    }
    if (!m_liveEnabled) {
        wanted.clear();
        entries.clear();
    }

    // 掉卡迟滞基准：记下本轮在册集合，缺席踢除交给 expireAbsentLiveCards
    //（reload 与 33ms 帧钟共用——只靠 reload 评估时，发布文件静默期
    //（载荷去重后无写）无 reload 可触发，被吞的卡满 alpha 卡在屏上直
    // 到下一次发布变化或 10s 兜底，"合并后三张卡/残影到切换才消失"的根因）。
    m_liveWanted = wanted;
    bool changed = expireAbsentLiveCards();
    for (const auto &e : entries) {
        const QString &eid = std::get<0>(e);
        // 渲染窗口匹配：优先 winId（v3 协议，id=组键）；旧载荷无 winId
        // 时回退按 id 匹配（id 即窗口 id）
        const CardMeta &emeta = std::get<2>(e);
        const QString winKey = emeta.winId.isEmpty() ? eid : emeta.winId;
        auto it = m_liveCards.find(eid);
        if (it == m_liveCards.end()) {
            EffectWindow *w = nullptr;
            const QList<EffectWindow *> all = effects->stackingOrder();
            for (EffectWindow *c : all) {
                // isDeleted 守卫（v82，与 rep 重接路径同款）：已删除窗口
                // window() 为空 → 注册成无源僵尸卡白占 wanted 名单
                if (c->isDeleted())
                    continue;
                if (c->internalId().toString(QUuid::WithoutBraces) == winKey) {
                    w = c;
                    break;
                }
            }
            if (!w) {
                m_livePending.insert(eid);
                continue;
            }
            // 交棒期注册免入（v82）：窗口已还原/正在还原（载荷 engaging
            // 或非最小化且有动画在飞）时注册＝全新卡入场动画在原槽位闪
            // 现，发布流随即丢弃 → 残影一闪（journal 实证：engage 瞬间
            // "live card +"迟到注册待定卡）。此前未注册的多为 winId 陈旧
            // 的待定卡，engage 让 rep 翻转、窗口变得可寻＝迟到注册。留在
            // 待定：真重新最小化（非 engaging 载荷）时正常注册
            if (emeta.engaging || (!w->isMinimized()
                    && m_animations.contains(w))) {
                m_livePending.insert(eid);
                continue;
            }
            auto card = QSharedPointer<LiveCard>::create();
            card->id = std::get<0>(e);
            card->window = w;
            card->target = std::get<1>(e);
            card->from = card->target; // 首次直接落位（与卡片淡入同拍）
            card->ease = TimeLine(std::chrono::milliseconds(80));
            applyCardMeta(*card, std::get<2>(e));
            // 注册时窗口正在装卡飞行＝收编落卡：强制 enterInstant（只淡
            // 入，时长=飞行时长）——侧滑/0.86 长大会画在飞行窗口之上
            // 横跳（v66 起交棒/收编期卡持续可见，见 liveCardPaintable）
            if (m_animations.contains(w))
                card->enterInstant = true;
            card->curTiltDeg = card->target.angleDeg; // 悬停引擎起点 = 静止角
            card->chromeKey.clear(); // 强制首帧光栅铭牌
            // 入场动画（老 QML 收编入场完整迁移）：x 侧滑 ±70（OutCubic）
            // + 淡入 OutCubic（enterInstant=飞行时长 animMs/普通=enterMs）
            // + 0.86 长到 1（OutBack）+ 拆分迸开错峰 70ms。
            // 窗口还没开始装卡飞行（发布先于最小化 ~120ms＝收编快照
            // 等待）时挂起起摆——按注册时刻起摆＝卡先于窗口出现在槽位
            //（"点桌面时最底下先冒卡再放收编动画"）。帧钟里等
            // isMinimized/最小化动画出现才同拍起摆（见 prePaintScreen）。
            card->alpha = 0.0;
            card->alphaFrom = 0.0;
            card->alphaTo = 1.0;
            if (!w->isMinimized() && !m_animations.contains(w)) {
                card->enterHold = true;
            } else {
                card->fadeTl = TimeLine(card->enterInstant
                    ? card->animMs : card->enterMs);
                card->fadeAnimating = true;
            }
            if (card->enterInstant) {
                // 收编落卡（老 QML enterInstant 语义）：**只淡入**，时长=
                // 窗口飞行时长（420ms 同拍收束）——窗口飞向槽位的全程卡在
                // 同位凝实，两头对接。无侧滑、无 86% 长大（那是非收编
                // 入场的版式；给收编卡加侧滑=窗口从上飞、卡从侧滑=割裂）
                card->curScale = 1.0;
                card->scaleFrom = card->scaleTo = 1.0;
                card->tiltFrom = card->tiltTo = card->target.angleDeg;
                card->hoverAnimating = false;
                card->spawnAtMs = 0;
            } else {
                card->spawnAtMs = 1; // 入场中标记（hoverTl 完成时清零）
                card->curScale = 0.86;
                card->scaleFrom = 0.86;
                card->scaleTo = 1.0;
                card->tiltFrom = card->target.angleDeg;
                card->tiltTo = card->target.angleDeg;
                card->spawnSlide = (card->rightSide ? -70.0 : 70.0);
                card->hoverTl = TimeLine(card->hoverMs);
                card->hoverAnimating = true;
            }
            card->dirty = true;
            attachLiveCardSources(*card);
            card->dpr = w->screen() ? w->screen()->scale() : 1.0;
            card->feedPhase = (m_liveFeedCounter++) % 4;
            m_liveCards.insert(eid, card);
            updateLiveFrameTimer();
            m_livePending.remove(eid);
            renderLiveTexture(*card); // 注册时机（非绘制）先拍一帧
            card->lastRenderMs = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now().time_since_epoch()).count();
            changed = true;
            qCInfo(STAGEANIM_LOG) << "live card +" << eid
                                     << "caption" << w->caption()
                                     << "rect" << card->target.rect
                                     << "angle" << card->target.angleDeg;
        } else {
            LiveCard &card = **it;
            const bool wasEngaging = card.engaging;
            applyCardMeta(card, std::get<2>(e));
            // dpr 刷新（v87 审查）：注册后冻结会在宿主改显示缩放/窗口
            // 迁屏后让 FBO 分辨率陈旧（卡面持续模糊直到重注册）——
            // 变化即置 dirty，renderLiveTexture 按尺寸差走 REALLOC 重拍
            if (!card.window.isNull() && card.window->screen()) {
                const qreal dprNow = card.window->screen()->scale();
                if (dprNow != card.dpr) {
                    card.dpr = dprNow;
                    card.dirty = true;
                }
            }
            // rep 翻转（组内激活换 rep 窗口）：同组键下原地换渲染窗口——
            // 重接源/重拍纹理，姿态/透明度全保留＝零闪烁。旧协议 id=窗口
            // id 时这是"销毁重注册+入场动画"，同位新旧双重绘＝左侧闪动根因
            if (!emeta.winId.isEmpty()
                && (card.window.isNull()
                    || card.window->internalId().toString(QUuid::WithoutBraces)
                        != emeta.winId)) {
                EffectWindow *nw = nullptr;
                const QList<EffectWindow *> allWins = effects->stackingOrder();
                for (EffectWindow *c2 : allWins) {
                    if (c2->internalId().toString(QUuid::WithoutBraces)
                        == emeta.winId) {
                        nw = c2;
                        break;
                    }
                }
                if (nw && !nw->isDeleted()) {
                    detachLiveCard(card);
                    card.window = nw;
                    attachLiveCardSources(card);
                    card.dirty = true;
                    card.dpr = nw->screen() ? nw->screen()->scale() : card.dpr;
                    renderLiveTexture(card);
                    changed = true;
                    qCInfo(STAGEANIM_LOG) << "live re-attach"
                                             << eid.left(12) << "win ->"
                                             << emeta.winId.left(8);
                }
            }
            if (card.dying) {
                // 复活（发布流抖动/快速去而复返）：重挂更新源，统一状态机
                // 从当前 alpha 无缝回淡到 1——展开反悔（快速连点）的回淡
                // 也由同一状态机自动处理，不再有专用路径
                card.dying = false;
                attachLiveCardSources(card);
                card.dirty = true;
            }
            if (card.engaging && !wasEngaging) {
                // 展开交棒：卡面**不独立淡出**——alpha 由窗口飞行进度驱动
                //（窗口长到哪卡隐到哪，同一条时间线＝"从卡里长出来"的整体
                // 感；独立 180ms 淡出会在 420ms 飞行中段留空＝割裂）。
                // 收缩对齐保留：缩回静止尺寸/倾角与飞行起点矩形对齐。
                card.scaleFrom = card.curScale;
                card.scaleTo = 1.0;
                card.tiltFrom = card.curTiltDeg;
                // 交棒保持倾角（老语义：scroll=deckRestTilt / adaptive=
                // tiltAngle——与窗口飞行起始姿态对齐，不压平到 0）
                card.tiltTo = card.engagingTilt;
                card.hoverTl = TimeLine(std::chrono::milliseconds(180));
                card.hoverAnimating = true;
            }
            const LiveCardPose &epose = std::get<1>(e);
            const bool poseChanged = card.target.rect != epose.rect
                || std::abs(card.target.angleDeg - epose.angleDeg) > 0.01
                || std::abs(card.target.yOff - epose.yOff) > 0.5
                || std::abs(card.target.radius - epose.radius) > 0.5;
            if (poseChanged) {
                // 16ms 发布节拍下姿态流是逐帧的（含 QML 悬停 OutBack 过冲），
                // 缓动只负责抹平取整抖动——80ms 短跟随；日志只记大位移
                //（逐帧姿态流会灌爆 journal）
                const bool bigMove = (card.target.rect.topLeft()
                        - epose.rect.topLeft()).manhattanLength() > 12
                    || std::abs(card.target.angleDeg - epose.angleDeg) > 2.0
                    || std::abs(card.target.yOff - epose.yOff) > 8.0;
                if (bigMove)
                    qCInfo(STAGEANIM_LOG) << "live pose change" << card.id.left(8)
                                             << card.target.rect << "->" << epose.rect
                                             << "yOff" << card.target.yOff << "->" << epose.yOff;
                card.from = currentPose(card);
                card.target = epose;
                // 静息倾角跟随（v82）：curTiltDeg 只在悬停翻转/注册时刷新，
                // 静息期发布角变化（静置角滑杆/切侧）不追＝画面停在旧角
                // 到下一次 hover——"拖滑杆没反应"的最后一块。未悬停未补间
                // 时对发布角起一段同源补间
                if (!card.hovered && !card.hoverAnimating && !card.dragging
                        && !card.enterHold
                        && std::abs(card.curTiltDeg - epose.angleDeg) > 0.05) {
                    card.tiltFrom = card.curTiltDeg;
                    card.tiltTo = epose.angleDeg;
                    card.hoverTl = TimeLine(card.tiltMs);
                    card.hoverAnimating = true;
                }
                // 自适应补间：上一变化 <60ms = 逐帧流在跟（拖拽避让/滚动
                // 期间壳恢复逐帧发布）→ 16ms 微跟随（所见即所得，无速度
                // 突变）；孤立跳变（布局提交/收编落位）→ hoverMs≈280ms
                // OutCubic 优雅补间
                const qint64 poseNow = std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::steady_clock::now().time_since_epoch()).count();
                const bool streaming = card.lastPoseChangeMs > 0
                    && poseNow - card.lastPoseChangeMs < 60;
                card.lastPoseChangeMs = poseNow;
                card.ease = TimeLine(streaming
                    ? std::chrono::milliseconds(16) : card.hoverMs);
                card.easing = true;
            }
        }
    }


    // pending 只增不减会自我维持：撤下的 id 永存 → 每个新窗口 added 都
    // 白跑一次 reload，reload 又把死 id 重新 insert。每轮按本轮文件内容
    // 重建（本轮仍想要但窗口未出现的条目由上面的 entries 循环重新插入）
    m_livePending.intersect(wanted);

    if (changed) {
        writeLiveStatus();
        effects->addRepaintFull();
    }
}

// 缺席超时踢除（对 m_liveWanted 钟控评估，reload 与帧钟双入口）。
// 掉卡迟滞：发布流里瞬时缺席（桥的 rep 记录抖动/minimized 翻转的那
// 一拍）不代表卡真没了——立即掉＝"不稳定消失"（淡出→重注册→入场
// 动画，30 分钟 83 次重注册的真相）。缺席满 600ms 才真掉（侧栏关闭
// 写空表也走同一迟滞）。
bool StageAnimEffect::expireAbsentLiveCards()
{
    if (m_liveCards.isEmpty())
        return false;
    const qint64 nowSteady = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
    static quint32 s_expireTick = 0;
    if (++s_expireTick % 300 == 1) // ~10s 心跳：踢除器活着与否一看便知
        qCInfo(STAGEANIM_LOG) << "live expire tick #" << s_expireTick
                                 << "wanted=" << m_liveWanted.size()
                                 << "cards=" << m_liveCards.size();
    bool changed = false;
    for (auto it = m_liveCards.begin(); it != m_liveCards.end(); ++it) {
        if (m_liveWanted.contains(it.key())) {
            (*it)->absentSinceMs = 0;
            continue;
        }
        if ((*it)->dying)
            continue; // 已在退场：让状态机安静走完。重复置 dying/
                       // fadeAnimating=false 会把 150ms 淡出每 33ms 无限
                       // 重启＝alpha 永不到 0＝永不清扫＝满 alpha 残影卡屏
        if ((*it)->absentSinceMs == 0)
            (*it)->absentSinceMs = nowSteady;
        if (nowSteady - (*it)->absentSinceMs > 600) {
            LiveCard &card = **it;
            // 退场：撤引用/损伤连接（窗口多半已还原/关闭），dying 标记交给
            // 统一透明度状态机渐隐。发布流回心转意时同卡原地复活（见
            // reloadLiveCards 的 entries 循环）。
            qCInfo(STAGEANIM_LOG) << "live expire DROP" << it.key().left(8)
                                     << "absent" << (nowSteady - (*it)->absentSinceMs)
                                     << "ms wanted=" << m_liveWanted.size();
            detachLiveCard(card);
            card.dying = true;
            card.enterHold = false; // 保持卡被踢：回状态机走完淡出→SWEEP
            card.fadeAnimating = false; // 由状态机接管起淡（一次性）
            card.hoverAnimating = false;
            changed = true;
        }
    }
    if (changed) {
        writeLiveStatus();
        effects->addRepaintFull();
    }
    return changed;
}

// 解除离屏引用与损伤连接但保留纹理（dying 淡出还要画一会儿）
void StageAnimEffect::detachLiveCard(LiveCard &card)
{
    if (!card.window.isNull()) {
        if (card.offscreenRef && card.window->window())
            card.window->window()->unrefOffscreenRendering();
        QObject::disconnect(card.damageConnection);
    }
    card.offscreenRef = false;
}

// 挂载活体更新源：refOffscreenRendering（隐藏窗继续出帧）+ Window::damaged
// 连接。注册与 dying 复活共用。
// ⚠️ 损伤信号必须用内部 Window::damaged（官方 screencast 同款，客户端每
// 次提交都发射）；EffectWindow::windowDamaged 只在窗口被绘制的路径上发射
// ——最小化窗永远不触发（"活体间歇性"的旧根因）。
// ⚠️ 回调里**只标脏 + 请求重绘**：损伤回调（合成器线程、非绘制时机）里
// 立即整窗渲染进 FBO，在客户端去节流后（Chrome 60fps）会把合成器线程
// 打满＝整机掉帧的根因；重拍统一由帧预算调度器 scheduleLiveRenders 执行。
void StageAnimEffect::attachLiveCardSources(LiveCard &card)
{
    if (!card.window || card.window.isNull() || !card.window->window())
        return;
    // 幂等守卫：同一 reload 里"换窗重接"与"复活"可先后命中（rep 翻转×
    // 去而复返回拍），双跑＝refOffscreenRendering 计数 +2 而 detach 只 −1
    // ＝该窗终身多 1 个离屏引用（隐藏后客户端永久出帧），且第一条损伤
    // 连接被覆盖泄漏（脏计数翻倍）
    if (card.offscreenRef)
        return;
    card.window->window()->refOffscreenRendering();
    card.offscreenRef = true;
    qCInfo(STAGEANIM_LOG) << "live offscreen-ref ok="
                          << card.window->window()->isOffscreenRendering()
                          << "id" << card.id.left(8);
    card.damageConnection = connect(
        card.window->window(), &Window::damaged, this,
        [this, id = card.id](KWin::Window *) {
            auto it2 = m_liveCards.find(id);
            if (it2 == m_liveCards.end())
                return;
            (*it2)->damageCount++;
            (*it2)->lastDamageMs = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now().time_since_epoch()).count();
            (*it2)->dirty = true;
            const QRectF r = currentPose(**it2).rect;
            addRepaintRectF(effects, r.adjusted(-40, -40, 40, 40));
        });
}

// 重拍预算调度器（33ms 帧拍驱动）：候选 = 脏且可画的卡；优先卡（悬停/
// 拖拽/engaging/悬停动画中）排前，其余按 lastRenderMs 最久未拍轮转。每拍
// 至多 kBudget 张 → 合成器线程整窗渲染总量恒 ≤ kBudget×30/s，与客户端
// 损伤率（60-120Hz）解耦；没轮到的卡 dirty 保持，下一拍继续排队。
void StageAnimEffect::scheduleLiveRenders()
{
    QVector<LiveCard *> cands;
    for (auto it = m_liveCards.begin(); it != m_liveCards.end(); ++it) {
        LiveCard &card = **it;
        if (card.dying || !card.dirty || !card.window
            || !liveCardPaintable(card) || !card.window->windowItem())
            continue;
        cands.append(&card);
    }
    if (cands.isEmpty())
        return;
    const qint64 now = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
    std::sort(cands.begin(), cands.end(), [](const LiveCard *a, const LiveCard *b) {
        const bool pa = a->hovered || a->dragging || a->engaging || a->hoverAnimating;
        const bool pb = b->hovered || b->dragging || b->engaging || b->hoverAnimating;
        if (pa != pb)
            return pa; // 优先卡在前
        return a->lastRenderMs < b->lastRenderMs; // 最久未拍先拍（轮转公平）
    });
    constexpr int kBudget = 2;
    const int n = std::min<int>(cands.size(), kBudget);
    for (int i = 0; i < n; ++i) {
        cands[i]->lastRenderMs = now;
        renderLiveTexture(*cands[i]);
    }
}

void StageAnimEffect::releaseLiveCard(LiveCard &card)
{
    // 主体收敛到 detachLiveCard（v87 审查：两函数逐行复制＝平行副本
    // 修一处漏一处的温床，attach 双跑泄漏正是这么来的）
    detachLiveCard(card);
    card.texture.reset();
    card.fbo.reset();
}

// 帧钟随卡启停：有卡才跑 33ms 自驱投喂/缺席踢除；全清即停（v87 审查）
void StageAnimEffect::updateLiveFrameTimer()
{
    if (m_liveCards.isEmpty())
        m_liveFrameTimer.stop();
    else if (!m_liveFrameTimer.isActive())
        m_liveFrameTimer.start();
}

// 窗口内容 → 卡面尺寸小 FBO（PreserveAspectCrop：与静态快照 Image
// fillMode 严格一致，宽高比取小裁边）。渲染走 effects->drawWindow 自建
// target/viewport（offscreeneffect maybeRender 同款嵌套，不经过
// paintWindow 钩子、无递归）。
void StageAnimEffect::renderLiveTexture(LiveCard &card)
{
    EffectWindow *w = card.window;
    // windowItem 守卫收口在本体：注册/重接/预算调度三个调用点防护不一
    // 致（窗口在但场景项未建时裸 renderItem＝空指针进渲染器）
    if (!w || !w->windowItem())
        return;
    // FBO 尺寸按静止矩形分配（悬停放大期间姿态矩形逐帧变，跟着分配
    // 会每帧 realloc；纹理按归一化采样，绘制侧拉伸即可）
    const QRectF content = card.target.rect;
    if (content.width() < 2 || content.height() < 2) {
        // dirty 必须清（v87 审查）：早退不清＝调度器每 33ms 重选它
        // 重跑重告警——退化几何卡永久占用重拍预算（kBudget=2 可被两张
        // 此类卡占满＝其它卡内容冻结）。姿态变化/损伤会重新置 dirty，
        // 重试语义不受影响
        card.dirty = false;
        qCWarning(STAGEANIM_LOG) << "live render skip tiny-content" << card.id.left(8);
        return;
    }
    QRectF client = w->clientGeometry();
    if (client.width() < 2 || client.height() < 2)
        client = w->frameGeometry();
    if (client.width() < 2 || client.height() < 2) {
        // 同上：client 会长回来（窗口收尾中的工具窗），损伤回调会再触发
        card.dirty = false;
        qCWarning(STAGEANIM_LOG) << "live render skip tiny-client" << card.id.left(8)
                                 << "client" << w->clientGeometry()
                                 << "frame" << w->frameGeometry();
        return;
    }

    const qreal plateAspect = content.width() / content.height();
    QRectF src = client;
    const qreal winAspect = client.width() / client.height();
    if (winAspect > plateAspect) {
        const qreal cw = client.height() * plateAspect;
        src = QRectF(client.center().x() - cw / 2, client.y(), cw, client.height());
    } else if (winAspect < plateAspect) {
        const qreal ch = client.width() / plateAspect;
        src = QRectF(client.x(), client.center().y() - ch / 2, client.width(), ch);
    }

    const int tw = std::max(2, int(std::lround(content.width() * card.dpr)));
    const int th = std::max(2, int(std::lround(content.height() * card.dpr)));
    if (!card.texture || card.texture->size() != QSize(tw, th)) {
        if (card.texture)
            qCWarning(STAGEANIM_LOG) << "live tex REALLOC" << card.id.left(8)
                                     << card.texture->size() << "->" << QSize(tw, th)
                                     << "rect" << content;
        card.texture = GLTexture::allocate(GL_RGBA8, QSize(tw, th));
        if (!card.texture)
            return;
        card.texture->setFilter(GL_LINEAR);
        card.texture->setWrapMode(GL_CLAMP_TO_EDGE);
        card.fbo = std::make_unique<GLFramebuffer>(card.texture.get());
        card.dirty = true; // 尺寸变化后必须重拍
    }
    if (!card.fbo)
        return;

    // 官方 WindowScreenCastSource::render 同款配方：ItemRenderer 直渲
    // 窗口项 + beginFrame/endFrame 包夹——⚠️ endFrame 是纹理换新的落点，
    // 走 effects->drawWindow 的旧路径不换新最小化窗的客户端缓冲（FBO
    // 恒渲旧帧、损伤计数却照爬的根因）。6.7+ 该入口被收进 KWin 进程内
    // 部（见 STAGE_LIVE_CONTENT_RENDER），编译为静态玻璃卡
#if STAGE_LIVE_CONTENT_RENDER
    RenderTarget renderTarget(card.fbo.get());
    const qreal scale = qreal(tw) / src.width();
    RenderViewport viewport(src, scale, renderTarget, QPoint());
    auto *scene = Compositor::self()->scene();
    // 官方 screencast 的 render() 由流的独立时机调用；从损伤回调等非绘制
    // 时机调用时必须自己把 FBO 绑上（beginFrame 不代劳）——漏绑 =
    // incomplete framebuffer，渲出来全黑（嵌套试验台实测定位）
    GLFramebuffer::pushFramebuffer(card.fbo.get());
    scene->renderer()->beginFrame(renderTarget, viewport);
    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    scene->renderer()->renderItem(renderTarget, viewport, w->windowItem(),
                                  Scene::PAINT_WINDOW_TRANSFORMED,
                                  Region::infinite(), WindowPaintData{}, {}, {});
    scene->renderer()->endFrame();
    card.renderCount++;
#else
    // 6.7+ 降级：内容不重拍，FBO 保持空（ct.a=0 → 着色器退化为纯背板）
    GLFramebuffer::pushFramebuffer(card.fbo.get());
    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    GLFramebuffer::popFramebuffer();
    card.dirty = false;
    return;
#endif
    if (card.renderCount % 2000 == 1) {
        GLubyte px[4] = {0, 0, 0, 0};
        GLubyte tl[4] = {0, 0, 0, 0};
        // 探针必须仍在 push 窗口内（pop 后读外层绑定 = incomplete
        // framebuffer 全黑假象）；⚠️ 此前 push/pop 修复提交漏删旧 pop
        // 造成双 pop 弹穿帧缓冲栈 = 嵌套崩溃真凶（2026-10-04 定位）
        glReadPixels(tw / 2, th / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
        glReadPixels(int(tw * 0.15), int(th * 0.97), 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, tl);
        qCInfo(STAGEANIM_LOG) << "live tex #" << card.renderCount
                                 << "id" << card.id.left(8)
                                 << "center=" << px[0] << px[1] << px[2] << px[3]
                                 << "top=" << tl[0] << tl[1] << tl[2] << tl[3]
                                 << "damage" << card.damageCount;
    }
    GLFramebuffer::popFramebuffer();
    card.dirty = false;
}

bool StageAnimEffect::liveCardPaintable(const LiveCard &card) const
{
    // 交棒期（engaging，窗口已还原）与飞行期（m_animations 含本窗，
    // 窗口正在进出卡位）卡都要**继续画**：特效后置通道画在窗口之上，
    // 交棒淡出＝卡覆在长大的窗口上隐去、收编淡入＝卡在飞来的窗口上
    // 凝实——旧门把这两种状态整段掐掉，卡在飞行起点瞬间消失/终点
    // 瞬间蹦出＝"闪动"的特效侧根源。真正不画的只有：窗口没了，或
    // 窗口在桌面上（非最小化且非 engaging/dying 的陈旧卡）。
    return !card.window.isNull() && !card.window->isDeleted()
        && (card.window->isMinimized() || card.engaging || card.dying);
}

void StageAnimEffect::drawLiveCards(const RenderTarget &renderTarget,
                                    const RenderViewport &viewport)
{
    Q_UNUSED(renderTarget);
    // ⚠️ 本函数运行在合成器绘制周期内：只画现成纹理。任何渲染器重入
    //（beginFrame/renderItem/endFrame、drawWindow）在这里都是状态机破坏
    //＝桌面崩溃（2026-10-03 事故元凶）。重拍全部发生在非绘制时机
    //（损伤回调/注册/状态心跳）。

    // 着色器（实例级重试——static 闩锁跨实例共享是黑卡事故元凶，勿回退；
    // 失败退避 v82：安装损坏时每帧重编译＝日志洪水+合成器空转，连续
    // 3 败后降频 5s 一次）。
    // ⚠️ 只判空不判 isValid：GLShader::isValid 在 6.7+ 被删，且装载失败
    // generateShaderFromFile 返回 nullptr，判空在两代语义等价
    auto ensureShader = [this](std::unique_ptr<GLShader> &slot, const QString &frag) {
        if (slot)
            return true;
        const qint64 nowMs = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now().time_since_epoch()).count();
        if (m_shaderFails >= 3 && nowMs - m_shaderLastFailMs < 5000)
            return false;
        slot.reset();
        slot = ShaderManager::instance()->generateShaderFromFile(
            ShaderTrait::MapTexture,
            QStringLiteral(":/stageanim/shaders/stage-live.vert"),
            frag);
        qCWarning(STAGEANIM_LOG) << "shader created:" << frag
                                 << (slot ? "valid" : "null");
        if (!slot) {
            slot.reset();
            m_shaderFails++;
            m_shaderLastFailMs = nowMs;
            return false;
        }
        m_shaderFails = 0;
        return true;
    };
    const bool shOk = ensureShader(m_liveShader,
                      QStringLiteral(":/stageanim/shaders/stage-live.frag"))
        && ensureShader(m_cardShader,
                      QStringLiteral(":/stageanim/shaders/stage-card.frag"))
        && ensureShader(m_cursorShader,
                      QStringLiteral(":/stageanim/shaders/stage-cursor.frag"));
    if (!shOk)
        return;

    // z 升序绘制（低者先画被高者盖住；同 z 按发布序稳定排序）
    QVector<QSharedPointer<LiveCard>> order;
    order.reserve(m_liveCards.size());
    for (auto it = m_liveCards.begin(); it != m_liveCards.end(); ++it)
        order.append(it.value());
    std::stable_sort(order.begin(), order.end(),
                     [](const QSharedPointer<LiveCard> &a,
                        const QSharedPointer<LiveCard> &b) { return a->z < b->z; });

    const qreal dpr = viewport.scale();
    const GLboolean blendWas = glIsEnabled(GL_BLEND);
    // blend 四通道全查全还（v82）：glBlendFunc 同时改 RGB/ALPHA，只存
    // RGB 会把上游 glBlendFuncSeparate 的独立 alpha func 抹平
    GLint blendSrcWas = GL_ONE, blendDstWas = GL_ONE_MINUS_SRC_ALPHA;
    GLint blendSrcAWas = GL_ONE, blendDstAWas = GL_ONE_MINUS_SRC_ALPHA;
    glGetIntegerv(GL_BLEND_SRC_RGB, &blendSrcWas);
    glGetIntegerv(GL_BLEND_DST_RGB, &blendDstWas);
    glGetIntegerv(GL_BLEND_SRC_ALPHA, &blendSrcAWas);
    glGetIntegerv(GL_BLEND_DST_ALPHA, &blendDstAWas);
    GLint activeTexWas = GL_TEXTURE0;
    glGetIntegerv(GL_ACTIVE_TEXTURE, &activeTexWas);
    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    glActiveTexture(GL_TEXTURE0);
    const GLboolean scissorWas = glIsEnabled(GL_SCISSOR_TEST);
    glDisable(GL_SCISSOR_TEST); // 渲染器按损伤区管理剪刀；直绘越区重画无害

    quint32 paintable = 0;
    for (const auto &cp : order)
        drawLiveCardBody(viewport, dpr, *cp, paintable);
    // 软件光标补绘（必须在全部卡之后：后置通道本身盖住了场景内光标）
    drawSoftwareCursor(viewport, dpr);
    if (scissorWas)
        glEnable(GL_SCISSOR_TEST);
    if (!blendWas)
        glDisable(GL_BLEND);
    // blendFunc 精确还原（本 pass 改成预乘 ONE/ONE_MINUS_SRC_ALPHA——
    // 猜默认值不如查询，上游若依赖进入前的 func 即翻车）
    glBlendFuncSeparate(blendSrcWas, blendDstWas, blendSrcAWas, blendDstAWas);
    glActiveTexture(activeTexWas);
    static quint32 s_pass = 0;
    if (++s_pass % 3000 == 1)
        qCInfo(STAGEANIM_LOG) << "live paint pass #" << s_pass
                                 << "paintable =" << paintable;
}


// ── drawLiveCards 拆出的三个成员（纯搬运）────────────────────

// 单 pass 原语：一个覆盖矩形（投影外接框），fanOnly 时传扇叠副本偏移。
// 返回前不清 GL 状态（调用方循环外统一恢复）。
void StageAnimEffect::liveCardPass(const RenderViewport &viewport, qreal dpr,
                                   GLShader &sh, const LiveCardPose &pose,
                                   qreal ix, qreal iy, qreal iw, qreal ih,
                                   const QVector2D &fanOff, bool fanOnly,
                                   const QColor &tint, const QColor &border,
                                   qreal borderWidth, qreal depthG,
                                   qreal topLight, GLTexture *tex, qreal alpha,
                                   qreal hoverBlend, float sideRight)
{
    ShaderBinder binder(&sh);
    sh.setUniform("modelViewProjectionMatrix", viewport.projectionMatrix());
    sh.setUniform("texUnit", 0);
    sh.setUniform("angleRad", float(qDegreesToRadians(pose.angleDeg)));
    sh.setUniform("focal", float(pose.focal * dpr));
    sh.setUniform("yOff", float(pose.yOff * dpr));
    sh.setUniform("camRel", QVector2D(float(iw / 2), float(ih / 2 - pose.yOff * dpr)));
    sh.setUniform("itemSize", QVector2D(float(iw), float(ih)));
    sh.setUniform("cardSize", QVector2D(float(pose.rect.width() * dpr),
                                        float(pose.rect.height() * dpr)));
    GLVertexBuffer *vbo = GLVertexBuffer::streamingBuffer();
    const QList<GLVertex2D> verts = {
        GLVertex2D{QVector2D(float(ix), float(iy)), QVector2D(0, 0)},
        GLVertex2D{QVector2D(float(ix + iw), float(iy)), QVector2D(1, 0)},
        GLVertex2D{QVector2D(float(ix + iw), float(iy + ih)), QVector2D(1, 1)},
        GLVertex2D{QVector2D(float(ix), float(iy + ih)), QVector2D(0, 1)},
    };
    vbo->reset();
    vbo->setVertices(verts);
    vbo->bindArrays();
    if (tex)
        tex->bind();
    if (&sh == m_cardShader.get()) {
        // 卡面整体 pass：chrome 参数（stage-card 独有 uniform）
        sh.setUniform("crad", float(pose.radius * dpr));
        sh.setUniform("fanOff", fanOff);
        sh.setUniform("fanOnly", fanOnly ? 1.0f : 0.0f);
        sh.setUniform("tint", QVector4D(tint.redF(), tint.greenF(),
                                         tint.blueF(), tint.alphaF()));
        sh.setUniform("borderColor", QVector4D(border.redF(), border.greenF(),
                                               border.blueF(), border.alphaF()));
        sh.setUniform("borderWidth", float(borderWidth * dpr));
        sh.setUniform("depthG", float(depthG));
        sh.setUniform("topLight", float(topLight));
        sh.setUniform("hasContent", tex && !fanOnly ? 1.0f : 0.0f);
        sh.setUniform("hoverBlend", float(hoverBlend));
        sh.setUniform("sideRight", sideRight);
    } else {
        sh.setUniform("crad", 0.0f);
    }
    sh.setUniform("alpha", float(alpha));
    vbo->draw(GL_TRIANGLE_FAN, 0, 4);
    vbo->unbindArrays(); // 头文件契约：与 bindArrays 成对（属性数组泄漏）
    if (tex)
        tex->unbind();
}

// 投影外接框（tiltProject 前向，全部设备像素）。⚠️ 外扩必须连同扇叠一起
// 罩住（卡面局部系偏出主卡 ±fanMax）——老 QML plane 的 fanPad 同款；
// quad 不够＝扇叠卡被直线裁边＝"堆叠卡变矩形"
QRectF StageAnimEffect::cardBodyQuad(const LiveCardPose &pose, qreal fanMax,
                                     qreal dpr) const
{
    const qreal fw = pose.rect.width() * dpr + fanMax * 2;
    const qreal fh = pose.rect.height() * dpr + fanMax * 2;
    const qreal focal = pose.focal * dpr;
    const qreal yOff = pose.yOff * dpr;
    const QPointF c = pose.rect.center() * dpr;
    const qreal rad = qDegreesToRadians(pose.angleDeg);
    const qreal sn = std::sin(rad), cs = std::cos(rad);
    qreal minX = 1e18, maxX = -1e18, minY = 1e18, maxY = -1e18;
    const qreal us[2] = {-fw / 2, fw / 2};
    const qreal vs[2] = {-fh / 2, fh / 2};
    for (const qreal u : us) {
        const qreal k = focal / (focal + u * sn);
        const qreal x = u * cs * k;
        minX = std::min(minX, x);
        maxX = std::max(maxX, x);
        for (const qreal v : vs) {
            const qreal y = (v + yOff) * k;
            minY = std::min(minY, y);
            maxY = std::max(maxY, y);
        }
    }
    const qreal margin = 10.0 * dpr;
    const qreal halfW = std::max(maxX, -minX) + margin;
    const qreal halfH = std::max(maxY, -minY) + margin;
    return QRectF(c.x() - halfW, c.y() - halfH, halfW * 2, halfH * 2);
}

// 单卡全 pass 序列：姿态（拖拽/入场侧滑/静止）→ 外接框 → 光栅铭牌 →
// 武装态配色 → 扇叠背板 → 主卡 → 铭牌/覆盖层 → 落屏探针
void StageAnimEffect::drawLiveCardBody(const RenderViewport &viewport,
                                       qreal dpr, LiveCard &card,
                                       quint32 &paintable)
{
    if (!card.dying && !liveCardPaintable(card)) {
        if (!card.dragging) // 拖拽卡可能短暂非最小化（交棒过渡）
            return;
    }
    // dying 卡：纹理/姿态冻结（悬停引擎已免它），只走统一淡出
    if (card.alpha <= 0.01 || !card.texture || !card.fbo)
        return;
    paintable++;
    card.paintCount++;

    // 有限姿态：静止矩形绕 TopLeft 放大（QML transformOrigin 语义）。
    // ⚠️ 基底必须直取 card.target（v85 回滚 v82 的 currentPose 接线）：
    // 发布流本身逐帧跟随 QML Behavior（已是平滑流），再叠效果侧缓动
    // ＝双重平滑+系统性拖一帧，所有卡面动画整体"糊/拖/不跟手"（用户
    // 实测"没有之前丝滑"）。currentPose 维持 damage-only 职责——孤立
    // 跳变的优雅补间在流式架构下没有收益，只有代价
    LiveCardPose pose = card.target;
    const qreal fadeMul = card.alpha * card.fade; // 入退场 × 压暗/边缘渐隐
    const qreal sc = card.dragging ? 1.0 : card.curScale;
    if (card.dragging) {
        // 拖拽卡画在发布矩形上（QML 逐帧跟手发布，鼠标/触摸通吃）；
        // 旧的光标钉位方案对触摸失效（触摸不动 cursorPos）
        pose.rect = QRectF(pose.rect.topLeft(),
                           QSizeF(pose.rect.width() * card.dragScale,
                                  pose.rect.height() * card.dragScale));
        pose.angleDeg = 0.0;
    } else if (card.spawnAtMs > 0 && card.hoverAnimating) {
        // 入场侧滑：从屏侧 ±70 滑进（OutCubic，与 QML x Behavior 同拍；
        // spawn 淡入/长大共用 hoverTl）。⚠️ 缩放必须在此分支同乘——
        // 只 translate 不乘 curScale 的话 0.86→1 长大是死动画（全尺寸
        // 滑入、结束瞬跳）
        const qreal t = qBound(0.0, card.hoverTl.value(), 1.0);
        const qreal cubic = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t);
        const qreal slide = card.spawnSlide * (1.0 - cubic);
        pose.rect = QRectF(pose.rect.topLeft(),
            QSizeF(pose.rect.width() * card.curScale,
                   pose.rect.height() * card.curScale));
        pose.rect.translate(slide, 0.0);
    } else {
        pose.rect = QRectF(pose.rect.topLeft(),
                           QSizeF(pose.rect.width() * sc, pose.rect.height() * sc));
        pose.angleDeg = card.curTiltDeg;
    }

    // 扇叠可见层数：用户定稿更多层（旧 cap 2＝共 3 张不够表达），
    // 上限 4（更多层视觉糊成一团，超出部分由图标排/+N 表达）
    const int fans = std::min(card.count - 1, 4);
    const qreal fanMax = fans * card.fanSpacing
        * std::max(1.0, card.fanHoverSpread) * dpr;
    const QRectF quad = cardBodyQuad(pose, fanMax, dpr);
    const qreal ix = quad.left(), iy = quad.top();
    const qreal iw = quad.width(), ih = quad.height();
    // ⚠️ 展示损伤声明（半透明↔不透明切换的真凶）：自定义后置绘制必须
    // 把自己画过的区域加进损伤集——本容器显示栈按损伤集做部分提交，
    // 卡面不在集合里＝页翻转保留旧内容，多缓冲轮换时卡面在"本帧绘制
    // /陈旧帧（卡面缺失露壁纸）"间摆动。后台缓冲读回（QUAD 探针）永远
    // 稳定正是这个病的签名：画了≠呈现了。每帧申报＝该区域恒进损伤集
    addRepaintRectF(effects, QRectF(quad.left() / dpr, quad.top() / dpr,
                               quad.width() / dpr, quad.height() / dpr));

    rasterChrome(card); // 绘制时机内执行；键（标题/计数/尺寸/态位）变才重光栅+上传

    // 武装态视觉（老 QML 两档完整迁移）：
    //   armed（dropHover/selfMerge）= 亮蓝 rgba(0.45,0.85,1.0,0.95) + 2px + 提亮
    //   dwell（驻留中）= rgba(0.45,0.85,1.0,0.78) + 2px + 提亮
    //   hover 边框蓝 = rgba(0.62,0.80,1.0,0.85)（随 hoverBlend 渐变）
    const bool armed = card.dropHover || card.selfMergeHint;
    const bool hinted = card.dwellHint;
    const QColor mainTint = (card.hovered || armed || hinted)
        ? card.tintHover : card.tint;
    QColor mainBorder = card.border;
    qreal borderWidth = 1.0;
    if (armed) {
        mainBorder = QColor(115, 217, 255, 242);
        borderWidth = 2.0;
    } else if (hinted) {
        mainBorder = QColor(115, 217, 255, 199);
        borderWidth = 2.0;
    } else if (card.hoverBlend > 0.01) {
        const QColor blue(158, 204, 255, 217);
        mainBorder = QColor(
            int(mainBorder.red() + (blue.red() - mainBorder.red()) * card.hoverBlend),
            int(mainBorder.green() + (blue.green() - mainBorder.green()) * card.hoverBlend),
            int(mainBorder.blue() + (blue.blue() - mainBorder.blue()) * card.hoverBlend),
            int(mainBorder.alpha() + (blue.alpha() - mainBorder.alpha()) * card.hoverBlend));
    }
    // 深度渐变悬停淡出（老 250ms Behavior → hoverBlend 渐变）；
    // 顶光悬停 ×2（上限 0.4）；右条镜像深度侧
    const qreal depthEff = card.depthStrength * (1.0 - card.hoverBlend);
    const qreal topEff = std::min(0.4,
        card.topLight * (1.0 + card.hoverBlend));
    // 扇叠扩散：hover 或武装/驻留都扩（老 dropHovered 同款）
    //（扩散目标在悬停引擎里由 fanBlend 补间逼近——armed/hinted 不再
    // 瞬时满扩）

    // 0) 辉光 pass 已撤（v57）：光栅环带在投影视口下渲染异常＝
    //    "奇怪的光影"；悬停视觉先由边框蓝+提亮+深度淡出承担
    // 1) 扇叠背板（同应用多窗：min(count-1,4) 张，**左上**探出——
    //    老 QML `plate.x − off`（用户定稿方向；条在右镜像到右上）。
    //    ⚠️ 与主卡同一 quad（外接框已含扇叠外扩），只走 SDF 偏移——
    //    旧实现 quad 平移 + SDF 偏移双重叠加＝画在 2× 偏移处且超出
    //    quad 被直线裁边（"堆叠卡变矩形"的真凶）。扩散由 fanBlend 补间
    //    驱动（150ms OutCubic，见悬停引擎）——hover/武装/驻留统一缓动；
    //    系数可调（fanHoverSpread）
    const qreal spreadEff = 1.0 + (card.fanHoverSpread - 1.0) * card.fanBlend;
    for (int i = fans - 1; i >= 0; --i) {
        const qreal off = (i + 1) * card.fanSpacing * spreadEff * dpr;
        // 老扇叠底色更暗：rgba(0.03,0.05,0.09,…) ≠ 主背板 (0.05,0.07,0.12)
        QColor ft(8, 13, 23);
        ft.setAlphaF(card.tint.alphaF() * (0.88 - i * 0.18));
        QColor fb = card.border;
        fb.setAlphaF(fb.alphaF() * (0.8 - i * 0.18));
        const qreal fx = card.rightSide ? off : -off;
        const qreal fy = -off;
        liveCardPass(viewport, dpr, *m_cardShader, pose, ix, iy, iw, ih,
                     QVector2D(float(fx), float(fy)), true, ft, fb,
                     1.0, 0.0, 0.0, nullptr, fadeMul);
    }

    // 2) 主卡（背板 + 渐变 + 内容 + 边框 + 圆角一体；hoverBlend 传
    //    shader 做深度淡出/顶光×2/深度侧镜像）
    liveCardPass(viewport, dpr, *m_cardShader, pose, ix, iy, iw, ih,
                 QVector2D(0, 0), false, mainTint, mainBorder, borderWidth,
                 depthEff, topEff, card.texture.get(), fadeMul,
                 card.hoverBlend, card.rightSide ? 1.0f : 0.0f);

    // 3) 铭牌（标题/关闭钮，光栅纹理；无圆角裁形）
    if (card.chromeTex && fadeMul > 0.3)
        liveCardPass(viewport, dpr, *m_liveShader, pose, ix, iy, iw, ih,
                     QVector2D(0, 0), false, QColor(), QColor(), 0, 0, 0,
                     card.chromeTex.get(), fadeMul);
    // 覆盖层（图标排/拆分芯片）：随卡投影（老 v52"正视覆盖层"是 QML
    // 双层时代的决定——全套特效直绘后，压平 angle=0 在悬停放大/压平
    // 动画里表现为钉死原地不跟卡动＝"固定位置不随卡片运动"，用户定稿
    // 改为跟卡：倾斜/keystone/缩放全程同步）
    if (card.overlayTex && fadeMul > 0.3) {
        liveCardPass(viewport, dpr, *m_liveShader, pose, ix, iy, iw, ih,
                     QVector2D(0, 0), false, QColor(), QColor(), 0, 0, 0,
                     card.overlayTex.get(), fadeMul);
    }

    // 落屏探针（节流）
    if (card.paintCount % 300 == 1) {
        GLubyte sp[4] = {255, 0, 255, 255};
        const qreal devH = viewport.renderRect().height(); // renderRect 已是设备像素，勿再乘 dpr（v82）
        glReadPixels(int(pose.rect.center().x() * dpr),
                     int(devH - pose.rect.center().y() * dpr),
                     1, 1, GL_RGBA, GL_UNSIGNED_BYTE, sp);
        qCInfo(STAGEANIM_LOG) << "live QUAD" << card.id.left(8)
                                 << "screen-px rgba =" << sp[0] << sp[1]
                                 << sp[2] << sp[3] << "damage" << card.damageCount;
    }
}

// 软件光标补绘：paintScreen 后置通道画在整场景（含场景内光标）之上，
// 无硬件光标平面的环境（本容器）里光标会被卡面盖住＝"卡不透明时鼠标
// 消失"。effects->cursorImage() 覆盖形状/表面两类光标；QImage 预乘，
// blend 状态沿用本函数的 (ONE, ONE_MINUS_SRC_ALPHA)。
void StageAnimEffect::drawSoftwareCursor(const RenderViewport &viewport,
                                         qreal dpr)
{
    const PlatformCursorImage ci = effects->cursorImage();
    const QImage img = ci.image();
    if (img.isNull() || img.width() < 1 || img.height() < 1)
        return;
    const qint64 key = img.cacheKey();
    if (!m_cursorTex || key != m_cursorImgKey) {
        m_cursorImgKey = key;
        m_cursorHotspot = ci.hotSpot();
        m_cursorTex = GLTexture::upload(
            img.convertToFormat(QImage::Format_ARGB32_Premultiplied));
        if (!m_cursorTex)
            return;
    }
    ShaderBinder binder(m_cursorShader.get());
    m_cursorShader->setUniform("modelViewProjectionMatrix",
                               viewport.projectionMatrix());
    m_cursorShader->setUniform("texUnit", 0);
    m_cursorShader->setUniform("alpha", 1.0f);
    const QPointF pos = effects->cursorPos() * dpr - m_cursorHotspot * dpr;
    const qreal w = img.width(), h = img.height(); // 设备像素直绘（主题光标本即设备分辨率）
    GLVertexBuffer *vbo = GLVertexBuffer::streamingBuffer();
    const QList<GLVertex2D> verts = {
        GLVertex2D{QVector2D(float(pos.x()), float(pos.y())), QVector2D(0, 0)},
        GLVertex2D{QVector2D(float(pos.x() + w), float(pos.y())), QVector2D(1, 0)},
        GLVertex2D{QVector2D(float(pos.x() + w), float(pos.y() + h)), QVector2D(1, 1)},
        GLVertex2D{QVector2D(float(pos.x()), float(pos.y() + h)), QVector2D(0, 1)},
    };
    vbo->reset();
    vbo->setVertices(verts);
    vbo->bindArrays();
    m_cursorTex->bind();
    vbo->draw(GL_TRIANGLE_FAN, 0, 4);
    vbo->unbindArrays();
    m_cursorTex->unbind();
    // 光标补绘区同样要进损伤集（理由同卡面）
    addRepaintRectF(effects, QRectF(pos.x() / dpr, pos.y() / dpr,
                               w / dpr, h / dpr));
}

void StageAnimEffect::writeLiveStatus()
{
    QSaveFile f(m_liveStatusPath);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return;
    QJsonObject obj;
    obj.insert(QStringLiteral("at"), QDateTime::currentMSecsSinceEpoch());
    obj.insert(QStringLiteral("active"), !m_liveCards.isEmpty());
    // chrome:true = 卡面视觉已由特效接管（QML 侧隐藏视觉只留输入热区）
    obj.insert(QStringLiteral("chrome"), !m_liveCards.isEmpty());
    QJsonArray ids;
    for (auto it = m_liveCards.constBegin(); it != m_liveCards.constEnd(); ++it)
        ids.append(it.key());
    obj.insert(QStringLiteral("cards"), ids);
    f.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
    f.commit();
}

LiveCardPose StageAnimEffect::lerpPose(const LiveCardPose &a,
                                                        const LiveCardPose &b,
                                                        qreal t)
{
    LiveCardPose out;
    out.rect = QRectF(a.rect.x() + (b.rect.x() - a.rect.x()) * t,
                      a.rect.y() + (b.rect.y() - a.rect.y()) * t,
                      a.rect.width() + (b.rect.width() - a.rect.width()) * t,
                      a.rect.height() + (b.rect.height() - a.rect.height()) * t);
    out.angleDeg = a.angleDeg + (b.angleDeg - a.angleDeg) * t;
    out.yOff = a.yOff + (b.yOff - a.yOff) * t;
    out.focal = b.focal;
    out.radius = b.radius;
    return out;
}

LiveCardPose StageAnimEffect::currentPose(const LiveCard &card)
{
    if (!card.easing)
        return card.target;
    static const QEasingCurve curve(QEasingCurve::OutCubic);
    return lerpPose(card.from, card.target, curve.valueForProgress(card.ease.value()));
}

} // namespace
