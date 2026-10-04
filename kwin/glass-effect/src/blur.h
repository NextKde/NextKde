/*
    SPDX-FileCopyrightText: 2010 Fredrik Höglund <fredrik@kde.org>
    SPDX-FileCopyrightText: 2018 Alex Nemeth <alex.nemeth329@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "effect/effect.h"
#ifndef GLASS_X11
#include "core/region.h"
#endif
#include "opengl/glutils.h"
#include "scene/item.h"
#include "settings.h"

#include <QList>
#include <QStringList>

#include <unordered_map>
#include <Plasma/plasma_version.h>

namespace KWin
{
class SurfaceShapeManager;

#if !defined(GLASS_X11) && !defined(GLASS_KWIN_67)
class BlurManagerInterface;
class ContrastManagerInterface;
#endif
class BackgroundEffectItem;

#ifdef GLASS_X11
using BlurOutput = Output;
using BlurRegion = QRegion;
#else
using BlurOutput = RenderView;
using BlurRegion = Region;
#endif

struct BlurRenderData
{
    /// Temporary render targets needed for the Dual Kawase algorithm, the first texture
    /// contains not blurred background behind the window, it's cached.
    std::vector<std::unique_ptr<GLTexture>> textures;
    std::vector<std::unique_ptr<GLFramebuffer>> framebuffers;
    // Scratch chain for the whole-surface scrim average: the backdrop is
    // reduced to 1x1 here so every fragment shares one uniform tone instead of
    // banding on a variegated backdrop.
    std::vector<std::unique_ptr<GLTexture>> scrimAvgTextures;
    std::vector<std::unique_ptr<GLFramebuffer>> scrimAvgFramebuffers;
    int scrimAvgLevels = 0;
    /// Size the scratch chain was built for. The level count alone does not
    /// change when the capture resizes inside one power-of-two octave, so the
    /// chain has to be keyed on the size as well or its levels no longer match
    /// the capture they are averaging.
    QSize scrimAvgSize;
    /// One scratch capture per declared blur-override level (protocol v4
    /// set_blur). runBlurPass overwrites the shared mip chain in place, so a
    /// level's result has to be copied out here before the next pass -- or the
    /// default one -- runs. Keyed by the compositor blur level.
    struct BlurOverrideScratch
    {
        std::unique_ptr<GLTexture> texture;
        std::unique_ptr<GLFramebuffer> framebuffer;
        QSize size;
    };
    std::unordered_map<uint, BlurOverrideScratch> blurOverrideScratch;
};

struct BlurEffectData
{
    /// True when the client or its decoration explicitly opted into blur.
    /// Forced-blur policy must not masquerade as an application request,
    /// otherwise class filters cannot distinguish the two paths.
    bool hasExplicitBlurRequest = false;

    /// The region that should be blurred behind the window
    std::optional<BlurRegion> content;

    /// The region that should be blurred behind the frame
    std::optional<BlurRegion> frame;

    /**
     * The render data per render view, as they can have different
     *  color spaces and even different windows on them
     */
    std::unordered_map<BlurOutput *, BlurRenderData> render;
#if PLASMA_VERSION >= 0x060404 && !defined(GLASS_X11)
    std::unique_ptr<BackgroundEffectItem> blurItem;
#endif

    ItemEffect windowEffect;

    /**
     * Color transformation matrix (contrast, and saturation).
     */
    std::optional<QMatrix4x4> colorMatrix;

    /**
     * Corner radius reported by the window before this effect overrides it.
     */
    std::optional<BorderRadius> originalCornerRadius;
};

class BlurEffect : public KWin::Effect
{
    Q_OBJECT

public:
    BlurEffect();
    ~BlurEffect() override;

    static bool supported();
    static bool enabledByDefault();

    void reconfigure(ReconfigureFlags flags) override;
#ifdef GLASS_KWIN_67
    void prePaintScreen(ScreenPrePaintData &data) override;

    // prePaintWindow is intentionally NOT overridden on KWin 6.7.
    // See the note in blur.cpp: BackgroundEffectItem owns paint-region
    // expansion via forceTranslucent in collectDamage(), and calling
    // data.setTranslucent() here corrupts the compositing path when a
    // Wayland popup is added/removed above a blurred surface.
#ifdef GLASS_X11
    void prePaintWindow(EffectWindow *w, WindowPrePaintData &data) override;
#endif
#else
    void prePaintScreen(ScreenPrePaintData &data, std::chrono::milliseconds presentTime) override;

#ifdef GLASS_X11
    void prePaintWindow(EffectWindow *w, WindowPrePaintData &data, std::chrono::milliseconds presentTime) override;
#else
    void prePaintWindow(RenderView *view, EffectWindow *w, WindowPrePaintData &data, std::chrono::milliseconds presentTime) override;
#endif
#endif
    void drawWindow(const RenderTarget &renderTarget, const RenderViewport &viewport, EffectWindow *w, int mask, const BlurRegion &deviceRegion, WindowPaintData &data) override;

    bool provides(Feature feature) override;
    bool isActive() const override;

    int requestedEffectChainPosition() const override
    {
        return 20;
    }

    bool eventFilter(QObject *watched, QEvent *event) override;

    bool blocksDirectScanout() const override;
    bool shouldFlattenCorner(KWin::EffectWindow *w, Qt::Corner corner) const;

public Q_SLOTS:
    void slotWindowAdded(KWin::EffectWindow *w);
    void slotWindowDeleted(KWin::EffectWindow *w);
    void slotOutputRemoved(KWin::BlurOutput *output);
#if KWIN_BUILD_X11
    void slotPropertyNotify(KWin::EffectWindow *w, long atom);
#endif
    void setupDecorationConnections(EffectWindow *w);

private:
    struct BlurPipelineSettings
    {
        size_t iterationCount;
        float offset;
        int expandSize;
        int noiseStrength;
    };

    void initBlurStrengthValues();
    BlurRegion contentRegion(EffectWindow *w, const BorderRadius *fallbackCornerRadius = nullptr) const;
    BlurRegion blurRegion(EffectWindow *w, const BorderRadius *fallbackCornerRadius = nullptr) const;
    BlurRegion roundedContentRegion(const QRect &rect, const BorderRadius &cornerRadius, qreal leftSideWidth, qreal rightSideWidth, qreal topHeight, qreal bottomHeight) const;
    BorderRadius effectiveWindowCornerRadius(EffectWindow *w, const BorderRadius &declaredCornerRadius, bool *isOverRounded = nullptr, bool applyDynamicCorners = true) const;
    QRectF dynamicCornerRect(EffectWindow *w) const;
    BlurRegion decorationBlurRegion(const EffectWindow *w) const;
    bool decorationSupportsBlurBehind(const EffectWindow *w) const;
    bool shouldBlur(const EffectWindow *w, int mask, const WindowPaintData &data) const;
    bool shapeTraceEnabled() const;
    void updateBlurRegion(EffectWindow *w);
    void repaintDynamicCorners();
    void blur(const RenderTarget &renderTarget, const RenderViewport &viewport, EffectWindow *w, int mask, const BlurRegion &deviceRegion, WindowPaintData &data);
    GLTexture *ensureNoiseTexture(int noiseStrength);
    QMatrix4x4 colorMatrix(const float &brightness, const float &saturation, const float &contrast) const;
    BlurPipelineSettings pipelineSettingsForStrength(int blurStrength, int noiseStrength) const;
    /// The pixels that have to be repainted below opaque regions so a moving
    /// blur never exposes unblurred content: the global expand, raised to the
    /// strongest expand any blur-override shape on this window's surface needs.
    int blurExpandSize(EffectWindow *w) const;

private:
    struct
    {
        std::unique_ptr<GLShader> shader;
        int mvpMatrixLocation;
        int colorMatrixLocation;
        int useOklabSaturationLocation;
        int saturationLocation;
        int offsetLocation;
        int halfpixelLocation;
        int viewportScaleLocation;
        int boxLocation;
        int cornerRadiusLocation;
        int cornerExponentLocation;
        int glassEnabledLocation;
        int opacityLocation;
        int texUnitLocation;

        int edgeSizePixelsLocation;
        int refractionStrengthLocation;
        int refractionNormalPowLocation;
        int refractionRGBFringingLocation;
        int refractionOffsetStrengthLocation;
        int materialSoftnessLocation;
        int materialReflectionStrengthLocation;

        int scrimModeLocation;
        int scrimCapLocation;
        int scrimDecayLocation;
        int scrimLumaTexLocation;
        int scrimLumaValidLocation;
    } m_roundedOnscreenPass;

    struct
    {
        std::unique_ptr<GLShader> shader;
        int mvpMatrixLocation;
        int offsetLocation;
        int halfpixelLocation;
    } m_downsamplePass;

    struct
    {
        std::unique_ptr<GLShader> shader;
        int mvpMatrixLocation;
        int offsetLocation;
        int halfpixelLocation;
        int saturationCompensationLocation;
    } m_upsamplePass;

    struct
    {
        std::unique_ptr<GLShader> shader;
        int mvpMatrixLocation;
        int noiseTextureSizeLocation;
        int boxLocation;
        int cornerRadiusLocation;
        int cornerExponentLocation;

        std::unique_ptr<GLTexture> noiseTexture;
        qreal noiseTextureScale = 1.0;
        int noiseTextureStength = 0;
    } m_noisePass;

    BlurSettings m_settings;
#ifndef GLASS_X11
    std::unique_ptr<SurfaceShapeManager> m_surfaceShapeManager;
#endif
    bool m_valid = false;
#ifdef GLASS_KWIN_67
    bool m_blurCapabilityRegistered = false;
#endif
#if KWIN_BUILD_X11
    long net_wm_blur_region = 0;
#endif
    BlurRegion m_paintedDeviceArea; // keeps track of all painted areas (from bottom to top)
    BlurRegion m_currentDeviceBlur; // keeps track of currently blurred area of the windows (from bottom to top)
    BlurOutput *m_currentOutput = nullptr;

    QMatrix4x4 m_colorMatrix;
    int m_expandSize;
    float m_blurRadius = 1.0f;
    float m_upsampleOffset = 1.0f;
    size_t m_maxIterationCount = 1; // number of times the texture will be downsized to half size
    BlurPipelineSettings m_contentBlurSettings{};
    BlurPipelineSettings m_decorationBlurSettings{};
    BlurPipelineSettings m_dockBlurSettings{};
    QStringList m_windowClasses;
    bool m_whitelist;

    struct OffsetStruct
    {
        float minOffset;
        float maxOffset;
        int expandSize;
    };

    QList<OffsetStruct> blurOffsets;

    struct BlurValuesStruct
    {
        int iteration;
        float offset;
    };

    QList<BlurValuesStruct> blurStrengthValues;

    QMap<EffectWindow *, QMetaObject::Connection> windowBlurChangedConnections;
#if !defined(GLASS_X11) && !defined(GLASS_KWIN_67)
    QMap<EffectWindow *, QMetaObject::Connection> windowContrastChangedConnections;
#endif
    QMap<EffectWindow *, QMetaObject::Connection> windowFrameGeometryChangedConnections;
    std::unordered_map<EffectWindow *, BlurEffectData> m_windows;

#if !defined(GLASS_X11) && !defined(GLASS_KWIN_67)
    static BlurManagerInterface *s_blurManager;
    static QTimer *s_blurManagerRemoveTimer;

    static ContrastManagerInterface *s_contrastManager;
    static QTimer *s_contrastManagerRemoveTimer;
#endif
};

inline bool BlurEffect::provides(Effect::Feature feature)
{
    if (feature == Blur) {
        return true;
    }
    return KWin::Effect::provides(feature);
}

} // namespace KWin
