/*
 * Shared source rendering follows KWin OffscreenEffect's color/geometry pipeline.
 * SPDX-FileCopyrightText: 2021 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#include "continuousclip.h"
#include "contour.h"
#ifdef KOS_KWIN_PAINT_RESULT_API
#include <opengl/eglcontext.h>
#endif

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
uniform float kosShadowOffset; // downward shift of the cast shadow, device px

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

    // The shadow contour is the frame translated down. `outer` stays on the
    // frame so the part of the shift that falls inside the window is clipped.
    float shadowDistance = kosDistance(kosPosition - vec2(0.0, kosShadowOffset));
    float d = max(0.0, shadowDistance - kosFrameWidth);
    float contact = kosShadow.z * exp(-0.5 * d * d / (kosShadow.x * kosShadow.x));
    float ambient = kosShadow.w * exp(-0.5 * d * d / (kosShadow.y * kosShadow.y));
    float shadow = (1.0 - (1.0 - contact) * (1.0 - ambient))
        * kosShadowOpacity * (1.0 - outer);
    return content + frame + vec4(0.0, 0.0, 0.0, shadow);
}
)";

// Baked path. The 9-slice atlas already contains the shape, outline, frame
// and shadow coverage; only the (animated) colours and opacities are
// uniforms. Every fragment is two texture fetches and a few multiply-adds.
constexpr auto MaskFragment = R"(
in vec2 kosMaskCoord;
uniform sampler2D kosMaskSampler;
uniform vec4 kosEdgeColor;
uniform vec4 kosFrameColor;
uniform float kosEdgeOpacity;
uniform float kosShadowOpacity;

vec4 kosMaskComposite(vec4 source)
{
    vec4 mask = texture(kosMaskSampler, kosMaskCoord);
    float edge = kosEdgeColor.a * kosEdgeOpacity * mask.g;
    vec4 result = source * mask.r - source * edge
        + vec4(kosEdgeColor.rgb, 1.0) * edge;
    float frame = kosFrameColor.a * kosEdgeOpacity * mask.b;
    result.rgb += kosFrameColor.rgb * frame;
    result.a += frame;
    result.a += kosShadowOpacity * mask.a;
    return result;
}
)";
}

ContinuousClip::ContinuousClip()
{

}

ContinuousClip::~ContinuousClip()
{
    clear();
    if (m_shader || m_maskShader || !m_masks.isEmpty()) {
        KWin::effects->makeOpenGLContextCurrent();
        m_masks.clear();
        m_shader.reset();
        m_maskShader.reset();
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
    // fwidth is core in GLSL 1.40 / GLES 3.00; KWin generates the shader header.
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
    // The mask variant must start from the untouched sources: the analytic
    // edits below re-declare uniforms that the mask fragment would duplicate.
    const QByteArray baseVertex = vertex;
    const QByteArray baseFragment = fragment;
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
    m_uniforms.shadowOffset = m_shader->uniformLocation("kosShadowOffset");

    // Same KWin pipeline, but the contour comes from the baked 9-slice mask.
    // If this variant fails to build, the analytic shader above stays in use.
    QByteArray maskVertex = baseVertex;
    QByteArray maskFragment = baseFragment;
    maskVertex.replace(vertexMain, "out vec2 kosMaskCoord;\nuniform mat4 kosMaskMatrix;\nvoid main()\n{\n    kosMaskCoord = (kosMaskMatrix * vec4(position.xy, 0.0, 1.0)).xy;");
    maskFragment.replace(fragmentMain, QByteArray(MaskFragment) + fragmentMain);
    maskFragment.replace(sampling, "result = kosMaskComposite(texture(sampler, texcoord0));");
    m_maskShader = KWin::ShaderManager::instance()->generateCustomShader(
        KWin::ShaderTrait::MapTexture | KWin::ShaderTrait::Modulate
        | KWin::ShaderTrait::AdjustSaturation | KWin::ShaderTrait::TransformColorspace,
        maskVertex, maskFragment);
    if (m_maskShader && m_maskShader->link()) {
        m_maskUniforms.maskMatrix = m_maskShader->uniformLocation("kosMaskMatrix");
        m_maskUniforms.edgeColor = m_maskShader->uniformLocation("kosEdgeColor");
        m_maskUniforms.frameColor = m_maskShader->uniformLocation("kosFrameColor");
        m_maskUniforms.edgeOpacity = m_maskShader->uniformLocation("kosEdgeOpacity");
        m_maskUniforms.shadowOpacity = m_maskShader->uniformLocation("kosShadowOpacity");
        m_maskUniforms.sampler = m_maskShader->uniformLocation("kosMaskSampler");
    } else {
        qWarning() << "KOS continuous corners: mask shader failed; using per-fragment contour";
        m_maskShader.reset();
    }
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
            this, [this, window] { invalidateDamage(window); });
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
    if (it == m_reservations.end()) return;
    it->fullDirty = true;
    it->damaged = false;
    it->captured = {};
    ++it->epoch;
}

void ContinuousClip::invalidateDamage(KWin::EffectWindow *window)
{
    auto it = m_reservations.find(window);
    if (it == m_reservations.end() || it->fullDirty) return;
    // Content changed, but we do not get the damage region. Forget what has
    // been captured; each subsequent draw re-captures the area it paints, and
    // anything the compositor skips (occluded/off screen) is caught up when
    // it is painted again.
    it->damaged = true;
    it->captured = {};
    ++it->epoch;
}

void ContinuousClip::invalidateAll()
{
    for (auto &cache : m_reservations) {
        cache.fullDirty = true;
        cache.damaged = false;
        cache.captured = {};
        ++cache.epoch;
    }
}

std::shared_ptr<ContinuousClip::MaskAsset> ContinuousClip::maskFor(
    const ContinuousStyle &style, qreal sourceScale, qreal padding)
{
    MaskKey key;
    key.radius = style.radius * sourceScale;
    key.exponent = curveExponent(style.smoothness);
    key.stroke = style.stroke * sourceScale;
    key.frameWidth = style.frameWidth * sourceScale;
    key.contactSigma = style.shadow.contactBlur * sourceScale;
    key.ambientSigma = (style.active ? style.shadow.activeBlur
                                     : style.shadow.inactiveBlur) * sourceScale;
    key.contactOpacity = style.shadow.contactOpacity;
    key.ambientOpacity = style.shadow.ambientOpacity;
    key.extent = cornerExtent(style.radius, style.smoothness) * sourceScale;
    key.padding = padding;
    key.offsetY = style.shadow.offsetY * sourceScale;
    const auto cached = m_masks.constFind(key);
    if (cached != m_masks.cend()) {
        return *cached;
    }
    // Focus changes swap the active/inactive shadow sigmas; keep a couple of
    // variants per style and drop the whole cache on configuration churn.
    if (m_masks.size() >= 8) {
        m_masks.clear();
    }
    CornerMaskStyle bake;
    bake.radius = key.radius;
    bake.exponent = key.exponent;
    bake.stroke = key.stroke;
    bake.frameWidth = key.frameWidth;
    bake.contactSigma = key.contactSigma;
    bake.ambientSigma = key.ambientSigma;
    bake.contactOpacity = key.contactOpacity;
    bake.ambientOpacity = key.ambientOpacity;
    bake.extent = key.extent;
    bake.padding = key.padding;
    bake.offsetY = key.offsetY;
    auto asset = std::make_shared<MaskAsset>();
    asset->atlas = bakeCornerMask(bake);
    auto texture = KWin::GLTexture::upload(asset->atlas.image);
    if (!texture) {
        return nullptr;
    }
    texture->setFilter(GL_LINEAR);
    texture->setWrapMode(GL_CLAMP_TO_EDGE);
    asset->texture = std::shared_ptr<KWin::GLTexture>(std::move(texture));
    asset->textureMatrix = asset->texture->matrix(KWin::NormalizedCoordinates);
    asset->atlas.image = QImage();
    m_masks.insert(key, asset);
    return asset;
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
    KWin::Region deviceClip = region & viewport.deviceRect();
    const auto *fullscreenEffect = KWin::effects->activeFullScreenEffect();
    if (!morph && fullscreenEffect && fullscreenEffect->inherits("KWin::SlideEffect")
        && (mask & PAINT_WINDOW_TRANSFORMED)
        && data.scale() == QVector3D(1, 1, 1) && qFuzzyIsNull(data.rotationAngle())) {
        // Slide paints each desktop once per output. Its destination clip
        // alone lets the expanded shadow of a window on the right enter the
        // left output's pass, even though the frame never belonged there.
        // Move only source outputs touched by the actual frame, then intersect
        // with Slide's desktop clip. A window spanning outputs keeps both.
        KWin::Region sourceOutputs;
        const QPointF translation(data.xTranslation(), data.yTranslation());
        for (auto *output : KWin::effects->screens()) {
            const QRectF outputGeometry(output->geometry());
            if (QRectF(window->frameGeometry()).intersects(outputGeometry)) {
                sourceOutputs |= viewport.mapToDeviceCoordinatesAligned(
                    KWin::RectF(outputGeometry.translated(translation)));
            }
        }
        deviceClip &= sourceOutputs;
    }
    // Empty output/desktop passes must not capture or draw the shared source.
    if (deviceClip.isEmpty()) {
        return true;
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
        cache.fullDirty = true;
        cache.damaged = false;
        cache.captured = {};
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
        cache.fullDirty = true;
        cache.damaged = false;
        cache.captured = {};
    }
    if (cache.fullDirty || cache.damaged) {
        KWin::RenderTarget sourceTarget(cache.fbo.get());
        KWin::RenderViewport sourceViewport(sourceGeometry, sourceScale, sourceTarget, QPoint());
        const bool morphing = static_cast<bool>(morph);
        const KWin::Region textureRegion(KWin::Rect(QPoint(0, 0), textureSize));
        // Transformed draws (drag, morph, slide) express their region in
        // target space, which cannot be mapped back to source pixels. Morph
        // captures also have to bake the controls, so refresh them whole.
        const bool wholeUpdate = cache.fullDirty || (cache.damaged
            && (morphing || (mask & PAINT_WINDOW_TRANSFORMED)));
        KWin::Region update = textureRegion;
        if (!wholeUpdate) {
            const KWin::Region logical = viewport.mapFromDeviceCoordinatesAligned(deviceClip);
            update = sourceViewport.mapToDeviceCoordinatesAligned(logical) & textureRegion;
            // Anything captured since the damage was raised is already
            // current; repainting it again would blend translucent content
            // onto itself.
            update -= cache.captured;
        }
        // An empty update still has to composite: the texture is current for
        // this draw region, so only the capture is skipped.
        if (!update.isEmpty()) {
#ifdef KOS_KWIN_PAINT_RESULT_API
            auto *sourceContext = KWin::EglContext::currentContext();
#endif
            KWin::GLFramebuffer::pushFramebuffer(cache.fbo.get());
            glClearColor(0, 0, 0, 0);
            if (wholeUpdate) {
                glClear(GL_COLOR_BUFFER_BIT);
            } else {
                // Clear only the area that is about to be repainted. The rest
                // of the texture keeps its previous pixels.
                // glScissor takes bottom-left origin, like GLVertexBuffer::draw.
                const QSize clearSize = sourceTarget.transformedSize();
                const GLboolean scissorWasEnabled = glIsEnabled(GL_SCISSOR_TEST);
                GLint scissorBox[4];
                glGetIntegerv(GL_SCISSOR_BOX, scissorBox);
                glEnable(GL_SCISSOR_TEST);
                for (const KWin::Rect &rect : update.rects()) {
                    glScissor(rect.x(), clearSize.height() - (rect.y() + rect.height()),
                        rect.width(), rect.height());
                    glClear(GL_COLOR_BUFFER_BIT);
                }
                glScissor(scissorBox[0], scissorBox[1], scissorBox[2], scissorBox[3]);
                if (!scissorWasEnabled) {
                    glDisable(GL_SCISSOR_TEST);
                }
            }
            // Invalidations raised while sampling the title bar stay pending
            // for the next frame, so the callback still sees the captured
            // state.
            const quint64 epochBefore = cache.epoch;
            cache.fullDirty = false;
            const bool painted = sourcePainter(sourceTarget, sourceViewport,
                wholeUpdate ? KWin::Region::infinite() : update);
#ifdef KOS_KWIN_PAINT_RESULT_API
            if (KWin::EglContext::currentContext() != sourceContext) {
                cache.fullDirty = true;
                cache.damaged = false;
                cache.captured = {};
                KWin::GLFramebuffer::popFramebuffer();
                return false;
            }
#endif
            KWin::GLFramebuffer::popFramebuffer();
            if (!painted) {
                cache.fullDirty = true;
                cache.damaged = false;
                cache.captured = {};
                return false;
            }
            if (cache.epoch == epochBefore) {
                cache.captured |= update;
                if (wholeUpdate || (textureRegion - cache.captured).isEmpty()) {
                    cache.damaged = false;
                    cache.captured = {};
                }
            }
        }
    }

    const qreal scale = viewport.scale();
    const auto expanded = KWin::snapToPixels(window->expandedGeometry(), scale);
    const auto frame = KWin::snapToPixels(window->frameGeometry(), scale);
    const QRectF bounds(expanded.topLeft() - frame.topLeft(), expanded.size());

    // Baked-mask path: paint the window as nine quads that sample the shared
    // style atlas. Interior fragments become a source fetch; the perimeter and
    // shadow cost one more fetch instead of pow/exp per pixel.
    if (m_maskShader && !morph) {
        const qreal sourceScale = window->screen()->scale();
        const qreal frameW = style.size.width() * scale;
        const qreal frameH = style.size.height() * scale;
        const qreal leftPad = -bounds.left() * scale;
        const qreal topPad = -bounds.top() * scale;
        const qreal rightPad = (bounds.left() + bounds.width()) * scale - frameW;
        const qreal bottomPad = (bounds.top() + bounds.height()) * scale - frameH;
        const qreal extentDev = cornerExtent(style.radius, style.smoothness) * scale;
        const qreal bandDev = std::max(extentDev,
            (style.stroke + style.frameWidth) * scale + 2.0);
        const qreal padding = std::ceil(std::max({leftPad, topPad, rightPad,
            bottomPad, 1.0}));
        const bool padsAgree = std::abs(leftPad - rightPad) <= 2.0
            && std::abs(topPad - bottomPad) <= 2.0
            && std::abs(leftPad - topPad) <= 2.0;
        if (qFuzzyCompare(scale + 1.0, sourceScale + 1.0) && padsAgree
            && frameW > 2.0 * bandDev + 2.0 && frameH > 2.0 * bandDev + 2.0) {
            if (auto asset = maskFor(style, sourceScale, padding)) {
                const auto &atlas = asset->atlas;
                const qreal atlasW = atlas.width;
                const qreal atlasH = atlas.height;
                const qreal x0 = -padding, x1 = bandDev;
                const qreal x2 = frameW - bandDev, x3 = frameW + padding;
                const qreal y0 = -padding, y1 = bandDev;
                const qreal y2 = frameH - bandDev, y3 = frameH + padding;
                const qreal sourceX = bounds.left() * scale;
                const qreal sourceY = bounds.top() * scale;
                const qreal sourceW = bounds.width() * scale;
                const qreal sourceH = bounds.height() * scale;
                KWin::WindowQuadList quads;
                const auto sourceUv = [&](qreal x, qreal y) {
                    return QPointF((x - sourceX) / sourceW, (y - sourceY) / sourceH);
                };
                const auto addQuad = [&](qreal ax, qreal ay, qreal bx, qreal by) {
                    KWin::WindowQuad q;
                    q[0] = KWin::WindowVertex(QPointF(ax / scale, ay / scale),
                        sourceUv(ax, ay));
                    q[1] = KWin::WindowVertex(QPointF(bx / scale, ay / scale),
                        sourceUv(bx, ay));
                    q[2] = KWin::WindowVertex(QPointF(bx / scale, by / scale),
                        sourceUv(bx, by));
                    q[3] = KWin::WindowVertex(QPointF(ax / scale, by / scale),
                        sourceUv(ax, by));
                    quads.append(q);
                };
                addQuad(x0, y0, x1, y1); // top-left corner
                addQuad(x2, y0, x3, y1); // top-right
                addQuad(x0, y2, x1, y3); // bottom-left
                addQuad(x2, y2, x3, y3); // bottom-right
                addQuad(x1, y0, x2, y1); // top edge
                addQuad(x1, y2, x2, y3); // bottom edge
                addQuad(x0, y1, x1, y2); // left edge
                addQuad(x2, y1, x3, y2); // right edge
                addQuad(x1, y1, x2, y2); // interior

                // Per-quad mapping from frame-relative device position to
                // atlas coordinates. Block texel i holds the value for inward
                // distance i + 0.5 - padding, i.e. texel coordinate
                // i + 0.5 = padding + distance (plus the block origin), so the
                // frame edge lands halfway between two texels and linear
                // sampling yields the antialiased transition. The straight-edge
                // profile is stored along the atlas row, so horizontal edges
                // drive the u coordinate from the fragment's y (and vice versa
                // for vertical edges).
                // Top and bottom corners bake different shadow shifts, so they
                // read their own block; the left/right pair of each still
                // mirrors horizontally. The edges pick the profile with the
                // matching shadow distance.
                const qreal topX = atlas.topBlockX, topY = atlas.topBlockY;
                const qreal bottomX = atlas.bottomBlockX;
                const qreal bottomY = atlas.bottomBlockY;
                // u = sux*x + suy*y + tu, v = svx*x + svy*y + tv.
                const auto affine = [&](qreal sux, qreal svx, qreal suy, qreal svy,
                                        qreal tu, qreal tv) {
                    QMatrix4x4 m;
                    m(0, 0) = float(sux);
                    m(0, 1) = float(suy);
                    m(0, 3) = float(tu);
                    m(1, 0) = float(svx);
                    m(1, 1) = float(svy);
                    m(1, 3) = float(tv);
                    return asset->textureMatrix * m;
                };
                const qreal padTexels = padding;
                const auto rowV = [&](int row) { return (row + 0.5) / atlasH; };
                const qreal sideV = rowV(atlas.sideProfileY);
                const auto topTx = (topX + padTexels) / atlasW;
                const auto topTy = (topY + padTexels) / atlasH;
                const auto bottomTx = (bottomX + padTexels) / atlasW;
                const auto bottomUpV = (bottomY + padTexels + frameH) / atlasH;
                QMatrix4x4 masks[9];
                masks[0] = affine(1 / atlasW, 0, 0, 1 / atlasH,
                    topTx, topTy);
                masks[1] = affine(-1 / atlasW, 0, 0, 1 / atlasH,
                    (topX + padTexels + frameW) / atlasW, topTy);
                masks[2] = affine(1 / atlasW, 0, 0, -1 / atlasH,
                    bottomTx, bottomUpV);
                masks[3] = affine(-1 / atlasW, 0, 0, -1 / atlasH,
                    (bottomX + padTexels + frameW) / atlasW, bottomUpV);
                masks[4] = affine(0, 0, 1 / atlasW, 0,
                    (atlas.topProfileX + padTexels) / atlasW,
                    rowV(atlas.topProfileY));
                masks[5] = affine(0, 0, -1 / atlasW, 0,
                    (atlas.bottomProfileX + padTexels + frameH) / atlasW,
                    rowV(atlas.bottomProfileY));
                masks[6] = affine(1 / atlasW, 0, 0, 0,
                    (atlas.sideProfileX + padTexels) / atlasW, sideV);
                masks[7] = affine(-1 / atlasW, 0, 0, 0,
                    (atlas.sideProfileX + padTexels + frameW) / atlasW, sideV);
                masks[8] = affine(0, 0, 0, 0,
                    (atlas.centerX + 0.5) / atlasW, (atlas.centerY + 0.5) / atlasH);

                KWin::WindowPaintData paintedData = data;
                KWin::ShaderBinder binder(m_maskShader.get());
                m_maskShader->setUniform(m_maskUniforms.edgeColor,
                    style.outline.colorFor(style.dark));
                m_maskShader->setUniform(m_maskUniforms.frameColor,
                    style.fill.colorFor(style.dark));
                m_maskShader->setUniform(m_maskUniforms.edgeOpacity, style.edgeOpacity);
                m_maskShader->setUniform(m_maskUniforms.shadowOpacity, style.shadowOpacity);
                m_maskShader->setUniform(m_maskUniforms.sampler, 1);
                auto *vbo = KWin::GLVertexBuffer::streamingBuffer();
                vbo->reset();
                vbo->setAttribLayout(std::span(KWin::GLVertexBuffer::GLVertex2DLayout),
                    sizeof(KWin::GLVertex2D));
                KWin::RenderGeometry geometry;
                geometry.setVertexSnappingMode(
                    KWin::RenderGeometry::VertexSnappingMode::None);
                for (const auto &q : quads) {
                    geometry.appendWindowQuad(q, scale);
                }
                geometry.postProcessTextureCoordinates(
                    cache.texture->matrix(KWin::NormalizedCoordinates));
                const auto mapped = vbo->map<KWin::GLVertex2D>(geometry.size());
                if (!mapped) {
                    return false;
                }
                geometry.copy(*mapped);
                vbo->unmap();
                vbo->bindArrays();
                QMatrix4x4 mvp = viewport.projectionMatrix();
                mvp.translate(std::round(window->x() * scale),
                    std::round(window->y() * scale));
                m_maskShader->setUniform(
                    KWin::GLShader::Mat4Uniform::ModelViewProjectionMatrix,
                    mvp * paintedData.toMatrix(scale));
                const qreal rgb = paintedData.brightness() * paintedData.opacity();
                m_maskShader->setUniform(KWin::GLShader::Vec4Uniform::ModulationConstant,
                    QVector4D(rgb, rgb, rgb, paintedData.opacity()));
                m_maskShader->setUniform(KWin::GLShader::FloatUniform::Saturation,
                    paintedData.saturation());
                const auto xyz = target.colorDescription()->containerColorimetry().toXYZ();
                m_maskShader->setUniform(KWin::GLShader::Vec3Uniform::PrimaryBrightness,
                    QVector3D(xyz(1, 0), xyz(1, 1), xyz(1, 2)));
                m_maskShader->setUniform(KWin::GLShader::IntUniform::TextureWidth,
                    cache.texture->width());
                m_maskShader->setUniform(KWin::GLShader::IntUniform::TextureHeight,
                    cache.texture->height());
                m_maskShader->setColorspaceUniforms(KWin::ColorDescription::sRGB,
                    target.colorDescription(), KWin::RenderingIntent::Perceptual);
                const auto clip = viewport.transform().map(deviceClip,
                    target.transformedSize());
                glEnable(GL_SCISSOR_TEST);
                glEnable(GL_BLEND);
                glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
                glActiveTexture(GL_TEXTURE1);
                asset->texture->bind();
                glActiveTexture(GL_TEXTURE0);
                cache.texture->bind();
                for (int i = 0; i < 9; ++i) {
                    m_maskShader->setUniform(m_maskUniforms.maskMatrix, masks[i]);
                    vbo->draw(clip, GL_TRIANGLES, i * 6, 6, true);
                }
                cache.texture->unbind();
                glActiveTexture(GL_TEXTURE1);
                asset->texture->unbind();
                glActiveTexture(GL_TEXTURE0);
                glDisable(GL_BLEND);
                glDisable(GL_SCISSOR_TEST);
                vbo->unbindArrays();
                return true;
            }
        }
    }

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
        m_shader->setUniform(m_uniforms.shadowOffset,
            qreal(style.shadow.offsetY) * scale);
    }
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
    const auto clip = viewport.transform().map(deviceClip, target.transformedSize());
    glEnable(GL_SCISSOR_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    cache.texture->bind();
    vbo->draw(clip, GL_TRIANGLES, 0, geometry.count(), true);
    cache.texture->unbind();
    glDisable(GL_BLEND);
    glDisable(GL_SCISSOR_TEST);
    vbo->unbindArrays();
    // The morph is local to this completed draw. WindowPaintData is copy
    // constructible but not assignable; callers need no mutated copy back.
    return true;
}

} // namespace KOS::WindowAppearance
