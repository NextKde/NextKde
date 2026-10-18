// Real GPU regression test for the production title-bar readback helper.
#include "../windowbuttons/titlebarmetrics.h"
#include <core/rendertarget.h>
#include <core/renderviewport.h>
#include <opengl/eglcontext.h>
#include <opengl/egldisplay.h>
#include <opengl/glframebuffer.h>
#include <opengl/gltexture.h>
#include <QCoreApplication>
#include <QByteArray>
#include <QThread>
#include <cstdio>
#include <cstdlib>
#include <epoxy/egl.h>
#include <epoxy/gl.h>

namespace {
GLuint compileShader(GLenum type, const char *source)
{
    const GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);
    GLint ok = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[4096];
        glGetShaderInfoLog(shader, sizeof(log), nullptr, log);
        std::fprintf(stderr, "%s\n", log);
        std::exit(1);
    }
    return shader;
}
}

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    auto display = KWin::EglDisplay::create(
        eglGetPlatformDisplayEXT(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, nullptr), nullptr);
    if (!display) return 77;
    auto context = KWin::EglContext::create(display.get(), EGL_NO_CONFIG_KHR, nullptr);
    if (!context || !context->makeCurrent()) return 77;
    std::printf("GPU: %s\n", glGetString(GL_RENDERER));
    std::printf("OpenGL: %s\n", glGetString(GL_VERSION));

    // KWin can create either a desktop GL or GLES context. Use the matching
    // shader language so the same readback cases run on both backends.
    const QByteArray shaderHeader = epoxy_is_desktop_gl()
        ? QByteArrayLiteral("#version 150\n")
        : QByteArrayLiteral("#version 300 es\nprecision highp float;\n");
    const QByteArray vertexSource = shaderHeader
        + "in vec2 position; uniform mat4 projection;"
          "uniform vec2 origin; uniform float scale; out vec2 pixel;"
          "void main(){pixel=(position-origin)*scale;gl_Position=projection*vec4(position*scale,0,1);}";
    const QByteArray fragmentSource = shaderHeader
        + "in vec2 pixel; out vec4 color;"
          "void main(){color=vec4(floor(pixel)/255.0,0,1);}";

    const GLuint vertex = compileShader(GL_VERTEX_SHADER, vertexSource.constData());
    const GLuint fragment = compileShader(GL_FRAGMENT_SHADER, fragmentSource.constData());
    const GLuint program = glCreateProgram();
    glAttachShader(program, vertex);
    glAttachShader(program, fragment);
    glBindAttribLocation(program, 0, "position");
    glLinkProgram(program);
    GLint linked = 0;
    glGetProgramiv(program, GL_LINK_STATUS, &linked);
    if (!linked) return 1;
    GLuint vao, vbo;
    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);
    glGenBuffers(1, &vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, nullptr);
    int failures = 0;
    int checks = 0;
    const QSize deviceSize(96, 64);
    for (int kind = 0; kind < 8; ++kind) {
        const KWin::OutputTransform transform(static_cast<KWin::OutputTransform::Kind>(kind));
        auto texture = KWin::GLTexture::allocate(GL_RGBA8, transform.map(deviceSize));
        if (!texture) return 1;
        texture->setContentTransform(transform);
        KWin::GLFramebuffer fbo(texture.get());
        if (!fbo.valid()) return 1;
        KWin::RenderTarget target(&fbo);
        KWin::GLFramebuffer::pushFramebuffer(&fbo);
        glViewport(0, 0, target.size().width(), target.size().height());
        glDisable(GL_BLEND);
        glDisable(GL_DITHER);
        glUseProgram(program);
        for (const float scale : {1.0f, 1.25f}) {
            const QPointF origin(-40, 20);
            KWin::RenderViewport viewport(KWin::RectF(origin, QSizeF(deviceSize) / scale), scale, target, QPoint());
            glUniformMatrix4fv(glGetUniformLocation(program, "projection"), 1, GL_FALSE,
                               viewport.projectionMatrix().constData());
            glUniform2f(glGetUniformLocation(program, "origin"), origin.x(), origin.y());
            glUniform1f(glGetUniformLocation(program, "scale"), scale);
            const float x = origin.x(), y = origin.y();
            const float w = deviceSize.width() / scale, h = deviceSize.height() / scale;
            const float vertices[] = {x,y, x+w,y, x,y+h, x+w,y, x+w,y+h, x,y+h};
            glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
            glDrawArrays(GL_TRIANGLES, 0, 6);
            const QRect interior = viewport.mapToRenderTargetTexture(
                KWin::RectF(origin + QPointF(8 / scale, 12 / scale), QSizeF(24 / scale, 16 / scale))).toAlignedRect();
            for (const QRect requested : {interior, QRect(-8,-4,32,24), QRect(80,48,32,24), QRect(200,200,8,8)}) {
                QByteArray pixels;
                QRect actual;
                // A different read FBO must be restored after the helper.
                glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
                KOS::TitlebarPixelReadback readback;
                bool ok = readback.enqueue(target, requested);
                if (ok) {
                    actual = readback.rect();
                    ok = false;
                    for (int attempt = 0; attempt < 1000 && !ok && readback.pending(); ++attempt) {
                        ok = readback.take(pixels);
                        if (!ok) QThread::msleep(1); // test driver only; production never waits
                    }
                }
                const QRect expected = requested.intersected(QRect(QPoint(), deviceSize));
                GLint restored = -1;
                glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &restored);
                bool correct = restored == 0 && ok == !expected.isEmpty();
                if (ok) {
                    correct &= actual == expected && pixels.size() == expected.width() * expected.height() * 4;
                    const auto *bytes = reinterpret_cast<const unsigned char *>(pixels.constData());
                    for (int row = 0; row < actual.height(); ++row) {
                        for (int col = 0; col < actual.width(); ++col) {
                            const int offset = (row * actual.width() + col) * 4;
                            if ((bytes[offset] != actual.x() + col || bytes[offset + 1] != actual.y() + row) && correct)
                                std::fprintf(stderr, "pixel (%d,%d): got (%u,%u), expected (%d,%d)\n", col, row, bytes[offset], bytes[offset+1],actual.x()+col,actual.y()+row);
                            correct &= bytes[offset] == actual.x() + col
                                && bytes[offset + 1] == actual.y() + row
                                && bytes[offset + 2] == 0 && bytes[offset + 3] == 255;
                        }
                    }
                }
                correct &= glGetError() == GL_NO_ERROR;
                ++checks;
                if (!correct) {
                    ++failures;
                    std::fprintf(stderr,"FAIL transform=%d scale=%.2f rect=(%d,%d,%d,%d)\n",
                                 kind, scale, requested.x(), requested.y(), requested.width(), requested.height());
                }
            }
        }
        KWin::GLFramebuffer::popFramebuffer();
    }
    glDeleteBuffers(1, &vbo);
    glDeleteVertexArrays(1, &vao);
    glDeleteProgram(program);
    glDeleteShader(vertex);
    glDeleteShader(fragment);
    std::printf("%d GPU readback cases, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}
