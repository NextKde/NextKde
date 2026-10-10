#pragma once

// Legacy framebuffer overlay renderer. Not part of the active kos_bridge
// target; window appearance now uses native scene items (sceneshadow.cpp).

#include <QHash>
#include <QImage>
#include <QRectF>
#include <map>
#include <memory>
#include <functional>

#include "appearanceshadow.h"

namespace KWin
{
class GLTexture;
class RenderViewport;
class Region;
}

namespace KOS::WindowAppearance
{

// Uploads the generated images as GL textures and blits them onto the frame.
// The blit is the one ButtonRenderer uses (premultiplied ARGB over an
// explicitly restored blend state, per-rectangle source slices for the
// occlusion-culled pieces), with one addition: the opacity the dynamic
// shadow tiers need is applied through the Modulate shader variant, which
// scales a premultiplied texture's colour and alpha together -- exactly a
// fade -- without rebuilding textures for every tier and transition step.
class AppearanceRenderer
{
public:
    AppearanceRenderer();
    // Defined in the .cpp: the texture cache owns GLTextures by pointer, and
    // a defaulted destructor here would need the complete type.
    ~AppearanceRenderer();

    AppearanceRenderer(const AppearanceRenderer &) = delete;
    AppearanceRenderer &operator=(const AppearanceRenderer &) = delete;

    // Drops every cached texture. Called when the configuration changes, so
    // a stale contour is never served from the cache.
    void invalidateAll();

    // The shadow texture for one window geometry, drawn with `opacity` on
    // top of everything painted so far (which is everything stacked below
    // the window -- the shadow is drawn before the window's own pixels).
    // `clip` is the part of the expanded rect that is actually visible on
    // screen; `textureRect` is the window rect grown by the shadow margin,
    // in global logical coordinates. `key` identifies the exact appearance
    // the image was built from (geometry, contour, scale); two windows that
    // produce the same key share one texture.
    void blitShadow(const KWin::RenderViewport &viewport,
                    const QRectF &textureRectLogical,
                    const KWin::Region &clip, const QString &key,
                    const std::function<QImage()> &makeShadow, qreal opacity);
    void blitEdge(const KWin::RenderViewport &viewport,
                  const QRectF &textureRectLogical, const KWin::Region &clip,
                  const QString &key,
                  const std::function<QImage()> &makeEdge, qreal opacity);

private:
    void blit(const KWin::RenderViewport &viewport, const KWin::Region &clip,
              const QRectF &logicalRect, KWin::GLTexture *texture,
              qreal opacity);

    KWin::GLTexture *cachedTexture(const QString &key,
                                  const std::function<QImage()> &makeImage);
    void evict();

    struct CacheEntry
    {
        std::unique_ptr<KWin::GLTexture> texture;
        qsizetype bytes = 0;
        // Increased on every cache hit; the smallest stamp is evicted first.
        // A full clear on overflow would drop every window's shadow at once
        // and rebuild them all in one frame -- a visible stall where nothing
        // but one cold texture was needed.
        quint64 stamp = 0;
    };

    std::map<QString, CacheEntry> m_textures;
    qsizetype m_textureBytes = 0;
    quint64 m_stamp = 0;
};

} // namespace KOS::WindowAppearance
