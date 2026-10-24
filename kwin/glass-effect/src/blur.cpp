/*
    SPDX-FileCopyrightText: 2010 Fredrik Höglund <fredrik@kde.org>
    SPDX-FileCopyrightText: 2011 Philipp Knechtges <philipp-dev@knechtges.com>
    SPDX-FileCopyrightText: 2018 Alex Nemeth <alex.nemeth329@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "blur.h"
#include <array>
#include <cmath>
#include <QSet>
// KConfigSkeleton
#include "blurconfig.h"
#include "settings.h"
#include "surfaceshapemanager.h"
#include "desktopblurpolicy.h"
#ifndef GLASS_X11
#include "legacyblurregion.h"
#endif

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
    // Initialize the embedded shader resources when the effect is loaded.
    Q_INIT_RESOURCE(blur);
}

namespace KWin
{

static const QByteArray s_blurAtomName = QByteArrayLiteral("_KDE_NET_WM_BLUR_BEHIND_REGION");

static bool isQuickshellWindow(const EffectWindow *window)
{
    if (!window || !window->window()) {
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
        m_roundedOnscreenPass.appearanceMaskEnabledLocation = m_roundedOnscreenPass.shader->uniformLocation("appearanceMaskEnabled");
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
        m_roundedOnscreenPass.tintLocation = m_roundedOnscreenPass.shader->uniformLocation("tint");
        m_roundedOnscreenPass.liquidEnabledLocation = m_roundedOnscreenPass.shader->uniformLocation("liquidEnabled");
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

    m_gaussianPass.shader = ShaderManager::instance()->generateShaderFromFile(ShaderTrait::MapTexture,
        QStringLiteral(":/effects/glass/generated/vertex.vert"),
        QStringLiteral(":/effects/glass/generated/gaussian.frag"));
    // Some KWin 6.7 packages already removed isValid(). Detect the API rather
    // than assuming its availability from the Plasma version number.
    const auto shaderReady = []<typename Shader>(const Shader *shader) {
        if (!shader) {
            return false;
        }
        if constexpr (requires { shader->isValid(); }) {
            return shader->isValid();
        }
        return true; // Newer ShaderManager APIs return null on failure.
    };
    if (shaderReady(m_gaussianPass.shader.get())) {
        m_gaussianPass.mvp = m_gaussianPass.shader->uniformLocation("modelViewProjectionMatrix");
        m_gaussianPass.direction = m_gaussianPass.shader->uniformLocation("direction");
        m_gaussianPass.kernel = m_gaussianPass.shader->uniformLocation("kernel[0]");
        m_gaussianPass.count = m_gaussianPass.shader->uniformLocation("pairCount");
    } else {
        qCWarning(KWIN_BLUR) << "Gaussian shader unavailable; continuous glass uses legacy blur fallback";
        m_gaussianPass.shader.reset();
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
                // Rebuild declared-shape fallback on output remapping too:
                // the new surface may not have received a blur-region request.
                updateBlurRegion(window);
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
    connect(m_surfaceShapeManager.get(), &SurfaceShapeManager::revealFrameChanged,
            this, [this](SurfaceInterface *surface, const QRectF &bounds) {
        // The timeline changes shader uniforms, not capture geometry or blur
        // strength. Repaint only the panel and sampling margin; do not rebuild
        // the legacy region or invalidate the full-screen transparent window.
        for (const auto &entry : m_windows) {
            EffectWindow *window = entry.first;
            if (window->surface() == surface) {
                const int padding = blurExpandSize(window);
                // Rect, not RectF: KWin 6.6's only EffectWindow overload takes
                // Rect, and 6.7's RectF overload converts from Rect implicitly
                // (core/rect.h), so this is the one form both accept.
                window->addRepaint(Rect(bounds.adjusted(-padding, -padding, padding, padding).toAlignedRect()));
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
    if (!m_settings.roundedCorners.dynamicCorners
        || m_settings.roundedCorners.useDeclaredCornerRadius) {
        return;
    }
    // Only these roles receive Glass's adjacency-dependent radii. Moving an
    // ordinary application must not repaint every output merely to update
    // the few Dock/menu corners; BackgroundEffectItem expands their damage.
    for (const auto &[window, data] : m_windows) {
        Q_UNUSED(data)
        if (!window->isVisible()
            || (!window->isDock() && !window->isMenu() && !window->isDropdownMenu()
                && !window->isPopupMenu() && !window->isPopupWindow())) {
            continue;
        }
        if (window->window()
            && window->window()->property("_kos_window_appearance_native_radii").canConvert<QVector4D>()) {
            continue;
        }
        window->addRepaintFull();
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
            if (shape.blurSigma >= 0) {
                expand = std::max(expand, int(std::ceil(3 * shape.blurSigma)) + 2);
                continue;
            }
            if (!shape.blurEnabled) continue;
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
#endif
    }

    if (auto internal = w->internalWindow()) {
        const auto property = internal->property("kwin_blur");
        if (property.isValid()) {
            content = property.value<BlurRegion>();
            hasExplicitBlurRequest = true;
        }
    }

#ifndef GLASS_X11
    if (m_surfaceShapeManager && w->surface() && m_surfaceShapeManager->ownsGeometry(w->surface())) {
        BlurRegion derived;
        for (const SurfaceShape &shape : m_surfaceShapeManager->shapesFor(w->surface())) {
            if (shape.enabled && shape.materialOpacity > 0)
                derived += Rect(surfaceCaptureBounds(shape).toAlignedRect());
        }
        content = derived;
        hasExplicitBlurRequest = true;
    } else if (!content.has_value() && isQuickshellWindow(w) && m_surfaceShapeManager && w->surface()) {
        const auto region = legacySurfaceBlurRegion(std::nullopt,
            m_surfaceShapeManager->shapesFor(w->surface()));
        if (region.has_value()) {
            BlurRegion derived;
            for (const QRect &rect : *region) derived += Rect(rect);
            content = derived;
            hasExplicitBlurRequest = true;
        }
    }
#endif

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
    if (!w || windowFrameGeometryChangedConnections.contains(w)) {
        return;
    }
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
    windowDecorationChangedConnections[w] = connect(w, &EffectWindow::windowDecorationChanged, this, [this, w]() {
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
    disconnect(windowDecorationChangedConnections.take(w));
    disconnect(decorationBlurChangedConnections.take(w));
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
    disconnect(decorationBlurChangedConnections.take(w));
    if (!w->decoration()) {
        return;
    }

    decorationBlurChangedConnections[w] = connect(w->decoration(), &KDecoration3::Decoration::blurRegionChanged, this, [this, w]() {
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

    // The unified appearance owns application-window geometry. In
    // continuous mode it deliberately requests an unrounded input texture;
    // restoring Glass's cached circular radius here cuts that texture twice.
    if (w->window()) {
        // Mirror the lightweight property ABI in kos-bridge geometryprotocol.h.
        // Keep Glass independently buildable from its own source directory.
        const QVariant appearance = w->window()->property("_kos_window_appearance_native_radii");
        if (appearance.canConvert<QVector4D>()) {
            const QVector4D radius = appearance.value<QVector4D>();
            return BorderRadius(radius.x(), radius.y(), radius.z(), radius.w());
        }
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

    // Ordinary windows are not owned by Glass. Consult their live radius
    // so enabling/disabling the appearance effect cannot resurrect a value
    // Glass happened to cache before the policy changed.
    if (!w->isDock() && !w->isMenu() && !w->isDropdownMenu()
        && !w->isPopupMenu() && !w->isPopupWindow()) {
        return w->window() ? w->window()->borderRadius() : declaredCornerRadius;
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
#ifndef GLASS_X11
    if (m_surfaceShapeManager && w->surface() && m_surfaceShapeManager->ownsGeometry(w->surface())) {
        for (const SurfaceShape &shape : m_surfaceShapeManager->shapesFor(w->surface())) {
            if (shape.enabled && shape.materialOpacity > 0)
                region += Rect(surfaceCaptureBounds(shape).toAlignedRect());
        }
        return region.translated(w->contentsRect().x(), w->contentsRect().y());
    }
#endif


    if (auto it = m_windows.find(w); it != m_windows.end()) {
        const std::optional<BlurRegion> &content = it->second.content;
        // Shell cards occupy only part of their transparent surface. Honour
        // their explicit region even when an old Glass configuration asks for
        // whole-window blur; otherwise the material is aligned to the surface
        // origin instead of the card. Ordinary applications keep the setting.
        if (!m_settings.roundedCorners.ignoreContentBlurRegion || w->isDock()
            || (content.has_value() && !content->isEmpty() && isQuickshellWindow(w))) {
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

void BlurEffect::postPaintScreen()
{
    effects->postPaintScreen();
#ifndef GLASS_X11
    // Client focus, hover and model work must not begin before the endpoint
    // frame's GPU commands have been submitted by the window draw chain.
    if (m_surfaceShapeManager) m_surfaceShapeManager->completeAnimations();
#endif
}

#ifdef GLASS_KWIN_67
void BlurEffect::prePaintScreen(ScreenPrePaintData &data)
#else
void BlurEffect::prePaintScreen(ScreenPrePaintData &data, std::chrono::milliseconds presentTime)
#endif
{
#ifndef GLASS_X11
    if (m_surfaceShapeManager) m_surfaceShapeManager->advanceAnimations();
#endif
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
    // The role is written by kwin/dock-window-animation.

    const auto windowClass = w->window()->resourceClass();
    const auto resourceName = w->window()->resourceName();
    const auto blurData = m_windows.find(const_cast<EffectWindow *>(w));
    const bool explicitlyRequestedBlur = blurData != m_windows.end()
        && blurData->second.hasExplicitBlurRequest;

    // DeskCenter is a real Desktop window so KWin cannot move/close it through
    // ordinary window shortcuts. Its declared card regions still need glass;
    // wallpapers and forced whole-desktop blur remain excluded.
    if (w->isDesktop()
        && (blurData == m_windows.end()
            || !desktopSurfaceRequestsBlur(isQuickshellWindow(w), explicitlyRequestedBlur,
                                           blurData->second.content))) {
        return false;
    }

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

    bool scaled = !qFuzzyCompare(data.xScale(), 1.0) || !qFuzzyCompare(data.yScale(), 1.0);
    bool translated = data.xTranslation() || data.yTranslation();

    if ((scaled || (translated || (mask & PAINT_WINDOW_TRANSFORMED))) && !w->data(WindowForceBlurRole).toBool()) {
        return false;
    }

    return true;
}

#ifdef KOS_KWIN_PAINT_RESULT_API
bool
#else
void
#endif
BlurEffect::drawWindow(const RenderTarget &renderTarget, const RenderViewport &viewport, EffectWindow *w, int mask, const BlurRegion &deviceRegion, WindowPaintData &data)
{
    blur(renderTarget, viewport, w, mask, deviceRegion, data);

    // Glass uses the original transform/capture. Only the already-composited
    // client surface is transformed as one group, never its individual items.
#ifndef GLASS_X11
    if (m_surfaceShapeManager && w->surface()) {
        if (const auto reveal = m_surfaceShapeManager->revealFor(w->surface())) {
            if (reveal->progress <= 0) {
#ifdef KOS_KWIN_PAINT_RESULT_API
                // Intentionally hidden content is a successful empty pass.
                return true;
#else
                return;
#endif
            }
            WindowPaintData contentData(data);
            const qreal scale = reveal->scale();
            const QPointF anchor = reveal->anchor();
            contentData.setXTranslation(data.xTranslation() + anchor.x() * data.xScale() * (1 - scale));
            contentData.setYTranslation(data.yTranslation() + anchor.y() * data.yScale() * (1 - scale));
            contentData.setXScale(data.xScale() * scale);
            contentData.setYScale(data.yScale() * scale);
            contentData.multiplyOpacity(reveal->progress);
            return effects->drawWindow(renderTarget, viewport, w, mask | PAINT_WINDOW_TRANSFORMED,
                                deviceRegion, contentData);
        }
    }
#endif
    return effects->drawWindow(renderTarget, viewport, w, mask, deviceRegion, data);
}

GLTexture *BlurEffect::ensureNoiseTexture(int noiseStrength)
{
    if (noiseStrength == 0) {
        return nullptr;
    }

    const QScreen *screen = QGuiApplication::primaryScreen();
    const qreal scale = screen ? std::max(1.0, screen->logicalDotsPerInch() / 96.0) : 1.0;
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

    // A completed close can outlive the client's blur-region commit. Keep
    // its transparent declaration authoritative and skip all capture/blur work.
    if (!declaredSurfaceShapes.isEmpty()
        && std::all_of(declaredSurfaceShapes.cbegin(), declaredSurfaceShapes.cend(),
                       [](const SurfaceShape &shape) { return shape.materialOpacity <= 0; })) {
        return;
    }

    auto transformShape = [&](BlurRegion shape) {
        shape.translate(w->pos().toPoint());
        if (data.xScale() != 1 || data.yScale() != 1) {
            QPoint pt = w->pos().toPoint();
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
    int gaussianPadding = 0;
    for (const SurfaceShape &shape : declaredSurfaceShapes)
        if (shape.blurSigma > 0) gaussianPadding = std::max(gaussianPadding, int(std::ceil(3 * shape.blurSigma)));
    const QRect backgroundRect = effectShape.boundingRect().adjusted(
        -gaussianPadding, -gaussianPadding, gaussianPadding, gaussianPadding);
#ifdef GLASS_X11
    const QRect scaledBackgroundRect = snapToPixelGrid(scaledRect(backgroundRect, viewport.scale()));
    const QRect deviceBackgroundRect = scaledBackgroundRect;
#else
    const QRectF scaledLogicalBackgroundRect(backgroundRect.x() * viewport.scale(),
                                             backgroundRect.y() * viewport.scale(),
                                             backgroundRect.width() * viewport.scale(),
                                             backgroundRect.height() * viewport.scale());
#ifdef KOS_KWIN_PAINT_RESULT_API
    const QRect scaledBackgroundRect = RectF(scaledLogicalBackgroundRect).rounded();
#else
    const QRect scaledBackgroundRect = snapToPixelGrid(scaledLogicalBackgroundRect);
#endif
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

    // Each declaration supplies both capture and outline. Never align a set
    // by comparing it with an independent region or discard unrelated panels.
    if (!declaredSurfaceShapes.isEmpty() && frameShape.isEmpty()) {
        decltype(effectiveContentShape) shapeGeometry;
        for (const SurfaceShape &shape : declaredSurfaceShapes) {
            if (!shape.enabled || shape.materialOpacity <= 0) continue;
            const QRect logicalRect = shape.geometry.toAlignedRect();
            if (logicalRect.isEmpty()) continue;
            BlurRegion local;
#ifdef GLASS_X11
            local += logicalRect;
#else
            local += Rect(logicalRect);
#endif
            local.translate(w->contentsRect().x(), w->contentsRect().y());
            const BlurRegion transformedShape = transformShape(local);
            SurfaceShapeDraw draw;
            draw.shape = shape;
            draw.rects = buildEffectiveShape(transformedShape);
            if (draw.rects.isEmpty()) continue;
            if (shape.blurEnabled && shape.blurSigma < 0 && !blurStrengthValues.isEmpty())
                draw.blurLevel = qBound(1, int(shape.blurLevel), int(blurStrengthValues.size()));
            const QRect bounds = transformedShape.boundingRect();
            draw.nativeBox = QRectF(bounds.x() * viewport.scale(), bounds.y() * viewport.scale(),
                                    bounds.width() * viewport.scale(), bounds.height() * viewport.scale())
                                 .translated(-scaledBackgroundRect.topLeft());
            shapeGeometry.append(draw.rects);
            surfaceShapeDraws.append(draw);
            if (shapeTraceEnabled()) {
                // Per-shape diagnostics retained from issue #214.
                qCWarning(shapeTraceCategory()) << "  declared shape" << shape.id
                    << "geom" << shape.geometry << "capture" << surfaceCaptureBounds(shape)
                    << "radius" << shape.radius << "exponent" << shape.exponent
                    << "enabled" << shape.enabled;
            }
        }
        effectiveContentShape = shapeGeometry;
        // An empty/hidden/clipped declaration is not a request for a rectangle.
        if (surfaceShapeDraws.isEmpty()) return;
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
    if (isQuickshellSurface && declaredSurfaceShapes.isEmpty() && surfaceShapeDraws.isEmpty() && !contentShape.isEmpty()) {
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
        if (shapeTraceEnabled()) {
            qCWarning(shapeTraceCategory()) << "glass trace: allocating capture chain" << backgroundRect.size();
        }
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

    // Offscreen filters replace their targets, including transparent pixels.
    // Blending here would mix the filtered backdrop with stale target content.
    glDisable(GL_BLEND);

    // Filter local backdrop luminance independently of the material blur.
    // Four downsample passes remove fine wallpaper detail without reducing
    // mixed light/dark regions to a whole-window mean. This texture remains
    // valid while per-shape blur overrides overwrite the material mip chain.
    const bool windowScrim = std::any_of(
        declaredSurfaceShapes.begin(), declaredSurfaceShapes.end(),
        [](const SurfaceShape &shape) {
            return shape.scrimEnabled && shape.scrimDecay <= 1.0;
        });
    if (!windowScrim) {
        renderInfo.scrimLumaFramebuffers.clear();
        renderInfo.scrimLumaTextures.clear();
        renderInfo.scrimLumaLevels = 0;
        renderInfo.scrimLumaSize = QSize();
    }
    GLTexture *scrimLuma = nullptr;
    if (windowScrim && renderInfo.framebuffers[0]
            && !backgroundRect.isEmpty()) {
        const int longest = std::max(backgroundRect.width(), backgroundRect.height());
        int levels = 0;
        for (int side = longest; side > 1 && levels < 4; side >>= 1)
            ++levels;
        if (levels <= 0) {
            scrimLuma = renderInfo.framebuffers[0]->colorAttachment();
        } else {
            if (renderInfo.scrimLumaLevels != levels
                || renderInfo.scrimLumaSize != backgroundRect.size()
                || renderInfo.scrimLumaFramebuffers.size() != static_cast<size_t>(levels)) {
                renderInfo.scrimLumaFramebuffers.clear();
                renderInfo.scrimLumaTextures.clear();
                // Zeroed until the chain is complete: a partially filled cache
                // must not look valid to the next frame.
                renderInfo.scrimLumaLevels = 0;
                for (int i = 0; i < levels; ++i) {
                    const QSize size = (backgroundRect.size() / (1 << (i + 1))).expandedTo(QSize(1, 1));
                    auto texture = GLTexture::allocate(textureFormat, size);
                    if (!texture) {
                        // Use neutral fallback luminance instead of returning:
                        // an early return here would skip unbindArrays() below
                        // and kill the whole frame's blur pass.
                        qCWarning(KWIN_BLUR) << "Failed to allocate a scrim luminance texture";
                        break;
                    }
                    texture->setFilter(GL_LINEAR);
                    texture->setWrapMode(GL_CLAMP_TO_EDGE);
                    auto framebuffer = std::make_unique<GLFramebuffer>(texture.get());
                    if (!framebuffer->valid()) {
                        qCWarning(KWIN_BLUR) << "Failed to create a scrim luminance framebuffer";
                        break;
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
                    renderInfo.scrimLumaTextures.push_back(std::move(texture));
                    renderInfo.scrimLumaFramebuffers.push_back(std::move(framebuffer));
                }
                if (renderInfo.scrimLumaFramebuffers.size() == static_cast<size_t>(levels)) {
                    renderInfo.scrimLumaSize = backgroundRect.size();
                    renderInfo.scrimLumaLevels = levels;
                }
            }

            // Halve each level with the same low-pass filter the blur uses.
            // Linear sampling of the final level preserves smooth local tone.
            // Only on a complete chain: an allocation failure above leaves the
            // chain partial and scrimLuma null, so this frame keeps its blur
            // (with the shader's neutral luminance fallback) instead of losing it.
            if (renderInfo.scrimLumaFramebuffers.size() == static_cast<size_t>(levels)) {
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
                    EglContext::currentContext()->pushFramebuffer(renderInfo.scrimLumaFramebuffers[i].get());
                    vbo->draw(GL_TRIANGLES, 0, 6);
                    EglContext::currentContext()->popFramebuffer();
                    read = renderInfo.scrimLumaFramebuffers[i]->colorAttachment();
                }
                ShaderManager::instance()->popShader();
                scrimLuma = read;
            }
        }
    }

    auto runBlurPass = [&](const BlurPipelineSettings &settings) -> GLTexture * {
        // Decoration passes can run after content has been composited onscreen.
        glDisable(GL_BLEND);
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

    auto ensureScratch = [&](BlurRenderData::BlurOverrideScratch &scratch) -> bool {
        const QSize size = backgroundRect.size();
        if (scratch.framebuffer && scratch.size == size && scratch.texture->internalFormat() == textureFormat) return true;
        scratch.framebuffer.reset(); scratch.texture.reset(); scratch.size = QSize();
        auto texture = GLTexture::allocate(textureFormat, size);
        if (!texture) return false;
        texture->setFilter(GL_LINEAR); texture->setWrapMode(GL_CLAMP_TO_EDGE);
        auto framebuffer = std::make_unique<GLFramebuffer>(texture.get());
        if (!framebuffer->valid()) return false;
        scratch.texture = std::move(texture); scratch.framebuffer = std::move(framebuffer); scratch.size = size;
        return true;
    };
    auto runGaussian = [&](qreal sigma) -> GLTexture * {
        if (sigma <= 0) return renderInfo.framebuffers[0]->colorAttachment();
        if (!m_gaussianPass.shader) return nullptr;
        auto &result = renderInfo.gaussianScratch[uint(qRound(sigma * 256))];
        if (!ensureScratch(renderInfo.gaussianTemp) || !ensureScratch(result)) return nullptr;
        // Pair adjacent Gaussian taps using GL_LINEAR. Sigma is logical pixels:
        // the capture is logical-resolution on every output scale.
        std::array<float, 98> kernel{};
        kernel[0] = 1; kernel[1] = 0;
        const int radius = std::min(96, int(std::ceil(3 * sigma)));
        int count = 0; float total = 1;
        for (int i = 1; i <= radius; i += 2) {
            const float a = std::exp(-0.5 * i * i / (sigma * sigma));
            const float b = i + 1 <= radius ? std::exp(-0.5 * (i + 1) * (i + 1) / (sigma * sigma)) : 0;
            ++count;
            kernel[count * 2] = a + b;
            kernel[count * 2 + 1] = i + (a + b > 0 ? b / (a + b) : 0);
            total += 2 * (a + b);
        }
        for (int i = 0; i <= count; ++i) kernel[i * 2] /= total;
        glDisable(GL_BLEND);
        ShaderManager::instance()->pushShader(m_gaussianPass.shader.get());
        QMatrix4x4 projection;
        projection.ortho(QRectF(QPointF(0, 0), QSizeF(backgroundRect.size())));
        m_gaussianPass.shader->setUniform(m_gaussianPass.mvp, projection);
        m_gaussianPass.shader->setUniform(m_gaussianPass.count, count);
        glUniform2fv(m_gaussianPass.kernel, count + 1, kernel.data());
        GLTexture *read = renderInfo.framebuffers[0]->colorAttachment();
        for (int axis = 0; axis < 2; ++axis) {
            auto &target = axis == 0 ? renderInfo.gaussianTemp : result;
            m_gaussianPass.shader->setUniform(m_gaussianPass.direction,
                axis == 0 ? QVector2D(1.0f / read->width(), 0) : QVector2D(0, 1.0f / read->height()));
            glActiveTexture(GL_TEXTURE0); read->bind();
            GLFramebuffer::pushFramebuffer(target.framebuffer.get());
            vbo->draw(GL_TRIANGLES, 0, 6);
            GLFramebuffer::popFramebuffer();
            read = target.texture.get();
        }
        ShaderManager::instance()->popShader();
        return read;
    };

    const QMatrix4x4 &colorMatrix = m_colorMatrix;
    // KOS: fade the whole glass material for a window that the Dock animation
    // is driving. Unset means a fully opaque material, so nothing changes for
    // every other window. The value is written by
    // kwin/dock-window-animation; both sides must keep the role
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
#ifdef KOS_KWIN_PAINT_RESULT_API
    const QRectF nativeBox = QRectF(snapToPixels(RectF(scaledTransformedRect), 1))
                                 .translated(-scaledBackgroundRect.topLeft());
#else
    const QRectF nativeBox = snapToPixelGridF(scaledTransformedRect)
                                 .translated(-scaledBackgroundRect.topLeft());
#endif
#endif
    const QVariant visualRadii = w->window()->property("_kos_window_appearance_visual_radii");
    const bool appearanceMask = visualRadii.canConvert<QVector4D>();
    const QVector4D appearanceRadius = appearanceMask ? visualRadii.value<QVector4D>() : QVector4D();
    const BorderRadius visualCornerRadius = appearanceMask
        ? BorderRadius(appearanceRadius.x(), appearanceRadius.y(), appearanceRadius.z(), appearanceRadius.w())
        : cornerRadius;
    // Keep the sharp native input for the final compositor mask; only blur
    // and noise use the visual contour. Continuous extents are not rounded
    // again, or their joins would disagree with the window-content shader.
    const BorderRadius nativeCornerRadius = appearanceMask
        ? visualCornerRadius.scaled(viewport.scale())
        : visualCornerRadius.scaled(viewport.scale()).rounded();
    const float visualExponent = appearanceMask
        ? static_cast<float>(w->window()->property("_kos_window_appearance_curve_exponent").toDouble())
        : m_settings.roundedCorners.cornerExponent;
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
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.appearanceMaskEnabledLocation, appearanceMask ? 1 : 0);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.cornerExponentLocation,
        visualExponent);
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
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.tintLocation, QVector4D(0, 0, 0, 0));
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.liquidEnabledLocation, 1);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.scrimModeLocation, 0);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.scrimCapLocation, 0.0f);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.scrimDecayLocation, 1.0f);
    // The softly filtered local backdrop, bound separately from the material
    // texture so refraction, rim highlights and blur overrides cannot steer it.
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.scrimLumaTexLocation, 1);
    m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.scrimLumaValidLocation,
        scrimLuma ? 1 : 0);
    if (scrimLuma) {
        glActiveTexture(GL_TEXTURE0 + 1);
        scrimLuma->bind();
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

    auto drawBlurredRegion = [&](GLTexture *blurredTexture, int vertexOffset, int currentVertexCount, float blurOffset) {
        // Restore premultiplied blending only when compositing onto the screen.
        glEnable(GL_BLEND);
        glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
        m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.offsetLocation, blurOffset * m_upsampleOffset);
        glActiveTexture(GL_TEXTURE0);
        blurredTexture->bind();
        vbo->draw(GL_TRIANGLES, vertexOffset, currentVertexCount);
    };

    auto protocolShapeUniforms = [&](const SurfaceShapeDraw &draw) {
        // Fade the complete premultiplied finish without changing capture bounds.
        m_roundedOnscreenPass.shader->setUniform(
            m_roundedOnscreenPass.opacityLocation,
            modulation * static_cast<float>(draw.shape.materialOpacity));
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
        m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.glassEnabledLocation, 1);
        m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.liquidEnabledLocation,
            draw.shape.effect == 0 ? 1 : 0);
        const float opticalScale = draw.shape.material == 0 ? 0.6f : draw.shape.material == 2 ? 1.2f : 1.0f;
        m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.refractionStrengthLocation,
            float(m_settings.refraction.refractionStrength) * opticalScale);
        QVector4D tint = draw.shape.tint;
        if (draw.shape.tintMode == 0) tint.setW(0);
        else if (draw.shape.tintMode == 2) tint = QVector4D(0.34, 0.335, 0.35, tint.w());
        else if (draw.shape.tintMode == 3) tint = QVector4D(0.92, 0.915, 0.905, tint.w());
        m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.tintLocation, tint);
        m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.scrimModeLocation,
            draw.shape.scrimEnabled ? 1 + (draw.shape.scrimTint == 1 ? 1 : 0) : 0);
        m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.scrimCapLocation, float(draw.shape.scrimCap));
        m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.scrimDecayLocation, float(draw.shape.scrimDecay));
    };

    auto drawNoiseRegion = [&](int noiseStrength, int vertexOffset,
                               int currentVertexCount,
                               const SurfaceShapeDraw *protocolDraw = nullptr) {
        if (noiseStrength <= 0 || currentVertexCount == 0) {
            return;
        }

        if (GLTexture *noiseTexture = ensureNoiseTexture(noiseStrength)) {
            const float shapeOpacity = protocolDraw
                ? static_cast<float>(protocolDraw->shape.materialOpacity) : 1.0f;
            // Additive noise must fade with the glass rather than remain visible.
            glBlendColor(0.0f, 0.0f, 0.0f, modulation * shapeOpacity);
            glBlendFunc(GL_CONSTANT_ALPHA, GL_ONE);
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
                    visualExponent);
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
    const auto filterKey = [](const SurfaceShapeDraw &draw) {
        return draw.shape.blurSigma >= 0 ? -1 - qRound(draw.shape.blurSigma * 256) : draw.blurLevel;
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
        QSet<uint> gaussianKeys;
        for (const SurfaceShapeDraw &draw : surfaceShapeDraws)
            if (draw.shape.blurSigma >= 0) gaussianKeys.insert(uint(qRound(draw.shape.blurSigma * 256)));
        std::vector<BlurRenderData::BlurOverrideScratch> reusable;
        for (auto it = renderInfo.gaussianScratch.begin(); it != renderInfo.gaussianScratch.end();) {
            if (!gaussianKeys.contains(it->first)) {
                reusable.push_back(std::move(it->second));
                it = renderInfo.gaussianScratch.erase(it);
            } else ++it;
        }
        for (uint key : gaussianKeys) {
            if (!renderInfo.gaussianScratch.contains(key) && !reusable.empty()) {
                renderInfo.gaussianScratch.emplace(key, std::move(reusable.back()));
                reusable.pop_back();
            }
        }
        for (uint key : gaussianKeys) {
            if (GLTexture *texture = runGaussian(key / 256.0))
                overridePasses.append({-1 - int(key), texture, 0});
        }
        // Levels that no current shape uses should not retain capture-sized
        // GPU scratch textures until this window is closed.
        std::erase_if(renderInfo.blurOverrideScratch, [&overrideLevels](const auto &entry) {
            return !overrideLevels.contains(int(entry.first));
        });
        for (int level : overrideLevels) {
            const BlurPipelineSettings overrideSettings =
                pipelineSettingsForStrength(level - 1, contentNoiseStrength);
            runBlurPass(overrideSettings);
            auto &scratch = renderInfo.blurOverrideScratch[uint(level)];
            const QSize size = renderInfo.framebuffers[1]->colorAttachment()->size();
            const GLenum overrideFormat = renderInfo.framebuffers[1]->colorAttachment()->internalFormat();
            if (!scratch.framebuffer || scratch.size != size
                || scratch.texture->internalFormat() != overrideFormat) {
                scratch.framebuffer.reset();
                scratch.texture.reset();
                scratch.size = QSize();
                auto texture = GLTexture::allocate(overrideFormat, size);
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
    } else {
        renderInfo.blurOverrideScratch.clear();
        renderInfo.gaussianScratch.clear();
    }

    // A default pass is only consumed by shapes without a successful override.
    // Keep the fallback when scratch allocation fails, but avoid computing an
    // extra whole-capture chain when all draws already have their own texture.
    const bool needsDefaultPass = surfaceShapeDraws.isEmpty()
        || std::any_of(surfaceShapeDraws.cbegin(), surfaceShapeDraws.cend(),
                       [&overridePasses, &filterKey](const SurfaceShapeDraw &draw) {
            return std::none_of(overridePasses.cbegin(), overridePasses.cend(),
                                [&draw, &filterKey](const BlurOverridePass &pass) {
                return pass.level == filterKey(draw);
            });
        });
    GLTexture *contentBlurredTexture = needsDefaultPass
        ? runBlurPass(splitBlurSettings ? contentBlurSettings : combinedBlurSettings)
        : nullptr;
    const float contentOffset = splitBlurSettings
        ? contentBlurSettings.offset : combinedBlurSettings.offset;
    if (surfaceShapeDraws.isEmpty()) {
        drawBlurredRegion(contentBlurredTexture, 6, contentVertexCount,
                          contentOffset);
    } else {
        for (const SurfaceShapeDraw &draw : surfaceShapeDraws) {
            protocolShapeUniforms(draw);
            const BlurOverridePass *override = nullptr;
            if (filterKey(draw) != 0) {
                for (const BlurOverridePass &pass : overridePasses) {
                    if (pass.level == filterKey(draw)) {
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
        // Per-shape opacity applies only to content, not a window decoration.
        m_roundedOnscreenPass.shader->setUniform(m_roundedOnscreenPass.opacityLocation, modulation);
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
        // drawNoiseRegion selects the additive blend factor for each shape.

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
