/*
    SPDX-FileCopyrightText: 2008 Martin Gräßlin <mgraesslin@kde.org>
    SPDX-FileCopyrightText: 2026 fg-sched stage animation

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "effect/effectwindow.h"
#include "effect/offscreeneffect.h"
#include "effect/timeline.h"

#include <QSet>
#include <QVector>

namespace KWin
{

struct StageTarget; // 定义在 stageanim.cpp（shell 发布的卡片矩形条目）

struct StageAnimAnimation
{
    EffectWindowVisibleRef visibleRef;
    TimeLine timeLine;
    // 每窗目标（shell 按 KWin internalId 发布的卡片矩形）；无效 = 全局/回落
    QRect target;
    qreal endScale = -1.0;
    bool flat = false; // 目标卡片是正视的（中心拖放）：无倾斜分量
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
    void prePaintScreen(ScreenPrePaintData &data) override;
    void prePaintWindow(RenderView *view, EffectWindow *w, WindowPrePaintData &data) override;
#endif
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
};

} // namespace
