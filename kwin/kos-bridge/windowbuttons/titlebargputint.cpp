#include "titlebargputint.h"
#include "titlebartint.h"

#include <core/rendertarget.h>
#include <effect/effecthandler.h>
#include <opengl/glframebuffer.h>
#include <opengl/glshader.h>
#include <opengl/glshadermanager.h>
#include <opengl/gltexture.h>
#include <QDebug>
#include <epoxy/gl.h>

namespace KOS
{
namespace
{
// Match TintHistogram's upper median and +/-3 luma cluster, including integer
// RGB truncation. This runs once for a single output texel, not per panel pixel.
const char ReduceFragment[] = R"(
uniform sampler2D sampler;
uniform int gutterWidth;
uniform int gutterHeight;
out vec4 fragColor;
int luma(ivec3 rgb) { return (54 * rgb.r + 183 * rgb.g + 19 * rgb.b) >> 8; }
ivec3 straightRgb(ivec4 p)
{
    if (p.a == 255) return p.rgb;
    return min(ivec3(255), (p.rgb * 255 + ivec3(p.a / 2)) / p.a);
}
void main()
{
    int bins[256];
    for (int i = 0; i < 256; ++i) bins[i] = 0;
    int count = 0;
    for (int y = 0; y < gutterHeight; ++y) {
        for (int x = 0; x < gutterWidth; ++x) {
            ivec4 p = ivec4(round(texelFetch(sampler, ivec2(x, y), 0) * 255.0));
            if (p.a < KOS_MIN_OPAQUE_ALPHA) continue;
            ++bins[luma(straightRgb(p))];
            ++count;
        }
    }
    if (count < max(64, (gutterWidth * gutterHeight * 3 + 3) / 4)) {
        fragColor = vec4(0.0);
        return;
    }
    int cumulative = 0;
    int median = 255;
    for (int i = 0; i < 256; ++i) {
        cumulative += bins[i];
        if (cumulative > count / 2) { median = i; break; }
    }
    ivec3 sum = ivec3(0);
    int cluster = 0;
    for (int y = 0; y < gutterHeight; ++y) {
        for (int x = 0; x < gutterWidth; ++x) {
            ivec4 p = ivec4(round(texelFetch(sampler, ivec2(x, y), 0) * 255.0));
            if (p.a < KOS_MIN_OPAQUE_ALPHA) continue;
            ivec3 rgb = straightRgb(p);
            if (abs(luma(rgb) - median) <= 3) {
                sum += rgb;
                ++cluster;
            }
        }
    }
    fragColor = vec4(vec3(sum / cluster) / 255.0, 1.0);
}
)";

const char PanelFragment[] = R"(
uniform sampler2D sampler;
uniform sampler2D tintSampler;
uniform vec4 modulation;
uniform int tintBackground;
in vec2 texcoord0;
out vec4 fragColor;
void main()
{
    vec4 tint = texture(tintSampler, vec2(0.5));
    if (tint.a == 0.0) tint = modulation;
    // The lights retain their own colors, but disappear with an invalid first
    // sample. A validated fallback keeps both the cover and lights visible.
    fragColor = texture(sampler, texcoord0)
        * (tintBackground != 0 ? tint : vec4(tint.a));
}
)";

const char Vertex[] = R"(
uniform mat4 modelViewProjectionMatrix;
in vec4 position;
in vec2 texcoord;
out vec2 texcoord0;
void main()
{
    texcoord0 = texcoord;
    gl_Position = modelViewProjectionMatrix * position;
}
)";

// Scratch painting must not inherit clipping, blending, a write mask or an
// unrelated FBO/texture unit. Restore raw bindings as well as KWin's shader stack.
class SavedState
{
public:
    SavedState() {
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &readFbo);
        glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &drawFbo);
        glGetIntegerv(GL_VIEWPORT, viewport);
        glGetIntegerv(GL_CURRENT_PROGRAM, &program);
        glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &vao);
        glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &buffer);
        glGetIntegerv(GL_ACTIVE_TEXTURE, &activeTexture);
        glActiveTexture(GL_TEXTURE0);
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &texture);
        glGetBooleanv(GL_COLOR_WRITEMASK, colorMask);
        for (int i = 0; i < 6; ++i) {
            enabled[i] = glIsEnabled(capabilities[i]);
            glDisable(capabilities[i]);
        }
        if (epoxy_is_desktop_gl()) {
            srgb = glIsEnabled(GL_FRAMEBUFFER_SRGB);
            glDisable(GL_FRAMEBUFFER_SRGB);
        }
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    }
    ~SavedState() {
        glBindFramebuffer(GL_READ_FRAMEBUFFER, readFbo);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, drawFbo);
        glViewport(viewport[0], viewport[1], viewport[2], viewport[3]);
        glUseProgram(program);
        glBindVertexArray(vao);
        glBindBuffer(GL_ARRAY_BUFFER, buffer);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, texture);
        glActiveTexture(activeTexture);
        glColorMask(colorMask[0], colorMask[1], colorMask[2], colorMask[3]);
        for (int i = 0; i < 6; ++i)
            if (enabled[i]) glEnable(capabilities[i]);
        if (srgb) glEnable(GL_FRAMEBUFFER_SRGB);
    }
private:
    static constexpr GLenum capabilities[] = {GL_BLEND, GL_SCISSOR_TEST, GL_DEPTH_TEST,
        GL_STENCIL_TEST, GL_CULL_FACE, GL_RASTERIZER_DISCARD};
    GLint readFbo, drawFbo, viewport[4], program, vao, buffer, activeTexture, texture;
    GLboolean colorMask[4], enabled[6], srgb = GL_FALSE;
};
}

TitlebarGpuTint::TitlebarGpuTint() = default;
TitlebarGpuTint::~TitlebarGpuTint()
{
    if (KWin::effects) KWin::effects->makeOpenGLContextCurrent();
}

bool TitlebarGpuTint::initialize()
{
    if (m_attempted) return m_panelShader && m_reduceShader;
    m_attempted = true;
    // A rotated gutter swaps its long/short axes. One fixed square avoids
    // reallocating between windows, scales and output transforms (100 KiB).
    m_gutter = KWin::GLTexture::allocate(GL_RGBA8, QSize(TintProbeWidth, TintProbeWidth));
    m_color = KWin::GLTexture::allocate(GL_RGBA8, QSize(1, 1));
    if (!m_gutter || !m_color) return false;
    m_gutter->setFilter(GL_NEAREST);
    m_color->setFilter(GL_NEAREST);
    m_gutterFbo = std::make_unique<KWin::GLFramebuffer>(m_gutter.get());
    m_colorFbo = std::make_unique<KWin::GLFramebuffer>(m_color.get());
    if (!m_gutterFbo->valid() || !m_colorFbo->valid()) return false;
    const QByteArray header = epoxy_is_desktop_gl()
        ? QByteArrayLiteral("#version 140\n")
        : QByteArrayLiteral("#version 300 es\nprecision highp float;\nprecision highp int;\n");
    auto *manager = KWin::ShaderManager::instance();
    const QByteArray alphaPolicy = QByteArrayLiteral("#define KOS_MIN_OPAQUE_ALPHA ")
        + QByteArray::number(TintHistogram::MinOpaqueAlpha) + '\n';
    m_reduceShader = manager->loadShaderFromCode(header + Vertex, header + alphaPolicy + ReduceFragment);
    m_panelShader = manager->loadShaderFromCode(header + Vertex, header + PanelFragment);
    if (!m_reduceShader || !m_reduceShader->link() || !m_panelShader || !m_panelShader->link()) {
        qWarning() << "KOS: same-frame titlebar shader unavailable; retaining asynchronous tint";
        m_reduceShader.reset();
        m_panelShader.reset();
        return false;
    }
    return true;
}

bool TitlebarGpuTint::update(const KWin::RenderTarget &target, const QRect &gutter)
{
    if (!target.framebuffer() || gutter.isEmpty()
        || !QRect(QPoint(), target.transformedSize()).contains(gutter)
        || gutter.width() * gutter.height() < TintHistogram::MinSamples
        || gutter.width() * gutter.height() > TintProbeWidth * 8) return false;
    const QRect source = target.transform().map(KWin::Rect(gutter), target.transformedSize());
    if (source.width() > TintProbeWidth || source.height() > TintProbeWidth) return false;

    const SavedState saved;
    if (!initialize()) return false;
    const GLuint fbo = target.framebuffer()->handle();
    // Default/integer/missing-color targets cannot supply this normalized copy.
    if (!fbo) return false;
    glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo);
    if (glCheckFramebufferStatus(GL_READ_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) return false;
    GLint attachment = GL_NONE, component = GL_NONE, previousReadBuffer = GL_NONE;
    glGetFramebufferAttachmentParameteriv(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
        GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, &attachment);
    if (attachment == GL_NONE) return false;
    glGetFramebufferAttachmentParameteriv(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
        GL_FRAMEBUFFER_ATTACHMENT_COMPONENT_TYPE, &component);
    if (component != GL_UNSIGNED_NORMALIZED && component != GL_FLOAT) return false;
    glGetIntegerv(GL_READ_BUFFER, &previousReadBuffer);
    glReadBuffer(GL_COLOR_ATTACHMENT0);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, m_gutterFbo->handle());
    const GLfloat transparent[4] = {};
    glClearBufferfv(GL_COLOR, 0, transparent);
    const int bottom = target.size().height() - source.y() - source.height();
    glBlitFramebuffer(source.x(), bottom, source.x() + source.width(), bottom + source.height(),
        0, 0, source.width(), source.height(), GL_COLOR_BUFFER_BIT, GL_NEAREST);
    glReadBuffer(previousReadBuffer);

    // The histogram is order-independent: no CPU row flip or rotation needed.
    glBindFramebuffer(GL_FRAMEBUFFER, m_colorFbo->handle());
    glClearBufferfv(GL_COLOR, 0, transparent);
    glViewport(0, 0, 1, 1);
    auto *manager = KWin::ShaderManager::instance();
    manager->pushShader(m_reduceShader.get());
    m_reduceShader->setUniform("sampler", 0);
    m_reduceShader->setUniform("gutterWidth", source.width());
    m_reduceShader->setUniform("gutterHeight", source.height());
    QMatrix4x4 projection;
    projection.ortho(0, 1, 1, 0, -1, 1);
    m_reduceShader->setUniform(KWin::GLShader::Mat4Uniform::ModelViewProjectionMatrix, projection);
    m_gutter->render(QSizeF(1, 1));
    manager->popShader();
    return true;
}

} // namespace KOS
