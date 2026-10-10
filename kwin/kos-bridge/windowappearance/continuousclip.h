#pragma once

#include "appearanceconfig.h"
#include "sharedwindowsource.h"
#include <effect/offscreeneffect.h>
#include <QHash>
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

// One source texture includes client content, decoration and KOS buttons.
// Both normal painting and Dock morphs consume it; damage invalidates it.
// Arc mode continues to use native scene rounding without redirection.
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
    void invalidateRegion(const QRectF &region);
    using SourcePainter = std::function<void(const KWin::RenderTarget &, const KWin::RenderViewport &)>;
    bool paint(const KWin::RenderTarget &target,
               const KWin::RenderViewport &viewport,
               KWin::EffectWindow *window, int mask,
               const KWin::Region &region, KWin::WindowPaintData &data,
               const ContinuousStyle &style, const SourcePainter &sourcePainter,
               const WindowSourceMorph &morph = {});
private:
    void release(KWin::EffectWindow *window);
    struct Rejection { QSizeF frameSize; qreal scale; };
    struct Reservation {
        qsizetype bytes = 0;
        QMetaObject::Connection visibilityConnection;
        QMetaObject::Connection damageConnection;
        std::shared_ptr<KWin::GLTexture> texture;
        std::shared_ptr<KWin::GLFramebuffer> fbo;
        std::shared_ptr<KWin::ItemEffect> effect;
        bool dirty = true;
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
    } m_uniforms;
    std::unique_ptr<KWin::GLShader> m_shader;
    QHash<KWin::EffectWindow *, Reservation> m_reservations;
    QHash<KWin::EffectWindow *, Rejection> m_rejected;
    qsizetype m_reservedBytes = 0;
    bool m_attempted = false;
    bool m_budgetWarning = false;
    int m_maxTextureSize = 0;
};

} // namespace KOS::WindowAppearance
