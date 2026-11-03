#include "titlebarreadback.h"

#include <cstring>

namespace KOS
{

TitlebarReadback::~TitlebarReadback()
{
    discard();
    if (m_buffer) glDeleteBuffers(1, &m_buffer);
}

void TitlebarReadback::discard()
{
    if (m_fence) glDeleteSync(m_fence);
    m_fence = nullptr;
}

bool TitlebarReadback::enqueue(GLuint framebuffer, const QSize &targetSize, const QRect &rect)
{
    if (pending() || rect.isEmpty()
        || !QRect(QPoint(), targetSize).contains(rect)) return false;

    GLint previousFbo = 0, previousBuffer = 0;
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &previousFbo);
    glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &previousBuffer);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, framebuffer);
    if (glCheckFramebufferStatus(GL_READ_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        glBindFramebuffer(GL_READ_FRAMEBUFFER, previousFbo);
        return false;
    }
    GLint sourceReadBuffer = 0;
    glGetIntegerv(GL_READ_BUFFER, &sourceReadBuffer);
    if (framebuffer) {
        GLint attachment = GL_NONE;
        glGetFramebufferAttachmentParameteriv(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                              GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, &attachment);
        if (attachment == GL_NONE) {
            glBindFramebuffer(GL_READ_FRAMEBUFFER, previousFbo);
            return false;
        }
        glReadBuffer(GL_COLOR_ATTACHMENT0);
    }
    // A caller may leave pack strides/skips configured. A tightly sized PBO
    // must not inherit those (including the previously bound pack buffer).
    constexpr GLenum PackNames[] = {GL_PACK_ALIGNMENT, GL_PACK_ROW_LENGTH,
                                    GL_PACK_SKIP_ROWS, GL_PACK_SKIP_PIXELS};
    GLint pack[4];
    for (int i = 0; i < 4; ++i) {
        glGetIntegerv(PackNames[i], &pack[i]);
        glPixelStorei(PackNames[i], i == 0 ? 1 : 0);
    }
    if (!m_buffer) glGenBuffers(1, &m_buffer);
    glBindBuffer(GL_PIXEL_PACK_BUFFER, m_buffer);
    m_bytes = qsizetype(rect.width()) * rect.height() * 4;
    // Failed reads must leave transparent pixels, not undefined buffer bytes
    // which can look like an opaque black titlebar. Reuse bounded zero storage
    // while still orphaning the GPU buffer; never wait for its previous fence.
    if (m_clearPixels.size() != m_bytes) m_clearPixels = QByteArray(m_bytes, '\0');
    glBufferData(GL_PIXEL_PACK_BUFFER, m_bytes, m_clearPixels.constData(), GL_STREAM_READ);
    glReadPixels(rect.x(), targetSize.height() - rect.y() - rect.height(),
                 rect.width(), rect.height(), GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    m_fence = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
    glBindBuffer(GL_PIXEL_PACK_BUFFER, previousBuffer);
    if (framebuffer) glReadBuffer(sourceReadBuffer);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, previousFbo);
    for (int i = 0; i < 4; ++i) glPixelStorei(PackNames[i], pack[i]);
    // Submit without waiting; even a static window must eventually finish.
    glFlush();
    return pending();
}

bool TitlebarReadback::take(QByteArray &pixels)
{
    if (!pending()) return false;
    const GLenum status = glClientWaitSync(m_fence, 0, 0);
    if (status == GL_TIMEOUT_EXPIRED) return false;
    discard();
    if (status == GL_WAIT_FAILED) return false;

    GLint previousBuffer = 0;
    glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &previousBuffer);
    glBindBuffer(GL_PIXEL_PACK_BUFFER, m_buffer);
    const void *data = glMapBufferRange(GL_PIXEL_PACK_BUFFER, 0, m_bytes, GL_MAP_READ_BIT);
    bool ok = false;
    if (data) {
        pixels.resize(m_bytes);
        std::memcpy(pixels.data(), data, size_t(m_bytes));
        ok = glUnmapBuffer(GL_PIXEL_PACK_BUFFER) == GL_TRUE;
    }
    glBindBuffer(GL_PIXEL_PACK_BUFFER, previousBuffer);
    if (!ok) pixels.clear();
    return ok;
}

} // namespace KOS
