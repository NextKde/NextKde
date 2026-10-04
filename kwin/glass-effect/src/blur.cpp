/*
    SPDX-FileCopyrightText: 2010 Fredrik Höglund <fredrik@kde.org>
    SPDX-FileCopyrightText: 2011 Philipp Knechtges <philipp-dev@knechtges.com>
    SPDX-FileCopyrightText: 2018 Alex Nemeth <alex.nemeth329@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "blur.h"
// KConfigSkeleton
#include "blurconfig.h"
#include "settings.h"
#include "surfaceshapemanager.h"

#include "core/pixelgrid.h"
#ifndef GLASS_X11
#include "core/region.h"
#endif
#include "core/rendertarget.h"
#include "core/renderviewport.h"
#include "effect/effecthandler.h"
#include "opengl/glplatform.h"
#include "scene/decorationitem.h"
#include "scene/scene.h"
#include "scene/surfaceitem.h"
#include "scene/windowitem.h"
#if defined(GLASS_X11) || !defined(GLASS_KWIN_67)
#include "wayland/blur.h"
#include "wayland/contrast.h"
#endif
#include "wayland/display.h"
#include "wayland/surface.h"
#include "window.h"

#ifdef GLASS_KWIN_67
#include "wayland/backgroundeffect_v1.h"
#include "wayland_server.h"
#endif

#if PLASMA_VERSION >= 0x060404 && !defined(GLASS_X11)
#include <scene/backgroundeffectitem.h>
#endif

#if KWIN_BUILD_X11
#include "utils/xcbutils.h"
#endif

#include <QGuiApplication>
#include <QPalette>
#include <QMatrix4x4>
#include <QScreen>
#include <QTime>
#include <QTimer>
#include <QWindow>
#include <algorithm>
#include <vector>
#include <cmath> // for ceil()
#include <cstdlib>

#include <KConfigGroup>
#include <KSharedConfig>

#include <KDecoration3/Decoration>

Q_LOGGING_CATEGORY(KWIN_BLUR, "kwin_effect_blur", QtWarningMsg)

static void ensureResources()
{
    // Must initialize resources manually because the effect is a static lib.
    Q_INIT_RESOURCE(blur);
}

namespace KWin
{

static const QByteArray s_blurAtomName = QByteArrayLiteral("_KDE_NET_WM_BLUR_BEHIND_REGION");

static bool isQuickshellWindow(const EffectWindow *window)
{
    if (!window) {
        return false;
    }
    return window->window()->resourceClass().contains(
               QLatin1String("quickshell"), Qt::CaseInsensitive)
        || window->window()->resourceName().contains(
               QLatin1String("quickshell"), Qt::CaseInsensitive);
}

// Shape-path tracing. The per-surface geometry is the one thing about this path
// that cannot be checked from the outside -- the numbers only mean something
// next to the blur region the compositor published for the same frame -- so a
// trace has to come from inside. Two switches: KOS_GLASS_TRACE for a compositor
// started with tracing already on, and kwinrc's ShapeTrace for a running one,
// which `Effects.reconfigureEffect glass` picks up without a plugin reload.
bool BlurEffect::shapeTraceEnabled() const
{
    static const bool forced = qEnvironmentVariableIsSet("KOS_GLASS_TRACE");
    return forced || m_settings.general.shapeTrace;
}

// Which category the trace lines go out on. kwin_effect_blur is where the rest
// of this effect's diagnostics live, but a trace exists to be *read*, and a
// filter the reader cannot see -- a QT_LOGGING_RULES entry, a kdebug setting --
// would silently turn it into no output at all, which is indistinguishable from
// the shape never arriving. So it falls back to the default category, which
// nothing filters, whenever the effect's own one is off.
static const QLoggingCategory &shapeTraceCategory()
{
    return KWIN_BLUR().isWarningEnabled() ? KWIN_BLUR()
                                          : *QLoggingCategory::defaultCategory();
}

#if !defined(GLASS_X11) && !defined(GLASS_KWIN_67)
BlurManagerInterface *BlurEffect::s_blurManager = nullptr;
QTimer *BlurEffect::s_blurManagerRemoveTimer = nullptr;

ContrastManagerInterface *BlurEffect::s_contrastManager = nullptr;
QTimer *BlurEffect::s_contrastManagerRemoveTimer = nullptr;
#endif

static QMatrix4x4 colorTransformMatrix(qreal saturation, qreal contrast, qreal brightness)
{
    QMatrix4x4 saturationMatrix;
    QMatrix4x4 contrastMatrix;
    QMatrix4x4 brightnessMatrix;

    if (!qFuzzyCompare(saturation, 1.0)) {
        const qreal rval = (1.0 - saturation) * 0.2126;
        const qreal gval = (1.0 - saturation) * 0.7152;
        const qreal bval = (1.0 - saturation) * 0.0722;

        saturationMatrix = QMatrix4x4(rval + saturation, rval, rval, 0.0,
                                      gval, gval + saturation, gval, 0.0,
                                      bval, bval, bval + saturation, 0.0,
                                      0.0, 0.0, 0.0, 1.0);
    }

    if (!qFuzzyCompare(contrast, 1.0)) {
        const float transl = (1.0 - contrast) / 2.0;

        contrastMatrix = QMatrix4x4(contrast, 0.0, 0.0, 0.0,
                                    0.0, contrast, 0.0, 0.0,
                                    0.0, 0.0, contrast, 0.0,
                                    transl, transl, transl, 1.0);
    }

    if (!qFuzzyCompare(brightness, 1.0)) {
        brightnessMatrix.scale(brightness, brightness, brightness);
    }

    return contrastMatrix * saturationMatrix * brightnessMatrix;
}

BlurEffect::BlurEffect()
{
    BlurConfig::instance(effects->config());
    ensureResources();

    // Built before anything that can fail: reconfigure() indexes this table, and
    // so does every later D-Bus reconfigure, so it must exist even when a shader
    // below fails to load.
    initBlurStrengthValues();

    m_roundedOnscreenPass.shader = ShaderManager::instance()->generateShaderFromFile(ShaderTrait::MapTexture,
                                                                                     QStringLiteral(":/effects/glass/generated/onscreen_rounded.vert"),
                                                                                     QStringLiteral(":/effects/glass/generated/onscreen_rounded.frag"));
    if (!m_roundedOnscreenPass.shader) {
        qCWarning(KWIN_BLUR) << "Failed to load onscreen pass shader";
        return;
    } else {
        m_roundedOnscreenPass.mvpMatrixLocation = m_roundedOnscreenPass.shader->uniformLocation("modelViewProjectionMatrix");
        m_roundedOnscreenPass.colorMatrixLocation = m_roundedOnscreenPass.shader->uniformLocation("colorMatrix");
        m_roundedOnscreenPass.useOklabSaturationLocation = m_roundedOnscreenPass.shader->uniformLocation("useOklabSaturation");
        m_roundedOnscreenPass.saturationLocation = m_roundedOnscreenPass.shader->uniformLocation("saturation");
        m_roundedOnscreenPass.offsetLocation = m_roundedOnscreenPass.shader->uniformLocation("offset");
        m_roundedOnscreenPass.halfpixelLocation = m_roundedOnscreenPass.shader->uniformLocation("halfpixel");
        m_roundedOnscreenPass.viewportScaleLocation = m_roundedOnscreenPass.shader->uniformLocation("viewportScale");
        m_roundedOnscreenPass.boxLocation = m_roundedOnscreenPass.shader->uniformLocation("box");
        m_roundedOnscreenPass.cornerRadiusLocation = m_roundedOnscreenPass.shader->uniformLocation("cornerRadius");
        m_roundedOnscreenPass.cornerExponentLocation = m_roundedOnscreenPass.shader->uniformLocation("cornerExponent");
        m_roundedOnscreenPass.glassEnabledLocation = m_roundedOnscreenPass.shader->uniformLocation("glassEnabled");
        m_roundedOnscreenPass.opacityLocation = m_roundedOnscreenPass.shader->uniformLocation("opacity");
        m_roundedOnscreenPass.texUnitLocation = m_roundedOnscreenPass.shader->uniformLocation("texUnit");
        m_roundedOnscreenPass.edgeSizePixelsLocation = m_roundedOnscreenPass.shader->uniformLocation("edgeSizePixels");
        m_roundedOnscreenPass.refractionStrengthLocation = m_roundedOnscreenPass.shader->uniformLocation("refractionStrength");
        m_roundedOnscreenPass.refractionNormalPowLocation = m_roundedOnscreenPass.shader->uniformLocation("refractionNormalPow");
        m_roundedOnscreenPass.refractionRGBFringingLocation = m_roundedOnscreenPass.shader->uniformLocation("refractionRGBFringing");
        m_roundedOnscreenPass.refractionOffsetStrengthLocation = m_roundedOnscreenPass.shader->uniformLocation("refractionOffsetStrength");
        m_roundedOnscreenPass.materialSoftnessLocation = m_roundedOnscreenPass.shader->uniformLocation("materialSoftness");
        m_roundedOnscreenPass.materialReflectionStrengthLocation = m_roundedOnscreenPass.shader->uniformLocation("materialReflectionStrength");
        m_roundedOnscreenPass.scrimModeLocation = m_roundedOnscreenPass.shader->uniformLocation("scrimMode");
        m_roundedOnscreenPass.scrimCapLocation = m_roundedOnscreenPass.shader->uniformLocation("scrimCap");
        m_roundedOnscreenPass.scrimDecayLocation = m_roundedOnscreenPass.shader->uniformLocation("scrimDecay");
        m_roundedOnscreenPass.scrimLumaTexLocation = m_roundedOnscreenPass.shader->uniformLocation("scrimLumaTex");
        m_roundedOnscreenPass.scrimLumaValidLocation = m_roundedOnscreenPass.shader->uniformLocation("scrimLumaValid");
    }

    m_downsamplePass.shader = ShaderManager::instance()->generateShaderFromFile(ShaderTrait::MapTexture,
                                                                                QStringLiteral(":/effects/glass/generated/vertex.vert"),
                                                                                QStringLiteral(":/effects/glass/generated/downsample.frag"));
    if (!m_downsamplePass.shader) {
        qCWarning(KWIN_BLUR) << "Failed to load downsampling pass shader";
        return;
    } else {
        m_downsamplePass.mvpMatrixLocation = m_downsamplePass.shader->uniformLocation("modelViewProjectionMatrix");
        m_downsamplePass.offsetLocation = m_downsamplePass.shader->uniformLocation("offset");
        m_downsamplePass.halfpixelLocation = m_downsamplePass.shader->uniformLocation("halfpixel");
    }

    m_upsamplePass.shader = ShaderManager::instance()->generateShaderFromFile(ShaderTrait::MapTexture,
                                                                              QStringLiteral(":/effects/glass/generated/vertex.vert"),
                                                                              QStringLiteral(":/effects/glass/generated/upsample.frag"));
    if (!m_upsamplePass.shader) {
        qCWarning(KWIN_BLUR) << "Failed to load upsampling pass shader";
        return;
    } else {
        m_upsamplePass.mvpMatrixLocation = m_upsamplePass.shader->uniformLocation("modelViewProjectionMatrix");
        m_upsamplePass.offsetLocation = m_upsamplePass.shader->uniformLocation("offset");
        m_upsamplePass.halfpixelLocation = m_upsamplePass.shader->uniformLocation("halfpixel");
        m_upsamplePass.saturationCompensationLocation = m_upsamplePass.shader->uniformLocation("saturationCompensation");
    }

    m_noisePass.shader = ShaderManager::instance()->generateShaderFromFile(ShaderTrait::MapTexture,
                                                                           QStringLiteral(":/effects/glass/generated/onscreen_rounded.vert"),
                                                                           QStringLiteral(":/effects/glass/generated/noise.frag"));
    if (!m_noisePass.shader) {
        qCWarning(KWIN_BLUR) << "Failed to load noise pass shader";
        return;
    } else {
        m_noisePass.mvpMatrixLocation = m_noisePass.shader->uniformLocation("modelViewProjectionMatrix");
        m_noisePass.noiseTextureSizeLocation = m_noisePass.shader->uniformLocation("noiseTextureSize");
        m_noisePass.boxLocation = m_noisePass.shader->uniformLocation("box");
        m_noisePass.cornerRadiusLocation = m_noisePass.shader->uniformLocation("cornerRadius");
        m_noisePass.cornerExponentLocation = m_noisePass.shader->uniformLocation("cornerExponent");
    }

    reconfigure(ReconfigureAll);
#if KWIN_BUILD_X11
    if (effects->xcbConnection()) {
        net_wm_blur_region = effects->announceSupportProperty(s_blurAtomName, this);
    }
#endif

#ifdef GLASS_KWIN_67
    waylandServer()->backgroundEffectManager()->addBlurCapability();
    m_blurCapabilityRegistered = true;
#endif

#ifndef GLASS_X11
    // Reach the display through EffectsHandler rather than the WaylandServer
    // singleton: waylandDisplay() has been part of the effect API since KWin 5.5,
    // while the singleton accessor was renamed between 6.6 (WaylandServer::self())
    // and 6.7 (the waylandServer() free function).
    m_surfaceShapeManager = std::make_unique<SurfaceShapeManager>(
        effects->waylandDisplay(), this);
    connect(m_surfaceShapeManager.get(), &SurfaceShapeManager::surfaceShapesChanged,
            this, [this](SurfaceInterface *surface) {
        for (EffectWindow *window : effects->stackingOrder()) {
            if (window->surface() == surface) {
                // A blur override appearing, disappearing or changing level
                // changes how far the repaint region has to expand, not just
                // what is drawn this frame.
                if (auto it = m_windows.find(window); it != m_windows.end() && it->second.blurItem) {
                    it->second.blurItem->setPixelsToExpandRepaintsBelowOpaqueRegions(
                        blurExpandSize(window));
                }
                window->addRepaintFull();
                break;
            }
        }
    });
#endif

    connect(effects, &EffectsHandler::windowAdded, this, &BlurEffect::slotWindowAdded);
    connect(effects, &EffectsHandler::windowDeleted, this, &BlurEffect::slotWindowDeleted);
#ifdef GLASS_X11
    connect(effects, &EffectsHandler::screenRemoved, this, &BlurEffect::slotOutputRemoved);
#else
    connect(effects, &EffectsHandler::viewRemoved, this, &BlurEffect::slotOutputRemoved);
#endif
#if KWIN_BUILD_X11
    connect(effects, &EffectsHandler::propertyNotify, this, &BlurEffect::slotPropertyNotify);
    connect(effects, &EffectsHandler::xcbConnectionChanged, this, [this]() {
        net_wm_blur_region = effects->announceSupportProperty(s_blurAtomName, this);
    });
#endif

#if !defined(GLASS_X11) && !defined(GLASS_KWIN_67)
    if (effects->waylandDisplay()) {
        if (!s_blurManagerRemoveTimer) {
            s_blurManagerRemoveTimer = new QTimer(QCoreApplication::instance());
            s_blurManagerRemoveTimer->setSingleShot(true);
            s_blurManagerRemoveTimer->callOnTimeout([]() {
                s_blurManager->remove();
                s_blurManager = nullptr;
            });
        }
        s_blurManagerRemoveTimer->stop();
        if (!s_blurManager) {
            s_blurManager = new BlurManagerInterface(effects->waylandDisplay(), s_blurManagerRemoveTimer);
        }

        if (!s_contrastManagerRemoveTimer) {
            s_contrastManagerRemoveTimer = new QTimer(QCoreApplication::instance());
            s_contrastManagerRemoveTimer->setSingleShot(true);
            s_contrastManagerRemoveTimer->callOnTimeout([]() {
                s_contrastManager->remove();
                s_contrastManager = nullptr;
            });
        }
        s_contrastManagerRemoveTimer->stop();
        if (!s_contrastManager) {
            s_contrastManager = new ContrastManagerInterface(effects->waylandDisplay(), s_contrastManagerRemoveTimer);
        }
    }
#endif

    // Fetch the blur regions for all windows
    const auto stackingOrder = effects->stackingOrder();
    for (EffectWindow *window : stackingOrder) {
        slotWindowAdded(window);
    }

    m_valid = true;
}

BlurEffect::~BlurEffect()
{
#if !defined(GLASS_X11) && !defined(GLASS_KWIN_67)
    // When compositing is restarted, avoid removing the manager immediately.
    if (s_blurManager) {
        s_blurManagerRemoveTimer->start(1000);
    }

    if (s_contrastManager) {
        s_contrastManagerRemoveTimer->start(1000);
    }
#endif

#ifdef GLASS_KWIN_67
    if (m_blurCapabilityRegistered) {
        waylandServer()->backgroundEffectManager()->removeBlurCapability();
    }
#endif
}

void BlurEffect::initBlurStrengthValues()
{
    // This function creates an array of blur strength values that are evenly distributed

    // The range of the slider on the blur settings UI
    int numOfBlurSteps = 15;
    int remainingSteps = numOfBlurSteps;

    /*
     * Explanation for these numbers:
     *
     * The texture blur amount depends on the downsampling iterations and the offset value.
     * By changing the offset we can alter the blur amount without relying on further downsampling.
     * But there is a minimum and maximum value of offset per downsample iteration before we
     * get artifacts.
     *
     * The minOffset variable is the minimum offset value for an iteration before we
     * get blocky artifacts because of the downsampling.
     *
     * The maxOffset value is the maximum offset value for an iteration before we
     * get diagonal line artifacts because of the nature of the dual kawase blur algorithm.
     *
     * The expandSize value is the minimum value for an iteration before we reach the end
     * of a texture in the shader and sample outside of the area that was copied into the
     * texture from the screen.
     */

    // {minOffset, maxOffset, expandSize}
    blurOffsets.append({1.0, 2.0, 10}); // Down sample size / 2
    blurOffsets.append({2.0, 3.0, 20}); // Down sample size / 4
    blurOffsets.append({2.0, 5.0, 50}); // Down sample size / 8
    blurOffsets.append({3.0, 8.0, 150}); // Down sample size / 16
    // blurOffsets.append({5.0, 10.0, 400}); // Down sample size / 32
    // blurOffsets.append({7.0, ?.0});       // Down sample size / 64

    float offsetSum = 0;

    for (int i = 0; i < blurOffsets.size(); i++) {
        offsetSum += blurOffsets[i].maxOffset - blurOffsets[i].minOffset;
    }

    for (int i = 0; i < blurOffsets.size(); i++) {
        int iterationNumber = std::ceil((blurOffsets[i].maxOffset - blurOffsets[i].minOffset) / offsetSum * numOfBlurSteps);
        remainingSteps -= iterationNumber;

        if (remainingSteps < 0) {
            iterationNumber += remainingSteps;
        }

        float offsetDifference = blurOffsets[i].maxOffset - blurOffsets[i].minOffset;

        for (int j = 1; j <= iterationNumber; j++) {
            // {iteration, offset}
            blurStrengthValues.append({i + 1, blurOffsets[i].minOffset + (offsetDifference / iterationNumber) * j});
        }
    }
}

void BlurEffect::reconfigure(ReconfigureFlags flags)
{
    // KConfigXT caches values. Re-read kwinrc before BlurConfig::read() so
    // reconfigureEffect applies Debug/preset changes without a KWin restart.
    if (const auto config = BlurConfig::self()->config()) {
        config->reparseConfiguration();
    }
    m_settings.read();

    m_contentBlurSettings = pipelineSettingsForStrength(
        m_settings.general.blurStrength,
        m_settings.general.noiseStrength
    );
    m_decorationBlurSettings = pipelineSettingsForStrength(
        m_settings.general.decorationBlurStrength,
        m_settings.general.decorationNoiseStrength
    );
    m_dockBlurSettings = pipelineSettingsForStrength(
        m_settings.general.dockBlurStrength,
        m_settings.general.dockNoiseStrength
    );
    m_maxIterationCount = 1;
    for (const BlurValuesStruct &values : blurStrengthValues) {
        m_maxIterationCount = std::max<size_t>(m_maxIterationCount, values.iteration);
    }
    m_expandSize = std::max({
        m_contentBlurSettings.expandSize,
        m_decorationBlurSettings.expandSize,
        m_dockBlurSettings.expandSize,
    });
    m_blurRadius = m_settings.general.blurRadius;
    m_upsampleOffset = m_settings.general.upsampleOffset;

    // If oklab saturation is enabled, the matrix should have a 
    // saturation value of 1.0 since the saturation is handled by the shader.
    const qreal matrixSaturation = m_settings.general.oklabSaturation ? 1.0 : m_settings.general.saturation;
    m_colorMatrix = colorTransformMatrix(
        matrixSaturation,
        m_settings.general.contrast,
        m_settings.general.brightness
    );
#if PLASMA_VERSION >= 0x060404 && !defined(GLASS_X11)
    for (auto &[window, data] : m_windows) {
        data.blurItem->setPixelsToExpandRepaintsBelowOpaqueRegions(blurExpandSize(window));
    }
#endif

    m_whitelist = (m_settings.forceBlur.windowClassMatchingMode == WindowClassMatchingMode::Whitelist);
    m_windowClasses = m_settings.forceBlur.windowClasses;

    // forceBlur.blurDecorations is materialized into each window's frame
    // region. Refresh from the compositor's stable stacking-order snapshot so
    // toggling it applies immediately and updateBlurRegion may safely erase
    // entries from m_windows. Initial construction uses slotWindowAdded below.
    if (m_valid) {
        const auto stackingOrder = effects->stackingOrder();
        for (EffectWindow *window : stackingOrder) {
            updateBlurRegion(window);
        }
    }

    // Update all windows for the blur to take effect
    effects->addRepaintFull();
}

void BlurEffect::repaintDynamicCorners()
{
    if (m_settings.roundedCorners.dynamicCorners) {
        effects->addRepaintFull();
    }
}

BlurEffect::BlurPipelineSettings BlurEffect::pipelineSettingsForStrength(int blurStrength, int noiseStrength) const
{
    // The strength table is built once, by the constructor. A shader that failed
    // to load used to return before that happened, which left the table empty
    // and turned the next reconfigure() -- any kwinrc write, including the
    // shell's own sync -- into an out-of-range index. QList asserts on that, so
    // a cosmetic GLSL error took the whole compositor down instead of merely
    // leaving the glass unrendered. Fall back to the weakest entry (one
    // downsampling iteration) and keep running.
    if (blurStrengthValues.isEmpty() || blurOffsets.isEmpty()
        || blurStrength < 0 || blurStrength >= blurStrengthValues.size()) {
        return BlurPipelineSettings{
            .iterationCount = 1,
            .offset = 1.0f,
            .expandSize = 10,
            .noiseStrength = noiseStrength,
        };
    }

    const BlurValuesStruct &values = blurStrengthValues[blurStrength];

    return BlurPipelineSettings{
        .iterationCount = static_cast<size_t>(values.iteration),
        .offset = values.offset,
        .expandSize = blurOffsets[values.iteration - 1].expandSize,
        .noiseStrength = noiseStrength,
    };
}

int BlurEffect::blurExpandSize(EffectWindow *w) const
{
    int expand = m_expandSize;
#ifndef GLASS_X11
    if (w && w->surface() && m_surfaceShapeManager && !blurStrengthValues.isEmpty()) {
        const QVector<SurfaceShape> shapes = m_surfaceShapeManager->shapesFor(w->surface());
        for (const SurfaceShape &shape : shapes) {
            if (!shape.blurEnabled) {
                continue;
            }
            const int level = qBound(1, int(shape.blurLevel), int(blurStrengthValues.size()));
            expand = std::max(expand, pipelineSettingsForStrength(level - 1, 0).expandSize);
        }
    }
#endif
    return expand;
}

void BlurEffect::updateBlurRegion(EffectWindow *w)
{
    std::optional<BlurRegion> content;
    std::optional<BlurRegion> frame;
    std::optional<qreal> saturation;
    std::optional<qreal> contrast;
    bool hasExplicitBlurRequest = false;

#ifdef GLASS_X11
    if (net_wm_blur_region != XCB_ATOM_NONE) {
        const QByteArray value = w->readProperty(net_wm_blur_region, XCB_ATOM_CARDINAL, 32);
        BlurRegion region;
        if (value.size() > 0 && !(value.size() % (4 * sizeof(uint32_t)))) {
            const uint32_t *cardinals = reinterpret_cast<const uint32_t *>(value.constData());
            for (unsigned int i = 0; i < value.size() / sizeof(uint32_t);) {
                int x = cardinals[i++];
                int y = cardinals[i++];
                int w = cardinals[i++];
                int h = cardinals[i++];
#ifdef GLASS_X11
                region += Xcb::fromXNative(QRect(x, y, w, h)).toRect();
#else
                region += Xcb::fromXNative(Rect(x, y, w, h)).toRect();
#endif
            }
        }
        if (!value.isNull()) {
            content = region;
            hasExplicitBlurRequest = true;
        }
    }
#endif

    if (SurfaceInterface *surface = w->surface()) {
#ifdef GLASS_KWIN_67
        const RegionF surfaceBlurRegion = surface->blurRegion();
        if (!surfaceBlurRegion.isEmpty()) {
            Region region;
            for (const RectF &rect : surfaceBlurRegion.rects()) {
                region += rect.toAlignedRect();
            }
            content = region;
            hasExplicitBlurRequest = true;
        }
#else
        if (surface->blur()) {
            content = surface->blur()->region();
            hasExplicitBlurRequest = true;
        }
        if (surface->contrast()) {
            saturation = surface->contrast()->saturation();
            contrast = surface->contrast()->contrast();
        }
#endif
    }

    if (auto internal = w->internalWindow()) {
        const auto property = internal->property("kwin_blur");
        if (property.isValid()) {
            content = property.value<BlurRegion>();
            hasExplicitBlurRequest = true;
        }
    }

    if (w->decorationHasAlpha() && decorationSupportsBlurBehind(w)) {
        frame = decorationBlurRegion(w);
        hasExplicitBlurRequest = true;
    }

    // KOS: scope the whole-window glass backdrop to windows that actually have
    // a server-side decoration, instead of every window that is not a dock or
    // a menu.
    //
    // The intent is that an application can leave its own background fully
    // transparent and let this effect supply the material, the same way the
    // shell's own surfaces are drawn. Relying on each application to declare a
    // blur region does not achieve that: a client that paints nothing may
    // publish no region at all, and then there is no glass behind it.
    //
    // Keying on the decoration is what keeps that from swallowing the desktop.
    // Layer-shell surfaces -- the Dock, the Bar, and above all the full-screen
    // DeskCenter -- carry no decoration, so they are left alone; with the old
    // condition DeskCenter's whole surface became a blur region and the
    // wallpaper behind it was permanently out of focus. Client-side decorated
    // windows are skipped too, which is correct: they draw their own frame and
    // never asked for this one.
    if (m_settings.forceBlur.blurDecorations && w->decoration()) {
#ifdef GLASS_X11
        BlurRegion glass(w->frameGeometry().translated(-w->x(), -w->y()).toRect());
#else
        BlurRegion glass(Rect(w->frameGeometry().translated(-w->x(), -w->y()).toRect()));
#endif

        // Whatever the client declares opaque is cut back out again.
        //
        // Glass behind an opaque area is invisible by definition, and paying
        // for it is not the real cost: a blur region that overlaps the
        // window's opaque region drives the repaint bookkeeping further down
        // this file (m_paintedDeviceArea / m_currentDeviceBlur) to keep
        // re-expanding the damaged area every frame, and the title bar visibly
        // flickers. That is why an opaque file manager flickered while a
        // terminal with a translucent profile, whose opaque region is empty,
        // did not.
        //
        // Subtracting it also makes the option mean what it says: the window
        // gets glass exactly where the client lets something show through, so
        // an application that paints nothing gets the full pane.
#ifndef GLASS_X11
        if (SurfaceInterface *surface = w->surface()) {
#ifdef GLASS_KWIN_67
            const RegionF opaque = surface->opaque();
            if (!opaque.isEmpty()) {
                // surface->opaque() is surface-local; contentsRect() places the
                // client area inside the frame the region above is built in.
                const QPoint clientOffset = w->contentsRect().topLeft().toPoint();
                Region opaqueInFrame;
                for (const RectF &rect : opaque.rects()) {
                    opaqueInFrame += rect.toAlignedRect().translated(clientOffset);
                }
                glass -= opaqueInFrame;
            }
#else
            const Region opaque = surface->opaque();
            if (!opaque.isEmpty()) {
                // surface->opaque() is surface-local; contentsRect() places the
                // client area inside the frame the region above is built in.
                const QPoint clientOffset = w->contentsRect().topLeft().toPoint();
                Region opaqueInFrame;
                for (const Rect &rect : opaque.rects()) {
                    opaqueInFrame += rect.translated(clientOffset);
                }
                glass -= opaqueInFrame;
            }
#endif
        }
#endif

        frame = glass;
    }

    if (content.has_value() || frame.has_value()) {
        BlurEffectData &data = m_windows[w];
        data.hasExplicitBlurRequest = hasExplicitBlurRequest;
        data.content = content;
        data.frame = frame;
        data.colorMatrix = colorTransformMatrix(saturation.value_or(1.0), contrast.value_or(1.0), 1.0);
#if PLASMA_VERSION < 0x060404 || defined(GLASS_X11)
        data.windowEffect = ItemEffect(w->windowItem());
#else
        if (!data.blurItem) {
            data.blurItem = std::make_unique<BackgroundEffectItem>(w->windowItem());
        }
        data.blurItem->setPixelsToExpandRepaintsBelowOpaqueRegions(blurExpandSize(w));
        data.blurItem->setEffectBoundingRect(blurRegion(w).boundingRect());
#endif
    } else {
        if (auto it = m_windows.find(w); it != m_windows.end()) {
            effects->makeOpenGLContextCurrent();
            m_windows.erase(it);
        }
    }
}

void BlurEffect::slotWindowAdded(EffectWindow *w)
{
    SurfaceInterface *surf = w->surface();

    if (surf) {
        windowBlurChangedConnections[w] = connect(surf, &SurfaceInterface::blurChanged, this, [this, w]() {
            if (w) {
                updateBlurRegion(w);
            }
        });
#if !defined(GLASS_X11) && !defined(GLASS_KWIN_67)
        windowContrastChangedConnections[w] = connect(surf, &SurfaceInterface::contrastChanged, this, [this, w]() {
            if (w) {
                updateBlurRegion(w);
            }
        });
#endif
    }

    windowFrameGeometryChangedConnections[w] = connect(w, &EffectWindow::windowFrameGeometryChanged, this, [this,w]() {
        if (w) {
            updateBlurRegion(w);
            repaintDynamicCorners();
        }
    });

    if (auto internal = w->internalWindow()) {
        internal->installEventFilter(this);
    }

    setupDecorationConnections(w);
    connect(w, &EffectWindow::windowDecorationChanged, this, [this, w]() {
        setupDecorationConnections(w);
        updateBlurRegion(w);
    });

    updateBlurRegion(w);
    repaintDynamicCorners();
}

void BlurEffect::slotWindowDeleted(EffectWindow *w)
{
    if (auto it = m_windows.find(w); it != m_windows.end()) {
        effects->makeOpenGLContextCurrent();
        m_windows.erase(it);
    }
    if (auto it = windowBlurChangedConnections.find(w); it != windowBlurChangedConnections.end()) {
        disconnect(*it);
        windowBlurChangedConnections.erase(it);
    }
#if !defined(GLASS_X11) && !defined(GLASS_KWIN_67)
    if (auto it = windowContrastChangedConnections.find(w); it != windowContrastChangedConnections.end()) {
        disconnect(*it);
        windowContrastChangedConnections.erase(it);
    }
#endif
    if (auto it = windowFrameGeometryChangedConnections.find(w); it != windowFrameGeometryChangedConnections.end()) {
        disconnect(*it);
        windowFrameGeometryChangedConnections.erase(it);
    }
    repaintDynamicCorners();
}

void BlurEffect::slotOutputRemoved(KWin::BlurOutput *output)
{
    for (auto &[window, data] : m_windows) {
        if (auto it = data.render.find(output); it != data.render.end()) {
            effects->makeOpenGLContextCurrent();
            data.render.erase(it);
        }
    }
}

#if KWIN_BUILD_X11
void BlurEffect::slotPropertyNotify(EffectWindow *w, long atom)
{
    if (w && atom == net_wm_blur_region && net_wm_blur_region != XCB_ATOM_NONE) {
        updateBlurRegion(w);
    }
}
#endif

void BlurEffect::setupDecorationConnections(EffectWindow *w)
{
    if (!w->decoration()) {
        return;
    }

    connect(w->decoration(), &KDecoration3::Decoration::blurRegionChanged, this, [this, w]() {
        updateBlurRegion(w);
    });
}

bool BlurEffect::eventFilter(QObject *watched, QEvent *event)
{
    auto internal = qobject_cast<QWindow *>(watched);
    if (internal && event->type() == QEvent::DynamicPropertyChange) {
        QDynamicPropertyChangeEvent *pe = static_cast<QDynamicPropertyChangeEvent *>(event);
        if (pe->propertyName() == "kwin_blur") {
            if (auto w = effects->findWindow(internal)) {
                updateBlurRegion(w);
            }
        }
    }
    return false;
}

bool BlurEffect::enabledByDefault()
{
    const auto context = effects->openglContext();
    if (!context || context->isSoftwareRenderer()) {
        return false;
    }
    GLPlatform *gl = context->glPlatform();

    if (gl->isIntel() && gl->chipClass() < SandyBridge) {
        return false;
    }
    if (gl->isPanfrost() && gl->chipClass() <= MaliT8XX) {
        return false;
    }
    // The blur effect works, but is painfully slow (FPS < 5) on Mali and VideoCore
    if (gl->isLima() || gl->isVideoCore4() || gl->isVideoCore3D()) {
        return false;
    }
    return true;
}

bool BlurEffect::supported()
{
    return effects->isOpenGLCompositing();
}

bool BlurEffect::decorationSupportsBlurBehind(const EffectWindow *w) const
{
    return w->decoration() && !w->decoration()->blurRegion().isNull();
}

BorderRadius BlurEffect::effectiveWindowCornerRadius(EffectWindow *w, const BorderRadius &declaredCornerRadius, bool *isOverRounded, bool applyDynamicCorners) const
{
    if (isOverRounded) {
        *isOverRounded = false;
    }

    if (!w) {
        return BorderRadius(0.0, 0.0, 0.0, 0.0);
    }

    // Quickshell sends the exact blur area for cards inside a transparent
    // layer-shell surface.  The region has already been chosen by the client;
    // applying this effect's window-sized corner mask on top would use a
    // different geometry and makes the card edge visibly stair-step.
    if (isQuickshellWindow(w)) {
        if (const auto it = m_windows.find(w); it != m_windows.end()
            && it->second.content.has_value() && !it->second.content->isEmpty()) {
            return declaredCornerRadius;
        }
    }

    if (m_settings.roundedCorners.useDeclaredCornerRadius) {
        return declaredCornerRadius;
    }

    float topCornerRadius = 0.0;
    float bottomCornerRadius = 0.0;
    if (w->isDock()) {
        topCornerRadius = m_settings.roundedCorners.dockRadius;
        bottomCornerRadius = m_settings.roundedCorners.dockRadius;
    } else if (w->isMenu() || w->isDropdownMenu() || w->isPopupMenu() || w->isPopupWindow()) {
        topCornerRadius = m_settings.roundedCorners.menuRadius;
        bottomCornerRadius = m_settings.roundedCorners.menuRadius;
    }

    // Normal application windows retain the radius declared by their client
    // or decoration. Glass only configures shell-owned Dock and menu surfaces.
    if (!w->isDock() && !w->isMenu() && !w->isDropdownMenu()
        && !w->isPopupMenu() && !w->isPopupWindow()) {
        return declaredCornerRadius;
    }

    if (topCornerRadius <= 0.0f && bottomCornerRadius <= 0.0f) {
        return BorderRadius(0.0, 0.0, 0.0, 0.0);
    }

    const QRectF frame = w->frameGeometry();
    const float winWidth = frame.width();
    const float winHeight = frame.height();
    const bool overRounded = (topCornerRadius + bottomCornerRadius) > winHeight ||
        (topCornerRadius * 2) > winWidth;

    if (isOverRounded) {
        *isOverRounded = overRounded;
    }

    if (overRounded) {
        if (w->isDock()) {
            topCornerRadius = 0;
            bottomCornerRadius = 0;
        }
    }

    return BorderRadius(
        applyDynamicCorners && shouldFlattenCorner(w, Qt::TopLeftCorner) ? 0.0f : topCornerRadius,
        applyDynamicCorners && shouldFlattenCorner(w, Qt::TopRightCorner) ? 0.0f : topCornerRadius,
        applyDynamicCorners && shouldFlattenCorner(w, Qt::BottomRightCorner) ? 0.0f : bottomCornerRadius,
        applyDynamicCorners && shouldFlattenCorner(w, Qt::BottomLeftCorner) ? 0.0f : bottomCornerRadius
    );
}

BlurRegion BlurEffect::roundedContentRegion(const QRect &rect, const BorderRadius &cornerRadius, qreal leftSideWidth, qreal rightSideWidth, qreal topHeight, qreal bottomHeight) const
{
    const QVector4D radius = cornerRadius.toVector();
    auto contentRadius = [](float windowRadius, qreal sideWidth) {
        if (windowRadius <= 0.0f) {
            return 0.0f;
        }
        return std::max(windowRadius * 0.5f, windowRadius - static_cast<float>(sideWidth));
    };

    const int maxRadius = std::max(0, std::min(rect.width(), rect.height()) / 2);
    const int topLeft = leftSideWidth || topHeight ? std::clamp(static_cast<int>(std::round(contentRadius(radius.x(), leftSideWidth))), 0, maxRadius) : 0;
    const int topRight = rightSideWidth || topHeight ? std::clamp(static_cast<int>(std::round(contentRadius(radius.y(), rightSideWidth))), 0, maxRadius) : 0;
    const int bottomLeft = leftSideWidth || bottomHeight ? std::clamp(static_cast<int>(std::round(contentRadius(radius.z(), leftSideWidth))), 0, maxRadius) : 0;
    const int bottomRight = rightSideWidth || bottomHeight ? std::clamp(static_cast<int>(std::round(contentRadius(radius.w(), rightSideWidth))), 0, maxRadius) : 0;

    if (topLeft == 0 && topRight == 0 && bottomRight == 0 && bottomLeft == 0) {
#ifdef GLASS_X11
        return BlurRegion(rect);
#else
        return Region(Rect(rect));
#endif
    }

    auto insetForRadius = [](int radius, double distanceFromEdge) {
        if (radius <= 0 || distanceFromEdge >= radius) {
            return 0;
        }

        const double clampedDistance = std::max(0.0, distanceFromEdge);
        const double y = radius - clampedDistance;
        return static_cast<int>(std::ceil(radius - std::sqrt(std::max(0.0, radius * radius - y * y))));
    };

    BlurRegion region;
    auto addRect = [&region](const QRect &rect) {
#ifdef GLASS_X11
        region += rect;
#else
        region += Rect(rect);
#endif
    };

    int spanY = -1;
    int spanX = 0;
    int spanWidth = 0;
    for (int y = 0; y < rect.height(); ++y) {
        const double distanceFromTop = y + 0.5;
        const double distanceFromBottom = rect.height() - y - 0.5;
        const int leftInset = std::max(insetForRadius(topLeft, distanceFromTop),
                                       insetForRadius(bottomLeft, distanceFromBottom));
        const int rightInset = std::max(insetForRadius(topRight, distanceFromTop),
                                        insetForRadius(bottomRight, distanceFromBottom));
        const int rowWidth = rect.width() - leftInset - rightInset;
        if (rowWidth <= 0) {
            if (spanY >= 0) {
                addRect(QRect(spanX, rect.top() + spanY, spanWidth, y - spanY));
                spanY = -1;
            }
            continue;
        }

        const int rowX = rect.left() + leftInset;
        if (spanY >= 0 && rowX == spanX && rowWidth == spanWidth) {
            continue;
        }

        if (spanY >= 0) {
            addRect(QRect(spanX, rect.top() + spanY, spanWidth, y - spanY));
        }
        spanY = y;
        spanX = rowX;
        spanWidth = rowWidth;
    }

    if (spanY >= 0) {
        addRect(QRect(spanX, rect.top() + spanY, spanWidth, rect.height() - spanY));
    }

    return region;
}

BlurRegion BlurEffect::decorationBlurRegion(const EffectWindow *w) const
{
    if (!decorationSupportsBlurBehind(w)) {
        return BlurRegion();
    }

#ifdef GLASS_X11
    BlurRegion decorationRegion = BlurRegion(w->decoration()->rect().toAlignedRect()) - w->contentsRect().toRect();
#else
    BlurRegion decorationRegion = BlurRegion(Rect(w->decoration()->rect().toAlignedRect())) - w->contentsRect().toRect();
#endif
    //! we return only blurred regions that belong to decoration region
    return decorationRegion.intersected(BlurRegion(w->decoration()->blurRegion()));
}

BlurRegion BlurEffect::contentRegion(EffectWindow *w, const BorderRadius *fallbackCornerRadius) const
{
    BlurRegion region;

    if (auto it = m_windows.find(w); it != m_windows.end()) {
        const std::optional<BlurRegion> &content = it->second.content;
        if (!m_settings.roundedCorners.ignoreContentBlurRegion || w->isDock()) {
            if (content.has_value()) {
                if (content->isEmpty()) {
                    // A number of layer-shell clients (notably Quickshell)
                    // bind the background-effect protocol for a transparent
                    // panel but leave its blur region empty.  In the protocol
                    // an empty region normally means the full surface; for a
                    // full-width transparent panel that incorrectly turns all
                    // unused space into liquid glass.  Explicit non-empty
                    // regions, such as the pill region used by a dock, retain
                    // their normal behaviour.
                    if (w->isDock() && m_settings.forceBlur.skipEmptyDockBlurRegions) {
                        return region;
                    }
#ifdef GLASS_X11
                    region = w->contentsRect().toAlignedRect();
#else
                    region = Rect(w->contentsRect().toAlignedRect());
#endif
                } else {
                    region = content->translated(
                            w->contentsRect().x(),
                            w->contentsRect().y()) & w->contentsRect().toAlignedRect();
                }
            }
        } else {
            const BorderRadius declaredCornerRadius = it->second.originalCornerRadius.value_or(w->window()->borderRadius());
            const BorderRadius cornerRadius = fallbackCornerRadius
                ? *fallbackCornerRadius
                : effectiveWindowCornerRadius(w, declaredCornerRadius, nullptr, false);
            const QRectF contentsRect = w->contentsRect();
            const qreal leftSideWidth = std::max<qreal>(0.0, contentsRect.x());
            const qreal rightSideWidth = std::max<qreal>(0.0, w->frameGeometry().width() - contentsRect.x() - contentsRect.width());
            const qreal topHeight = std::max<qreal>(0.0, contentsRect.y());
            const qreal bottomHeight = std::max<qreal>(0.0, w->frameGeometry().height() - contentsRect.y() - contentsRect.height());
            region = roundedContentRegion(w->contentsRect().toRect(),
                                          cornerRadius,
                                          leftSideWidth,
                                          rightSideWidth,
                                          topHeight,
                                          bottomHeight);
        }

    }

    return region;
}

BlurRegion BlurEffect::blurRegion(EffectWindow *w, const BorderRadius *fallbackCornerRadius) const
{
    BlurRegion region = contentRegion(w, fallbackCornerRadius);

    if (auto it = m_windows.find(w); it != m_windows.end()) {
        const std::optional<BlurRegion> &frame = it->second.frame;
        if (frame.has_value()) {
            region += frame.value();
        }
    }

    return region;
}

QRectF BlurEffect::dynamicCornerRect(EffectWindow *w) const
{
    if (w->isDock()) {
        const BlurRegion region = blurRegion(w);
        if (!region.isEmpty()) {
            return QRectF(region.boundingRect()).translated(w->pos());
        }
    }

    return w->frameGeometry();
}

#ifdef GLASS_KWIN_67
void BlurEffect::prePaintScreen(ScreenPrePaintData &data)
#else
void BlurEffect::prePaintScreen(ScreenPrePaintData &data, std::chrono::milliseconds presentTime)
#endif
{
    m_paintedDeviceArea = BlurRegion();
    m_currentDeviceBlur = BlurRegion();
#ifdef GLASS_X11
    m_currentOutput = effects->waylandDisplay() ? data.screen : nullptr;
#else
    m_currentOutput = data.view;
#endif

#ifdef GLASS_KWIN_67
    effects->prePaintScreen(data);
#else
    effects->prePaintScreen(data, presentTime);
#endif
}

#ifdef GLASS_X11
#ifdef GLASS_KWIN_67
void BlurEffect::prePaintWindow(EffectWindow *w, WindowPrePaintData &data)
#else
void BlurEffect::prePaintWindow(EffectWindow *w, WindowPrePaintData &data, std::chrono::milliseconds presentTime)
#endif
{
    // this effect relies on prePaintWindow being called in the bottom to top order
#ifdef GLASS_KWIN_67
    effects->prePaintWindow(w, data);
#else
    effects->prePaintWindow(w, data, presentTime);
#endif

    const QRegion oldOpaque = data.opaque;
    if (data.opaque.intersects(m_currentDeviceBlur)) {
        QRegion newOpaque;
        const int expand = blurExpandSize(w);
        for (const QRect &rect : data.opaque) {
            newOpaque += rect.adjusted(expand, expand, -expand, -expand);
        }
        data.opaque = newOpaque;
        m_currentDeviceBlur -= newOpaque;
    }

    if ((data.paint - oldOpaque).intersects(m_currentDeviceBlur)) {
        data.paint += m_currentDeviceBlur;
    }

    const QRegion blurArea = blurRegion(w).boundingRect().translated(w->pos().toPoint());
    if (m_paintedDeviceArea.intersects(blurArea) || data.paint.intersects(blurArea)) {
        data.paint += blurArea;
        if (blurArea.intersects(m_currentDeviceBlur)) {
            data.paint += m_currentDeviceBlur;
        }
    }

    m_currentDeviceBlur += blurArea;
    m_paintedDeviceArea -= data.opaque;
    m_paintedDeviceArea += data.paint;
}
#else
#ifdef GLASS_KWIN_67
// KWin 6.7: prePaintWindow is intentionally NOT overridden.
//
// Previously this called data.setTranslucent() for blurred windows, which
// marks them as non-opaque in paintSimpleScreen's occlusion cull.  That
// prevents visible -= deviceOpaque for the dock, so the WALL keeps painting
// behind it -- but it also means the dock's own drawWindow() uses
// PAINT_WINDOW_TRANSLUCENT, so effects->drawWindow() composites the dock
// semi-transparently over whatever is already in the renderTarget.
//
// When a popup appears/disappears, the screen damage is narrow (the popup's
// footprint).  The dock's deviceRegion shrinks to that sliver, so
// renderTarget is NOT cleared outside it -- it retains the previous frame's
// (blur + dock) content.  The blur onscreen pass then uses GL_BLEND to
// composite over that stale content, producing a double-rendered flicker.
//
// Upstream KDE 6.7.3 blur does not override prePaintWindow.  Instead it
// relies on BackgroundEffectItem + setPixelsToExpandRepaintsBelowOpaqueRegions
// to expand the repaint region via the forceTranslucent mechanism in
// collectDamage(), which subtracts the blur area from the dock's opaque
// region so the WALL repaints behind it -- without marking the dock
// translucent for compositing.
#else
void BlurEffect::prePaintWindow(RenderView *view, EffectWindow *w, WindowPrePaintData &data, std::chrono::milliseconds presentTime)
{
    effects->prePaintWindow(view, w, data, presentTime);

    const Region blurArea = view->mapToDeviceCoordinatesAligned(
        QRectF(blurRegion(w).boundingRect()).translated(w->pos())
    );

    if (!blurArea.isEmpty()) {
        data.deviceOpaque -= blurArea;

        Region expandedBlur = blurArea;
        const int expand = blurExpandSize(w);
        for (const Rect &rect : blurArea.rects()) {
            expandedBlur += rect.adjusted(-expand, -expand, expand, expand);
        }

        data.devicePaint += (expandedBlur - data.deviceOpaque);
    }

    if (m_paintedDeviceArea.intersects(blurArea) || data.devicePaint.intersects(blurArea)) {
        data.devicePaint += blurArea;
        if (blurArea.intersects(m_currentDeviceBlur)) {
            data.devicePaint += m_currentDeviceBlur;
        }
    }

    m_currentDeviceBlur += blurArea;
    m_paintedDeviceArea -= data.deviceOpaque;
    m_paintedDeviceArea += data.devicePaint;
}
#endif
#endif

bool BlurEffect::shouldBlur(const EffectWindow *w, int mask, const WindowPaintData &data) const
{
    if (effects->activeFullScreenEffect() && !w->data(WindowForceBlurRole).toBool()) {
        return false;
    }

    // KOS: the Dock animation owns this window while it flies to or from the
    // Dock. Glass regions are anchored to the window's original frame, so they
    // cannot follow the deformation; the animation therefore fades the glass
    // material out and back in through a data role instead of leaving a frozen
    // blurred strip behind (or switching the blur back on in one step).
    // The role is written by integrations/kwin/dock-window-animation.

    if (w->isDesktop()) {
        return false;
    }

    const auto windowClass = w->window()->resourceClass();
    const auto resourceName = w->window()->resourceName();
    const auto blurData = m_windows.find(const_cast<EffectWindow *>(w));
    const bool explicitlyRequestedBlur = blurData != m_windows.end()
        && blurData->second.hasExplicitBlurRequest;

    // Layer-shell clients may expose either "quickshell" or an application
    // id such as "org.quickshell".  Match both resource fields instead of
    // relying on a single exact, user-maintained window-class entry. These
    // filters govern forced blur only: a normal application that explicitly
    // publishes a blur-behind region must retain the standard KDE contract.
    if (!explicitlyRequestedBlur && m_settings.forceBlur.onlyQuickshell) {
        if (!isQuickshellWindow(w)) {
            return false;
        }
    }

    auto classes = m_windowClasses;

    // Add some apps to the exclusion list
    if (!m_whitelist) {
      classes << QString("xwaylandvideobridge");
    }

    const auto matches = classes.contains(windowClass) || classes.contains(resourceName);

    if (!explicitlyRequestedBlur
        && ((m_whitelist && !matches) || (!m_whitelist && matches))) {
        return false;
    }

    // special condition for spectacle
    if (windowClass.contains("spectacle")) {
        const KWin::Layer layer = w->window()->layer();
        if (layer == KWin::Layer::OverlayLayer || layer == KWin::Layer::ActiveLayer) {
            return false;
        }
    }

    bool scaled = !qFuzzyCompare(data.xScale(), 1.0) && !qFuzzyCompare(data.yScale(), 1.0);
    bool translated = data.xTranslation() || data.yTranslation();

    if ((scaled || (translated || (mask & PAINT_WINDOW_TRANSFORMED))) && !w->data(WindowForceBlurRole).toBool()) {
        return false;
    }

    return true;
}

void BlurEffect::drawWindow(const RenderTarget &renderTarget, const RenderViewport &viewport, EffectWindow *w, int mask, const BlurRegion &deviceRegion, WindowPaintData &data)
{
    blur(renderTarget, viewport, w, mask, deviceRegion, data);

    // Draw the window over the blurred area
    effects->drawWindow(renderTarget, viewport, w, mask, deviceRegion, data);
}

GLTexture *BlurEffect::ensureNoiseTexture(int noiseStrength)
{
    if (noiseStrength == 0) {
        return nullptr;
    }

    const qreal scale = std::max(1.0, QGuiApplication::primaryScreen()->logicalDotsPerInch() / 96.0);
    if (!m_noisePass.noiseTexture || m_noisePass.noiseTextureScale != scale || m_noisePass.noiseTextureStength != noiseStrength) {
        // Init randomness based on time
        std::srand((uint)QTime::currentTime().msec());

        QImage noiseImage(QSize(256, 256), QImage::Format_Grayscale8);

        for (int y = 0; y < noiseImage.height(); y++) {
            uint8_t *noiseImageLine = (uint8_t *)noiseImage.scanLine(y);

            for (int x = 0; x < noiseImage.width(); x++) {
                noiseImageLine[x] = std::rand() % noiseStrength;
            }
        }

        noiseImage = noiseImage.scaled(noiseImage.size() * scale);

        m_noisePass.noiseTexture = GLTexture::upload(noiseImage);
        if (!m_noisePass.noiseTexture) {
            return nullptr;
        }
        m_noisePass.noiseTexture->setFilter(GL_NEAREST);
        m_noisePass.noiseTexture->setWrapMode(GL_REPEAT);
        m_noisePass.noiseTextureScale = scale;
        m_noisePass.noiseTextureStength = noiseStrength;
    }

    return m_noisePass.noiseTexture.get();
}

void BlurEffect::blur(const RenderTarget &renderTarget, const RenderViewport &viewport, EffectWindow *w, int mask, const BlurRegion &deviceRegion, WindowPaintData &data)
{
    auto it = m_windows.find(w);
    if (it == m_windows.end()) {
        return;
    }

    BlurEffectData &blurInfo = it->second;
    BlurRenderData &renderInfo = blurInfo.render[m_currentOutput];
    if (!shouldBlur(w, mask, data)) {
        return;
    }

    QVector<SurfaceShape> declaredSurfaceShapes;
#ifndef GLASS_X11
    if (m_surfaceShapeManager && w->surface()) {
        declaredSurfaceShapes = m_surfaceShapeManager->shapesFor(w->surface());
    }
#endif

    auto transformShape = [&](BlurRegion shape) {
        shape.translate(w->pos().toPoint());
        if (data.xScale() != 1 || data.yScale() != 1) {
            QPoint pt = shape.boundingRect().topLeft();
            BlurRegion scaledShape;
#ifdef GLASS_X11
            for (const QRect &r : shape) {
#else
            for (const Rect &r : shape.rects()) {
#endif
                const QPointF topLeft(pt.x() + (r.x() - pt.x()) * data.xScale() + data.xTranslation(),
                                      pt.y() + (r.y() - pt.y()) * data.yScale() + data.yTranslation());
                const QPoint bottomRight(std::floor(topLeft.x() + r.width() * data.xScale()) - 1,
                                         std::floor(topLeft.y() + r.height() * data.yScale()) - 1);
                scaledShape += QRect(QPoint(std::floor(topLeft.x()), std::floor(topLeft.y())), bottomRight);
            }
            return scaledShape;
        }
        if (data.xTranslation() || data.yTranslation()) {
            shape.translate(std::round(data.xTranslation()), std::round(data.yTranslation()));
        }
        return shape;
    };

    BorderRadius cornerRadius = w->window()->borderRadius();
    if (!blurInfo.originalCornerRadius.has_value()) {
        blurInfo.originalCornerRadius = cornerRadius;
    }
    bool isOverRounded = false;

    const bool isQuickshellWindowSurface = isQuickshellWindow(w);
    // KOS: the liquid material is tied to a declared shape, not merely to being a
    // Quickshell window. Declared shapes are the geometry that material is drawn
    // from, and the glass forms declare one per card; a Quickshell surface that
    // declares nothing therefore stays on the plain blur pipeline and never
    // enters refraction, glints, or liquid noise. That is what lets the Material
    // form read as frost instead of as glass -- its cards paint themselves and
    // publish a blur region, and publish no shape at all.
    const bool usesGlobalQuickshellMaterial = isQuickshellWindowSurface
        && !declaredSurfaceShapes.isEmpty();
    // Geometry, unlike the material, still follows the window itself: the region
    // has to keep being reconstructed as a shell card whether or not a shape was
    // declared. Ordinary windows keep the same blur pipeline but never enter
    // refraction, glints, or liquid noise.
    const bool isQuickshellSurface = isQuickshellWindowSurface
        || !declaredSurfaceShapes.isEmpty();
    // The window's own corner radius still feeds the region reconstruction
    // (contentRegion()) and, through setBorderRadius() below, KWin's own
    // window rounding for *every* surface -- zeroing it for non-Quickshell
    // windows squared off corners this effect does not own.
    cornerRadius = effectiveWindowCornerRadius(w, blurInfo.originalCornerRadius.value(), &isOverRounded);

    const BlurRegion effectShape = transformShape(blurRegion(w, &cornerRadius));
    const BlurRegion contentShape = transformShape(contentRegion(w, &cornerRadius));
    const BlurRegion frameShape = effectShape - contentShape;
    const BlurPipelineSettings &contentBlurSettings = w->isDock()
        ? m_dockBlurSettings
        : m_contentBlurSettings;
    const BlurPipelineSettings &combinedBlurSettings =
        (contentShape.isEmpty() && !frameShape.isEmpty()) ? m_decorationBlurSettings : contentBlurSettings;
    const bool splitBlurSettings = !frameShape.isEmpty() &&
        !contentShape.isEmpty();
    const bool splitDecorationSettings = m_settings.general.excludeDecorations &&
        !frameShape.isEmpty() &&
        !contentShape.isEmpty();
    const bool splitRenderRegions = splitBlurSettings || splitDecorationSettings;
    const QRect backgroundRect = effectShape.boundingRect();
#ifdef GLASS_X11
    const QRect scaledBackgroundRect = snapToPixelGrid(scaledRect(backgroundRect, viewport.scale()));
    const QRect deviceBackgroundRect = scaledBackgroundRect;
#else
    const QRectF scaledLogicalBackgroundRect(backgroundRect.x() * viewport.scale(),
                                             backgroundRect.y() * viewport.scale(),
                                             backgroundRect.width() * viewport.scale(),
                                             backgroundRect.height() * viewport.scale());
    const QRect scaledBackgroundRect = snapToPixelGrid(scaledLogicalBackgroundRect);
    const QRect deviceBackgroundRect = viewport.mapToDeviceCoordinates(Rect(backgroundRect)).rounded();
#endif
    const auto opacity = data.opacity();

    // Get the effective shape that will be painted on screen. It's possible that all of it will be clipped.
    auto buildEffectiveShape = [&](const BlurRegion &shape) {
#ifdef GLASS_X11
        QList<QRectF> effectiveShape;
        effectiveShape.reserve(shape.rectCount());
        if (deviceRegion != infiniteRegion()) {
            for (const QRect &clipRect : deviceRegion) {
                const QRectF deviceClipRect = snapToPixelGridF(scaledRect(clipRect, viewport.scale()))
                                                  .translated(-deviceBackgroundRect.topLeft());
                for (const QRect &shapeRect : shape) {
                    const QRectF deviceShapeRect = snapToPixelGridF(scaledRect(shapeRect.translated(-backgroundRect.topLeft()), viewport.scale()));
                    if (const QRectF intersected = deviceClipRect.intersected(deviceShapeRect); !intersected.isEmpty()) {
                        effectiveShape.append(intersected);
                    }
                }
            }
        } else {
            for (const QRect &rect : shape) {
                effectiveShape.append(snapToPixelGridF(scaledRect(rect.translated(-backgroundRect.topLeft()), viewport.scale())));
            }
        }
        return effectiveShape;
#else
        QList<RectF> effectiveShape;
        effectiveShape.reserve(shape.rects().size());
        if (deviceRegion != Region::infinite()) {
            for (const Rect &clipRect : deviceRegion.rects()) {
                const RectF deviceClipRect = clipRect.translated(-deviceBackgroundRect.topLeft());
                for (const Rect &shapeRect : shape.rects()) {
                    const RectF deviceShapeRect = shapeRect.translated(-backgroundRect.topLeft()).scaled(viewport.scale()).rounded();
                    if (const QRectF intersected = deviceClipRect.intersected(deviceShapeRect); !intersected.isEmpty()) {
                        effectiveShape.append(intersected);
                    }
                }
            }
        } else {
            for (const Rect &rect : shape.rects()) {
                effectiveShape.append(rect.translated(-backgroundRect.topLeft()).scaled(viewport.scale()).rounded());
            }
        }
        return effectiveShape;
#endif
    };

    const auto effectiveEffectShape = buildEffectiveShape(effectShape);
    auto effectiveContentShape = splitRenderRegions ? buildEffectiveShape(contentShape) : effectiveEffectShape;
    const auto effectiveFrameShape = splitRenderRegions ? buildEffectiveShape(frameShape) : decltype(effectiveEffectShape){};

    struct SurfaceShapeDraw
    {
        SurfaceShape shape;
        decltype(effectiveContentShape) rects;
        QRectF nativeBox;
        int vertexOffset = 0;
        int vertexCount = 0;
        // Compositor blur level 1..15 requested by set_blur, clamped to the
        // strength table. 0 = follow the window's default blur pipeline.
        int blurLevel = 0;
    };
    QVector<SurfaceShapeDraw> surfaceShapeDraws;

    if (effectiveEffectShape.isEmpty()) {
        return;
    }

    // Explicit protocol shapes replace only the compositor's reconstructed
    // content geometry. Blur Region still decides which background pixels are
    // captured; the protocol supplies the exact anti-aliased output outline.
    //
    // The swap is all-or-nothing, and it is committed only after at least one
    // shape turned into geometry to draw. A shape that is off-screen, clipped
    // away or zero-sized must not take the surface's whole glass with it: the
    // region geometry it was meant to refine is then the only thing left, and
    // dropping it leaves the window unblurred until something else happens to
    // damage those pixels. That reads as "the middle of the Dock has no glass"
    // rather than as a missing shape.
    if (!declaredSurfaceShapes.isEmpty() && frameShape.isEmpty()) {
        QVector<SurfaceShapeDraw> draws;
        decltype(effectiveContentShape) shapeGeometry;
        // The blur protocol reaches us in compositor coordinates, whereas
        // SurfaceShape geometry is surface-local. Align the complete declared
        // shape set with the already transformed blur region before producing
        // texture-local vertices. Using transformShape() here is insufficient
        // for layer-shell surfaces whose blur region has already been placed
        // by KWin; it leaves nested cards offset inside the cropped texture.
        QRect declaredShapeBounds;
        for (const SurfaceShape &shape : declaredSurfaceShapes) {
            declaredShapeBounds = declaredShapeBounds.united(
                shape.geometry.toAlignedRect());
        }
        const QPoint declaredShapeTranslation = effectShape.boundingRect().topLeft()
            - declaredShapeBounds.topLeft();
        // The declared set has to describe the same thing as the region: the
        // alignment below is one translation for all of it, so a set that is a
        // strict subset (or superset) of the region shifts every shape by the
        // difference -- a card panel whose overlay sheet was left out of the
        // union slid its whole glass by 238px. Report it (the geometry below is
        // still the best available guess) rather than fail silently.
        if (declaredShapeBounds.size() != effectShape.boundingRect().size()
            || declaredShapeTranslation != QPoint(0, 0)) {
            if (shapeTraceEnabled()) {
                qCWarning(shapeTraceCategory())
                    << "declared shape set does not match the blur region;"
                    << "shapes:" << declaredShapeBounds << "region:" << effectShape.boundingRect()
                    << "translation:" << declaredShapeTranslation;
            }
            // KOS: a declared set that does not describe this surface's region
            // cannot supply its material geometry. Left alone, the alignment
            // below applies one translation for every shape and slides the
            // whole card's glass by the difference -- which is what a region
            // shaped by one of the cards (the desk clock's gear) triggers, since
            // that card deliberately declares no shape: the declared set becomes
            // a strict subset of the region.
            //
            // Dropping the draws leaves surfaceShapeDraws empty, and the
            // region-driven path below then supplies both the geometry and the
            // blur level from the region the compositor actually published.
            draws.clear();
            shapeGeometry = decltype(shapeGeometry){};
        }
        for (const SurfaceShape &shape : declaredSurfaceShapes) {
            const QRect logicalRect = shape.geometry.toAlignedRect();
            if (logicalRect.isEmpty()) {
                continue;
            }
            BlurRegion shapeRegion;
#ifdef GLASS_X11
            shapeRegion += logicalRect;
#else
            shapeRegion += Rect(logicalRect);
#endif
            shapeRegion.translate(declaredShapeTranslation);
            const BlurRegion transformedShape = shapeRegion;
            if (!transformedShape.intersects(effectShape)) {
                continue;
            }
            SurfaceShapeDraw draw;
            draw.shape = shape;
            draw.rects = buildEffectiveShape(transformedShape);
            if (draw.rects.isEmpty()) {
                continue;
            }
            if (shape.blurEnabled && !blurStrengthValues.isEmpty()) {
                draw.blurLevel = qBound(1, int(shape.blurLevel), int(blurStrengthValues.size()));
            }
            const QRect transformedBounds = transformedShape.boundingRect();
#ifdef GLASS_X11
            draw.nativeBox = snapToPixelGridF(scaledRect(transformedBounds,
                viewport.scale())).translated(-scaledBackgroundRect.topLeft());
#else
            draw.nativeBox = QRectF(transformedBounds.x() * viewport.scale(),
                transformedBounds.y() * viewport.scale(),
                transformedBounds.width() * viewport.scale(),
                transformedBounds.height() * viewport.scale())
                .translated(-scaledBackgroundRect.topLeft());
#endif
            shapeGeometry.append(draw.rects);
            draws.append(draw);
        }
        if (!draws.isEmpty()) {
            effectiveContentShape = shapeGeometry;
            surfaceShapeDraws = draws;
        } else if (shapeTraceEnabled()) {
            qCWarning(shapeTraceCategory())
                << "glass trace: shapes declared but none drawable, keeping the"
                << "blur region geometry;" << (w && w->surface() ? "window" : "no-window")
                << "declared" << declaredSurfaceShapes.size()
                << "effectShape" << effectShape.boundingRect();
        }
    }

    // ── KOS: region-shaped material for a surface with no declared shape ─────
    //
    // A surface can publish a blur region of any shape — the region is a list of
    // rectangles and the compositor blurs exactly what they cover — but its
    // *material* is drawn from the SurfaceShape declarations, and
    // kos_surface_shape_v1 can only declare a rectangle with rounded corners.
    // The desk clock's gear therefore publishes a region and no shape at all.
    //
    // Without a declaration there is also no per-shape blur level, so such a
    // surface falls back to the window's content strength. On this shell that is
    // BlurStrength=1, a single down/up pass: the finish then reads as a tinted
    // plate rather than as frosted. Adopt the region's own geometry as the
    // material shape and floor the blur level, so a region-shaped surface gets
    // the frost its shape implies. kwinrc can still raise it via BlurStrength.
    //
    // The geometry needs no work here: effectiveContentShape was initialised
    // from the blur region at the top of this function, and neither overriding
    // branch below can have run, because a declared shape set is precisely what
    // this case does not have.
    //
    // The Quickshell gate is load-bearing: ordinary blurred windows also publish
    // a region and declare no shape, and their blur must keep following the
    // strength kwinrc actually asks for instead of this floor.
    constexpr int kMinimumRegionMaterialLevel = 6;
    if (isQuickshellSurface && surfaceShapeDraws.isEmpty() && !contentShape.isEmpty()) {
        SurfaceShapeDraw draw;
        draw.rects = buildEffectiveShape(contentShape);
        if (!draw.rects.isEmpty()) {
            draw.blurLevel = qBound(1,
                std::max(kMinimumRegionMaterialLevel,
                    static_cast<int>(m_settings.general.blurStrength)),
                static_cast<int>(blurStrengthValues.size()));
            const QRect transformedBounds = contentShape.boundingRect();
#ifdef GLASS_X11
            draw.nativeBox = snapToPixelGridF(scaledRect(transformedBounds,
                viewport.scale())).translated(-scaledBackgroundRect.topLeft());
#else
            draw.nativeBox = QRectF(transformedBounds.x() * viewport.scale(),
                transformedBounds.y() * viewport.scale(),
                transformedBounds.width() * viewport.scale(),
                transformedBounds.height() * viewport.scale())
                .translated(-scaledBackgroundRect.topLeft());
#endif
            surfaceShapeDraws.append(draw);
        }
    }

    // Maybe reallocate offscreen render targets. Keep in mind that the first one contains
    // original background behind the window, it's not blurred.
    GLenum textureFormat = GL_RGBA8;
    if (renderTarget.texture()) {
        textureFormat = renderTarget.texture()->internalFormat();
    }

    if (renderInfo.framebuffers.size() != (m_maxIterationCount + 1) || renderInfo.textures[0]->size() != backgroundRect.size() || renderInfo.textures[0]->internalFormat() != textureFormat) {
        renderInfo.framebuffers.clear();
        renderInfo.textures.clear();

        glClearColor(0, 0, 0, 0);
        for (size_t i = 0; i <= m_maxIterationCount; ++i) {
            // Dual Kawase halves each level. Very thin blur regions (for
            // example KOS's 6 px dock reveal handle) eventually truncate to
            // zero in one dimension. Keep those levels valid without skipping
            // the window's early animation frames altogether.
            const QSize textureSize = (backgroundRect.size() / (1 << i)).expandedTo(QSize(1, 1));
            auto texture = GLTexture::allocate(textureFormat, textureSize);
            if (!texture) {
                qCWarning(KWIN_BLUR) << "Failed to allocate an offscreen texture";
                return;
            }
            texture->setFilter(GL_LINEAR);
            texture->setWrapMode(GL_CLAMP_TO_EDGE);

            auto framebuffer = std::make_unique<GLFramebuffer>(texture.get());
            if (!framebuffer->valid()) {
                qCWarning(KWIN_BLUR) << "Failed to create an offscreen framebuffer";
                return;
            }
#ifdef GLASS_X11
            GLFramebuffer::pushFramebuffer(framebuffer.get());
            glClear(GL_COLOR_BUFFER_BIT);
            GLFramebuffer::popFramebuffer();
#else
            EglContext::currentContext()->pushFramebuffer(framebuffer.get());
            glClear(GL_COLOR_BUFFER_BIT);
            EglContext::currentContext()->popFramebuffer();
#endif
            renderInfo.textures.push_back(std::move(texture));
            renderInfo.framebuffers.push_back(std::move(framebuffer));
        }
    }

    // Fetch the pixels behind the shape that is going to be blurred.
#ifdef GLASS_X11
    const QRegion dirtyRegion = deviceRegion & backgroundRect;
    for (const QRect &dirtyRect : dirtyRegion) {
        renderInfo.framebuffers[0]->blitFromRenderTarget(renderTarget, viewport, dirtyRect, dirtyRect.translated(-backgroundRect.topLeft()));
    }
#else
    const Region dirtyRegion = viewport.mapFromDeviceCoordinatesContained(deviceRegion) & backgroundRect;
    for (const Rect &dirtyRect : dirtyRegion.rects()) {
        renderInfo.framebuffers[0]->blitFromRenderTarget(renderTarget, viewport, dirtyRect, dirtyRect.translated(-backgroundRect.topLeft()));
    }
#endif

    // Upload the geometry: the first 6 vertices are used when downsampling and upsampling offscreen,
    // the remaining vertices are used when rendering on the screen.
    GLVertexBuffer *vbo = GLVertexBuffer::streamingBuffer();
    vbo->reset();
    vbo->setAttribLayout(std::span(GLVertexBuffer::GLVertex2DLayout), sizeof(GLVertex2D));

    const int contentVertexCount = effectiveContentShape.size() * 6;
    const int frameVertexCount = effectiveFrameShape.size() * 6;
    const int vertexCount = splitRenderRegions ? (contentVertexCount + frameVertexCount) : contentVertexCount;
    if (auto result = vbo->map<GLVertex2D>(6 + vertexCount)) {
        auto map = *result;

        size_t vboIndex = 0;

        // The geometry that will be blurred offscreen, in logical pixels.
        {
            const QRectF localRect = QRectF(0, 0, backgroundRect.width(), backgroundRect.height());

            const float x0 = localRect.left();
            const float y0 = localRect.top();
            const float x1 = localRect.right();
            const float y1 = localRect.bottom();

            const float u0 = x0 / backgroundRect.width();
            const float v0 = 1.0f - y0 / backgroundRect.height();
            const float u1 = x1 / backgroundRect.width();
            const float v1 = 1.0f - y1 / backgroundRect.height();

            // first triangle
            map[vboIndex++] = GLVertex2D{
                .position = QVector2D(x0, y0),
                .texcoord = QVector2D(u0, v0),
            };
            map[vboIndex++] = GLVertex2D{
                .position = QVector2D(x1, y1),
                .texcoord = QVector2D(u1, v1),
            };
            map[vboIndex++] = GLVertex2D{
                .position = QVector2D(x0, y1),
                .texcoord = QVector2D(u0, v1),
            };

            // second triangle
            map[vboIndex++] = GLVertex2D{
                .position = QVector2D(x0, y0),
                .texcoord = QVector2D(u0, v0),
            };
            map[vboIndex++] = GLVertex2D{
                .position = QVector2D(x1, y0),
                .texcoord = QVector2D(u1, v0),
            };
            map[vboIndex++] = GLVertex2D{
                .position = QVector2D(x1, y1),
                .texcoord = QVector2D(u1, v1),
            };
        }

        auto appendScreenGeometry = [&](const auto &shapeRects) {
            for (const auto &rect : shapeRects) {
                const float x0 = rect.left();
                const float y0 = rect.top();
                const float x1 = rect.right();
                const float y1 = rect.bottom();

                const float u0 = x0 / scaledBackgroundRect.width();
                const float v0 = 1.0f - y0 / scaledBackgroundRect.height();
                const float u1 = x1 / scaledBackgroundRect.width();
                const float v1 = 1.0f - y1 / scaledBackgroundRect.height();

                map[vboIndex++] = GLVertex2D{
                    .position = QVector2D(x0, y0),
                    .texcoord = QVector2D(u0, v0),
                };
                map[vboIndex++] = GLVertex2D{
                    .position = QVector2D(x1, y1),
                    .texcoord = QVector2D(u1, v1),
                };
                map[vboIndex++] = GLVertex2D{
                    .position = QVector2D(x0, y1),
                    .texcoord = QVector2D(u0, v1),
                };

                map[vboIndex++] = GLVertex2D{
                    .position = QVector2D(x0, y0),
                    .texcoord = QVector2D(u0, v0),
                };
                map[vboIndex++] = GLVertex2D{
                    .position = QVector2D(x1, y0),
                    .texcoord = QVector2D(u1, v0),
                };
                map[vboIndex++] = GLVertex2D{
                    .position = QVector2D(x1, y1),
                    .texcoord = QVector2D(u1, v1),
                };
            }
        };

        if (surfaceShapeDraws.isEmpty()) {
            appendScreenGeometry(effectiveContentShape);
        } else {
            int shapeOffset = 6;
            for (SurfaceShapeDraw &draw : surfaceShapeDraws) {
                draw.vertexOffset = shapeOffset;
                draw.vertexCount = draw.rects.size() * 6;
                appendScreenGeometry(draw.rects);
                shapeOffset += draw.vertexCount;
            }
        }
        if (splitBlurSettings) {
            appendScreenGeometry(effectiveFrameShape);
        }

        vbo->unmap();
    } else {
        qCWarning(KWIN_BLUR) << "Failed to map vertex buffer";
        return;
    }

    vbo->bindArrays();

    // Whole-surface scrim tone. A scrim that read the per-pixel backdrop
    // luminance turned a variegated wallpaper into uneven light/dark blocks
    // inside one panel. Instead, reduce the captured backdrop to a 1x1 average
    // (pure GPU, no readback) and let every fragment share that single value.
    const bool windowScrim = std::any_of(
        declaredSurfaceShapes.begin(), declaredSurfaceShapes.end(),
        [](const SurfaceShape &shape) { return shape.scrimEnabled; });
    GLTexture *scrimAvg = nullptr;
    if (windowScrim && renderInfo.framebuffers[0]
            && !backgroundRect.isEmpty()) {
        const int longest = std::max(backgroundRect.width(), backgroundRect.height());
        int levels = 0;
        for (int side = longest; side > 1; side >>= 1)
            ++levels;
        if (levels <= 0) {
            scrimAvg = renderInfo.framebuffers[0]->colorAttachment();
        } else {
            if (renderInfo.scrimAvgLevels != levels
                || renderInfo.scrimAvgSize != backgroundRect.size()
                || renderInfo.scrimAvgFramebuffers.size() != static_cast<size_t>(levels)) {
                renderInfo.scrimAvgFramebuffers.clear();
                renderInfo.scrimAvgTextures.clear();
                // Zeroed until the chain is complete: a partially filled cache
                // must not look valid to the next frame.
                renderInfo.scrimAvgLevels = 0;
                for (int i = 0; i < levels; ++i) {
                    const QSize size = (backgroundRect.size() / (1 << (i + 1))).expandedTo(QSize(1, 1));
                    auto texture = GLTexture::allocate(textureFormat, size);
                    if (!texture) {
                        qCWarning(KWIN_BLUR) << "Failed to allocate a scrim average texture";
                        return;
                    }
                    texture->setFilter(GL_LINEAR);
                    texture->setWrapMode(GL_CLAMP_TO_EDGE);
                    auto framebuffer = std::make_unique<GLFramebuffer>(texture.get());
                    if (!framebuffer->valid()) {
                        qCWarning(KWIN_BLUR) << "Failed to create a scrim average framebuffer";
                        return;
                    }
#ifdef GLASS_X11
                    GLFramebuffer::pushFramebuffer(framebuffer.get());
                    glClear(GL_COLOR_BUFFER_BIT);
                    GLFramebuffer::popFramebuffer();
#else
                    EglContext::currentContext()->pushFramebuffer(framebuffer.get());
                    glClear(GL_COLOR_BUFFER_BIT);
                    EglContext::currentContext()->popFramebuffer();
#endif
                    renderInfo.scrimAvgTextures.push_back(std::move(texture));
                    renderInfo.scrimAvgFramebuffers.push_back(std::move(framebuffer));
                }
                renderInfo.scrimAvgSize = backgroundRect.size();
                renderInfo.scrimAvgLevels = levels;
            }

            // Halve each level with the same box-average pass the blur uses,
            // reaching 1x1 (a single texel = the whole-surface mean colour).
            ShaderManager::instance()->pushShader(m_downsamplePass.shader.get());
            QMatrix4x4 projectionMatrix;
            projectionMatrix.ortho(QRectF(0.0, 0.0, backgroundRect.width(), backgroundRect.height()));
            m_downsamplePass.shader->setUniform(m_downsamplePass.mvpMatrixLocation, projectionMatrix);
            m_downsamplePass.shader->setUniform(m_downsamplePass.offsetLocation, 1.0f);
            GLTexture *read = renderInfo.framebuffers[0]->colorAttachment();
            for (int i = 0; i < levels && read; ++i) {
                const QVector2D halfpixel(0.5f / read->width(), 0.5f / read->height());
                m_downsamplePass.shader->setUniform(m_downsamplePass.halfpixelLocation, halfpixel);
                glActiveTexture(GL_TEXTURE0);
                read->bind();
                EglContext::currentContext()->pushFramebuffer(renderInfo.scrimAvgFramebuffers[i].get());
                vbo->draw(GL_TRIANGLES, 0, 6);
                EglContext::currentContext()->popFramebuffer();
                read = renderInfo.scrimAvgFramebuffers[i]->colorAttachment();
            }
            ShaderManager::instance()->popShader();
            scrimAvg = read;
        }
    }

    auto runBlurPass = [&](const BlurPipelineSettings &settings) -> GLTexture * {
        ShaderManager::instance()->pushShader(m_downsamplePass.shader.get());

        QMatrix4x4 projectionMatrix;
        projectionMatrix.ortho(QRectF(0.0, 0.0, backgroundRect.width(), backgroundRect.height()));

        m_downsamplePass.shader->setUniform(m_downsamplePass.mvpMatrixLocation, projectionMatrix);
        m_downsamplePass.shader->setUniform(m_downsamplePass.offsetLocation, settings.offset * m_blurRadius);

        for (size_t i = 1; i <= settings.iterationCount; ++i) {
            const auto &read = renderInfo.framebuffers[i - 1];
            const auto &draw = renderInfo.framebuffers[i];

            const QVector2D halfpixel(0.5 / read->colorAttachment()->width(),
                                      0.5 / read->colorAttachment()->height());
            m_downsamplePass.shader->setUniform(m_downsamplePass.halfpixelLocation, halfpixel);

            glActiveTexture(GL_TEXTURE0);
            read->colorAttachment()->bind();

            GLFramebuffer::pushFramebuffer(draw.get());
            vbo->draw(GL_TRIANGLES, 0, 6);
        }

        ShaderManager::instance()->popShader();

        ShaderManager::instance()->pushShader(m_upsamplePass.shader.get());

        m_upsamplePass.shader->setUniform(m_upsamplePass.mvpMatrixLocation, projectionMatrix);
        m_upsamplePass.shader->setUniform(m_upsamplePass.offsetLocation, settings.offset * m_upsampleOffset);

        const float upsampleSaturationBoost = m_settings.general.saturationCompensation
            ? (1.18f + 0.13f * (m_blurRadius + m_upsampleOffset) * 0.5f)
            : 1.0f;

        for (size_t i = settings.iterationCount; i > 1; --i) {
            GLFramebuffer::popFramebuffer();
            const auto &read = renderInfo.framebuffers[i];

            const QVector2D halfpixel(0.5 / read->colorAttachment()->width(),
                                      0.5 / read->colorAttachment()->height());
            m_upsamplePass.shader->setUniform(m_upsamplePass.halfpixelLocation, halfpixel);
            m_upsamplePass.shader->setUniform(m_upsamplePass.saturationCompensationLocation, i == 2 ? upsampleSaturationBoost : 1.0f);

            glActiveTexture(GL_TEXTURE0);
            read->colorAttachment()->bind();

            vbo->draw(GL_TRIANGLES, 0, 6);
        }

        ShaderManager::instance()->popShader();
        GLFramebuffer::popFramebuffer();

        return renderInfo.framebuffers[1]->colorAttachment();
    };

    const QMatrix4x4 &colorMatrix = m_colorMatrix;
    // KOS: fade the whole glass material for a window that the Dock animation
    // is driving. Unset means a fully opaque material, so nothing changes for
    // every other window. The value is written by
    // integrations/kwin/dock-window-animation; both sides must keep the role
    // value in sync.
    static constexpr int KosDockAnimationGlassFadeRole = 0x4b4f5342; // "KOSB"
    const QVariant glassFade = w->data(KosDockAnimationGlassFadeRole);
    const float modulation = opacity * opacity
        * (glassFade.isValid() ? static_cast<float>(glassFade.toReal()) : 1.0f);

    w->window()->setBorderRadius(cornerRadius);


    ShaderManager::instance()->pushShader(m_roundedOnscreenPass.shader.get());

    QMatrix4x4 projectionMatrix = viewport.projectionMatrix();
    projectionMatrix.translate(scaledBackgroundRect.x(), scaledBackgroundRect.y());

    const QVector2D halfpixel(0.5 / renderInfo.framebuffers[1]->colorAttachment()->width(),
                              0.5 / renderInfo.framebuffers[1]->colorAttachment()->height());

    const QRectF transformedRect = QRectF{
        w->frameGeometry().x() + data.xTranslation(),
        w->frameGeometry().y() + data.yTranslation(),
        w->frameGeometry().width() * data.xScale(),
        w->frameGeometry().height() * data.yScale(),
    };
#ifdef GLASS_X11
    const QRectF nativeBox = snapToPixelGridF(scaledRect(transformedRect, viewport.scale()))
                                 .translated(-scaledBackgroundRect.topLeft());
#else
    const QRectF scaledTransformedRect(transformedRect.x() * viewport.scale(),
                                       transformedRect.y() * viewport.scale(),
                                       transformedRect.width() * viewport.scale(),
                                       transformedRect.height() * viewport.scale());
    const QRectF nativeBox = snapToPixelGridF(scaledTransformedRect)
                                 .translated(-scaledBackgroundRect.topLeft());
#endif
    const BorderRadius nativeCornerRadius = cornerRadius.scaled(viewport.scale()).rounded();
    const QVector4D shaderBox = QVector4D(nativeBox.x() + nativeBox.width() * 0.5,
                    nativeBox.y() + nativeBox.height() * 0.5,
                    nativeBox.width() * 0.5,
                    nativeBox.height() * 0.5);

    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.mvpMatrixLocation, projectionMatrix);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.colorMatrixLocation, colorMatrix);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.useOklabSaturationLocation, m_settings.general.oklabSaturation ? 1 : 0);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.saturationLocation, static_cast<float>(m_settings.general.saturation));
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.halfpixelLocation, halfpixel);
    // The shape boxes in this pass are device pixels, the capture the shader
    // samples is logical (backgroundRect.size()); the refraction stage needs the
    // ratio to keep its sample inside the captured backdrop.
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.viewportScaleLocation,
        static_cast<float>(viewport.scale()));
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.offsetLocation, combinedBlurSettings.offset * m_upsampleOffset);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.boxLocation, shaderBox);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.cornerRadiusLocation, nativeCornerRadius.toVector());
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.cornerExponentLocation,
        m_settings.roundedCorners.cornerExponent);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.glassEnabledLocation,
        usesGlobalQuickshellMaterial ? 1 : 0);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.opacityLocation, modulation);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.texUnitLocation, 0);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.edgeSizePixelsLocation, m_settings.refraction.edgeSizePixels);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.refractionStrengthLocation, m_settings.refraction.refractionStrength);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.refractionNormalPowLocation, m_settings.refraction.refractionNormalPow);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.refractionRGBFringingLocation, m_settings.refraction.refractionRGBFringing);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.refractionOffsetStrengthLocation, m_settings.refraction.refractionOffsetStrength);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.materialSoftnessLocation, m_settings.refraction.materialSoftness);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.materialReflectionStrengthLocation, m_settings.refraction.materialReflectionStrength);

    // The glow colour / edge-lighting uniforms that used to be uploaded here
    // were read by nothing in the shader, so every setUniform against them was a
    // silent no-op driven by dead conditions.

    // Contrast scrim defaults to off. A surface that declares a KosRoundedBlurRegion
    // carries per-shape scrim state (see protocolShapeUniforms below); anything that
    // reaches this pass on the region path must not inherit a stale tint.
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.scrimModeLocation, 0);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.scrimCapLocation, 0.0f);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.scrimDecayLocation, 1.0f);
    // One whole-surface scrim value from the 1x1 average above, bound at unit 1
    // so the fragment shader samples one shared tone (no per-pixel banding).
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.scrimLumaTexLocation, 1);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.scrimLumaValidLocation,
        scrimAvg ? 1 : 0);
    if (scrimAvg) {
        glActiveTexture(GL_TEXTURE0 + 1);
        scrimAvg->bind();
        glActiveTexture(GL_TEXTURE0);
    }


    if (shapeTraceEnabled()) {
        // Everything needed to tell "the shape never arrived" apart from "the
        // shape arrived somewhere else" and from "the shader's field rejected
        // it". `box` is the field the SDF is evaluated in, native to the blur
        // texture; each draw's nativeBox has to contain its rects for the
        // gate in onscreen_rounded.glsl to let anything through.
        qCWarning(shapeTraceCategory())
            << "glass trace:" << (isQuickshellSurface ? "quickshell" : "other")
            << "path" << (surfaceShapeDraws.isEmpty() ? "region" : "shapes")
            << "declared" << declaredSurfaceShapes.size()
            << "effectShape" << effectShape.boundingRect()
            << "backgroundRect" << backgroundRect
            << "scaledBackgroundRect" << scaledBackgroundRect
            << "shaderBox" << shaderBox
            << "shaderRadius" << nativeCornerRadius.toVector()
            << "cornerExponent" << m_settings.roundedCorners.cornerExponent
            << "contentVerts" << contentVertexCount;
        for (const SurfaceShapeDraw &draw : surfaceShapeDraws) {
            QRectF rectBounds;
            for (const auto &rect : draw.rects) {
                rectBounds = rectBounds.united(rect);
            }
            qCWarning(shapeTraceCategory())
                << "  shape" << draw.shape.id
                << "geom" << draw.shape.geometry
                << "radius" << draw.shape.radius
                << "exponent" << draw.shape.exponent
                << "nativeBox" << draw.nativeBox
                << "drawnBounds" << rectBounds
                << "rects" << draw.rects.size()
                << "verts" << draw.vertexCount;
        }
    }

    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

    auto drawBlurredRegion = [&](GLTexture *blurredTexture, int vertexOffset, int currentVertexCount, float blurOffset) {
        m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.offsetLocation, blurOffset * m_upsampleOffset);
        glActiveTexture(GL_TEXTURE0);
        blurredTexture->bind();
        vbo->draw(GL_TRIANGLES, vertexOffset, currentVertexCount);
    };

    auto protocolShapeUniforms = [&](const SurfaceShapeDraw &draw) {
        const QVector4D box(draw.nativeBox.x() + draw.nativeBox.width() * 0.5,
            draw.nativeBox.y() + draw.nativeBox.height() * 0.5,
            draw.nativeBox.width() * 0.5, draw.nativeBox.height() * 0.5);
        const float radius = static_cast<float>(std::min(draw.shape.radius
            * viewport.scale(), std::min(draw.nativeBox.width(),
                draw.nativeBox.height()) * 0.5));
        const QVector4D radii(radius, radius, radius, radius);
        m_roundedOnscreenPass.shader->setUniform(
            m_roundedOnscreenPass.boxLocation, box);
        m_roundedOnscreenPass.shader->setUniform(
            m_roundedOnscreenPass.cornerRadiusLocation, radii);
        m_roundedOnscreenPass.shader->setUniform(
            m_roundedOnscreenPass.cornerExponentLocation,
            static_cast<float>(draw.shape.exponent));
        // Shader modes: 1/2 adaptive black/white, 3/4 fixed black/white.
        // decay > 1 is the backward-compatible fixed-mode wire encoding.
        if (draw.shape.scrimEnabled) {
            m_roundedOnscreenPass.shader->setUniform(
                m_roundedOnscreenPass.scrimModeLocation,
                draw.shape.scrimDecay > 3.0 ? 6
                    : draw.shape.scrimDecay > 2.0 ? 5
                    : (draw.shape.scrimDecay > 1.0 ? 3 : 1)
                        + (draw.shape.scrimTint == 1 ? 1 : 0));
            m_roundedOnscreenPass.shader->setUniform(
                m_roundedOnscreenPass.scrimCapLocation,
                static_cast<float>(draw.shape.scrimCap));
            m_roundedOnscreenPass.shader->setUniform(
                m_roundedOnscreenPass.scrimDecayLocation,
                static_cast<float>(std::min(draw.shape.scrimDecay, 1.0)));
        } else {
            m_roundedOnscreenPass.shader->setUniform(
                m_roundedOnscreenPass.scrimModeLocation, 0);
        }
    };

    auto drawNoiseRegion = [&](int noiseStrength, int vertexOffset,
                               int currentVertexCount,
                               const SurfaceShapeDraw *protocolDraw = nullptr) {
        if (noiseStrength <= 0 || currentVertexCount == 0) {
            return;
        }

        if (GLTexture *noiseTexture = ensureNoiseTexture(noiseStrength)) {
            ShaderManager::instance()->pushShader(m_noisePass.shader.get());

            QMatrix4x4 noiseProjectionMatrix = viewport.projectionMatrix();
            noiseProjectionMatrix.translate(scaledBackgroundRect.x(), scaledBackgroundRect.y());

            m_noisePass.shader->setUniform(m_noisePass.mvpMatrixLocation, noiseProjectionMatrix);
            m_noisePass.shader->setUniform(m_noisePass.noiseTextureSizeLocation, QVector2D(noiseTexture->width(), noiseTexture->height()));
            if (protocolDraw) {
                const QRectF &box = protocolDraw->nativeBox;
                const QVector4D shaderShapeBox(box.x() + box.width() * 0.5,
                    box.y() + box.height() * 0.5,
                    box.width() * 0.5, box.height() * 0.5);
                const float radius = static_cast<float>(std::min(
                    protocolDraw->shape.radius * viewport.scale(),
                    std::min(box.width(), box.height()) * 0.5));
                m_noisePass.shader->setUniform(m_noisePass.boxLocation,
                    shaderShapeBox);
                m_noisePass.shader->setUniform(m_noisePass.cornerRadiusLocation,
                    QVector4D(radius, radius, radius, radius));
                m_noisePass.shader->setUniform(m_noisePass.cornerExponentLocation,
                    static_cast<float>(protocolDraw->shape.exponent));
            } else {
                m_noisePass.shader->setUniform(m_noisePass.boxLocation, shaderBox);
                m_noisePass.shader->setUniform(m_noisePass.cornerRadiusLocation,
                    nativeCornerRadius.toVector());
                m_noisePass.shader->setUniform(m_noisePass.cornerExponentLocation,
                    m_settings.roundedCorners.cornerExponent);
            }

            glActiveTexture(GL_TEXTURE0);
            noiseTexture->bind();
            vbo->draw(GL_TRIANGLES, vertexOffset, currentVertexCount);

            ShaderManager::instance()->popShader();
        }
    };

    // Per-shape blur overrides (protocol v4 set_blur) each need their own mip
    // chain: runBlurPass rewrites the shared chain in place and always leaves
    // its result in framebuffers[1], so every distinct override level runs
    // first and copies its result into a scratch texture before the default
    // pass claims framebuffers[1] for itself. The overrides pay one extra
    // full-backgroundRect blur chain plus one blit each; shapes without an
    // override keep rendering exactly as before.
    struct BlurOverridePass
    {
        int level;
        GLTexture *texture;
        float offset;
    };
    QVector<BlurOverridePass> overridePasses;
    if (!surfaceShapeDraws.isEmpty()) {
        const int contentNoiseStrength = splitBlurSettings
            ? contentBlurSettings.noiseStrength
            : combinedBlurSettings.noiseStrength;
        QVector<int> overrideLevels;
        for (const SurfaceShapeDraw &draw : surfaceShapeDraws) {
            if (draw.blurLevel > 0 && !overrideLevels.contains(draw.blurLevel)) {
                overrideLevels.append(draw.blurLevel);
            }
        }
        for (int level : overrideLevels) {
            const BlurPipelineSettings overrideSettings =
                pipelineSettingsForStrength(level - 1, contentNoiseStrength);
            runBlurPass(overrideSettings);
            auto &scratch = renderInfo.blurOverrideScratch[uint(level)];
            const QSize size = renderInfo.framebuffers[1]->colorAttachment()->size();
            if (!scratch.framebuffer || scratch.size != size) {
                auto texture = GLTexture::allocate(
                    renderInfo.framebuffers[1]->colorAttachment()->internalFormat(), size);
                if (texture) {
                    texture->setFilter(GL_LINEAR);
                    texture->setWrapMode(GL_CLAMP_TO_EDGE);
                    auto framebuffer = std::make_unique<GLFramebuffer>(texture.get());
                    if (framebuffer->valid()) {
                        scratch.texture = std::move(texture);
                        scratch.framebuffer = std::move(framebuffer);
                        scratch.size = size;
                    }
                }
            }
            if (!scratch.framebuffer) {
                continue;
            }
            // Copy the pass result out of the shared chain before the next
            // pass overwrites framebuffers[1].
            GLFramebuffer::pushFramebuffer(renderInfo.framebuffers[1].get());
            scratch.framebuffer->blitFromFramebuffer();
            GLFramebuffer::popFramebuffer();
            overridePasses.append({level, scratch.framebuffer->colorAttachment(),
                                   overrideSettings.offset});
        }
    }

    GLTexture *contentBlurredTexture = runBlurPass(splitBlurSettings ? contentBlurSettings : combinedBlurSettings);
    const float contentOffset = splitBlurSettings
        ? contentBlurSettings.offset : combinedBlurSettings.offset;
    if (surfaceShapeDraws.isEmpty()) {
        drawBlurredRegion(contentBlurredTexture, 6, contentVertexCount,
                          contentOffset);
    } else {
        for (const SurfaceShapeDraw &draw : surfaceShapeDraws) {
            protocolShapeUniforms(draw);
            const BlurOverridePass *override = nullptr;
            if (draw.blurLevel > 0) {
                for (const BlurOverridePass &pass : overridePasses) {
                    if (pass.level == draw.blurLevel) {
                        override = &pass;
                        break;
                    }
                }
            }
            drawBlurredRegion(override ? override->texture : contentBlurredTexture,
                              draw.vertexOffset, draw.vertexCount,
                              override ? override->offset : contentOffset);
        }
        m_roundedOnscreenPass.shader->setUniform(
            m_roundedOnscreenPass.boxLocation, shaderBox);
        m_roundedOnscreenPass.shader->setUniform(
            m_roundedOnscreenPass.cornerRadiusLocation,
            nativeCornerRadius.toVector());
        m_roundedOnscreenPass.shader->setUniform(
            m_roundedOnscreenPass.cornerExponentLocation,
            m_settings.roundedCorners.cornerExponent);
    }

    if (splitRenderRegions && frameVertexCount > 0) {
        GLTexture *frameBlurredTexture = splitBlurSettings ? runBlurPass(m_decorationBlurSettings) : contentBlurredTexture;
        drawBlurredRegion(frameBlurredTexture,
                          6 + contentVertexCount,
                          frameVertexCount,
                          splitBlurSettings ? m_decorationBlurSettings.offset : combinedBlurSettings.offset);
    }

    glDisable(GL_BLEND);

    ShaderManager::instance()->popShader();

    if (usesGlobalQuickshellMaterial && (combinedBlurSettings.noiseStrength > 0
        || (splitRenderRegions && m_decorationBlurSettings.noiseStrength > 0))) {
        // Apply an additive noise onto the blurred image. The noise is useful to mask banding
        // artifacts, which often happens due to the smooth color transitions in the blurred image.

        glEnable(GL_BLEND);
        if (opacity < 1.0) {
            glBlendFunc(GL_CONSTANT_ALPHA, GL_ONE);
        } else {
            glBlendFunc(GL_ONE, GL_ONE);
        }

        const int contentNoiseStrength = splitBlurSettings
            ? contentBlurSettings.noiseStrength
            : combinedBlurSettings.noiseStrength;
        if (surfaceShapeDraws.isEmpty()) {
            drawNoiseRegion(contentNoiseStrength, 6, contentVertexCount);
        } else {
            for (const SurfaceShapeDraw &draw : surfaceShapeDraws) {
                drawNoiseRegion(contentNoiseStrength, draw.vertexOffset,
                                draw.vertexCount, &draw);
            }
        }
        if (splitRenderRegions) {
            drawNoiseRegion(splitBlurSettings ? m_decorationBlurSettings.noiseStrength : combinedBlurSettings.noiseStrength,
                            6 + contentVertexCount,
                            frameVertexCount);
        }

        glDisable(GL_BLEND);
    }

    vbo->unbindArrays();
}

bool BlurEffect::isActive() const
{
    return m_valid && !effects->isScreenLocked();
}

bool BlurEffect::blocksDirectScanout() const
{
    return false;
}

bool BlurEffect::shouldFlattenCorner(KWin::EffectWindow *w, Qt::Corner corner) const {
    if (!w || !m_settings.roundedCorners.dynamicCorners) {
        return false;
    } else if (m_settings.roundedCorners.dynamicCornersExcludeDocks && w->isDock()) {
        return false;
    } else if (m_settings.roundedCorners.dynamicCornersExcludeTooltips && w->isTooltip()) {
        return false;
    } else if (
        m_settings.roundedCorners.dynamicCornersExcludeMenus &&
        !w->isTooltip() &&
        (w->isMenu() || w->isDropdownMenu() || w->isPopupMenu() || w->isPopupWindow())
    ) {
        return false;
    }

    const QRectF rect = dynamicCornerRect(w);
    const double margin = 1.0; // Tolerance in pixels

    QPointF cornerPos;
    bool isLeft = corner == Qt::TopLeftCorner || corner == Qt::BottomLeftCorner;
    bool isRight = corner == Qt::TopRightCorner || corner == Qt::BottomRightCorner;
    bool isTop = corner == Qt::TopLeftCorner || corner == Qt::TopRightCorner;
    bool isBottom = corner == Qt::BottomLeftCorner || corner == Qt::BottomRightCorner;

    switch (corner) {
        case Qt::TopLeftCorner:     cornerPos = rect.topLeft(); break;
        case Qt::TopRightCorner:    cornerPos = rect.topRight(); break;
        case Qt::BottomLeftCorner:  cornerPos = rect.bottomLeft(); break;
        case Qt::BottomRightCorner: cornerPos = rect.bottomRight(); break;
    }

    const QRectF screenRect = effects->clientArea(KWin::FullScreenArea, w);

    bool touchesDesktopLeft   = isLeft   && std::abs(cornerPos.x() - screenRect.left())   < margin;
    bool touchesDesktopRight  = isRight  && std::abs(cornerPos.x() - screenRect.right())  < margin;
    bool touchesDesktopTop    = isTop    && std::abs(cornerPos.y() - screenRect.top())    < margin;
    bool touchesDesktopBottom = isBottom && std::abs(cornerPos.y() - (screenRect.y() + screenRect.height())) < margin;

    if (touchesDesktopLeft ||
        touchesDesktopRight ||
        touchesDesktopTop ||
        touchesDesktopBottom) return true;

    for (auto it = m_windows.begin(); it != m_windows.end(); ++it) {
        KWin::EffectWindow *other = it->first;
        if (other == w ||
            other->isMinimized() ||
            !other->isManaged() ||
            !other->isOnCurrentDesktop() ||
            !other->isOnCurrentActivity()
        ) continue;

        const QRectF otherRect = dynamicCornerRect(other);

        bool onLeft   = isRight  && std::abs(cornerPos.x() - otherRect.left())   < margin;
        bool onRight  = isLeft   && std::abs(cornerPos.x() - otherRect.right())  < margin;
        bool onTop    = isBottom && std::abs(cornerPos.y() - otherRect.top())    < margin;
        bool onBottom = isTop    && std::abs(cornerPos.y() - otherRect.bottom()) < margin;

        if (onLeft || onRight) {
            if (cornerPos.y() >= (otherRect.top() - margin) && cornerPos.y() <= (otherRect.bottom() + margin)) {
                return true;
            }
        }

        if (onTop || onBottom) {
            if (cornerPos.x() >= (otherRect.left() - margin) && cornerPos.x() <= (otherRect.right() + margin)) {
                return true;
            }
        }
    }

    return false;
}

} // namespace KWin

#include "moc_blur.cpp"
