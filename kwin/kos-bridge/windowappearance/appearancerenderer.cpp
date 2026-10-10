#include "appearancerenderer.h"

#include <core/region.h>
#include <core/renderviewport.h>
#include <opengl/glshader.h>
#include <opengl/glshadermanager.h>
#include <opengl/gltexture.h>

#include <QMatrix4x4>
#include <QPainterPath>
#include <QVector4D>

#include <epoxy/gl.h>

#include <algorithm>

namespace KOS::WindowAppearance
{

namespace
{

// The whole cache is dropped when it outgrows this. Shadows of maximized
// windows on hidpi screens are the large end (a few dozen megabytes each);
// the cache holds the distinct geometries of the windows on screen, and
// clearing all of it on overflow is the same bounded answer the button panel
// cache gives.
constexpr qsizetype MaxTextureCacheBytes = 192 * 1024 * 1024;

} // namespace

AppearanceRenderer::AppearanceRenderer() = default;

AppearanceRenderer::~AppearanceRenderer() = default;

void AppearanceRenderer::invalidateAll()
{
    m_textures.clear();
    m_textureBytes = 0;
}

void AppearanceRenderer::evict()
{
    // Drop the least recently used textures until the cache fits again.
    // Evicting at least one keeps a single oversized texture (a maximized
    // window's shadow on a hidpi screen) from looping forever.
    while (m_textureBytes > MaxTextureCacheBytes && !m_textures.empty()) {
        auto oldest = m_textures.begin();
        for (auto it = m_textures.begin(); it != m_textures.end(); ++it) {
            if (it->second.stamp < oldest->second.stamp) {
                oldest = it;
            }
        }
        m_textureBytes -= oldest->second.bytes;
        m_textures.erase(oldest);
    }
}

KWin::GLTexture *AppearanceRenderer::cachedTexture(
    const QString &key, const std::function<QImage()> &makeImage)
{
    if (const auto it = m_textures.find(key);
        it != m_textures.end()) {
        it->second.stamp = ++m_stamp;
        return it->second.texture.get();
    }

    const QImage image = makeImage();
    if (image.isNull()) {
        return nullptr;
    }

    const qsizetype bytes = image.sizeInBytes();
    auto texture = KWin::GLTexture::upload(image);
    if (!texture) {
        return nullptr;
    }
    // Sliced draws can sample just beyond an outer texel at a fractional-
    // scale edge. Repeating would pull pixels from the opposite side of the
    // image into the shadow.
    texture->setWrapMode(GL_CLAMP_TO_EDGE);
    // The shadow raster is built at a fraction of its device size and the
    // blit stretches it over the full rect; linear filtering is what makes
    // that upscale smooth instead of blocky.
    texture->setFilter(GL_LINEAR);
    m_textureBytes += bytes;
    evict();
    return m_textures
        .emplace(key,
                 CacheEntry{std::move(texture), bytes, ++m_stamp})
        .first->second.texture.get();
}

void AppearanceRenderer::blitShadow(const KWin::RenderViewport &viewport,
                                    const QRectF &textureRectLogical,
                                    const KWin::Region &clip,
                                    const QString &key,
                                    const std::function<QImage()> &makeShadow,
                                    qreal opacity)
{
    if (opacity <= 0.0) {
        return;
    }
    if (KWin::GLTexture *texture = cachedTexture(key, makeShadow)) {
        blit(viewport, clip, textureRectLogical, texture, opacity);
    }
}

void AppearanceRenderer::blitEdge(const KWin::RenderViewport &viewport,
                                  const QRectF &textureRectLogical,
                                  const KWin::Region &clip, const QString &key,
                                  const std::function<QImage()> &makeEdge,
                                  qreal opacity)
{
    if (opacity <= 0.0) {
        return;
    }
    if (KWin::GLTexture *texture = cachedTexture(key, makeEdge)) {
        blit(viewport, clip, textureRectLogical, texture, opacity);
    }
}

void AppearanceRenderer::blit(const KWin::RenderViewport &viewport,
                              const KWin::Region &clip,
                              const QRectF &logicalRect,
                              KWin::GLTexture *texture, qreal opacity)
{
    if (!texture || clip.isEmpty()) {
        return;
    }

    // The projection matrix takes scaled global coordinates, while damage
    // and visible regions are in viewport device coordinates. Keep both
    // origins so a visible piece can be positioned and sampled from the same
    // image.
    const qreal scale = viewport.scale();
    const QRectF deviceAbs(logicalRect.topLeft() * scale,
                           logicalRect.size() * scale);
    const QRectF textureDevice = viewport.mapToDeviceCoordinates(logicalRect);
    if (textureDevice.isEmpty()) {
        return;
    }
    const KWin::Rect textureBounds = textureDevice.toAlignedRect();
    const KWin::Region visiblePieces = clip & KWin::Region(textureBounds);
    if (visiblePieces.isEmpty()) {
        return;
    }

    auto *shaderManager = KWin::ShaderManager::instance();
    // Modulate scales every channel of the premultiplied texture by the same
    // factor, which is exactly a fade: the shadow is black with a graded
    // alpha (its rgb stays zero), and the edge fades to nothing without its
    // colours shifting. The transparent parts of the texture multiply to
    // zero on all channels and leave the framebuffer untouched.
    shaderManager->pushShader(KWin::ShaderTrait::MapTexture
                              | KWin::ShaderTrait::Modulate);
    KWin::GLShader *shader = shaderManager->getBoundShader();
    shader->setUniform(KWin::GLShader::IntUniform::TextureWidth,
                       texture->width());
    shader->setUniform(KWin::GLShader::IntUniform::TextureHeight,
                       texture->height());
    const int modulationLocation = shader->uniformLocation("modulation");
    if (modulationLocation >= 0) {
        shader->setUniform(modulationLocation,
                           QVector4D(opacity, opacity, opacity, opacity));
    }

    // These textures are premultiplied ARGB with transparent regions. Blend
    // them properly and restore the previous state afterwards.
    const GLboolean blendWasEnabled = glIsEnabled(GL_BLEND);
    GLint prevSrcRgb = 0;
    GLint prevDstRgb = 0;
    GLint prevSrcAlpha = 0;
    GLint prevDstAlpha = 0;
    glGetIntegerv(GL_BLEND_SRC_RGB, &prevSrcRgb);
    glGetIntegerv(GL_BLEND_DST_RGB, &prevDstRgb);
    glGetIntegerv(GL_BLEND_SRC_ALPHA, &prevSrcAlpha);
    glGetIntegerv(GL_BLEND_DST_ALPHA, &prevDstAlpha);

    glEnable(GL_BLEND);
    glBlendFuncSeparate(GL_ONE, GL_ONE_MINUS_SRC_ALPHA, GL_ONE,
                        GL_ONE_MINUS_SRC_ALPHA);

    // Each visible rectangle maps to the corresponding source slice of the
    // texture, so the hardware clip never has to see viewport coordinates.
    if (visiblePieces.contains(textureBounds)) {
        QMatrix4x4 mvp = viewport.projectionMatrix();
        mvp.translate(deviceAbs.x(), deviceAbs.y());
        shader->setUniform(KWin::GLShader::Mat4Uniform::ModelViewProjectionMatrix,
                           mvp);
        texture->render(deviceAbs.size());
    } else {
        const qreal sourceScaleX = texture->width() / textureDevice.width();
        const qreal sourceScaleY = texture->height() / textureDevice.height();
        for (const KWin::Rect &piece : visiblePieces.rects()) {
            const qreal dx = piece.x() - textureDevice.x();
            const qreal dy = piece.y() - textureDevice.y();
            const QRectF source(dx * sourceScaleX, dy * sourceScaleY,
                                piece.width() * sourceScaleX,
                                piece.height() * sourceScaleY);
            QMatrix4x4 mvp = viewport.projectionMatrix();
            mvp.translate(deviceAbs.x() + dx, deviceAbs.y() + dy);
            shader->setUniform(KWin::GLShader::Mat4Uniform::ModelViewProjectionMatrix,
                               mvp);
            texture->render(source, KWin::Region::infinite(), piece.size());
        }
    }

    glBlendFuncSeparate(prevSrcRgb, prevDstRgb, prevSrcAlpha, prevDstAlpha);
    if (!blendWasEnabled) {
        glDisable(GL_BLEND);
    }

    shaderManager->popShader();
}

} // namespace KOS::WindowAppearance
