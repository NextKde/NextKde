#include "contourclip.h"

#include "appearanceshadow.h"
#include "contour.h"

#include <core/rect.h>
#include <core/region.h>
#include <core/rendertarget.h>
#include <core/renderviewport.h>
#include <effect/effectwindow.h>
#include <opengl/glframebuffer.h>
#include <opengl/glshader.h>
#include <opengl/glshadermanager.h>
#include <opengl/gltexture.h>
#include <opengl/glvertexbuffer.h>
#include <window.h>

#include <QMatrix4x4>
#include <QPainter>
#include <QPainterPath>

#include <epoxy/gl.h>

namespace KOS::WindowAppearance
{

namespace
{

// The patch shader, written against the shader conventions the glass effect
// uses in this repository (#version 140, in/out). Both stages are ours, so
// the vertex layout is whatever the GLVertexBuffer feed says it is -- there
// is no dependency on how the scene streams window geometry.
//
// The fragment reads the captured backdrop and the outside-of-contour mask
// and writes their product: where the mask is opaque the backdrop returns,
// where it is transparent the window's own pixels stay. Both textures are
// premultiplied, so scaling every channel by the mask alpha is a correct
// fade.
constexpr auto PatchVertexSource = R"(
#version 140

uniform mat4 modelViewProjectionMatrix;

in vec2 position;
in vec2 texcoord;

out vec2 uv;

void main(void)
{
    gl_Position = modelViewProjectionMatrix * vec4(position, 0.0, 1.0);
    uv = texcoord;
}
)";

constexpr auto PatchFragmentSource = R"(
#version 140

uniform sampler2D uBackdrop;
uniform sampler2D uMask;

in vec2 uv;
out vec4 fragColor;

void main(void)
{
    vec4 backdrop = texture(uBackdrop, uv);
    float mask = texture(uMask, uv).a;
    fragColor = backdrop * mask;
}
)";

// One visible piece of the frame, as a quad in device pixels relative to the
// frame's top-left, sampling the matching slice of the two full-frame
// textures. Six vertices, two triangles -- the same per-piece geometry the
// panel blits draw instead of touching the scissor.
void appendPieceQuad(std::array<KWin::GLVertex2D, 96> &vertices, int &count,
                     const QRectF &piece, float frameWidth, float frameHeight)
{
    const float u0 = float(piece.x()) / frameWidth;
    const float v0 = float(piece.y()) / frameHeight;
    const float u1 = float(piece.right()) / frameWidth;
    const float v1 = float(piece.bottom()) / frameHeight;
    const float x1 = float(piece.x());
    const float y1 = float(piece.y());
    const float x2 = float(piece.right());
    const float y2 = float(piece.bottom());

    const KWin::GLVertex2D quad[6] = {
        {{x1, y1}, {u0, v0}},
        {{x2, y1}, {u1, v0}},
        {{x2, y2}, {u1, v1}},
        {{x1, y1}, {u0, v0}},
        {{x2, y2}, {u1, v1}},
        {{x1, y2}, {u0, v1}},
    };
    for (const auto &vertex : quad) {
        vertices[count++] = vertex;
    }
}

} // namespace

ContourClip::ContourClip() = default;

ContourClip::~ContourClip() = default;

void ContourClip::invalidate()
{
    m_shader.reset();
    m_captures.clear();
    m_masks.clear();
}

void ContourClip::forgetWindow(KWin::EffectWindow *window)
{
    m_captures.erase(window);
}

bool ContourClip::ensureShader()
{
    if (m_shader) {
        return true;
    }
    if (m_failed) {
        return false;
    }
    m_shader = KWin::ShaderManager::instance()->loadShaderFromCode(
        PatchVertexSource, PatchFragmentSource);
    if (!m_shader) {
        m_failed = true;
        return false;
    }
    m_mvpLocation = m_shader->uniformLocation("modelViewProjectionMatrix");
    m_backdropLocation = m_shader->uniformLocation("uBackdrop");
    m_maskLocation = m_shader->uniformLocation("uMask");
    return true;
}

KWin::GLFramebuffer *ContourClip::captureBuffer(KWin::EffectWindow *window,
                                                const QSize &deviceSize)
{
    if (deviceSize.isEmpty()) {
        return nullptr;
    }
    Capture &capture = m_captures[window];
    if (capture.size != deviceSize) {
        capture.texture = KWin::GLTexture::upload(
            QImage(deviceSize, QImage::Format_ARGB32_Premultiplied));
        if (!capture.texture) {
            capture.size = QSize();
            return nullptr;
        }
        capture.texture->setWrapMode(GL_CLAMP_TO_EDGE);
        capture.texture->setFilter(GL_LINEAR);
        capture.framebuffer = std::make_unique<KWin::GLFramebuffer>(
            capture.texture.get());
        capture.size = deviceSize;
    }
    return capture.framebuffer->valid() ? capture.framebuffer.get() : nullptr;
}

void ContourClip::captureFrame(const KWin::RenderTarget &renderTarget,
                               const KWin::RenderViewport &viewport,
                               KWin::EffectWindow *window,
                               const QRectF &frameLogical)
{
    const KWin::Rect deviceFrame =
        viewport.mapToDeviceCoordinatesAligned(frameLogical);
    KWin::GLFramebuffer *buffer =
        captureBuffer(window, QSize(deviceFrame.width(), deviceFrame.height()));
    if (!buffer) {
        return;
    }
    // Copy the frame region out of the screen target while it still holds
    // the backdrop: everything stacked below this window is drawn, the
    // window itself is not. The source rect is logical, the destination
    // texture-local -- the blit accounts for the transforms between them.
    const KWin::Rect destination(0, 0, deviceFrame.width(),
                                 deviceFrame.height());
    buffer->blitFromRenderTarget(renderTarget, viewport,
                                 KWin::Rect(frameLogical.toAlignedRect()),
                                 destination);
}

KWin::GLTexture *ContourClip::maskTexture(const QSize &deviceSize,
                                          const CornerRadii &radii,
                                          qreal smoothness, qreal scale)
{
    // The mask is opaque outside the contour and transparent inside it, with
    // the antialiasing QPainter gives the curve. Built in the window's frame
    // rect: it is drawn 1:1 over the captured backdrop. The key is the same
    // kind of key every generated image in this module uses.
    const QString key = QStringLiteral("wa.clipmask.%1x%2.s%3.r%4,%5,%6,%7.m%8")
                            .arg(deviceSize.width())
                            .arg(deviceSize.height())
                            .arg(smoothness, 0, 'f', 2)
                            .arg(radii.topLeft, 0, 'f', 1)
                            .arg(radii.topRight, 0, 'f', 1)
                            .arg(radii.bottomRight, 0, 'f', 1)
                            .arg(radii.bottomLeft, 0, 'f', 1)
                            .arg(scale, 0, 'f', 2);
    if (auto it = m_masks.find(key); it != m_masks.end()) {
        return it->second.get();
    }

    QImage image(deviceSize, QImage::Format_ARGB32_Premultiplied);
    if (image.isNull()) {
        return nullptr;
    }
    image.fill(0xFF000000);
    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing, true);
    const QRectF frame(0, 0, deviceSize.width(), deviceSize.height());
    const QPainterPath contour = contourPath(frame, radii, smoothness);
    painter.setCompositionMode(QPainter::CompositionMode_DestinationOut);
    painter.fillPath(contour, QColor(Qt::black));
    painter.end();

    auto texture = KWin::GLTexture::upload(image);
    if (!texture) {
        return nullptr;
    }
    texture->setWrapMode(GL_CLAMP_TO_EDGE);
    texture->setFilter(GL_LINEAR);
    return m_masks.emplace(key, std::move(texture)).first->second.get();
}

void ContourClip::patchFrame(const KWin::RenderTarget &renderTarget,
                             const KWin::RenderViewport &viewport,
                             KWin::EffectWindow *window,
                             const QRectF &frameLogical,
                             const CornerRadii &radii, qreal smoothness,
                             const KWin::Region &clip)
{
    Q_UNUSED(renderTarget)
    if (!ensureShader() || clip.isEmpty()) {
        return;
    }
    Capture &capture = m_captures[window];
    if (!capture.texture || capture.size.isEmpty()) {
        return;
    }
    const qreal scale = viewport.scale();
    KWin::GLTexture *mask = maskTexture(capture.size, radii, smoothness, scale);
    if (!mask) {
        return;
    }

    // The backdrop was captured before the window drew; drawing it back
    // through the outside-of-contour mask rebuilds the cut corners from the
    // real content behind the window.
    auto *shaderManager = KWin::ShaderManager::instance();
    shaderManager->pushShader(m_shader.get());
    m_shader->setUniform(m_backdropLocation, 0);
    m_shader->setUniform(m_maskLocation, 1);

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

    glActiveTexture(GL_TEXTURE0);
    capture.texture->bind();
    glActiveTexture(GL_TEXTURE1);
    mask->bind();

    const QMatrix4x4 mvp = viewport.projectionMatrix();

    // The visible pieces of the frame, each drawn as its own quad sampling
    // the matching slice of the two full-frame textures -- the same
    // per-piece geometry the panel blits draw instead of touching the
    // scissor.
    const KWin::Rect deviceFrame =
        viewport.mapToDeviceCoordinatesAligned(frameLogical);
    const KWin::Region visiblePieces =
        clip & KWin::Region(deviceFrame);

    std::array<KWin::GLVertex2D, 96> vertices;
    int count = 0;
    for (const KWin::Rect &piece : visiblePieces.rects()) {
        if (count + 6 > int(vertices.size())) {
            break;
        }
        appendPieceQuad(vertices, count,
                        QRectF(piece.x() - deviceFrame.x(),
                               piece.y() - deviceFrame.y(), piece.width(),
                               piece.height()),
                        deviceFrame.width(), deviceFrame.height());
    }

    QMatrix4x4 translated = mvp;
    translated.translate(deviceFrame.x(), deviceFrame.y());
    m_shader->setUniform(m_mvpLocation, translated);

    KWin::GLVertexBuffer *vbo = KWin::GLVertexBuffer::streamingBuffer();
    vbo->setData(vertices.data(), count * sizeof(KWin::GLVertex2D));
    vbo->setVertexCount(count);
    vbo->setAttribLayout(std::span(KWin::GLVertexBuffer::GLVertex2DLayout),
                         sizeof(KWin::GLVertex2D));
    vbo->bindArrays();
    vbo->render(GL_TRIANGLES);
    vbo->unbindArrays();

    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, 0);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, 0);

    glBlendFuncSeparate(prevSrcRgb, prevDstRgb, prevSrcAlpha, prevDstAlpha);
    if (!blendWasEnabled) {
        glDisable(GL_BLEND);
    }
    shaderManager->popShader();
}

} // namespace KOS::WindowAppearance
