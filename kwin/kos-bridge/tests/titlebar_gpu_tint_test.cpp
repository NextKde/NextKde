#include "../windowbuttons/titlebargputint.h"
#include "../windowbuttons/titlebarmetrics.h"
#include "../windowbuttons/titlebartint.h"

#include <core/rendertarget.h>
#include <core/renderviewport.h>
#include <core/region.h>
#include <opengl/eglcontext.h>
#include <opengl/egldisplay.h>
#include <opengl/glframebuffer.h>
#include <opengl/glshader.h>
#include <opengl/glshadermanager.h>
#include <opengl/gltexture.h>
#include <QCoreApplication>
#include <QElapsedTimer>
#include <array>
#include <cstdio>
#include <vector>
#include <epoxy/egl.h>
#include <epoxy/gl.h>

namespace
{
int checks = 0, failures = 0;
#define CHECK(expr) do { ++checks; if (!(expr)) { ++failures; std::fprintf(stderr, "%d: %s\n", __LINE__, #expr); } } while (false)

template<typename Display>
auto createDisplay(EGLDisplay handle)
{
    if constexpr (requires { Display::create(handle, nullptr); }) return Display::create(handle, nullptr);
    else return Display::create(handle);
}

QColor readPixel(KWin::GLTexture *texture)
{
    // Test oracle only: production never reads or waits for this color on CPU.
    KWin::GLFramebuffer fbo(texture);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo.handle());
    glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glPixelStorei(GL_PACK_ROW_LENGTH, 0);
    glPixelStorei(GL_PACK_SKIP_ROWS, 0);
    glPixelStorei(GL_PACK_SKIP_PIXELS, 0);
    std::array<uchar, 4> pixel{};
    glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel.data());
    return QColor(pixel[0], pixel[1], pixel[2], pixel[3]);
}

std::unique_ptr<KWin::GLTexture> drawPanel(KOS::TitlebarGpuTint &tint, bool background,
                                          const QColor &fallback, int alpha = 255)
{
    auto output = KWin::GLTexture::allocate(GL_RGBA8, QSize(1, 1));
    KWin::GLFramebuffer fbo(output.get());
    QImage image(1, 1, QImage::Format_ARGB32_Premultiplied);
    QColor ink(background ? Qt::white : Qt::red);
    ink.setAlpha(alpha);
    image.fill(ink);
    auto mask = KWin::GLTexture::upload(image);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo.handle());
    glViewport(0, 0, 1, 1);
    glDisable(GL_BLEND);
    glDisable(GL_SCISSOR_TEST);
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glActiveTexture(GL_TEXTURE1);
    tint.texture()->bind();
    glActiveTexture(GL_TEXTURE0);
    auto *manager = KWin::ShaderManager::instance();
    manager->pushShader(tint.panelShader());
    tint.panelShader()->setUniform("sampler", 0);
    tint.panelShader()->setUniform("tintSampler", 1);
    tint.panelShader()->setUniform("tintBackground", int(background));
    tint.panelShader()->setUniform(KWin::GLShader::Vec4Uniform::ModulationConstant,
        QVector4D(fallback.redF(), fallback.greenF(), fallback.blueF(), fallback.alphaF()));
    QMatrix4x4 projection;
    projection.ortho(0, 1, 1, 0, -1, 1);
    tint.panelShader()->setUniform(KWin::GLShader::Mat4Uniform::ModelViewProjectionMatrix, projection);
    mask->render(QSizeF(1, 1));
    manager->popShader();
    return output;
}

QColor paintPanel(KOS::TitlebarGpuTint &tint, bool background, const QColor &fallback, int alpha = 255)
{
    const auto output = drawPanel(tint, background, fallback, alpha);
    return readPixel(output.get());
}
}

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    auto display = createDisplay<KWin::EglDisplay>(
        eglGetPlatformDisplayEXT(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, nullptr));
    if (!display) return 77;
    auto context = KWin::EglContext::create(display.get(), EGL_NO_CONFIG_KHR, nullptr);
    if (!context || !context->makeCurrent()) return 77;
    std::printf("GPU: %s\nOpenGL: %s\n", glGetString(GL_RENDERER), glGetString(GL_VERSION));
    KOS::TitlebarGpuTint tint;
    KWin::ShaderBinder originalShader(KWin::ShaderTrait::MapTexture | KWin::ShaderTrait::Modulate);
    const QSize logicalSize(360, 96);
    for (int kind = 0; kind < 8; ++kind) {
        const KWin::OutputTransform transform(static_cast<KWin::OutputTransform::Kind>(kind));
        const QSize size = transform.map(logicalSize);
        // Use uploadable GL storage for test pixels. KWin's allocator can use
        // EGLImage-backed render storage which rejects CPU subimage uploads.
        GLuint sourceId = 0;
        glGenTextures(1, &sourceId);
        glBindTexture(GL_TEXTURE_2D, sourceId);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, size.width(), size.height(), 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
        auto source = KWin::GLTexture::createNonOwningWrapper(sourceId, GL_RGBA8, size);
        source->setContentTransform(transform);
        KWin::GLFramebuffer fbo(source.get());
        KWin::RenderTarget target(&fbo);
        for (int frame = 0; frame < 3; ++frame) {
            std::vector<uchar> pixels(size.width() * size.height() * 4, 255);
            for (int y = 0; y < size.height(); ++y) for (int x = 0; x < size.width(); ++x) {
                auto *p = pixels.data() + (y * size.width() + x) * 4;
                // Black initial content, then a light titlebar, then a colored
                // titlebar. Glyph outliers must not replace the median RGB.
                const int base = frame == 0 ? 0 : frame == 1 ? 230 : 42;
                p[0] = uchar(base + (x % 3));
                p[1] = uchar(base + (y % 3));
                p[2] = uchar(base + (frame == 2 ? 25 : 0));
                if ((x + y * 3) % 7 == 0) p[0] = p[1] = p[2] = 255;
            }
            glActiveTexture(GL_TEXTURE0);
            source->bind();
            glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
            glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, size.width(), size.height(), GL_RGBA, GL_UNSIGNED_BYTE, pixels.data());
            CHECK(glGetError() == GL_NO_ERROR);
            for (const QRect rect : {QRect(170, 4, 32, 4), QRect(4, 8, 160, 4)}) {
                const QRect physical = transform.map(KWin::Rect(rect), logicalSize);
                KOS::TintHistogram histogram;
                for (int y = 0; y < physical.height(); ++y) for (int x = 0; x < physical.width(); ++x) {
                    const int row = size.height() - physical.y() - physical.height() + y;
                    histogram.add(pixels.data() + (row * size.width() + physical.x() + x) * 4);
                }
                QColor expected;
                bool dark = false;
                CHECK(histogram.tint(&dark, &expected));
                glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo.handle());
                glReadBuffer(GL_NONE);
                glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
                glBindFramebuffer(GL_DRAW_FRAMEBUFFER, fbo.handle());
                glViewport(7, 11, 13, 17);
                glEnable(GL_SCISSOR_TEST);
                glScissor(1, 2, 0, 0);
                glEnable(GL_BLEND);
                glColorMask(GL_FALSE, GL_TRUE, GL_FALSE, GL_FALSE);
                glActiveTexture(GL_TEXTURE3);
                GLint originalProgram = 0, originalVao = 0, originalBuffer = 0;
                glGetIntegerv(GL_CURRENT_PROGRAM, &originalProgram);
                glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &originalVao);
                glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &originalBuffer);
                const bool updated = tint.update(target, rect);
                CHECK(updated);
                if (!updated) return 1;
                CHECK(glGetError() == GL_NO_ERROR);
                GLint value = -1, viewport[4];
                GLboolean mask[4];
                glGetIntegerv(GL_ACTIVE_TEXTURE, &value);
                CHECK(value == GL_TEXTURE3);
                glGetIntegerv(GL_CURRENT_PROGRAM, &value);
                CHECK(value == originalProgram && KWin::ShaderManager::instance()->getBoundShader() == originalShader.shader());
                glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &value);
                CHECK(value == originalVao);
                glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &value);
                CHECK(value == originalBuffer);
                glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &value);
                CHECK(value == 0);
                glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &value);
                CHECK(value == GLint(fbo.handle()));
                glGetIntegerv(GL_VIEWPORT, viewport);
                CHECK(viewport[0] == 7 && viewport[1] == 11 && viewport[2] == 13 && viewport[3] == 17);
                glGetBooleanv(GL_COLOR_WRITEMASK, mask);
                CHECK(!mask[0] && mask[1] && !mask[2] && !mask[3]);
                CHECK(glIsEnabled(GL_BLEND) && glIsEnabled(GL_SCISSOR_TEST));
                glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo.handle());
                glGetIntegerv(GL_READ_BUFFER, &value);
                CHECK(value == GL_NONE);
                // Draw the cover in this same command stream, before any CPU
                // read or subsequent frame. Read only the finished panel pixel.
                CHECK(paintPanel(tint, true, Qt::transparent) == expected);
                CHECK(paintPanel(tint, false, Qt::transparent) == QColor(Qt::red));
                CHECK(glGetError() == GL_NO_ERROR);
            }
        }
        for (qreal scale : {1.0, 1.25}) {
            const QPointF origin(-40, 20);
            const QRectF frame(origin, QSizeF(logicalSize) / scale);
            KWin::RenderViewport viewport(KWin::RectF(frame), scale, target, QPoint());
            const QRectF cover(frame.width() - 80, 0, 80, 30);
            const QRect probe = KOS::visibleTitlebarGutter(target, viewport, frame,
                KWin::Region::infinite(), cover, cover);
            CHECK(!probe.isEmpty());
            CHECK(!probe.intersects(viewport.mapToRenderTargetTexture(cover.translated(origin)).toAlignedRect()));
            CHECK(KOS::visibleTitlebarGutter(target, viewport, frame, KWin::Region(), cover, cover).isEmpty());
        }
        glDeleteTextures(1, &sourceId);
    }
    // A transparent gutter is not black; both cover and lights fail closed
    // until a real color (or a previously validated fallback) is available.
    auto transparent = KWin::GLTexture::allocate(GL_RGBA8, QSize(32, 4));
    KWin::GLFramebuffer emptyFbo(transparent.get());
    KWin::RenderTarget emptyTarget(&emptyFbo);
    glBindFramebuffer(GL_FRAMEBUFFER, emptyFbo.handle());
    glDisable(GL_SCISSOR_TEST);
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    const GLfloat zero[4] = {};
    glClearBufferfv(GL_COLOR, 0, zero);
    CHECK(tint.update(emptyTarget, QRect(0, 0, 32, 4)));
    CHECK(paintPanel(tint, true, Qt::transparent) == QColor(0, 0, 0, 0));
    CHECK(paintPanel(tint, false, Qt::transparent) == QColor(0, 0, 0, 0));
    CHECK(paintPanel(tint, true, QColor(240, 240, 240)) == QColor(240, 240, 240));
    CHECK(paintPanel(tint, false, QColor(240, 240, 240)) == QColor(Qt::red));
    CHECK(!tint.update(emptyTarget, {}));
    CHECK(!tint.update(emptyTarget, QRect(-1, 0, 32, 4)));
    CHECK(!tint.update(emptyTarget, QRect(0, 0, 8, 4)));

    glBindFramebuffer(GL_FRAMEBUFFER, emptyFbo.handle());
    const GLfloat black[4] = {0, 0, 0, 1};
    glClearBufferfv(GL_COLOR, 0, black);
    CHECK(tint.update(emptyTarget, QRect(0, 0, 32, 4)));
    CHECK(paintPanel(tint, true, Qt::transparent) == QColor(0, 0, 0));
    CHECK(paintPanel(tint, false, Qt::transparent) == QColor(Qt::red));
    CHECK(paintPanel(tint, true, Qt::transparent, 128) == QColor(0, 0, 0, 128));
    CHECK(paintPanel(tint, false, Qt::transparent, 128) == QColor(128, 0, 0, 128));

    // Multiple windows reuse one scratch color. Queue both panels before any
    // CPU read to prove a later window cannot recolor an earlier draw.
    const auto blackPanel = drawPanel(tint, true, Qt::transparent);
    glBindFramebuffer(GL_FRAMEBUFFER, emptyFbo.handle());
    const GLfloat white[4] = {1, 1, 1, 1};
    glClearBufferfv(GL_COLOR, 0, white);
    CHECK(tint.update(emptyTarget, QRect(0, 0, 32, 4)));
    const auto whitePanel = drawPanel(tint, true, Qt::transparent);
    CHECK(readPixel(blackPanel.get()) == QColor(Qt::black));
    CHECK(readPixel(whitePanel.get()) == QColor(Qt::white));

    glBindFramebuffer(GL_FRAMEBUFFER, emptyFbo.handle());
    glClearBufferfv(GL_COLOR, 0, black);
    glEnable(GL_SCISSOR_TEST);
    glScissor(0, 0, 32, 1);
    glClearBufferfv(GL_COLOR, 0, zero);
    CHECK(tint.update(emptyTarget, QRect(0, 0, 32, 4)));
    CHECK(paintPanel(tint, true, Qt::transparent) == QColor(0, 0, 0)); // 75% opaque.
    glBindFramebuffer(GL_FRAMEBUFFER, emptyFbo.handle());
    glEnable(GL_SCISSOR_TEST);
    glScissor(0, 1, 32, 1);
    glClearBufferfv(GL_COLOR, 0, zero);
    CHECK(tint.update(emptyTarget, QRect(0, 0, 32, 4)));
    CHECK(paintPanel(tint, true, Qt::transparent) == QColor(0, 0, 0, 0)); // 50% is unusable.

    GLuint invalidFbo = 0, integerTexture = 0;
    glGenFramebuffers(1, &invalidFbo);
    {
        KWin::GLFramebuffer wrapper(invalidFbo, QSize(32, 4));
        KWin::RenderTarget target(&wrapper);
        CHECK(!tint.update(target, QRect(0, 0, 32, 4)));
        glGenTextures(1, &integerTexture);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, integerTexture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8UI, 32, 4, 0, GL_RGBA_INTEGER, GL_UNSIGNED_BYTE, nullptr);
        glBindFramebuffer(GL_FRAMEBUFFER, invalidFbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, integerTexture, 0);
        CHECK(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);
        CHECK(!tint.update(target, QRect(0, 0, 32, 4)));
    }
    glDeleteTextures(1, &integerTexture);
    glDeleteFramebuffers(1, &invalidFbo);
    CHECK(glGetError() == GL_NO_ERROR);
    if (application.arguments().contains(QStringLiteral("--benchmark"))) {
        auto texture = KWin::GLTexture::allocate(GL_RGBA8, QSize(160, 8));
        KWin::GLFramebuffer fbo(texture.get());
        KWin::RenderTarget target(&fbo);
        glBindFramebuffer(GL_FRAMEBUFFER, fbo.handle());
        glDisable(GL_SCISSOR_TEST);
        glClearBufferfv(GL_COLOR, 0, black);
        glFinish(); // Test timing only; production never waits.
        QElapsedTimer timer;
        timer.start();
        for (int i = 0; i < 1000; ++i) CHECK(tint.update(target, QRect(0, 0, 160, 8)));
        glFinish();
        std::printf("1000 maximum-gutter copies/reductions: %.1f us each (excludes window/panel painting)\n",
            double(timer.nsecsElapsed()) / 1000000.0);
    }
    std::printf("%d same-frame GPU checks, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}
