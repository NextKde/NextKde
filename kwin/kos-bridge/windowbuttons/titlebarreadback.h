#pragma once

#include <QByteArray>
#include <QRect>
#include <epoxy/gl.h>

namespace KOS
{

// The caller owns the GL context and must make it current before destruction.
// Never map a busy buffer or wait for the compositor's GPU in its paint hook.
class TitlebarReadback
{
public:
    ~TitlebarReadback();
    TitlebarReadback() = default;
    TitlebarReadback(const TitlebarReadback &) = delete;
    TitlebarReadback &operator=(const TitlebarReadback &) = delete;

    bool enqueue(GLuint framebuffer, const QSize &targetSize, const QRect &rect);
    bool take(QByteArray &pixels);
    bool pending() const { return m_fence != nullptr; }
    void discard();

private:
    GLuint m_buffer = 0;
    GLsync m_fence = nullptr;
    qsizetype m_bytes = 0;
};

} // namespace KOS
