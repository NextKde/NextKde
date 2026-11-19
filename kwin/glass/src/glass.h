/*
    SPDX-FileCopyrightText: 2026 NextKDE contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <core/region.h>
#include <effect/effect.h>

#include <QElapsedTimer>
#include <QHash>
#include <QMetaObject>
#include <QRectF>
#include <QTimer>

#include <memory>

namespace KWin
{

class EffectWindow;
class GlassPointerSpy;
class InputEventSpy;
class SurfaceShapeManager;
class SurfaceInterface;
struct GlassShape;
struct RenderData;
struct RenderPasses;

// Global liquid-optics configuration, read from the `Effect-blurplus` kwinrc
// group the shell already writes through `theme.sync-glass`. Values are kept in
// shader units: strengths 0..1, lengths in logical pixels.
struct MaterialSettings
{
    float refractionStrength = 0.0f;
    float edgeSizePixels = 20.0f;
    float refractionNormalPow = 1.0f;
    float refractionRGBFringing = 0.05f;
    float refractionOffsetStrength = 0.0f;
    float materialSoftness = 0.0f;
    float materialReflectionStrength = 0.0f;
    // Dual Kawase chain resolved from `BlurStrength` / `BlurFinetune`. Strength
    // picks how many levels run; the offset stays in the 1..2 texel band where
    // each level is a smooth low-pass instead of a ghosted copy.
    int blurIterations = 6;
    float blurDownsampleOffset = 1.78f;
    float blurUpsampleOffset = 1.78f;
    float saturationCompensation = 1.296f;
    // Pointer light (liquid profile only). The hover lobe fades in quickly and
    // decays over ~150 ms; the parallax uniform biases the lens a few device
    // pixels toward the pointer. Both share the same repaint policy and are
    // disabled independently from the KCM.
    bool hoverLight = true;
    float hoverLightStrength = 0.5f;
    // Light reach in logical pixels; zero selects the adaptive default that
    // scales with the surface's smaller half size.
    float hoverLightRadius = 0.0f;
    bool pointerParallax = true;
    // Click ripple: an expanding rim light emitted at the press position.
    // Radius is the final reach in logical pixels, duration the fade in ms.
    bool clickLight = true;
    float clickLightStrength = 0.5f;
    float clickLightRadius = 200.0f;
    int clickLightDuration = 450;
};

class GlassEffect : public Effect
{
    Q_OBJECT

public:
    GlassEffect();
    ~GlassEffect() override;

    static bool supported();
    static bool enabledByDefault();

    void reconfigure(ReconfigureFlags flags) override;

#ifdef GLASS_KWIN_67
    void prePaintScreen(ScreenPrePaintData &data) override;
#else
    void prePaintScreen(ScreenPrePaintData &data,
                        std::chrono::milliseconds presentTime) override;
    void prePaintWindow(RenderView *view, EffectWindow *w, WindowPrePaintData &data,
                        std::chrono::milliseconds presentTime) override;
#endif
    void postPaintScreen() override;

#ifdef KOS_KWIN_PAINT_RESULT_API
    bool
#else
    void
#endif
    drawWindow(const RenderTarget &renderTarget, const RenderViewport &viewport,
               EffectWindow *w, int mask, const Region &deviceRegion,
               WindowPaintData &data) override;

    bool isActive() const override;

    int requestedEffectChainPosition() const override
    {
        return 20;
    }

private:
    friend class GlassPointerSpy;

    void render(const RenderTarget &renderTarget, const RenderViewport &viewport,
                EffectWindow *w, const Region &deviceRegion, const WindowPaintData &paint);
    void ensurePasses();
    void readMaterialSettings();
    void updateItem(EffectWindow *w);
    void removeWindow(EffectWindow *w);
    // Backdrop invalidation. The blur only depends on what is painted below
    // the glass surface, so a window's own repaints (hover animations, a
    // scrolling list inside the panel) must not rerun the chain. Client
    // commits are the only reliable "the pixels below changed" signal; moves,
    // stacking changes and desktop switches are folded in conservatively.
    void trackDamageSources(EffectWindow *w);
    void untrackDamageSources(EffectWindow *w);
    void slotWindowContentDamaged(EffectWindow *w);
    // Pointer light. The pointer position is sampled on mouseChanged and
    // re-applied while the fade runs; the timer stops as soon as every hover
    // value has settled, so a still desktop does not keep repainting.
    void installPointerSpy();
    void slotPointerMoved(const QPointF &scenePos);
    void slotPointerButton(const QPointF &scenePos);
    void stepHoverAnimation();
    void repaintShapes(EffectWindow *w, const QVector<struct GlassShape> &shapes);
    void slotStackingOrderChanged();
    // Invalidate every glass surface stacked above `changed`; surfaces below
    // it still sample exactly the pixels they sampled before.
    void invalidateAbove(EffectWindow *changed);
    void invalidateBackdrops();

    std::unique_ptr<SurfaceShapeManager> m_shapes;
    std::unique_ptr<RenderPasses> m_passes;
    QHash<EffectWindow *, RenderData *> m_render;
    QHash<EffectWindow *, QMetaObject::Connection> m_windowDamageConnections;
    QHash<EffectWindow *, QMetaObject::Connection> m_geometryConnections;
    // Stacking order as of the last structural change. The signal that
    // reports a deletion no longer contains the window, so the previous order
    // is what tells us which glass surfaces it was covering.
    QList<EffectWindow *> m_stackingOrder;
    MaterialSettings m_material;
    QTimer m_hoverTimer;
    QElapsedTimer m_hoverClock;
    qint64 m_lastHoverTick = 0;
    // Active click pulse, in scene coordinates. -1 means idle. The envelope is
    // derived from the clock in render(), so no per-window state is needed.
    QPointF m_clickScene;
    qint64 m_clickStart = -1;
    std::unique_ptr<InputEventSpy> m_pointerSpy;
    bool m_pointerSpyInstalled = false;
    // 6.6 prePaintWindow runs bottom to top. Damage written by lower windows
    // must be replayed on top of every glass surface it is visible through,
    // otherwise the frame keeps the lower window's pixels and the surface
    // content disappears. Both regions are reset for every frame.
    Region m_paintedDeviceArea;
    Region m_currentDeviceBlur;
    bool m_valid = false;
};

} // namespace KWin
