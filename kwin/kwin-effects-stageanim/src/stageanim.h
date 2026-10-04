/*
    SPDX-FileCopyrightText: 2008 Martin Gräßlin <mgraesslin@kde.org>
    SPDX-FileCopyrightText: 2026 fg-sched stage animation

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "core/rendertarget.h"
#include "core/renderviewport.h"
#include "effect/effectwindow.h"
#include "effect/offscreeneffect.h"
#include "effect/timeline.h"
#include "opengl/glframebuffer.h"
#include "opengl/glshader.h"
#include "opengl/gltexture.h"

// 6.6 公开的离屏渲染入口（Compositor::scene()->renderer()）在 6.7+ 被收进
// KWin 进程内部（kwinApp()->scene() / renderer(RenderDevice*) 均不在公开头
// 里）。活体内容重渲管线只在 6.6 分支编译；6.7+ 编译为静态玻璃卡降级
//（发布协议本就支持无内容卡：FBO 空内容 ct.a=0 时着色器退化为纯背板，
// 与占位形态同一代码路径，无需额外分支）
#ifdef KOS_KWIN_PAINT_TIME_API
#define STAGE_LIVE_CONTENT_RENDER 1
#else
#define STAGE_LIVE_CONTENT_RENDER 0
#endif

#include <QFileSystemWatcher>
#include <QPointer>
#include <QSet>
#include <QTimer>
#include <QVector>

namespace KWin
{

struct StageTarget; // 定义在 stageanim.cpp（shell 发布的卡片矩形条目）

struct StageAnimAnimation
{
    EffectWindowVisibleRef visibleRef;
    TimeLine timeLine;
    // 多输出同帧去重（逐窗！）：prePaintWindow 每屏各调一次，同一帧
    // advance 两遍＝动画 2 倍速。⚠️ 必须挂在条目上——共享全局时间戳
    // 会让同帧内除第一扇窗外全部跳过 advance＝多窗齐飞按窗数减速
    // （v83.1 收起/退避卡顿事故）
    std::chrono::milliseconds lastAdvance{-1};
    // 每窗目标（shell 按 KWin internalId 发布的卡片矩形）；无效 = 全局/回落
    QRect target;
    qreal endScale = -1.0;
    bool flat = false; // 目标卡片是正视的（中心拖放）：无倾斜分量
};

// 活体卡姿态：终态卡面（plate）未倾斜矩形 + 透视参数。与 QML 的
// stage_tilt.frag 同一套数学（tiltProject 孪生），角/yOff/焦距全部由
// shell 按当前状态发布（悬停压平/列滚动都会改变它们）。
struct LiveCardPose
{
    QRectF rect;      // 屏幕逻辑坐标的卡面矩形（= 快照所在 plate）
    qreal angleDeg = 0; // 已含右侧镜像符号的终态倾角
    qreal yOff = 0;   // 卡中心相对共享地平线的 y 偏移（正 = 地平线下方）
    qreal focal = 2200;
    qreal radius = 10; // 圆角半径（与 plate.radius 同源）
};

// 一张活体卡：持 refOffscreenRendering（KWin 给隐藏窗补发帧回调 →
// 客户端继续出帧，成本等同窗口可见）+ 窗口内容渲染进卡面尺寸的
// 小 FBO（损伤驱动重拍，填充率可忽略），绘制时逐像素逆投影 + 圆角
// SDF，画进侧栏浮层窗口的绘制过程中（chrome 之下、桌面之上）。
struct LiveCard
{
    QString id;
    // 渲染窗（rep）id 字符串：发布流携带，用于 EffectWindow 连接建立前
    // 的匹配（收编飞行窗活体跟踪——窗口最小化早于卡窗连接 ~50ms）
    QString winId;
    QPointer<EffectWindow> window;
    LiveCardPose target;  // 最新发布的终态
    LiveCardPose from;    // 缓动起点
    TimeLine ease{std::chrono::milliseconds(220)};
    bool easing = false;
    bool offscreenRef = false;
    QMetaObject::Connection damageConnection;
    std::unique_ptr<GLTexture> texture; // 卡面尺寸 × dpr 的小纹理
    std::unique_ptr<GLFramebuffer> fbo;
    bool dirty = true; // 窗口有新损伤待重拍
    qreal dpr = 1.0;  // 最近一次绘制时的输出缩放（纹理分配依据）
    // 诊断计数（LiveTrace 节流日志）
    quint32 damageCount = 0;
    qint64 lastRenderMs = 0; // 损伤重拍限频（30fps 上限）
    qint64 lastDamageMs = 0; // 最近损伤时刻（动静自适应喂帧判据）
    qint64 lastPoseChangeMs = 0; // 上次姿态变化（密集流 vs 孤立跳变判据）
    qint64 absentSinceMs = 0; // 发布流缺席起点（掉卡迟滞 350ms）
    int feedPhase = 0; // 非优先卡的帧投喂轮询相位
    quint32 renderCount = 0;
    quint32 paintCount = 0;

    // ── 卡面本体（方案"卡进特效"：chrome 由特效同管线绘制）──
    // 元数据（QML 发布，v2 协议）
    QString title;        // 显示名（QML 拼好含 ×N 后缀）
    int count = 1;        // 组内窗数（扇叠背板数 = min(count-1, 2)）
    qreal z = 0;          // 叠序（QML slot.z）
    bool dragging = false; // 跟手模式：矩形逐帧由 QML 发布，特效免悬停
    bool engaging = false; // 展开中：整体淡出后让位给窗口动画
    bool dying = false;    // 退场中：发布流已除名，统一淡出后释放（ghost 并入本体）
    bool dropHover = false; // 拖放目标预示（边框蓝）
    bool dwellHint = false; // 驻留合并预示（边框蓝）
    QColor tint{13, 18, 31};      // 背板基色（QML rgba(0.05,0.07,0.12,tint)）
    QColor tintHover{26, 33, 51}; // 悬停提亮（×1.3 色族）
    QColor border{255, 255, 255, 33};
    // 以下默认值与 reload 解析回落一致（= StageConfigService._schema 的
    // def，v87 审查收敛：三套默认漂移＝发布端漏字段时静默落到另一套视觉）
    qreal hoverScale = 1.05;
    qreal hoverTiltDeg = 0;       // 悬停终态倾角（已含右条镜像符号）
    // v52 视觉补全（老 QML 行为迁移）
    bool selfMergeHint = false;
    bool rightSide = false;
    bool merged = false;
    bool showCardTitle = true;
    bool enterInstant = false;
    bool chipHot = false;
    QString iconsJson;
    qreal iconSize = 40;   // 图标排图标边长（payload，v88：原硬编码 24）
    int iconSlots = 4;     // 图标排并列上限（payload，v88：原仅按宽度封顶）
    qreal engagingTilt = 0;
    std::chrono::milliseconds tiltMs{250};
    std::chrono::milliseconds enterMs{240};
    std::chrono::milliseconds animMs{420};
    qreal dragScale = 1.0;
    // hoverBlend 基线（v87 审查）：与 scale/tilt/fanBlend 同款 from→to
    // 插值——旧实现直接 (hovered?1:0)*cubic，方向翻转/拖拽打断瞬间从
    // 0.6 单帧硬跳到 0（边框蓝/深度淡出瞬灭）
    qreal hoverBlend = 0.0;    // 悬停态混合量（边框蓝/深度淡出/顶光×2）
    qreal hoverBlendFrom = 0.0, hoverBlendTo = 0.0;
    qreal spawnSlide = 0.0;    // 入场 x 侧滑起点（±70）
    qint64 spawnAtMs = 0;      // 入场起表时刻（迸开错峰 +70ms/张）
    std::chrono::milliseconds hoverMs{280};
    qreal fanSpacing = 8;
    qreal fanHoverSpread = 1.4; // 悬停/武装时扇叠间距扩散系数（可调）
    qreal depthStrength = 0.38;
    qreal topLight = 0.07;
    // 悬停状态机（特效自驱：cursorPos 命中静止矩形——与 QML 输入区同界；
    // 动画在本进程跑，与内容同管线同时钟 = 像素级同步）
    bool hovered = false;
    qreal curScale = 1.0;   // 当前插值（绘制用）
    qreal curTiltDeg = 0;
    qreal scaleFrom = 1.0, scaleTo = 1.0, tiltFrom = 0, tiltTo = 0;
    TimeLine hoverTl{std::chrono::milliseconds(240)};
    bool hoverAnimating = false;
    // 扇叠扩散补间（老 QML Behavior 140ms 同族）：hover/武装/驻留任一
    // 即扩散，但都必须**缓动**过去——旧实现武装/驻留瞬时满扩（跳变＝
    // "生硬"），悬停又只挂 hoverBlend（离开时与放大曲线耦合）
    qreal fanBlend = 0.0;     // 0=收拢 1=全扩
    qreal fanFrom = 0.0, fanTo = 0.0;
    TimeLine fanTl{std::chrono::milliseconds(150)};
    bool fanAnimating = false;
    // 入场/退场/engaging 淡变（alphaFrom→alphaTo）× QML 发布的 fade
    //（压暗 × 视口边缘渐隐）
    qreal alpha = 1.0;
    qreal alphaFrom = 1.0, alphaTo = 1.0;
    // 入场起摆保持：发布先于最小化落地（收编快照等待 ~120ms），
    // 按发布时刻起摆淡入＝卡先于窗口出现在槽位（"先出现卡片再收编"）。
    // 挂起等窗口真开始装卡飞行（isMinimized/最小化动画）才同拍起摆
    bool enterHold = false;
    qreal fade = 1.0;
    bool closeHot = false;
    TimeLine fadeTl{std::chrono::milliseconds(180)};
    bool fadeAnimating = false;
    // 铭牌（标题/关闭钮，QPainter 光栅 → 纹理；键变才重绘，Y 镜像匹配
    // stage-live 的 FBO 朝向采样）
    std::unique_ptr<GLTexture> chromeTex;
    std::unique_ptr<GLTexture> overlayTex; // 正视覆盖层（图标排/拆分芯片）
    QString chromeKey;
    QString overlayKey;
};

// MagicLamp derivative whose minimize target is resolved per animation
// trigger: ① the card rect the shell publishes for this window (KWin
// internalId) — the window shrinks into / grows out of its own Stage sidebar
// card; ② the global strip rect from kwinrc [Effect-stageanim] Target*;
// ③ the original MagicLamp behaviour (iconGeometry / cursor fallback).
class StageAnimEffect : public OffscreenEffect
{
    Q_OBJECT

public:
    StageAnimEffect();

    void reconfigure(ReconfigureFlags) override;
#ifdef KOS_KWIN_PAINT_TIME_API
    void prePaintScreen(ScreenPrePaintData &data, std::chrono::milliseconds presentTime) override;
    void prePaintWindow(RenderView *view, EffectWindow *w, WindowPrePaintData &data, std::chrono::milliseconds presentTime) override;
#else
    // 6.7+：prePaint 钩子移除 presentTime；paintScreen 签名两代一致（void）
    void prePaintScreen(ScreenPrePaintData &data) override;
    void prePaintWindow(RenderView *view, EffectWindow *w, WindowPrePaintData &data) override;
#endif
    void paintScreen(const RenderTarget &renderTarget, const RenderViewport &viewport,
                     int mask, const Region &deviceRegion, LogicalOutput *screen) override;
    void postPaintScreen() override;
    bool isActive() const override;

    int requestedEffectChainPosition() const override
    {
        return 50;
    }

    static bool supported();

protected:
    void apply(EffectWindow *window, int mask, WindowPaintData &data, WindowQuadList &quads) override;

public Q_SLOTS:
    void slotWindowAdded(KWin::EffectWindow *w);
    void slotWindowDeleted(KWin::EffectWindow *w);
    void slotWindowMinimized(KWin::EffectWindow *w);
    void slotWindowUnminimized(KWin::EffectWindow *w);

private:
    void resolveTarget(KWin::EffectWindow *w, StageAnimAnimation &anim, const QVector<StageTarget> &targets);
    std::chrono::milliseconds m_duration;
    QHash<EffectWindow *, StageAnimAnimation> m_animations;
    QSet<EffectWindow *> m_connected; // 已挂 minimizedChanged 的窗口
    QRect m_target; // 全局配置目标（Stage 侧栏区域）；无效 = 回落行为
    QEasingCurve m_easing{QEasingCurve::InOutCubic};
    qreal m_tiltAngle = 22.0; // kwinrc TiltAngle：卡片倾斜角，动画起止姿态
    qreal m_glassOpacity = 0.65; // kwinrc GlassOpacity：飞行途中透明度（1=关）
    bool m_trace = false; // kwinrc TraceTargets：正常路径也打目标解析日志
    bool m_mirrorTargets = false; // kwinrc TargetMirror：右侧常驻——装卡姿态镜像

    // ── 活体卡（合成器直绘，stage-live.json 由 shell 发布）──
    void reloadLiveCards();
    void detachLiveCard(LiveCard &card);
    void releaseLiveCard(LiveCard &card);
    void updateLiveFrameTimer(); // 帧钟随卡启停（零卡不空转，v87 审查）
    void attachLiveCardSources(LiveCard &card); // refOffscreenRendering + 损伤连接（注册/复活共用）
    void scheduleLiveRenders(); // 重拍预算：每拍最多 2 张（优先卡先、其余最久未拍轮转）
    bool expireAbsentLiveCards(); // 缺席超时踢除：对 m_liveWanted 钟控评估（不依赖发布文件再变）
    void renderLiveTexture(LiveCard &card);
    void drawLiveCards(const RenderTarget &renderTarget, const RenderViewport &viewport);
    void drawSoftwareCursor(const RenderViewport &viewport, qreal dpr);
    // drawLiveCards 拆分（306 行巨函数＝历次回归高发区）：单 pass 原语 /
    // 投影外接框 / 单卡全 pass 序列。全部纯搬运，行为零变化
    void liveCardPass(const RenderViewport &viewport, qreal dpr, GLShader &sh,
                      const LiveCardPose &pose, qreal ix, qreal iy, qreal iw,
                      qreal ih, const QVector2D &fanOff, bool fanOnly,
                      const QColor &tint, const QColor &border,
                      qreal borderWidth, qreal depthG, qreal topLight,
                      GLTexture *tex, qreal alpha, qreal hoverBlend = 0.0,
                      float sideRight = 0.0f);
    QRectF cardBodyQuad(const LiveCardPose &pose, qreal fanMax, qreal dpr) const;
    void drawLiveCardBody(const RenderViewport &viewport, qreal dpr,
                          LiveCard &card, quint32 &paintable);
    void writeLiveStatus();
    bool liveCardPaintable(const LiveCard &card) const;
    static LiveCardPose lerpPose(const LiveCardPose &a, const LiveCardPose &b, qreal t);
    static LiveCardPose currentPose(const LiveCard &card);
    // 卡面铭牌（标题/关闭钮）光栅化；键（标题/计数/尺寸）变才重绘
    void rasterChrome(LiveCard &card);

    QString m_livePath;
    QString m_liveStatusPath;
    QFileSystemWatcher *m_liveWatcher = nullptr;
    QTimer m_liveStatusTimer;   // 周期刷 status 文件（shell 据此让位快照）
    QTimer m_liveStaleTimer;    // 10s 周期 reload 兜底（真正的心跳超时判定在 reload 内按 mtime 25s）
    QTimer m_liveFrameTimer;    // 自驱帧回调投喂（30Hz framePainted）
    qint64 m_lastLiveFrameKey = -1; // 多输出同帧去重键（6.6=presentTime 值 / 6.7=RenderView 指针），状态机只推进一次
    QDateTime m_lastLiveReadMtime; // 已消费的发布文件 mtime（回执写同目录会自触发 directoryChanged——比对后跳过纯浪费的 reload，v87 审查）
    int m_shaderFails = 0;            // 着色器编译连败计数（退避用，成功清零）
    qint64 m_shaderLastFailMs = 0;    // 最近一次编译失败时刻（steady ms）
    QHash<QString, QSharedPointer<LiveCard>> m_liveCards; // 含 dying 退场卡（统一绘制管线）
    QSet<QString> m_liveWanted; // 最近一次发布在册的 id（缺席踢除的对照基准）
    QSet<QString> m_livePending; // 文件里有、窗口还没出现（等 windowAdded）
    quint32 m_liveFeedTick = 0;  // 帧投喂分级节拍
    quint32 m_liveFeedCounter = 0; // 相位分配计数
    std::unique_ptr<GLShader> m_liveShader;
    std::unique_ptr<GLShader> m_cardShader; // 卡面整体（背板/渐变/边框/内容合一）
    // 软件光标补绘：后置通道盖住场景内光标（容器无硬件光标平面），
    // 卡画完后按 effects->cursorImage() 在光标位重绘精灵
    std::unique_ptr<GLShader> m_cursorShader;
    std::unique_ptr<GLTexture> m_cursorTex;
    qint64 m_cursorImgKey = 0;
    QPointF m_cursorHotspot;
    bool m_liveEnabled = true; // kwinrc LiveCards 总闸（默认开，排障用）
};

} // namespace
