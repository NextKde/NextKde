#include "windowbuttons/titlebarreadback.h"

#include <QGuiApplication>
#include <QOffscreenSurface>
#include <QOpenGLContext>
#include <QSurfaceFormat>
#include <QThread>
#include <cstdio>

using namespace KOS;
namespace
{
int checks = 0, failures = 0;
#define CHECK(expr) do { ++checks; if (!(expr)) { ++failures; std::fprintf(stderr, "%d: %s\n", __LINE__, #expr); } } while (false)
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    QSurfaceFormat format;
    format.setVersion(3, 3);
    format.setProfile(QSurfaceFormat::CoreProfile);
    QOpenGLContext context;
    context.setFormat(format);
    if (!context.create()) return 77;
    QOffscreenSurface surface;
    surface.setFormat(context.format());
    surface.create();
    if (!surface.isValid() || !context.makeCurrent(&surface)) return 77;
    std::printf("GL renderer: %s\n", glGetString(GL_RENDERER));

    GLuint fbo, texture, otherBuffer;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 64, 64, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
    CHECK(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);
    glClearColor(0, 0, 1, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    glEnable(GL_SCISSOR_TEST);
    glScissor(0, 48, 64, 16); // top 16 rows in the Qt/top-left coordinate system
    glClearColor(1, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    glDisable(GL_SCISSOR_TEST);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
    glGenBuffers(1, &otherBuffer);
    glBindBuffer(GL_PIXEL_PACK_BUFFER, otherBuffer);
    glBufferData(GL_PIXEL_PACK_BUFFER, 8192, nullptr, GL_STREAM_READ);
    glPixelStorei(GL_PACK_ALIGNMENT, 8);
    glPixelStorei(GL_PACK_ROW_LENGTH, 37);
    glPixelStorei(GL_PACK_SKIP_ROWS, 3);
    glPixelStorei(GL_PACK_SKIP_PIXELS, 2);
    {
        TitlebarReadback readback;
        CHECK(!readback.enqueue(fbo, QSize(64,64), QRect(-1,0,7,20)));
        for (int pass = 0; pass < 3; ++pass) {
            CHECK(readback.enqueue(fbo, QSize(64,64), QRect(3,4,7,20)));
            CHECK(readback.pending());
            CHECK(!readback.enqueue(fbo, QSize(64,64), QRect(0,0,1,1)));
            GLint value = 0;
            glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &value); CHECK(value == 0);
            glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &value); CHECK(GLuint(value) == fbo);
            glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &value); CHECK(GLuint(value) == otherBuffer);
            glGetIntegerv(GL_PACK_ALIGNMENT, &value); CHECK(value == 8);
            glGetIntegerv(GL_PACK_ROW_LENGTH, &value); CHECK(value == 37);
            glGetIntegerv(GL_PACK_SKIP_ROWS, &value); CHECK(value == 3);
            glGetIntegerv(GL_PACK_SKIP_PIXELS, &value); CHECK(value == 2);
            if (pass == 0) {
                readback.discard();
                CHECK(!readback.pending());
                continue; // orphan a potentially busy buffer and reuse it
            }
            QByteArray pixels;
            bool ready = false;
            for (int attempt = 0; attempt < 1000 && !ready; ++attempt) {
                ready = readback.take(pixels);
                if (!ready) QThread::msleep(1); // test driver only, never production
            }
            CHECK(ready && !readback.pending());
            CHECK(pixels.size() == 7*20*4);
            if (pixels.size() == 7*20*4) {
                for (int y = 0; y < 20; ++y) for (int x = 0; x < 7; ++x) {
                    const auto *p = reinterpret_cast<const uchar *>(pixels.constData()) + (y*7+x)*4;
                    // Bottom-up read: 8 lower blue rows, then 12 upper red rows.
                    CHECK(p[0] == (y < 8 ? 0 : 255) && p[1] == 0
                          && p[2] == (y < 8 ? 255 : 0) && p[3] == 255);
                }
            }
            glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &value); CHECK(GLuint(value) == otherBuffer);
            CHECK(!readback.take(pixels));
        }
        CHECK(glGetError() == GL_NO_ERROR);
    }
    glDeleteBuffers(1, &otherBuffer);
    glDeleteFramebuffers(1, &fbo);
    glDeleteTextures(1, &texture);
    std::printf("%d checks, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}
