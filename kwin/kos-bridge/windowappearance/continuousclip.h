#pragma once

#include "appearanceconfig.h"
#include "cornermask.h"
#include "sharedwindowsource.h"
#include <core/region.h>
#include <effect/offscreeneffect.h>
#include <QHash>
#include <QMatrix4x4>
#include <QMetaObject>
#include <optional>

namespace KWin { class GLTexture; class GLFramebuffer; class ItemEffect; }

namespace KOS::WindowAppearance
{

struct ContinuousStyle
{
    QSizeF size;
    qreal radius = 0; // tangent extent, after size clamp
    qreal smoothness = 0;
    qreal stroke = 0;
    qreal frameWidth = 0;
    bool dark = false;
    bool active = false;
    qreal edgeOpacity = 0;
    qreal shadowOpacity = 0;
    OutlineSettings outline;
    FillSettings fill;
    ShadowSettings shadow;
};

// One source texture includes client content and decoration. Animated (morph)
// captures also bake the KOS buttons in because the deformation moves them
// with the window; stationary frames paint the panel as an overlay instead,
// so panel/tint changes never dirty this texture. Client damage is refreshed
// per damaged region: drawWindow's device region is mapped back into source
// texture coordinates and only that area is cleared and repainted. Areas the
// compositor never drew (occluded or off screen) stay marked uncaptured and
// are filled in when they become visible again. Arc mode continues to use
// native scene rounding without redirection.
class ContinuousClip : public KWin::Effect
{
public:
    ContinuousClip();
    ~ContinuousClip() override;
    bool available();
    bool availableFor(KWin::EffectWindow *window);
    void clear();
    bool configure(KWin::EffectWindow *window,
                   const std::optional<ContinuousStyle> &style);
    void forget(KWin::EffectWindow *window);
    void invalidate(KWin::EffectWindow *window);
    void invalidateAll();
    using SourcePainter = std::function<bool(const KWin::RenderTarget &,
        const KWin::RenderViewport &, const KWin::Region &sourceRegion)>;
    bool paint(const KWin::RenderTarget &target,
               const KWin::RenderViewport &viewport,
               KWin::EffectWindow *window, int mask,
               const KWin::Region &region, KWin::WindowPaintData &data,
               const ContinuousStyle &style, const SourcePainter &sourcePainter,
               const WindowSourceMorph &morph = {});
private:
    void release(KWin::EffectWindow *window);
    void invalidateDamage(KWin::EffectWindow *window);
    struct Rejection { QSizeF frameSize; qreal scale; };
    struct Reservation {
        qsizetype bytes = 0;
        QMetaObject::Connection visibilityConnection;
        QMetaObject::Connection damageConnection;
        std::shared_ptr<KWin::GLTexture> texture;
        std::shared_ptr<KWin::GLFramebuffer> fbo;
        std::shared_ptr<KWin::ItemEffect> effect;
        // The whole texture must be repainted (new texture, geometry change,
        // invalidation raised by the effect itself).
        bool fullDirty = true;
        // Client damage was reported, but the compositor has not yet drawn
        // every affected area (occluded/off-screen parts wait for a draw).
        bool damaged = false;
        // Source-device areas refreshed since `damaged` was raised. A draw
        // outside this union has never been captured since the damage and is
        // therefore repainted when it becomes visible.
        KWin::Region captured;
        // Bumped by every invalidation. A draw that raced with one must not
        // record its (possibly stale) capture as covering the new damage.
        quint64 epoch = 0;
        qreal sourceScale = 0;
        QPointF sourceOrigin;
        QSizeF frameSize;
    };
    struct UniformLocations {
        int sourceRect = -1;
        int size = -1;
        int radius = -1;
        int exponent = -1;
        int stroke = -1;
        int frameWidth = -1;
        int edgeColor = -1;
        int frameColor = -1;
        int edgeOpacity = -1;
        int shadowOpacity = -1;
        int shadow = -1;
        int shadowOffset = -1;
    } m_uniforms;
    // The style-only 9-slice mask. All entries describe the same contour math
    // as the shader above, evaluated once on the CPU and shared by every
    // window that uses the same style.
    struct MaskKey {
        qreal radius = 0;
        qreal exponent = 0;
        qreal stroke = 0;
        qreal frameWidth = 0;
        qreal contactSigma = 0;
        qreal ambientSigma = 0;
        qreal contactOpacity = 0;
        qreal ambientOpacity = 0;
        qreal extent = 0;
        qreal padding = 0;
        qreal offsetY = 0;
        bool operator==(const MaskKey &other) const
        {
            return qFuzzyCompare(radius + 1, other.radius + 1)
                && qFuzzyCompare(exponent + 1, other.exponent + 1)
                && qFuzzyCompare(stroke + 1, other.stroke + 1)
                && qFuzzyCompare(frameWidth + 1, other.frameWidth + 1)
                && qFuzzyCompare(contactSigma + 1, other.contactSigma + 1)
                && qFuzzyCompare(ambientSigma + 1, other.ambientSigma + 1)
                && qFuzzyCompare(contactOpacity + 1, other.contactOpacity + 1)
                && qFuzzyCompare(ambientOpacity + 1, other.ambientOpacity + 1)
                && qFuzzyCompare(extent + 1, other.extent + 1)
                && qFuzzyCompare(padding + 1, other.padding + 1)
                && qFuzzyCompare(offsetY + 1, other.offsetY + 1);
        }
        friend size_t qHash(const MaskKey &key, size_t seed)
        {
            const qreal values[] = {key.radius, key.exponent, key.stroke,
                key.frameWidth, key.contactSigma, key.ambientSigma,
                key.contactOpacity, key.ambientOpacity, key.extent, key.padding,
                key.offsetY};
            for (qreal value : values) {
                seed = ::qHash(qRound64(value * 64.0), seed);
            }
            return seed;
        }
    };
    struct MaskAsset {
        std::shared_ptr<KWin::GLTexture> texture;
        CornerMaskAtlas atlas;
        QMatrix4x4 textureMatrix;
    };
    std::shared_ptr<MaskAsset> maskFor(const ContinuousStyle &style,
                                       qreal sourceScale, qreal padding);
    struct MaskUniformLocations {
        int maskMatrix = -1;
        int edgeColor = -1;
        int frameColor = -1;
        int edgeOpacity = -1;
        int shadowOpacity = -1;
        int sampler = -1;
    } m_maskUniforms;
    std::unique_ptr<KWin::GLShader> m_maskShader;
    QHash<MaskKey, std::shared_ptr<MaskAsset>> m_masks;
    std::unique_ptr<KWin::GLShader> m_shader;
    QHash<KWin::EffectWindow *, Reservation> m_reservations;
    QHash<KWin::EffectWindow *, Rejection> m_rejected;
    qsizetype m_reservedBytes = 0;
    bool m_attempted = false;
    bool m_budgetWarning = false;
    int m_maxTextureSize = 0;
};

} // namespace KOS::WindowAppearance
