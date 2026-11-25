/*
    SPDX-FileCopyrightText: 2026 NextKDE contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "glass.h"

#include "glassshape.h"
#include "surfaceshapemanager.h"

#include "../../common/windoweffectpolicy.h"

#include <core/rect.h>
#include <core/region.h>
#include <core/rendertarget.h>
#include <core/renderviewport.h>
#include <effect/effecthandler.h>
#include <effect/effectwindow.h>
#include <input.h>
#include <input_event.h>
#include <input_event_spy.h>
#include <opengl/glframebuffer.h>
#include <opengl/glshader.h>
#include <opengl/glshadermanager.h>
#include <opengl/gltexture.h>
#include <opengl/glvertexbuffer.h>
#include <opengl/glutils.h>
#include <scene/scene.h>
#include <wayland/surface.h>
#include <window.h>

#include <KSharedConfig>

#include <QMatrix4x4>
#include <QRegion>
#include <QVariant>
#include <QVector2D>
#include <QVector4D>

#include <algorithm>
#include <cmath>
#include <span>
#include <utility>
#include <vector>

#if __has_include(<scene/backgroundeffectitem.h>)
#include <scene/backgroundeffectitem.h>
#define GLASS_HAS_BACKGROUND_ITEM 1
#else
#include <scene/item.h>
#endif

#include <QLoggingCategory>

Q_LOGGING_CATEGORY(KWIN_GLASS, "kwin_effect_glass", QtWarningMsg)

namespace KWin
{

namespace
{
// Maximum number of Dual Kawase levels the chain allocates. How many of them
// actually run comes from the configured blur strength (1..15): the radius is
// built from levels, and each level taps only 1..2 texels of its own
// resolution so no level introduces ghosted copies.
constexpr int kIterations = 6;
// Logical margin captured around the declared shapes so the widest blur level
// still reads real backdrop instead of clamping at the capture edge.
constexpr int kCaptureExpand = 160;
// The hover light starts slightly before the pointer crosses the outline and
// stays until it leaves the same margin; a pointer on the glass is the common
// case for a Dock or panel, so the margin is small.
constexpr qreal kHoverMargin = 24.0;

// kwin/dock-window-animation fades the glass material while it morphs a window
// into or out of the Dock. The shapes are anchored to the window frame and do
// not follow the deformation, so the animation fades them instead of leaving a
// frozen blurred strip behind. The value must stay in sync with that effect.
constexpr int kDockAnimationGlassFadeRole = 0x4b4f5342; // "KOSB"

struct RenderPass
{
    std::unique_ptr<GLShader> shader;
    int mvpMatrix = -1;
    int offset = -1;
    int halfpixel = -1;
    int saturationCompensation = -1;
};

struct OnscreenPass
{
    std::unique_ptr<GLShader> shader;
    int mvpMatrix = -1;
    int box = -1;
    int cornerRadius = -1;
    int cornerExponent = -1;
    int tint = -1;
    int opacity = -1;
    int scrimMode = -1;
    int scrimCap = -1;
    int scrimDecay = -1;
    int scrimLumaSmooth = -1;
    int texUnit = -1;
    int viewportScale = -1;
    int liquidEnabled = -1;
    int edgeSizePixels = -1;
    int refractionStrength = -1;
    int refractionNormalPow = -1;
    int refractionRGBFringing = -1;
    int refractionOffsetStrength = -1;
    int materialSoftness = -1;
    int materialReflectionStrength = -1;
    int pointerLocal = -1;
    int hoverAmount = -1;
    int hoverStrength = -1;
    int hoverRadius = -1;
    int parallaxStrength = -1;
    int clickLocal = -1;
    int clickRadius = -1;
    int clickAmount = -1;
};

} // namespace

struct RenderPasses
{
    RenderPass downsample;
    RenderPass upsample;
    OnscreenPass onscreen;
};

// One Dual Kawase configuration's texture levels. Shapes that resolve to the
// same (iterations, offsets) share a chain; `textures[0]` is level 1, the
// blurred backdrop the on-screen pass samples.
struct BlurChain
{
    int iterations = 0;
    float downsampleOffset = 0.0f;
    float upsampleOffset = 0.0f;
    std::vector<std::unique_ptr<GLTexture>> textures;
    std::vector<std::unique_ptr<GLFramebuffer>> framebuffers;
    // True while the levels hold the blur of the current captureRect.
    bool valid = false;
    // Shapes that used the chain in this frame; unused chains are freed at
    // the end of the frame so a per-shape override that disappears does not
    // keep its textures allocated.
    bool used = false;
};

struct RenderData
{
    // Shared level-0 capture. Every chain downsamples it, and a shape whose
    // material asks for no blur samples it directly.
    std::unique_ptr<GLTexture> captureTexture;
    std::unique_ptr<GLFramebuffer> captureFramebuffer;
    // One chain per distinct per-shape blur configuration. The shell drives
    // most surfaces from the same settings, so this normally holds one entry.
    std::vector<BlurChain> chains;
    QSize captureSize;
    GLenum format = GL_RGBA8;
    // Last capture in scene-logical coordinates. A rect change means the
    // cached texture no longer aligns with the screen and has to be refilled.
    QRect captureRect;
    // Set when something painted below this surface may have changed. Window
    // content damage alone does not touch it: the chain result is still the
    // correct backdrop, only the composite has to run again.
    bool backdropDirty = true;
    // Pointer light state. hover runs 0..1 and is the only animated part; it
    // changes shader uniforms, never the blur chain.
    QPointF pointerScene;
    bool pointerKnown = false;
    float hover = 0.0f;
    float hoverTarget = 0.0f;
#if defined(GLASS_HAS_BACKGROUND_ITEM)
    std::unique_ptr<BackgroundEffectItem> item;
#else
    std::unique_ptr<ItemEffect> item;
#endif
};

namespace
{

EffectWindow *windowForSurface(SurfaceInterface *surface)
{
    if (!surface) {
        return nullptr;
    }
    const QList<EffectWindow *> windows = effects->stackingOrder();
    for (EffectWindow *w : windows) {
        if (w->surface() == surface) {
            return w;
        }
    }
    return nullptr;
}

#ifndef GLASS_KWIN_67
// Only the 6.6 paint bookkeeping needs the untransformed union; 6.7+ expands
// damage through BackgroundEffectItem instead.
QRectF shapeUnion(EffectWindow *w, const QVector<GlassShape> &shapes, bool capture)
{
    QRectF unionRect;
    for (const GlassShape &shape : shapes) {
        if (!shape.hasArea()) {
            continue;
        }
        const QRectF rect = capture ? shape.captureBounds() : shape.geometry;
        unionRect |= rect;
    }
    if (unionRect.isEmpty()) {
        return unionRect;
    }
    return unionRect.translated(w->pos() + w->contentsRect().topLeft());
}
#endif

// How far the strength slider (1..15) reaches: the radius is built from the
// number of downsample levels, and every level taps a small, artifact-free
// distance (1..2 texels of its own resolution). Large taps on a single coarse
// level are what produce ghosted, banded "copies" instead of a smooth falloff;
// many small taps look Gaussian and cost a quarter of the previous level each.
// The tap distance in *pixels* keeps growing across level boundaries because
// offset 2.0 on level N is the same pixel distance as offset 1.0 on level N+1.
struct BlurStep
{
    int iterations = 1;
    float offset = 1.0f;
};

BlurStep blurStepForStrength(int index)
{
    struct Level
    {
        float minOffset;
        float maxOffset;
    };
    // Same band for every level: one texel of the read level up to two. The
    // capture margin kCaptureExpand covers the widest possible tap (64 px at
    // the sixth level).
    constexpr Level levels[kIterations] = {
        {1.0f, 2.0f},
        {1.0f, 2.0f},
        {1.0f, 2.0f},
        {1.0f, 2.0f},
        {1.0f, 2.0f},
        {1.0f, 2.0f},
    };
    constexpr int kLevelCount = kIterations;
    constexpr int kSteps = 15;

    // Even split that keeps the offset reset at level boundaries monotonic in
    // pixels: 15 steps over 6 levels = 3,3,3,2,2,2.
    const int base = kSteps / kLevelCount;
    const int extra = kSteps % kLevelCount;

    int entry = 0;
    for (int i = 0; i < kLevelCount; ++i) {
        const int count = base + (i < extra ? 1 : 0);
        const float span = levels[i].maxOffset - levels[i].minOffset;
        for (int j = 1; j <= count; ++j) {
            const float offset = levels[i].minOffset + span / count * j;
            if (entry++ == index) {
                return BlurStep{i + 1, offset};
            }
        }
    }
    return BlurStep{};
}

// Resolved blur for one shape; `iterations == 0` means the composite samples
// the unblurred capture.
struct BlurConfig
{
    int iterations = 0;
    float downsampleOffset = 1.0f;
    float upsampleOffset = 1.0f;
};

// Per-shape blur. v8 surfaces carry a continuous sigma in surface-local
// logical pixels, with 0 meaning "show the backdrop undisturbed"; the old
// strength level (1..15) is the fallback for pre-v8 clients, and the kwinrc
// setting covers surfaces that declare neither.
//
// Sigma maps onto the same level chain. One 9-tap tent taps `o` texels of its
// own level; at level `i` a texel is `2^i` logical pixels, so that pass adds
// `0.79 * o * 2^i` of standard deviation and both the down and the up pass
// apply it. The composed spread is therefore about
// `kChainSigmaPerLevel * o * 2^levels`. Solving for the artifact-free 1..2
// texel band gives `n = ceil(log2(sigma / (2 * k)))` and
// `o = sigma / (k * 2^n)`.
//
// The chain is a smooth approximation of the old plugin's true Gaussian, not
// the same kernel; the visual sigma is matched, the tail shape is not.
constexpr float kChainSigmaPerLevel = 1.29f;

BlurConfig resolveBlurConfig(const GlassShape &shape, const MaterialSettings &material)
{
    if (shape.blurSigmaSet) {
        if (shape.blurSigma <= 0.0) {
            return BlurConfig{};
        }
        const float sigma = static_cast<float>(shape.blurSigma);
        const int iterations = std::clamp(
            static_cast<int>(std::ceil(std::log2(sigma / (2.0f * kChainSigmaPerLevel)))),
            1, kIterations);
        const float offset = std::clamp(
            sigma / (kChainSigmaPerLevel * static_cast<float>(1 << iterations)),
            1.0f, 2.0f);
        return BlurConfig{iterations, offset, offset};
    }
    if (shape.blurEnabled && shape.blurLevel >= 1) {
        const BlurStep step = blurStepForStrength(static_cast<int>(shape.blurLevel) - 1);
        return BlurConfig{step.iterations, step.offset, step.offset};
    }
    return BlurConfig{std::clamp(material.blurIterations, 1, kIterations),
                      material.blurDownsampleOffset,
                      material.blurUpsampleOffset};
}

// Quantise the capture rect to a grid so a shape that slides a few pixels per
// frame does not change the texture size (and force a chain reallocation) on
// every commit. Growing left/top down to the grid is deliberate: it keeps the
// origin fixed for most of an animation, and the origin is what needs a full
// refill when it does change -- that is cheap compared to rebuilding the chain.
QRect stableCapture(const QRectF &logicalUnion, const QRect &screen)
{
    if (logicalUnion.isEmpty() || screen.isEmpty()) {
        return QRect();
    }
    constexpr int kGrid = 64;
    const QRectF expanded = logicalUnion.adjusted(-kCaptureExpand, -kCaptureExpand,
                                                  kCaptureExpand, kCaptureExpand);
    const int left = static_cast<int>(std::floor(expanded.left() / kGrid)) * kGrid;
    const int top = static_cast<int>(std::floor(expanded.top() / kGrid)) * kGrid;
    const qreal right = std::max<qreal>(expanded.right(), left + 1);
    const qreal bottom = std::max<qreal>(expanded.bottom(), top + 1);
    const int width = static_cast<int>(std::ceil((right - left) / kGrid)) * kGrid;
    const int height = static_cast<int>(std::ceil((bottom - top) / kGrid)) * kGrid;
    return QRect(left, top, width, height).intersected(screen);
}

// Size of a blur level. Must match the allocation loop exactly (integer
// division, clamped to one pixel).
QSize levelSize(const QSize &capture, int level)
{
    return (capture / (1 << level)).expandedTo(QSize(1, 1));
}

// Grow every rect by a tap radius in the read level. One extra texel covers
// bilinear filtering landing between texels.
QRegion expandRegion(const QRegion &region, int texels)
{
    QRegion result;
    for (const QRect &rect : region) {
        result += rect.adjusted(-texels, -texels, texels, texels);
    }
    return result;
}

// Downsample: source texels cover twice the target's spacing. A changed source
// rect affects the target rects it overlaps, after the tap expansion.
QRegion toDownLevel(const QRegion &region, const QSize &targetSize)
{
    const QRect bounds(QPoint(0, 0), targetSize);
    QRegion result;
    for (const QRect &rect : region) {
        const int left = static_cast<int>(std::floor(rect.left() / 2.0));
        const int top = static_cast<int>(std::floor(rect.top() / 2.0));
        const int right = static_cast<int>(std::ceil(rect.right() / 2.0));
        const int bottom = static_cast<int>(std::ceil(rect.bottom() / 2.0));
        result += QRect(QPoint(left, top), QPoint(right, bottom)).intersected(bounds);
    }
    return result;
}

// Upsample: one read texel feeds a 2x2 patch of the target.
QRegion toUpLevel(const QRegion &region, const QSize &targetSize)
{
    const QRect bounds(QPoint(0, 0), targetSize);
    QRegion result;
    for (const QRect &rect : region) {
        const QRect scaled(rect.x() * 2, rect.y() * 2,
                           rect.width() * 2, rect.height() * 2);
        result += scaled.intersected(bounds);
    }
    return result;
}

// Find or create the chain for one blur configuration. Creation allocates and
// clears every level; a failure leaves the chain list untouched.
BlurChain *ensureChain(RenderData *data, const BlurConfig &config)
{
    for (BlurChain &chain : data->chains) {
        if (chain.iterations == config.iterations
            && chain.downsampleOffset == config.downsampleOffset
            && chain.upsampleOffset == config.upsampleOffset) {
            chain.used = true;
            return &chain;
        }
    }

    BlurChain chain;
    chain.iterations = config.iterations;
    chain.downsampleOffset = config.downsampleOffset;
    chain.upsampleOffset = config.upsampleOffset;
    chain.used = true;

    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
    for (int i = 1; i <= config.iterations; ++i) {
        const QSize size = levelSize(data->captureSize, i);
        std::unique_ptr<GLTexture> texture = GLTexture::allocate(data->format, size);
        if (!texture) {
            qCWarning(KWIN_GLASS) << "Failed to allocate a glass texture";
            return nullptr;
        }
        texture->setFilter(GL_LINEAR);
        texture->setWrapMode(GL_CLAMP_TO_EDGE);

        auto framebuffer = std::make_unique<GLFramebuffer>(texture.get());
        if (!framebuffer->valid()) {
            qCWarning(KWIN_GLASS) << "Failed to create a glass framebuffer";
            return nullptr;
        }
        GLFramebuffer::pushFramebuffer(framebuffer.get());
        glClear(GL_COLOR_BUFFER_BIT);
        GLFramebuffer::popFramebuffer();

        chain.textures.push_back(std::move(texture));
        chain.framebuffers.push_back(std::move(framebuffer));
    }
    data->chains.push_back(std::move(chain));
    return &data->chains.back();
}

} // namespace

GlassEffect::GlassEffect()
{
    // The generated resource object registers itself from a static
    // initializer; no explicit Q_INIT_RESOURCE call is needed (and the symbol
    // is hidden by the project's visibility flags).
    m_passes = std::make_unique<RenderPasses>();
    readMaterialSettings();
    ensurePasses();

    if (effects->waylandDisplay()) {
        m_shapes = std::make_unique<SurfaceShapeManager>(effects->waylandDisplay());
        connect(m_shapes.get(), &SurfaceShapeManager::surfaceShapesChanged, this,
                [this](SurfaceInterface *surface) {
                    EffectWindow *w = windowForSurface(surface);
                    if (!w) {
                        return;
                    }
                    updateItem(w);
                    w->addRepaintFull();
                });
        connect(m_shapes.get(), &SurfaceShapeManager::revealFrameChanged, this,
                [this](SurfaceInterface *surface, const QRectF &bounds) {
                    EffectWindow *w = windowForSurface(surface);
                    if (!w) {
                        return;
                    }
                    // The capture allocation is fixed for the whole timeline;
                    // only the item bounds and the on-screen quads move. Do not
                    // rebuild the legacy region or invalidate the full window.
                    updateItem(w);
                    const RectF panel = RectF(bounds.translated(w->contentsRect().topLeft()))
                                            .adjusted(-kCaptureExpand, -kCaptureExpand,
                                                      kCaptureExpand, kCaptureExpand);
                    w->addRepaint(Rect(panel.toAlignedRect()));
                });

        m_hoverClock.start();
        m_hoverTimer.setInterval(16);
        connect(&m_hoverTimer, &QTimer::timeout, this, &GlassEffect::stepHoverAnimation);
        installPointerSpy();
    }

    connect(effects, &EffectsHandler::windowAdded, this, [this](EffectWindow *w) {
        trackDamageSources(w);
        updateItem(w);
        // The new window is already in the stacking order. Only glass surfaces
        // it was added below can have a different backdrop; popups and menus
        // land on top of everything and must not invalidate anything.
        m_stackingOrder = effects->stackingOrder();
        invalidateAbove(w);
    });
    connect(effects, &EffectsHandler::windowDeleted, this, [this](EffectWindow *w) {
        untrackDamageSources(w);
        // Whatever it was covering is now unreachable for the damage signals.
        // The deleted window is already gone from the current stacking order,
        // so resolve its position against the last known one.
        invalidateAbove(w);
        removeWindow(w);
        m_stackingOrder.removeAll(w);
    });
    // Stacking changes move windows above/below each other without any client
    // commit; a backdrop that used to be hidden can become visible.
    connect(effects, &EffectsHandler::stackingOrderChanged, this,
            [this] { slotStackingOrderChanged(); });
    connect(effects, &EffectsHandler::desktopChanged, this,
            [this](VirtualDesktop *, VirtualDesktop *, EffectWindow *) {
                invalidateBackdrops();
            });
    connect(effects, &EffectsHandler::virtualScreenGeometryChanged, this,
            [this] { invalidateBackdrops(); });

    // The effect is normally loaded after the shell surfaces already exist.
    const QList<EffectWindow *> windows = effects->stackingOrder();
    for (EffectWindow *w : windows) {
        trackDamageSources(w);
        updateItem(w);
    }
    m_stackingOrder = windows;
}

// InputEventSpy observes every pointer motion before KWin's input filters and
// cannot consume input. It is the same mechanism the context-menu effect uses
// and is available on every supported KWin version.
class GlassPointerSpy final : public InputEventSpy
{
public:
    explicit GlassPointerSpy(GlassEffect *effect)
        : m_effect(effect)
    {
    }

    void pointerMotion(PointerMotionEvent *) override
    {
        if (effects) {
            m_effect->slotPointerMoved(effects->cursorPos());
        }
    }

    void pointerButton(PointerButtonEvent *event) override
    {
        if (effects && event && event->state == PointerButtonState::Pressed
            && event->button == Qt::LeftButton) {
            // The event position is the compositor's global cursor position;
            // it is authoritative even if no motion event preceded the press
            // on this surface.
            m_effect->slotPointerButton(event->position);
        }
    }

private:
    GlassEffect *m_effect;
};

GlassEffect::~GlassEffect()
{
    if (m_pointerSpyInstalled) {
        if (auto *inputRedirection = input()) {
            inputRedirection->uninstallInputEventSpy(m_pointerSpy.get());
        }
    }
    if (!m_render.isEmpty()) {
        effects->makeOpenGLContextCurrent();
        qDeleteAll(m_render);
        m_render.clear();
    }
}

bool GlassEffect::supported()
{
    return effects->isOpenGLCompositing();
}

bool GlassEffect::enabledByDefault()
{
    return supported();
}

void GlassEffect::ensurePasses()
{
    auto &passes = *m_passes;

    passes.onscreen.shader = ShaderManager::instance()->generateShaderFromFile(
        ShaderTrait::MapTexture,
        QStringLiteral(":/effects/glass/generated/onscreen.vert"),
        QStringLiteral(":/effects/glass/generated/onscreen.frag"));
    passes.downsample.shader = ShaderManager::instance()->generateShaderFromFile(
        ShaderTrait::MapTexture,
        QStringLiteral(":/effects/glass/generated/vertex.vert"),
        QStringLiteral(":/effects/glass/generated/downsample.frag"));
    passes.upsample.shader = ShaderManager::instance()->generateShaderFromFile(
        ShaderTrait::MapTexture,
        QStringLiteral(":/effects/glass/generated/vertex.vert"),
        QStringLiteral(":/effects/glass/generated/upsample.frag"));

    if (!passes.onscreen.shader || !passes.downsample.shader || !passes.upsample.shader) {
        qCWarning(KWIN_GLASS) << "Failed to load a glass shader; glass stays inactive";
        passes = RenderPasses{};
        m_valid = false;
        return;
    }

    passes.onscreen.mvpMatrix = passes.onscreen.shader->uniformLocation("modelViewProjectionMatrix");
    passes.onscreen.box = passes.onscreen.shader->uniformLocation("box");
    passes.onscreen.cornerRadius = passes.onscreen.shader->uniformLocation("cornerRadius");
    passes.onscreen.cornerExponent = passes.onscreen.shader->uniformLocation("cornerExponent");
    passes.onscreen.tint = passes.onscreen.shader->uniformLocation("tint");
    passes.onscreen.opacity = passes.onscreen.shader->uniformLocation("opacity");
    passes.onscreen.scrimMode = passes.onscreen.shader->uniformLocation("scrimMode");
    passes.onscreen.scrimCap = passes.onscreen.shader->uniformLocation("scrimCap");
    passes.onscreen.scrimDecay = passes.onscreen.shader->uniformLocation("scrimDecay");
    passes.onscreen.scrimLumaSmooth =
        passes.onscreen.shader->uniformLocation("scrimLumaSmooth");
    passes.onscreen.texUnit = passes.onscreen.shader->uniformLocation("texUnit");
    passes.onscreen.viewportScale = passes.onscreen.shader->uniformLocation("viewportScale");
    passes.onscreen.liquidEnabled = passes.onscreen.shader->uniformLocation("liquidEnabled");
    passes.onscreen.edgeSizePixels =
        passes.onscreen.shader->uniformLocation("edgeSizePixels");
    passes.onscreen.refractionStrength =
        passes.onscreen.shader->uniformLocation("refractionStrength");
    passes.onscreen.refractionNormalPow =
        passes.onscreen.shader->uniformLocation("refractionNormalPow");
    passes.onscreen.refractionRGBFringing =
        passes.onscreen.shader->uniformLocation("refractionRGBFringing");
    passes.onscreen.refractionOffsetStrength =
        passes.onscreen.shader->uniformLocation("refractionOffsetStrength");
    passes.onscreen.materialSoftness =
        passes.onscreen.shader->uniformLocation("materialSoftness");
    passes.onscreen.materialReflectionStrength =
        passes.onscreen.shader->uniformLocation("materialReflectionStrength");
    passes.onscreen.pointerLocal =
        passes.onscreen.shader->uniformLocation("pointerLocal");
    passes.onscreen.hoverAmount =
        passes.onscreen.shader->uniformLocation("hoverAmount");
    passes.onscreen.hoverStrength =
        passes.onscreen.shader->uniformLocation("hoverStrength");
    passes.onscreen.hoverRadius =
        passes.onscreen.shader->uniformLocation("hoverRadius");
    passes.onscreen.parallaxStrength =
        passes.onscreen.shader->uniformLocation("parallaxStrength");
    passes.onscreen.clickLocal =
        passes.onscreen.shader->uniformLocation("clickLocal");
    passes.onscreen.clickRadius =
        passes.onscreen.shader->uniformLocation("clickRadius");
    passes.onscreen.clickAmount =
        passes.onscreen.shader->uniformLocation("clickAmount");

    passes.downsample.mvpMatrix = passes.downsample.shader->uniformLocation("modelViewProjectionMatrix");
    passes.downsample.offset = passes.downsample.shader->uniformLocation("offset");
    passes.downsample.halfpixel = passes.downsample.shader->uniformLocation("halfpixel");
    passes.upsample.mvpMatrix = passes.upsample.shader->uniformLocation("modelViewProjectionMatrix");
    passes.upsample.offset = passes.upsample.shader->uniformLocation("offset");
    passes.upsample.halfpixel = passes.upsample.shader->uniformLocation("halfpixel");
    passes.upsample.saturationCompensation =
        passes.upsample.shader->uniformLocation("saturationCompensation");

    m_valid = true;
}

void GlassEffect::readMaterialSettings()
{
    // KConfigXT caches values in the writer process, not here; parse the file
    // again so a shell sync is visible without a KWin restart.
    KSharedConfigPtr config = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
    config->reparseConfiguration();
    const KConfigGroup group = config->group(QStringLiteral("Effect-blurplus"));

    MaterialSettings settings;
    settings.refractionStrength =
        static_cast<float>(group.readEntry("RefractionStrength", 0.0)) / 20.0f;
    settings.edgeSizePixels =
        static_cast<float>(group.readEntry("RefractionEdgeSize", 20.0));
    settings.refractionNormalPow =
        static_cast<float>(group.readEntry("RefractionNormalPow", 2.0)) / 2.0f;
    settings.refractionRGBFringing =
        static_cast<float>(group.readEntry("RefractionRGBFringing", 1.0)) / 20.0f;
    settings.refractionOffsetStrength =
        static_cast<float>(group.readEntry("RefractionOffsetStrength", 0.0)) / 2.0f;
    settings.materialSoftness =
        std::clamp(static_cast<float>(group.readEntry("MaterialSoftness", 0.0)),
                   0.0f, 1.0f);
    settings.materialReflectionStrength = std::clamp(
        static_cast<float>(group.readEntry("MaterialReflectionStrength", 0.0)),
        0.0f, 1.0f);

    // Blur pipeline: same knobs and ranges the previous implementation read
    // from [Effect-blurplus]. BlurStrength is the 1..15 slider value; here it
    // selects the level count and a small per-level offset instead of the old
    // single coarse level with huge taps. Finetune scales every offset.
    const int strength = qBound(1, static_cast<int>(group.readEntry("BlurStrength", 15)), 15);
    const int finetune = qBound(0, static_cast<int>(group.readEntry("BlurFinetune", 3)), 10);
    const bool saturationCompensation =
        group.readEntry("BlurSaturationCompensation", true);
    const float radius = 0.5f + static_cast<float>(finetune) * 0.13f;
    const BlurStep step = blurStepForStrength(strength - 1);
    settings.blurIterations = step.iterations;
    settings.blurDownsampleOffset = step.offset * radius;
    settings.blurUpsampleOffset = step.offset * radius;
    settings.saturationCompensation =
        saturationCompensation ? (1.18f + 0.13f * (radius + radius) * 0.5f) : 1.0f;

    // Pointer light. Absent keys mean "on": the feature is part of the liquid
    // profile, and the KCM writes the same keys.
    settings.hoverLight = group.readEntry("HoverLight", true);
    settings.hoverLightStrength = std::clamp(
        static_cast<float>(group.readEntry("HoverLightStrength", 10)) / 20.0f,
        0.0f, 1.0f);
    settings.hoverLightRadius = std::clamp(
        static_cast<float>(group.readEntry("HoverLightRadius", 0)), 0.0f, 400.0f);
    settings.pointerParallax = group.readEntry("PointerParallax", true);
    settings.clickLight = group.readEntry("ClickLight", true);
    settings.clickLightStrength = std::clamp(
        static_cast<float>(group.readEntry("ClickLightStrength", 10)) / 20.0f,
        0.0f, 1.0f);
    settings.clickLightRadius = std::clamp(
        static_cast<float>(group.readEntry("ClickLightRadius", 200)), 20.0f, 600.0f);
    settings.clickLightDuration = std::clamp(
        static_cast<int>(group.readEntry("ClickLightDuration", 450)), 100, 2000);

    m_material = settings;
}

void GlassEffect::reconfigure(ReconfigureFlags flags)
{
    Q_UNUSED(flags)
    // Material values arrive through `Effect-blurplus` in kwinrc (written by
    // the shell's theme sync), so every reconfigure re-reads them. The passes
    // are only rebuilt when the GL context was lost and the shaders are gone.
    readMaterialSettings();
    if (!m_valid) {
        ensurePasses();
    }
    // Config changes do not damage any window by themselves. Repaint once so a
    // new strength/tint/offset is visible without waiting for unrelated damage,
    // which is also what the previous implementation did.
    effects->addRepaintFull();
}

void GlassEffect::updateItem(EffectWindow *w)
{
    if (!m_shapes || !w || !w->surface()) {
        return;
    }
    // This is an ownership exclusion, not a blur blacklist: even explicitly
    // requested material must not land on a Mime frame. The application ID can
    // arrive after mapping, so retire whatever the window built before the
    // client identified itself instead of only skipping the next build.
    if (KOS::keepsClientAppearance(w->windowClass())) {
        if (auto it = m_render.find(w); it != m_render.end()) {
            effects->makeOpenGLContextCurrent();
            delete it.value();
            m_render.erase(it);
        }
        return;
    }
    const QVector<GlassShape> shapes = m_shapes->shapesFor(w->surface());

    QRectF bounds;
    for (const GlassShape &shape : shapes) {
        if (!shape.hasArea()) {
            continue;
        }
        bounds |= shape.geometry.translated(w->contentsRect().topLeft());
    }

    RenderData *data = m_render.value(w);
    if (bounds.isEmpty()) {
        // No visible shape: stop expanding damage. Keep the textures so a
        // reopen reuses the same chain sizes instead of reallocating.
        if (data && data->item) {
            data->item.reset();
        }
        return;
    }

    if (!data) {
        data = new RenderData;
        m_render.insert(w, data);
    }
#if defined(GLASS_HAS_BACKGROUND_ITEM)
    if (!data->item) {
        data->item = std::make_unique<BackgroundEffectItem>(w->windowItem());
    }
    data->item->setEffectBoundingRect(RectF(bounds));
    data->item->setPixelsToExpandRepaintsBelowOpaqueRegions(kCaptureExpand);
#else
    if (!data->item) {
        data->item = std::make_unique<ItemEffect>(w->windowItem());
    }
#endif
}

void GlassEffect::removeWindow(EffectWindow *w)
{
    auto it = m_render.find(w);
    if (it == m_render.end()) {
        return;
    }
    effects->makeOpenGLContextCurrent();
    delete it.value();
    m_render.erase(it);
}

void GlassEffect::trackDamageSources(EffectWindow *w)
{
    if (!w || m_windowDamageConnections.contains(w)) {
        return;
    }
    // Client commits are the one reliable "the pixels under this surface
    // changed" signal. EffectWindow::windowDamaged fires on the paint path,
    // which also fires for a surface's own content updates -- the case we
    // want to skip -- so the internal Window::damaged (the same signal
    // screencast uses) is connected instead.
    if (Window *client = w->window()) {
        m_windowDamageConnections[w] = connect(
            client, &Window::damaged, this,
            [this, w](Window *) { slotWindowContentDamaged(w); });
    }
    // A moved or resized window changes the backdrop without committing new
    // content underneath the glass -- but only for surfaces below it.
    m_geometryConnections[w] = connect(
        w, &EffectWindow::windowFrameGeometryChanged, this,
        [this](EffectWindow *window, const QRectF &) { invalidateAbove(window); });
}

void GlassEffect::untrackDamageSources(EffectWindow *w)
{
    if (const QMetaObject::Connection c = m_windowDamageConnections.take(w)) {
        disconnect(c);
    }
    if (const QMetaObject::Connection c = m_geometryConnections.take(w)) {
        disconnect(c);
    }
}

void GlassEffect::slotWindowContentDamaged(EffectWindow *w)
{
    // Runs on the client-commit path, not on the paint path: touch nothing but
    // the dirty flags (the stageanim effect documents the same constraint).
    invalidateAbove(w);
}

void GlassEffect::installPointerSpy()
{
    if (m_pointerSpyInstalled) {
        return;
    }
    if (auto *inputRedirection = input()) {
        if (!m_pointerSpy) {
            m_pointerSpy = std::make_unique<GlassPointerSpy>(this);
        }
        inputRedirection->installInputEventSpy(m_pointerSpy.get());
        m_pointerSpyInstalled = true;
        return;
    }
    // Effects may be constructed before KWin finishes bringing up input on a
    // compositor restart; retry instead of ending up permanently inactive.
    QTimer::singleShot(100, this, &GlassEffect::installPointerSpy);
}

void GlassEffect::slotPointerMoved(const QPointF &scenePos)
{
    if (!m_shapes || (!m_material.hoverLight && !m_material.pointerParallax)) {
        return;
    }
    const bool reduceMotion = effects->animationTimeFactor() <= 0.0;
    for (auto it = m_render.cbegin(); it != m_render.cend(); ++it) {
        EffectWindow *w = it.key();
        RenderData *data = it.value();
        if (!data || !w || !w->surface()) {
            continue;
        }
        const QVector<GlassShape> shapes = m_shapes->shapesFor(w->surface());
        if (shapes.isEmpty()) {
            continue;
        }
        const QPointF origin = w->pos() + w->contentsRect().topLeft();
        bool inside = false;
        for (const GlassShape &shape : shapes) {
            // Only shapes that opted into hover light or parallax keep the
            // pointer pipeline alive; a panel that disabled both must not
            // repaint while the cursor passes over it.
            if (!shape.hasArea() || (shape.pointerEffects & 0x3) == 0) {
                continue;
            }
            if (shape.geometry.translated(origin)
                    .adjusted(-kHoverMargin, -kHoverMargin, kHoverMargin, kHoverMargin)
                    .contains(scenePos)) {
                inside = true;
                break;
            }
        }
        const bool wasLit = data->hover > 0.0f;
        data->pointerScene = scenePos;
        data->pointerKnown = true;
        data->hoverTarget = m_material.hoverLight && inside ? 1.0f : 0.0f;
        if (reduceMotion) {
            // Reduced motion keeps a static spot: no fade timeline at all.
            data->hover = data->hoverTarget;
            if (inside || wasLit) {
                repaintShapes(w, shapes);
            }
            continue;
        }
        if (data->hover != data->hoverTarget && !m_hoverTimer.isActive()) {
            m_lastHoverTick = m_hoverClock.elapsed();
            m_hoverTimer.start();
        }
        // Parallax follows the pointer while it is on the glass; the moving
        // lobe needs a frame even when the fade has already settled.
        if (inside || data->hover != data->hoverTarget) {
            repaintShapes(w, shapes);
        }
    }
}

void GlassEffect::slotPointerButton(const QPointF &scenePos)
{
    if (!m_shapes || !m_material.clickLight) {
        return;
    }
    // Reduced motion: a pulse is pure movement, so leave it out entirely.
    if (effects->animationTimeFactor() <= 0.0) {
        return;
    }
    m_clickScene = scenePos;
    m_clickStart = m_hoverClock.elapsed();
    if (!m_hoverTimer.isActive()) {
        m_lastHoverTick = m_clickStart;
        m_hoverTimer.start();
    }
    // Frame the ripple once immediately; the timer carries it afterwards.
    for (auto it = m_render.cbegin(); it != m_render.cend(); ++it) {
        EffectWindow *w = it.key();
        if (w && w->surface()) {
            repaintShapes(w, m_shapes->shapesFor(w->surface()));
        }
    }
}

void GlassEffect::stepHoverAnimation()
{
    if (!m_shapes) {
        m_hoverTimer.stop();
        return;
    }
    const qint64 now = m_hoverClock.elapsed();
    const float dt = std::clamp((now - m_lastHoverTick) / 1000.0f, 0.001f, 0.05f);
    m_lastHoverTick = now;
    bool active = false;
    for (auto it = m_render.cbegin(); it != m_render.cend(); ++it) {
        EffectWindow *w = it.key();
        RenderData *data = it.value();
        if (!data || !w || data->hover == data->hoverTarget) {
            continue;
        }
        // Fast attack, slow decay; the decay time constant is ~150 ms, inside
        // the 120-180 ms band the requirements ask for.
        const float tau = data->hoverTarget > data->hover ? 0.045f : 0.15f;
        const float k = 1.0f - std::exp(-dt / tau);
        data->hover += (data->hoverTarget - data->hover) * k;
        if (std::abs(data->hover - data->hoverTarget) < 0.004f) {
            data->hover = data->hoverTarget;
        }
        repaintShapes(w, w->surface() ? m_shapes->shapesFor(w->surface())
                                      : QVector<GlassShape>());
        active = active || data->hover != data->hoverTarget;
    }

    // The click ripple shares the timer: while a pulse is running every glass
    // window under it gets a frame, so the expanding rim moves.
    if (m_clickStart >= 0) {
        const qint64 duration = std::max<int>(1, m_material.clickLightDuration);
        if (now - m_clickStart >= duration) {
            m_clickStart = -1;
            for (auto it = m_render.cbegin(); it != m_render.cend(); ++it) {
                EffectWindow *w = it.key();
                if (w && w->surface()) {
                    repaintShapes(w, m_shapes->shapesFor(w->surface()));
                }
            }
        } else {
            active = true;
            for (auto it = m_render.cbegin(); it != m_render.cend(); ++it) {
                EffectWindow *w = it.key();
                if (w && w->surface()) {
                    repaintShapes(w, m_shapes->shapesFor(w->surface()));
                }
            }
        }
    }

    if (!active) {
        m_hoverTimer.stop();
    }
}

void GlassEffect::repaintShapes(EffectWindow *w, const QVector<GlassShape> &shapes)
{
    if (!w) {
        return;
    }
    QRectF bounds;
    const QPointF offset = w->contentsRect().topLeft();
    for (const GlassShape &shape : shapes) {
        if (shape.hasArea()) {
            bounds |= shape.geometry.translated(offset);
        }
    }
    if (bounds.isEmpty()) {
        return;
    }
    // The composite pass only: the shader uniform changed, the chain did not.
    w->addRepaint(Rect(bounds.adjusted(-4.0, -4.0, 4.0, 4.0).toAlignedRect()));
}

void GlassEffect::slotStackingOrderChanged()
{
    const QList<EffectWindow *> order = effects->stackingOrder();
    for (auto it = m_render.cbegin(); it != m_render.cend(); ++it) {
        RenderData *data = it.value();
        if (!data) {
            continue;
        }
        const int oldIndex = m_stackingOrder.indexOf(it.key());
        const int newIndex = order.indexOf(it.key());
        // A swap between two windows below the glass changes what shows
        // through it; the ordered prefix below the surface is the exact
        // dependency, so compare that instead of invalidating on any reorder.
        if (oldIndex < 0 || newIndex < 0
            || m_stackingOrder.mid(0, oldIndex) != order.mid(0, newIndex)) {
            data->backdropDirty = true;
        }
    }
    m_stackingOrder = order;
}

void GlassEffect::invalidateAbove(EffectWindow *changed)
{
    if (m_render.isEmpty()) {
        return;
    }
    // Without a trustworthy position the safest answer is "anything may have
    // changed"; this only costs one chain run.
    const int changedIndex = changed ? m_stackingOrder.indexOf(changed) : -1;
    if (changedIndex < 0) {
        invalidateBackdrops();
        return;
    }
    for (auto it = m_render.cbegin(); it != m_render.cend(); ++it) {
        RenderData *data = it.value();
        if (!data || it.key() == changed) {
            continue;
        }
        const int glassIndex = m_stackingOrder.indexOf(it.key());
        if (glassIndex < 0 || glassIndex > changedIndex) {
            data->backdropDirty = true;
        }
    }
}

void GlassEffect::invalidateBackdrops()
{
    for (RenderData *data : std::as_const(m_render)) {
        if (data) {
            data->backdropDirty = true;
        }
    }
}

#ifdef GLASS_KWIN_67
void GlassEffect::prePaintScreen(ScreenPrePaintData &data)
#else
void GlassEffect::prePaintScreen(ScreenPrePaintData &data,
                                 std::chrono::milliseconds presentTime)
#endif
{
    // Advance client-driven reveal timelines before anything is painted so
    // every shape in this frame sees the same progress.
    if (m_shapes) {
        m_shapes->advanceAnimations();
    }
#ifdef GLASS_KWIN_67
    effects->prePaintScreen(data);
#else
    effects->prePaintScreen(data, presentTime);
    m_paintedDeviceArea = Region();
    m_currentDeviceBlur = Region();
#endif
}

void GlassEffect::postPaintScreen()
{
    effects->postPaintScreen();
    // Client focus and model work must not begin before this frame's GPU
    // commands have been submitted by the window draw chain.
    if (m_shapes) {
        m_shapes->completeAnimations();
    }
}

#ifndef GLASS_KWIN_67
void GlassEffect::prePaintWindow(RenderView *view, EffectWindow *w, WindowPrePaintData &data,
                                 std::chrono::milliseconds presentTime)
{
    // KWin calls this bottom to top. The bookkeeping below is what keeps a
    // glass surface correct when a window underneath it repaints: the lower
    // window is allowed to paint through the translucent material, so the
    // glass window has to be scheduled again on top of it. Without this the
    // frame keeps the lower window's pixels where the surface content should
    // be -- the Dock loses its icons for a frame whenever a fullscreen window
    // below it (the desktop menu scrim) is damaged.
    effects->prePaintWindow(view, w, data, presentTime);

    Region blurArea;
    // An excluded window paints no material, so it must not expand damage or
    // schedule repaints for a glass region that will never be drawn.
    if (m_shapes && w->surface() && !KOS::keepsClientAppearance(w->windowClass())) {
        const QVector<GlassShape> shapes = m_shapes->shapesFor(w->surface());
        if (!shapes.isEmpty()) {
            const QRectF logical = shapeUnion(w, shapes, false);
            if (!logical.isEmpty()) {
                blurArea = view->mapToDeviceCoordinatesAligned(logical);
            }
        }
    }

    if (!blurArea.isEmpty()) {
        // The damage region is in device pixels while the capture margin is
        // logical; scale it or the glass repaints too small a margin on HiDPI
        // outputs.
        const int expand = static_cast<int>(std::ceil(kCaptureExpand * view->scale()));
        Region expandedBlur = blurArea;
        for (const Rect &rect : blurArea.rects()) {
            expandedBlur += rect.adjusted(-expand, -expand, expand, expand);
        }

        data.deviceOpaque -= blurArea;
        data.devicePaint += (expandedBlur - data.deviceOpaque);
    }

    if (!blurArea.isEmpty()
        && (m_paintedDeviceArea.intersects(blurArea)
            || data.devicePaint.intersects(blurArea))) {
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

bool GlassEffect::isActive() const
{
    return m_valid && !effects->isScreenLocked();
}

void GlassEffect::render(const RenderTarget &renderTarget, const RenderViewport &viewport,
                         EffectWindow *w, const Region &deviceRegion,
                         const WindowPaintData &paint)
{
    const qreal windowOpacity = paint.opacity();
    if (!m_valid || !m_shapes || !w->surface() || windowOpacity <= 0.0) {
        return;
    }
    // A late application ID must stop the material immediately, even before
    // updateItem() gets a chance to retire the cached backdrop.
    if (KOS::keepsClientAppearance(w->windowClass())) {
        return;
    }
    // Nothing under this window is damaged, so the glass already in the target
    // is still current. Re-compositing it would double-blend a translucent
    // material and burn fill rate for no pixel change.
    if (deviceRegion.isEmpty()) {
        return;
    }

    // Set only while the Dock animation owns this window; anything else gets a
    // fully opaque material.
    const QVariant dockFade = w->data(kDockAnimationGlassFadeRole);
    const float glassFade = dockFade.isValid()
        ? std::clamp(static_cast<float>(dockFade.toReal()), 0.0f, 1.0f)
        : 1.0f;

    const QVector<GlassShape> declared = m_shapes->shapesFor(w->surface());
    QVector<GlassShape> shapes;
    shapes.reserve(declared.size());
    for (const GlassShape &shape : declared) {
        if (shape.hasArea()) {
            shapes.append(shape);
        }
    }
    if (shapes.isEmpty()) {
        return;
    }

    // Effects that ask for blur through WindowForceBlurRole paint the window
    // through their own scale/translation (overview-style thumbnails, desktop
    // slide, maximisation). Shapes are declared in surface coordinates, so the
    // same window transform has to be applied to them or the glass would stay
    // anchored to the untransformed frame. Scale is anchored at the window's
    // scene position, matching how KWin transforms the window itself.
    const QPointF anchor = w->pos();
    const qreal scaleX = paint.xScale();
    const qreal scaleY = paint.yScale();
    const qreal offsetX = paint.xTranslation();
    const qreal offsetY = paint.yTranslation();
    auto transformedScene = [&](QRectF scene) {
        if (scaleX != 1.0 || scaleY != 1.0) {
            const QPointF topLeft(
                anchor.x() + (scene.x() - anchor.x()) * scaleX + offsetX,
                anchor.y() + (scene.y() - anchor.y()) * scaleY + offsetY);
            scene = QRectF(topLeft, QSizeF(scene.width() * scaleX, scene.height() * scaleY));
        } else if (offsetX != 0.0 || offsetY != 0.0) {
            scene.translate(offsetX, offsetY);
        }
        return scene;
    };
    auto shapeSceneRect = [&](const GlassShape &shape, bool capture) {
        const QRectF local = capture ? shape.captureBounds() : shape.geometry;
        return transformedScene(local.translated(w->pos() + w->contentsRect().topLeft()));
    };

    QRectF captureUnion;
    for (const GlassShape &shape : shapes) {
        captureUnion |= shapeSceneRect(shape, true);
    }
    const QRect capture = stableCapture(captureUnion,
                                        QRect(effects->virtualScreenGeometry()));
    if (capture.isEmpty()) {
        return;
    }

    RenderData *data = m_render.value(w);
    if (!data) {
        return;
    }

    const GLenum format = renderTarget.texture()
        ? renderTarget.texture()->internalFormat()
        : GL_RGBA8;
    bool freshCapture = false;
    if (data->captureSize != capture.size() || data->format != format) {
        // A different size or format invalidates every level; the chains are
        // recreated from scratch below.
        data->chains.clear();
        data->captureFramebuffer.reset();
        data->captureTexture.reset();
        data->captureRect = QRect();
        data->format = format;

        std::unique_ptr<GLTexture> texture = GLTexture::allocate(format, capture.size());
        if (!texture) {
            qCWarning(KWIN_GLASS) << "Failed to allocate the glass capture";
            return;
        }
        texture->setFilter(GL_LINEAR);
        texture->setWrapMode(GL_CLAMP_TO_EDGE);
        auto framebuffer = std::make_unique<GLFramebuffer>(texture.get());
        if (!framebuffer->valid()) {
            qCWarning(KWIN_GLASS) << "Failed to create the glass capture framebuffer";
            return;
        }
        glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
        GLFramebuffer::pushFramebuffer(framebuffer.get());
        glClear(GL_COLOR_BUFFER_BIT);
        GLFramebuffer::popFramebuffer();

        data->captureTexture = std::move(texture);
        data->captureFramebuffer = std::move(framebuffer);
        data->captureSize = capture.size();
        freshCapture = true;
    }

    const bool rectChanged = data->captureRect != capture;
    if (rectChanged) {
        // A moved capture origin no longer aligns with the cached level pixels.
        for (BlurChain &chain : data->chains) {
            chain.valid = false;
        }
    }

    // Resolve every shape's chain up front; shapes on the same settings share
    // one chain (the shell drives most surfaces from the same values), and a
    // shape that asked for no blur samples the capture directly.
    for (BlurChain &chain : data->chains) {
        chain.used = false;
    }
    QVector<BlurChain *> shapeChains;
    shapeChains.reserve(shapes.size());
    for (const GlassShape &shape : shapes) {
        const BlurConfig config = resolveBlurConfig(shape, m_material);
        BlurChain *chain = config.iterations > 0 ? ensureChain(data, config) : nullptr;
        if (config.iterations > 0 && !chain) {
            return;
        }
        shapeChains.append(chain);
    }

    // Copy only the damaged part of the backdrop; the rest of the capture still
    // holds the previous frame's pixels. KWin paints bottom to top, so by now
    // everything below this window is already in the render target. A fresh or
    // moved capture has no history and refills the whole rect.
    const Region dirty = (freshCapture || rectChanged)
        ? Region(Rect(capture))
        : viewport.mapFromDeviceCoordinatesContained(deviceRegion) & Region(Rect(capture));

    // The blurred image depends on the backdrop only. A surface repainting its
    // own content still needs the composite below, but the cached chain result
    // is already correct. When the backdrop flag is raised without any damage
    // reaching the capture, keep the flag for the frame that carries it.
    const bool backdropDirty = data->backdropDirty;
    auto chainNeedsRefresh = [&](const BlurChain &chain) {
        return !chain.valid || freshCapture || rectChanged
            || (backdropDirty && !dirty.isEmpty());
    };
    const bool chainRefresh = std::any_of(
        data->chains.begin(), data->chains.end(),
        [&](const BlurChain &chain) { return chain.used && chainNeedsRefresh(chain); });
    // The capture is level 0 for every chain and the direct source for a shape
    // that asked for no blur, so it has to be refilled even when no chain runs
    // (a window whose shapes are all sigma = 0 has no chains at all).
    const bool captureNeedsRefresh =
        freshCapture || rectChanged || (backdropDirty && !dirty.isEmpty());
    const bool refresh = chainRefresh || captureNeedsRefresh;
    if (refresh) {
        for (const Rect &rect : dirty.rects()) {
            data->captureFramebuffer->blitFromRenderTarget(
                renderTarget, viewport, rect, rect.translated(-capture.topLeft()));
        }
    }

    GLVertexBuffer *vbo = GLVertexBuffer::streamingBuffer();
    vbo->reset();
    vbo->setAttribLayout(std::span(GLVertexBuffer::GLVertex2DLayout), sizeof(GLVertex2D));

    // KWin builds the RenderViewport from the output's scene rect, so
    // mapToDeviceCoordinates*() returns render-target-local coordinates (the
    // output's scene origin is subtracted). The projection matrix and KWin's
    // own item vertices live in global scene device coordinates. Feeding the
    // local rects to the projection shifted the material by the output origin:
    // invisible on a single output at (0, 0), but on a second output the glass
    // landed at the output's top-left edge and the dock's quads fell outside
    // the render target entirely. Move the quad and clip rects into the space
    // the projection expects.
    const QPoint globalDeviceOffset =
        viewport.scaledRenderRect().topLeft() - viewport.renderOffset();

    // The on-screen quads have to be clipped to the region KWin is painting.
    // The renderer clips the window content that follows this effect, but an
    // effect draws before renderItem() runs, so there is no scissor here. A
    // full-shape quad would then blend the material over the whole surface on
    // top of the previously composited content: a partially damaged window
    // (a dock repainted under an opening desktop menu) loses every pixel that
    // is not repainted -- the icons stay underneath a fresh, mostly opaque
    // material layer until the next full repaint. The previous implementation
    // clipped its on-screen geometry the same way.
    QVector<Rect> clipRects;
    if (deviceRegion != Region::infinite()) {
        const auto rects = deviceRegion.rects();
        clipRects.reserve(static_cast<int>(rects.size()));
        for (const Rect &rect : rects) {
            clipRects.append(rect.translated(globalDeviceOffset));
        }
    }

    struct ShapeQuads
    {
        Rect device;
        QVector<QRect> rects;
    };
    QVector<ShapeQuads> shapeQuads;
    shapeQuads.reserve(shapes.size());
    int quadCount = 1; // the off-screen capture quad
    for (const GlassShape &shape : shapes) {
        ShapeQuads entry;
        entry.device = viewport.mapToDeviceCoordinatesAligned(shapeSceneRect(shape, false))
                           .translated(globalDeviceOffset);
        if (clipRects.isEmpty()) {
            entry.rects.append(QRect(entry.device));
        } else {
            for (const Rect &clip : clipRects) {
                const Rect clipped = entry.device & clip;
                if (!clipped.isEmpty()) {
                    entry.rects.append(QRect(clipped));
                }
            }
        }
        quadCount += static_cast<int>(entry.rects.size());
        shapeQuads.append(std::move(entry));
    }

    const int vertexCount = 6 * quadCount;
    auto mapping = vbo->map<GLVertex2D>(vertexCount);
    if (!mapping) {
        qCWarning(KWIN_GLASS) << "Failed to map the glass vertex buffer";
        return;
    }
    auto map = *mapping;

    const float captureWidth = capture.width();
    const float captureHeight = capture.height();
    size_t index = 0;

    auto appendQuad = [&](const QRectF &rect, auto texcoordFor) {
        const float x0 = rect.left();
        const float y0 = rect.top();
        const float x1 = rect.right();
        const float y1 = rect.bottom();
        const QVector2D uv00 = texcoordFor(x0, y0);
        const QVector2D uv10 = texcoordFor(x1, y0);
        const QVector2D uv01 = texcoordFor(x0, y1);
        const QVector2D uv11 = texcoordFor(x1, y1);

        map[index++] = GLVertex2D{QVector2D(x0, y0), uv00};
        map[index++] = GLVertex2D{QVector2D(x1, y1), uv11};
        map[index++] = GLVertex2D{QVector2D(x0, y1), uv01};
        map[index++] = GLVertex2D{QVector2D(x0, y0), uv00};
        map[index++] = GLVertex2D{QVector2D(x1, y0), uv10};
        map[index++] = GLVertex2D{QVector2D(x1, y1), uv11};
    };

    // Offscreen quad, in capture-local logical pixels.
    appendQuad(QRectF(0, 0, captureWidth, captureHeight), [&](float x, float y) {
        return QVector2D(x / captureWidth, 1.0f - y / captureHeight);
    });

    // On-screen quads, in capture-local device pixels. The capture texture is
    // logical resolution; normalised coordinates make that independent.
    const Rect captureDevice =
        viewport.mapToDeviceCoordinatesAligned(QRectF(capture)).translated(globalDeviceOffset);
    for (const ShapeQuads &entry : shapeQuads) {
        for (const QRect &device : entry.rects) {
            const QRectF local(device.translated(-captureDevice.x(), -captureDevice.y()));
            appendQuad(local, [&](float x, float y) {
                return QVector2D(x / captureDevice.width(),
                                 1.0f - y / captureDevice.height());
            });
        }
    }
    vbo->unmap();
    vbo->bindArrays();

    glDisable(GL_BLEND);

    auto &passes = *m_passes;
    GLint savedScissor[4];
    const GLboolean hadScissor = glIsEnabled(GL_SCISSOR_TEST);
    glGetIntegerv(GL_SCISSOR_BOX, savedScissor);

    auto drawLevel = [&](const QSize &size, const QRegion &region) {
        if (region.isEmpty()) {
            return;
        }
        const QRect full(QPoint(0, 0), size);
        if (region.rectCount() == 1 && region.boundingRect() == full) {
            // Always drop the scissor here. A previous partial draw in this
            // same chain leaves the test enabled with a box in *that* level's
            // pixels; a full-size target that still has it on gets clipped to
            // a stale corner, which is exactly the "sharp blocks" artifact:
            // the chain result only lands in one corner and the rest keeps the
            // single-level downsample.
            glDisable(GL_SCISSOR_TEST);
            vbo->draw(GL_TRIANGLES, 0, 6);
            return;
        }
        glEnable(GL_SCISSOR_TEST);
        for (const QRect &rect : region) {
            glScissor(rect.x(), size.height() - (rect.y() + rect.height()),
                      rect.width(), rect.height());
            vbo->draw(GL_TRIANGLES, 0, 6);
        }
    };

    QMatrix4x4 projection;
    projection.ortho(QRectF(0, 0, captureWidth, captureHeight));

    if (refresh) {
        // Each chain runs on its own level count and offsets. The shared
        // capture is level 0 for all of them, so chains on the same backdrop
        // never re-read the screen.
        for (BlurChain &chain : data->chains) {
            if (!chain.used) {
                continue;
            }
            const bool chainFull = !chain.valid || freshCapture || rectChanged;
            if (!chainFull && !(backdropDirty && !dirty.isEmpty())) {
                continue;
            }
            const int iterations = chain.iterations;
            const int tap = static_cast<int>(std::ceil(
                                std::max(chain.downsampleOffset,
                                         chain.upsampleOffset))) + 1;
            // A new chain has no history, so it has to rebuild every level of
            // the capture even when only part of the backdrop changed.
            const Region refreshRegion = chainFull ? Region(Rect(capture)) : dirty;

            // Only the perturbed part of each level has to be rewritten.
            // Everything outside keeps the value it had when that pixel of the
            // backdrop last changed, which is the incremental-blur invariant.
            QRegion levelDirty[kIterations + 1];
            for (const Rect &rect : refreshRegion.rects()) {
                levelDirty[0] += QRect(rect.x() - capture.x(), rect.y() - capture.y(),
                                       rect.width(), rect.height());
            }
            for (int i = 1; i <= iterations; ++i) {
                levelDirty[i] = toDownLevel(expandRegion(levelDirty[i - 1], tap),
                                            levelSize(capture.size(), i));
            }

            ShaderManager::instance()->pushShader(passes.downsample.shader.get());
            passes.downsample.shader->setUniform(passes.downsample.mvpMatrix, projection);
            passes.downsample.shader->setUniform(passes.downsample.offset,
                                                 chain.downsampleOffset);
            for (int i = 1; i <= iterations; ++i) {
                GLTexture *read = i == 1 ? data->captureTexture.get()
                                         : chain.textures[i - 2].get();
                passes.downsample.shader->setUniform(
                    passes.downsample.halfpixel,
                    QVector2D(0.5f / read->width(), 0.5f / read->height()));
                glActiveTexture(GL_TEXTURE0);
                read->bind();
                GLFramebuffer::pushFramebuffer(chain.framebuffers[i - 1].get());
                drawLevel(levelSize(capture.size(), i), levelDirty[i]);
            }
            ShaderManager::instance()->popShader();

            ShaderManager::instance()->pushShader(passes.upsample.shader.get());
            passes.upsample.shader->setUniform(passes.upsample.mvpMatrix, projection);
            passes.upsample.shader->setUniform(passes.upsample.offset,
                                               chain.upsampleOffset);
            QRegion upDirty = levelDirty[iterations];
            for (int i = iterations; i > 1; --i) {
                GLFramebuffer::popFramebuffer();
                GLTexture *read = chain.textures[i - 1].get();
                passes.upsample.shader->setUniform(
                    passes.upsample.halfpixel,
                    QVector2D(0.5f / read->width(), 0.5f / read->height()));
                // Apply the boost on the pass that writes the final level only;
                // stacking it on every level would over-saturate.
                passes.upsample.shader->setUniform(
                    passes.upsample.saturationCompensation,
                    i == 2 ? m_material.saturationCompensation : 1.0f);
                glActiveTexture(GL_TEXTURE0);
                read->bind();
                const QRegion targetDirty = toUpLevel(expandRegion(upDirty, tap),
                                                      levelSize(capture.size(), i - 1));
                drawLevel(levelSize(capture.size(), i - 1), targetDirty);
                upDirty = targetDirty;
            }
            ShaderManager::instance()->popShader();
            GLFramebuffer::popFramebuffer();
            chain.valid = true;
        }

        if (hadScissor) {
            glEnable(GL_SCISSOR_TEST);
        } else {
            glDisable(GL_SCISSOR_TEST);
        }
        glScissor(savedScissor[0], savedScissor[1], savedScissor[2], savedScissor[3]);
        data->backdropDirty = false;
    }
    data->captureRect = capture;

    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

    QMatrix4x4 onscreenProjection = viewport.projectionMatrix();
    onscreenProjection.translate(captureDevice.x(), captureDevice.y());

    ShaderManager::instance()->pushShader(passes.onscreen.shader.get());
    passes.onscreen.shader->setUniform(passes.onscreen.mvpMatrix, onscreenProjection);
    passes.onscreen.shader->setUniform(passes.onscreen.texUnit, 0);
    passes.onscreen.shader->setUniform(
        passes.onscreen.viewportScale, static_cast<float>(viewport.scale()));
    // Global optics are the same for every shape in this frame; only the
    // material scale and the liquid gate differ per shape.
    passes.onscreen.shader->setUniform(passes.onscreen.edgeSizePixels,
                                       m_material.edgeSizePixels);
    passes.onscreen.shader->setUniform(passes.onscreen.refractionNormalPow,
                                       m_material.refractionNormalPow);
    passes.onscreen.shader->setUniform(passes.onscreen.refractionRGBFringing,
                                       m_material.refractionRGBFringing);
    passes.onscreen.shader->setUniform(passes.onscreen.refractionOffsetStrength,
                                       m_material.refractionOffsetStrength);
    passes.onscreen.shader->setUniform(passes.onscreen.materialSoftness,
                                       m_material.materialSoftness);
    passes.onscreen.shader->setUniform(passes.onscreen.materialReflectionStrength,
                                       m_material.materialReflectionStrength);
    // Each shape samples its own chain's final level; a shape that requested
    // no blur reads the capture itself.
    GLTexture *boundSource = nullptr;

    const qreal scale = viewport.scale();
    int offsetIndex = 6;
    for (int i = 0; i < shapes.size(); ++i) {
        const GlassShape &shape = shapes[i];
        const int vertexCountForShape = 6 * static_cast<int>(shapeQuads[i].rects.size());
        if (vertexCountForShape == 0) {
            continue;
        }
        BlurChain *chain = shapeChains[i];
        GLTexture *source = chain ? chain->textures[0].get()
                                  : data->captureTexture.get();
        if (source != boundSource) {
            glActiveTexture(GL_TEXTURE0);
            source->bind();
            boundSource = source;
        }
        const Rect device = shapeQuads[i].device.translated(-captureDevice.topLeft());
        const float radius = static_cast<float>(
            std::min(shape.radius * scale,
                     std::min<qreal>(device.width(), device.height()) * 0.5));
        const QVector4D radii(radius, radius, radius, radius);
        const QVector4D box(device.x() + device.width() * 0.5,
                            device.y() + device.height() * 0.5,
                            device.width() * 0.5,
                            device.height() * 0.5);

        const float tintOpacity = static_cast<float>(shape.tintOpacity);
        QVector4D tint(static_cast<float>(shape.tint.redF()),
                       static_cast<float>(shape.tint.greenF()),
                       static_cast<float>(shape.tint.blueF()),
                       tintOpacity);
        if (shape.tintMode == 0) {
            tint.setW(0);
        } else if (shape.tintMode == 2) {
            tint = QVector4D(0.34, 0.335, 0.35, tintOpacity);
        } else if (shape.tintMode == 3) {
            tint = QVector4D(0.92, 0.915, 0.905, tintOpacity);
        }

        passes.onscreen.shader->setUniform(passes.onscreen.box, box);
        passes.onscreen.shader->setUniform(passes.onscreen.cornerRadius, radii);
        passes.onscreen.shader->setUniform(passes.onscreen.cornerExponent,
                                           static_cast<float>(shape.exponent));
        passes.onscreen.shader->setUniform(passes.onscreen.tint, tint);

        // Adaptive scrim: dark (mode 1) for the default finishes, light
        // (mode 2) when the theme follows a light appearance. Both curves are
        // the previous implementation's; cap and decay come from the theme's
        // readable/balanced/transparent presets.
        const int scrimMode =
            shape.scrimEnabled ? 1 + (shape.scrimTint == 1 ? 1 : 0) : 0;
        passes.onscreen.shader->setUniform(passes.onscreen.scrimMode, scrimMode);
        passes.onscreen.shader->setUniform(passes.onscreen.scrimLumaSmooth,
                                           chain ? 0 : 1);
        passes.onscreen.shader->setUniform(
            passes.onscreen.scrimCap,
            static_cast<float>(std::clamp<qreal>(shape.scrimCap, 0.0, 1.0)));
        passes.onscreen.shader->setUniform(
            passes.onscreen.scrimDecay,
            static_cast<float>(std::clamp<qreal>(shape.scrimDecay, 0.0, 1.0)));

        // Liquid optics are a per-shape choice; thicker materials bend more.
        const float opticalScale = shape.material == 0 ? 0.6f
            : shape.material == 2 ? 1.2f : 1.0f;
        passes.onscreen.shader->setUniform(passes.onscreen.liquidEnabled,
                                           shape.effect == 0 ? 1 : 0);
        passes.onscreen.shader->setUniform(passes.onscreen.refractionStrength,
                                           m_material.refractionStrength * opticalScale);
        // Pointer light. Only the liquid profile receives it; the frosted
        // profile is a tone, not a lens, and has nothing for the light to
        // refract. The uniform is in the shader's flipped-Y device space.
        const bool pointerLiquid = shape.effect == 0 && data->pointerKnown;
        QVector2D pointerPosition(0.0f, 0.0f);
        if (pointerLiquid) {
            const QPointF pointerDevice =
                (data->pointerScene - QPointF(capture.topLeft())) * scale;
            pointerPosition = QVector2D(
                static_cast<float>(pointerDevice.x() - box.x()),
                static_cast<float>(box.y() - pointerDevice.y()));
        }
        passes.onscreen.shader->setUniform(passes.onscreen.pointerLocal, pointerPosition);
        // Pointer effects are a per-shape choice (protocol v9): the shell
        // decides which panels receive the light, the parallax and the ripple.
        passes.onscreen.shader->setUniform(
            passes.onscreen.hoverAmount,
            m_material.hoverLight && pointerLiquid && (shape.pointerEffects & 0x1)
                ? data->hover : 0.0f);
        passes.onscreen.shader->setUniform(passes.onscreen.hoverStrength,
                                           m_material.hoverLightStrength);
        // A configured reach is stored in logical pixels; the shader works in
        // capture-local device pixels. Zero keeps the adaptive default.
        passes.onscreen.shader->setUniform(
            passes.onscreen.hoverRadius,
            m_material.hoverLightRadius > 0.0f
                ? static_cast<float>(m_material.hoverLightRadius * scale) : 0.0f);
        passes.onscreen.shader->setUniform(
            passes.onscreen.parallaxStrength,
            m_material.pointerParallax && pointerLiquid
                    && (shape.pointerEffects & 0x2)
                ? 1.0f : 0.0f);
        // Click ripple: an expanding rim, evaluated from the shared clock. The
        // pulse is global; shapes it does not reach simply stay dark because
        // the falloff is zero far from the press point.
        QVector2D clickPosition(0.0f, 0.0f);
        float clickRadius = 0.0f;
        float clickAmount = 0.0f;
        if (m_material.clickLight && m_clickStart >= 0 && shape.effect == 0
            && (shape.pointerEffects & 0x4)) {
            const qint64 duration = std::max<int>(1, m_material.clickLightDuration);
            const qreal t = std::clamp<qreal>(
                qreal(m_hoverClock.elapsed() - m_clickStart) / duration, 0.0, 1.0);
            if (t < 1.0) {
                const qreal ease = 1.0 - std::pow(1.0 - t, 3.0);
                clickAmount = m_material.clickLightStrength
                    * static_cast<float>((1.0 - t) * (1.0 - t));
                clickRadius = static_cast<float>(
                    m_material.clickLightRadius * scale * ease);
                const QPointF clickDevice =
                    (m_clickScene - QPointF(capture.topLeft())) * scale;
                clickPosition = QVector2D(
                    static_cast<float>(clickDevice.x() - box.x()),
                    static_cast<float>(box.y() - clickDevice.y()));
            }
        }
        passes.onscreen.shader->setUniform(passes.onscreen.clickLocal, clickPosition);
        passes.onscreen.shader->setUniform(passes.onscreen.clickRadius, clickRadius);
        passes.onscreen.shader->setUniform(passes.onscreen.clickAmount, clickAmount);
        // The window's own fade multiplies the material too; it is squared like
        // the previous implementation so a closing window's glass does not
        // linger over its already faded content.
        const float modulation = static_cast<float>(shape.materialOpacity)
            * static_cast<float>(windowOpacity * windowOpacity) * glassFade;
        passes.onscreen.shader->setUniform(passes.onscreen.opacity, modulation);
        vbo->draw(GL_TRIANGLES, offsetIndex, vertexCountForShape);
        offsetIndex += vertexCountForShape;
    }

    glDisable(GL_BLEND);
    ShaderManager::instance()->popShader();
    vbo->unbindArrays();

    // Free chains no shape used this frame: a per-shape override that went
    // away should not keep its levels allocated.
    data->chains.erase(std::remove_if(data->chains.begin(), data->chains.end(),
                                      [](const BlurChain &chain) { return !chain.used; }),
                       data->chains.end());
}

#ifdef KOS_KWIN_PAINT_RESULT_API
bool GlassEffect::drawWindow(const RenderTarget &renderTarget, const RenderViewport &viewport,
                             EffectWindow *w, int mask, const Region &deviceRegion,
                             WindowPaintData &data)
#else
void GlassEffect::drawWindow(const RenderTarget &renderTarget, const RenderViewport &viewport,
                             EffectWindow *w, int mask, const Region &deviceRegion,
                             WindowPaintData &data)
#endif
{
    // Mime owns its complete frame, including transparent margins and any
    // client-drawn reveal: no material and no surface transform is applied.
    if (w && KOS::keepsClientAppearance(w->windowClass())) {
#ifdef KOS_KWIN_PAINT_RESULT_API
        return effects->drawWindow(renderTarget, viewport, w, mask, deviceRegion, data);
#else
        effects->drawWindow(renderTarget, viewport, w, mask, deviceRegion, data);
        return;
#endif
    }

    // KWin's transformed-window contract: a window painted through a scale or
    // translation, or while a fullscreen effect runs, only keeps its backdrop
    // if that effect asks for it via WindowForceBlurRole (Slide, Present
    // Windows and Maximize do). Everything else is skipped, exactly like the
    // previous implementation. The Dock animation deliberately does not set
    // the role: it fades the material through its own role instead.
    const bool transformed = data.xScale() != 1.0 || data.yScale() != 1.0
        || data.xTranslation() != 0.0 || data.yTranslation() != 0.0
        || (mask & PAINT_WINDOW_TRANSFORMED) != 0;
    const bool forced = w->data(WindowForceBlurRole).toBool();
    if (forced || (!effects->activeFullScreenEffect() && !transformed)) {
        render(renderTarget, viewport, w, deviceRegion, data);
    }

    // A reveal timeline scales the already-composited client surface as one
    // group around its bottom-center anchor, exactly like the glass quads that
    // shapesFor() produced this frame. Individual items are never touched.
    if (m_shapes && w->surface()) {
        if (const auto reveal = m_shapes->revealFor(w->surface())) {
            if (reveal->progress <= 0.0) {
                // Intentionally hidden content: draw neither surface nor glass.
#ifdef KOS_KWIN_PAINT_RESULT_API
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
#ifdef KOS_KWIN_PAINT_RESULT_API
            return effects->drawWindow(renderTarget, viewport, w,
                                       mask | PAINT_WINDOW_TRANSFORMED,
                                       deviceRegion, contentData);
#else
            effects->drawWindow(renderTarget, viewport, w,
                                mask | PAINT_WINDOW_TRANSFORMED,
                                deviceRegion, contentData);
#endif
        }
    }

#ifdef KOS_KWIN_PAINT_RESULT_API
    return effects->drawWindow(renderTarget, viewport, w, mask, deviceRegion, data);
#else
    effects->drawWindow(renderTarget, viewport, w, mask, deviceRegion, data);
#endif
}

} // namespace KWin
