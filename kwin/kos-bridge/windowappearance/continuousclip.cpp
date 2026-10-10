/*
 * Shared source rendering follows KWin OffscreenEffect's color/geometry pipeline.
 * SPDX-FileCopyrightText: 2021 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#include "continuousclip.h"

#include <core/output.h>
#include <core/pixelgrid.h>
#include <scene/itemgeometry.h>
#include <core/rendertarget.h>
#include <opengl/glframebuffer.h>
#include <opengl/gltexture.h>
#include <opengl/glvertexbuffer.h>
#include <scene/item.h>
#include <core/renderviewport.h>
#include <effect/effecthandler.h>
#include <effect/effectwindow.h>
#include <opengl/glshader.h>
#include <opengl/glshadermanager.h>
#include <scene/windowitem.h>
#include <QDebug>
#include <QFile>
#include <QPointer>
#include <algorithm>
#include <cmath>

namespace KOS::WindowAppearance
{
namespace
{
// 256 MiB of additional RGBA8 window textures. Admission is reconsidered
// after resize/output changes; when exceeded the manager uses native arcs.
constexpr qsizetype TextureBudget = 256 * 1024 * 1024;

// KWin 6.6 generates these stages in ShaderManager instead of providing the
// base.vert/base.frag resources. Keep its MapTexture/Modulate/Saturation/
// TransformColorspace pipeline and let KWin preprocess its own GLSL helpers.
constexpr auto LegacyVertex = R"(#version 140
in vec4 position;
in vec4 texcoord;
out vec2 texcoord0;
uniform mat4 modelViewProjectionMatrix;
void main()
{
    texcoord0 = texcoord.st;
    gl_Position = modelViewProjectionMatrix * position;
}
)";
constexpr auto LegacyFragment = R"(#version 140
uniform sampler2D sampler;
in vec2 texcoord0;
uniform vec4 modulation;
#include "saturation.glsl"
#include "colormanagement.glsl"
out vec4 fragColor;
void main(void)
{
    vec4 result;
    result = texture(sampler, texcoord0);
    result = sourceEncodingToNitsInDestinationColorspace(result);
    result = adjustSaturation(result);
    result *= modulation;
    result = nitsToDestinationEncoding(result);
    fragColor = result;
}
)";

constexpr auto ContourFragment = R"(
in vec2 kosPosition;
uniform vec4 kosSourceRect; // source bounds in output-device pixels
uniform vec2 kosSize;
uniform float kosRadius;
uniform float kosExponent;
uniform float kosStroke;
uniform float kosFrameWidth;
uniform vec4 kosEdgeColor;
uniform vec4 kosFrameColor;
uniform float kosEdgeOpacity;
uniform float kosShadowOpacity;
uniform vec4 kosShadow; // contact sigma, ambient sigma, their opacities

float kosDistance(vec2 p)
{
    vec2 q = abs(p - kosSize * 0.5) - (kosSize * 0.5 - vec2(kosRadius));
    if (kosRadius <= 0.0 || min(q.x, q.y) <= 0.0) {
        return max(q.x, q.y) - kosRadius;
    }
    vec2 v = max(q / kosRadius, vec2(0.0));
    float norm = pow(pow(v.x, kosExponent) + pow(v.y, kosExponent), 1.0 / kosExponent);
    vec2 gradient = pow(v / max(norm, 0.0001), vec2(kosExponent - 1.0));
    // Normalize by the gradient: the inner stroke has a constant normal
    // width at the diagonal as well as on straight edges.
    return kosRadius * (norm - 1.0) / max(length(gradient), 0.0001);
}

vec4 kosComposite(vec4 source)
{
    float distance = kosDistance(kosPosition);
    float aa = max(fwidth(distance), 0.0001);
    // Most fragments are ordinary opaque content. Avoid shadow exponentials
    // and layer blending away from the narrow perimeter.
    if (distance < -(kosStroke + aa)) {
        return source;
    }
    float inside = 1.0 - clamp(0.5 + distance / aa, 0.0, 1.0);
    float inner = 1.0 - clamp(0.5 + (distance + kosStroke) / aa, 0.0, 1.0);
    float outer = 1.0 - clamp(0.5 + (distance - kosFrameWidth) / aa, 0.0, 1.0);

    // Composite the hairline in unmasked content, then apply the outside
    // coverage once. This avoids a double AA mask/dark seam at the corner.
    float edgeAlpha = kosEdgeColor.a * kosEdgeOpacity
        * clamp((inside - inner) / max(inside, 0.0001), 0.0, 1.0);
    vec4 content = (vec4(kosEdgeColor.rgb * edgeAlpha, edgeAlpha)
        + source * (1.0 - edgeAlpha)) * inside;
    float frameAlpha = kosFrameColor.a * kosEdgeOpacity * max(0.0, outer - inside);
    vec4 frame = vec4(kosFrameColor.rgb * frameAlpha, frameAlpha);

    float d = max(0.0, distance - kosFrameWidth);
    float contact = kosShadow.z * exp(-0.5 * d * d / (kosShadow.x * kosShadow.x));
    float ambient = kosShadow.w * exp(-0.5 * d * d / (kosShadow.y * kosShadow.y));
    float shadow = (1.0 - (1.0 - contact) * (1.0 - ambient))
        * kosShadowOpacity * (1.0 - outer);
    return content + frame + vec4(0.0, 0.0, 0.0, shadow);
}
)";
}

ContinuousClip::ContinuousClip()
{

}

ContinuousClip::~ContinuousClip()
{
    clear();
    if (m_shader) {
        KWin::effects->makeOpenGLContextCurrent();
        m_shader.reset();
    }
}

bool ContinuousClip::availableFor(KWin::EffectWindow *window)
{
    if (!window || !window->screen() || !available()) {
        return false;
    }
    const auto rejected = m_rejected.constFind(window);
    // A failed admission must not alternate sharp/arc properties on every
    // frame. Retry only after geometry, scale, configuration or budget changes.
    return rejected == m_rejected.cend()
        || rejected->frameSize != window->frameGeometry().size()
        || rejected->scale != window->screen()->scale();
}

void ContinuousClip::clear()
{
    const auto windows = m_reservations.keys();
    for (auto *window : windows) {
        release(window);
    }
    m_rejected.clear();
}

bool ContinuousClip::available()
{
    if (m_attempted) {
        return bool(m_shader);
    }
    m_attempted = true;
    if (!KWin::OffscreenEffect::supported()) {
        return false;
    }
    KWin::effects->makeOpenGLContextCurrent();
    glGetIntegerv(GL_MAX_TEXTURE_SIZE, &m_maxTextureSize);
    QFile vertexFile(QStringLiteral(":/opengl/base.vert"));
    QFile fragmentFile(QStringLiteral(":/opengl/base.frag"));
    QByteArray vertex;
    QByteArray fragment;
    if (vertexFile.open(QIODevice::ReadOnly) && fragmentFile.open(QIODevice::ReadOnly)) {
        vertex = vertexFile.readAll();
        fragment = fragmentFile.readAll();
    } else {
        vertex = LegacyVertex;
        fragment = LegacyFragment;
    }
    fragment.replace("#version 140", "#version 140\n#if GL_OES_standard_derivatives\n#extension GL_OES_standard_derivatives : enable\n#endif");
    // Preserve KWin's transfer functions, colorimetry, HDR, saturation and
    // modulation. Add the contour before its existing color pipeline.
    const QByteArray vertexMain("void main()\n{");
    const QByteArray fragmentMain("void main(void)\n{");
    const QByteArray sampling("result = texture(sampler, texcoord0);");
    if (!vertex.contains(vertexMain) || !fragment.contains(fragmentMain)
        || !fragment.contains(sampling)) {
        qWarning() << "KOS continuous corners: unsupported KWin shader layout; using native arcs";
        return false;
    }
    vertex.replace(vertexMain, "out vec2 kosPosition;\nuniform vec4 kosSourceRect;\nvoid main()\n{\n    kosPosition = kosSourceRect.xy + vec2(texcoord.x, 1.0 - texcoord.y) * kosSourceRect.zw;");
    fragment.replace(fragmentMain, QByteArray(ContourFragment) + fragmentMain);
    fragment.replace(sampling, "result = kosComposite(texture(sampler, texcoord0));");
    m_shader = KWin::ShaderManager::instance()->generateCustomShader(
        KWin::ShaderTrait::MapTexture | KWin::ShaderTrait::Modulate
        | KWin::ShaderTrait::AdjustSaturation | KWin::ShaderTrait::TransformColorspace,
        vertex, fragment);
    if (!m_shader || !m_shader->link()) {
        qWarning() << "KOS continuous corners: shader failed; using native arcs";
        m_shader.reset();
        return false;
    }
    m_uniforms.sourceRect = m_shader->uniformLocation("kosSourceRect");
    m_uniforms.size = m_shader->uniformLocation("kosSize");
    m_uniforms.radius = m_shader->uniformLocation("kosRadius");
    m_uniforms.exponent = m_shader->uniformLocation("kosExponent");
    m_uniforms.stroke = m_shader->uniformLocation("kosStroke");
    m_uniforms.frameWidth = m_shader->uniformLocation("kosFrameWidth");
    m_uniforms.edgeColor = m_shader->uniformLocation("kosEdgeColor");
    m_uniforms.frameColor = m_shader->uniformLocation("kosFrameColor");
    m_uniforms.edgeOpacity = m_shader->uniformLocation("kosEdgeOpacity");
    m_uniforms.shadowOpacity = m_shader->uniformLocation("kosShadowOpacity");
    m_uniforms.shadow = m_shader->uniformLocation("kosShadow");
    return true;
}

bool ContinuousClip::configure(KWin::EffectWindow *window,
                              const std::optional<ContinuousStyle> &style)
{
    if (!window || !style || !availableFor(window)) {
        release(window);
        return false;
    }
    const qreal scale = window->screen()->scale();
    const QSizeF size = window->expandedGeometry().size();
    // Pixel snapping of both edges can add two texels to either dimension.
    const qreal width = std::ceil(size.width() * scale) + 2;
    const qreal height = std::ceil(size.height() * scale) + 2;
    const qreal estimated = width * height * 4;
    const qsizetype previous = m_reservations.value(window).bytes;
    if (!std::isfinite(estimated) || estimated <= 0
        || width > m_maxTextureSize || height > m_maxTextureSize
        || estimated > TextureBudget - (m_reservedBytes - previous)) {
        release(window);
        m_rejected.insert(window, Rejection{window->frameGeometry().size(), scale});
        if (!m_budgetWarning) {
            qWarning() << "KOS continuous corners: GPU texture size or 256 MiB budget limit reached; using native arcs for excess windows";
            m_budgetWarning = true;
        }
        return false;
    }
    const qsizetype bytes = qsizetype(estimated);
    if (bytes < previous) {
        m_rejected.clear();
    }
    m_reservedBytes += bytes - previous;
    auto &reservation = m_reservations[window];
    reservation.bytes = bytes;
    if (!reservation.visibilityConnection && window->windowItem()) {
        const QPointer<KWin::EffectWindow> guarded(window);
        reservation.visibilityConnection = connect(window->windowItem(),
            &KWin::Item::visibleChanged, this, [this, guarded] {
                // EffectWindow::isVisible ignores animation visibility refs.
                // Wait until all signal handlers have installed those refs,
                // then check the actual scene item. Do not release a source
                // that is still being used by minimize/desktop animations.
                if (guarded && guarded->windowItem()
                    && !guarded->windowItem()->isVisible()) {
                    release(guarded.data());
                }
            }, Qt::QueuedConnection);
    }
    m_rejected.remove(window);
    if (!reservation.damageConnection) {
        reservation.damageConnection = connect(window, &KWin::EffectWindow::windowDamaged,
            this, [this, window] { invalidate(window); });
        reservation.effect = std::make_shared<KWin::ItemEffect>(window->windowItem());
    }
    return true;
}

void ContinuousClip::forget(KWin::EffectWindow *window)
{
    release(window);
    m_rejected.remove(window);
}

void ContinuousClip::release(KWin::EffectWindow *window)
{
    const Reservation released = m_reservations.take(window);
    KWin::effects->makeOpenGLContextCurrent();
    disconnect(released.visibilityConnection);
    disconnect(released.damageConnection);
    m_reservedBytes -= released.bytes;
    if (released.bytes > 0) {
        m_rejected.clear();
    }

}

void ContinuousClip::invalidate(KWin::EffectWindow *window)
{
    auto it = m_reservations.find(window);
    if (it != m_reservations.end()) it->dirty = true;
}

void ContinuousClip::invalidateAll()
{
    for (auto &cache : m_reservations) cache.dirty = true;
}

void ContinuousClip::invalidateRegion(const QRectF &region)
{
    for (auto it = m_reservations.begin(); it != m_reservations.end(); ++it) {
        if (QRectF(it.key()->frameGeometry()).intersects(region)) it->dirty = true;
    }
}

bool ContinuousClip::paint(const KWin::RenderTarget &target,
    const KWin::RenderViewport &viewport, KWin::EffectWindow *window, int mask,
    const KWin::Region &region, KWin::WindowPaintData &data,
    const ContinuousStyle &style, const SourcePainter &sourcePainter,
    const WindowSourceMorph &morph)
{
    auto it = m_reservations.find(window);
    if (it == m_reservations.end() || !m_shader) {
        return false;
    }
    auto &cache = it.value();
    const qreal sourceScale = window->screen()->scale();
    const auto reject = [this, window, sourceScale] {
        release(window);
        m_rejected.insert(window, Rejection{window->frameGeometry().size(), sourceScale});
        return false;
    };
    const KWin::RectF sourceGeometry = KWin::snapToPixels(window->expandedGeometry(), sourceScale);
    const QPointF relativeOrigin = sourceGeometry.topLeft() - window->frameGeometry().topLeft();
    if (cache.sourceScale != sourceScale || cache.sourceOrigin != relativeOrigin
        || cache.frameSize != window->frameGeometry().size()) {
        cache.dirty = true;
        cache.sourceScale = sourceScale;
        cache.sourceOrigin = relativeOrigin;
        cache.frameSize = window->frameGeometry().size();
    }
    const QSize textureSize = (sourceGeometry.size() * sourceScale).toSize();
    if (textureSize.isEmpty()) {
        return reject();
    }
    KWin::effects->makeOpenGLContextCurrent();
    if (!cache.texture || cache.texture->size() != textureSize) {
        auto texture = KWin::GLTexture::allocate(GL_RGBA8, textureSize);
        if (!texture) {
            return reject();
        }
        texture->setFilter(GL_LINEAR);
        texture->setWrapMode(GL_CLAMP_TO_EDGE);
        cache.fbo.reset();
        cache.texture = std::move(texture);
        cache.fbo = std::make_shared<KWin::GLFramebuffer>(cache.texture.get());
        if (!cache.fbo->valid()) {
            return reject();
        }
        cache.dirty = true;
    }
    if (cache.dirty) {
        // Clear before the callback: invalidations raised while sampling the
        // title bar remain pending for the next frame.
        cache.dirty = false;
        KWin::RenderTarget sourceTarget(cache.fbo.get());
        KWin::RenderViewport sourceViewport(sourceGeometry, sourceScale, sourceTarget, QPoint());
        KWin::GLFramebuffer::pushFramebuffer(cache.fbo.get());
        glClearColor(0, 0, 0, 0);
        glClear(GL_COLOR_BUFFER_BIT);
        sourcePainter(sourceTarget, sourceViewport);
        KWin::GLFramebuffer::popFramebuffer();
    }

    const qreal scale = viewport.scale();
    const auto expanded = KWin::snapToPixels(window->expandedGeometry(), scale);
    const auto frame = KWin::snapToPixels(window->frameGeometry(), scale);
    const QRectF bounds(expanded.topLeft() - frame.topLeft(), expanded.size());
    KWin::WindowQuad quad;
    quad[0] = KWin::WindowVertex(bounds.topLeft(), QPointF(0, 0));
    quad[1] = KWin::WindowVertex(bounds.topRight(), QPointF(1, 0));
    quad[2] = KWin::WindowVertex(bounds.bottomRight(), QPointF(1, 1));
    quad[3] = KWin::WindowVertex(bounds.bottomLeft(), QPointF(0, 1));
    KWin::WindowQuadList quads;
    quads.append(quad);
    KWin::WindowPaintData paintedData = data;
    if (morph) {
        morph(paintedData, quads);
    }
    {
        KWin::ShaderBinder binder(m_shader.get());
        m_shader->setUniform(m_uniforms.sourceRect, QVector4D(bounds.x() * scale,
            bounds.y() * scale, bounds.width() * scale, bounds.height() * scale));
        m_shader->setUniform(m_uniforms.size, QVector2D(style.size.width() * scale, style.size.height() * scale));
        m_shader->setUniform(m_uniforms.radius, style.radius * scale);
        m_shader->setUniform(m_uniforms.exponent, curveExponent(style.smoothness));
        m_shader->setUniform(m_uniforms.stroke, style.stroke * scale);
        m_shader->setUniform(m_uniforms.frameWidth, style.frameWidth * scale);
        m_shader->setUniform(m_uniforms.edgeColor, style.outline.colorFor(style.dark));
        m_shader->setUniform(m_uniforms.frameColor, style.fill.colorFor(style.dark));
        m_shader->setUniform(m_uniforms.edgeOpacity, style.edgeOpacity);
        m_shader->setUniform(m_uniforms.shadowOpacity, style.shadowOpacity);
        const qreal ambient = style.active ? style.shadow.activeBlur : style.shadow.inactiveBlur;
        m_shader->setUniform(m_uniforms.shadow, QVector4D(style.shadow.contactBlur * scale,
            ambient * scale, style.shadow.contactOpacity, style.shadow.ambientOpacity));
    }
    Q_UNUSED(mask)
    // UVs survive the mesh deformation. Compute the continuous contour in
    // source coordinates, then deform its coverage together with the buttons.
    KWin::ShaderBinder binder(m_shader.get());
    auto *vbo = KWin::GLVertexBuffer::streamingBuffer();
    vbo->reset();
    vbo->setAttribLayout(std::span(KWin::GLVertexBuffer::GLVertex2DLayout), sizeof(KWin::GLVertex2D));
    KWin::RenderGeometry geometry;
    geometry.setVertexSnappingMode(KWin::RenderGeometry::VertexSnappingMode::None);
    for (const auto &q : quads) {
        geometry.appendWindowQuad(q, scale);
    }
    geometry.postProcessTextureCoordinates(cache.texture->matrix(KWin::NormalizedCoordinates));
    const auto mapped = vbo->map<KWin::GLVertex2D>(geometry.size());
    if (!mapped) {
        return false;
    }
    geometry.copy(*mapped);
    vbo->unmap();
    vbo->bindArrays();
    QMatrix4x4 mvp = viewport.projectionMatrix();
    mvp.translate(std::round(window->x() * scale), std::round(window->y() * scale));
    m_shader->setUniform(KWin::GLShader::Mat4Uniform::ModelViewProjectionMatrix, mvp * paintedData.toMatrix(scale));
    const qreal rgb = paintedData.brightness() * paintedData.opacity();
    m_shader->setUniform(KWin::GLShader::Vec4Uniform::ModulationConstant,
        QVector4D(rgb, rgb, rgb, paintedData.opacity()));
    m_shader->setUniform(KWin::GLShader::FloatUniform::Saturation, paintedData.saturation());
    const auto xyz = target.colorDescription()->containerColorimetry().toXYZ();
    m_shader->setUniform(KWin::GLShader::Vec3Uniform::PrimaryBrightness,
        QVector3D(xyz(1, 0), xyz(1, 1), xyz(1, 2)));
    m_shader->setUniform(KWin::GLShader::IntUniform::TextureWidth, cache.texture->width());
    m_shader->setUniform(KWin::GLShader::IntUniform::TextureHeight, cache.texture->height());
    m_shader->setColorspaceUniforms(KWin::ColorDescription::sRGB,
        target.colorDescription(), KWin::RenderingIntent::Perceptual);
    const bool clipping = region != KWin::Region::infinite();
    const auto clip = clipping ? viewport.transform().map(region, target.transformedSize()) : KWin::Region::infinite();
    if (clipping) glEnable(GL_SCISSOR_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    cache.texture->bind();
    vbo->draw(clip, GL_TRIANGLES, 0, geometry.count(), clipping);
    cache.texture->unbind();
    glDisable(GL_BLEND);
    if (clipping) glDisable(GL_SCISSOR_TEST);
    vbo->unbindArrays();
    // The morph is local to this completed draw. WindowPaintData is copy
    // constructible but not assignable; callers need no mutated copy back.
    return true;
}

} // namespace KOS::WindowAppearance
