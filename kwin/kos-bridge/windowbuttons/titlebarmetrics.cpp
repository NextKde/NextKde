#include "titlebarmetrics.h"
#include "titlebartint.h"

#include <effect/effecthandler.h>
#include <effect/effectwindow.h>
#include <core/region.h>
#include <core/rendertarget.h>
#include <core/renderviewport.h>
#include <opengl/glframebuffer.h>

#include <algorithm>

namespace KOS
{

bool TitlebarPixelReadback::enqueue(const KWin::RenderTarget &target, const QRect &rect)
{
    if (pending() || !target.framebuffer()) return false;
    const QSize bounds = target.transformedSize();
    const QRect clipped = rect.intersected(QRect(QPoint(), bounds));
    if (clipped.isEmpty()) return false;
    const auto transform = target.transform();
    const QRect bufferRect = transform.map(KWin::Rect(clipped), bounds);
    if (!m_readback.enqueue(target.framebuffer()->handle(), target.size(), bufferRect)) return false;

    // Preserve upstream's pixel-center mapping: edges are off by one for
    // mirrors, and DRM FlipY is not the same as GL's bottom-up row order.
    const QPointF origin = transform.map(QPointF(clipped.x() + 0.5, clipped.y() + 0.5), QSizeF(bounds));
    const QPointF stepX = transform.map(QPointF(clipped.x() + 1.5, clipped.y() + 0.5), QSizeF(bounds)) - origin;
    const QPointF stepY = transform.map(QPointF(clipped.x() + 0.5, clipped.y() + 1.5), QSizeF(bounds)) - origin;
    m_origin = QPoint(int(origin.x()) - bufferRect.x(), bufferRect.bottom() - int(origin.y()));
    m_stepX = QPoint(qRound(stepX.x()), -qRound(stepX.y()));
    m_stepY = QPoint(qRound(stepY.x()), -qRound(stepY.y()));
    m_rect = clipped;
    m_bufferRect = bufferRect;
    return true;
}

bool TitlebarPixelReadback::take(QByteArray &pixels)
{
    QByteArray raw;
    if (!m_readback.take(raw)) return false;
    pixels.resize(m_rect.width() * m_rect.height() * 4);
    for (int y = 0; y < m_rect.height(); ++y) {
        for (int x = 0; x < m_rect.width(); ++x) {
            const QPoint source = m_origin + x * m_stepX + y * m_stepY;
            const qsizetype offset = (qsizetype(source.y()) * m_bufferRect.width() + source.x()) * 4;
            std::copy_n(raw.constData() + offset, 4,
                        pixels.data() + (qsizetype(y) * m_rect.width() + x) * 4);
        }
    }
    return true;
}

TitlebarSampler::~TitlebarSampler()
{
    // Cache eviction also happens on window close/config reload, outside paint.
    if (KWin::effects) KWin::effects->makeOpenGLContextCurrent();
}

bool TitlebarSampler::enqueue(const KWin::RenderTarget &renderTarget,
                              const KWin::RenderViewport &viewport,
                              KWin::EffectWindow *window, const KWin::Region &deviceClip,
                              const QRectF &panel)
{
    if (pending() || !window || panel.height() < 2) return false;
    const QRectF frame = window->frameGeometry();
    if (frame.width() < 8 || frame.height() < 8) return false;
    const QRectF bandLogical(frame.x(), frame.y() + panel.y(), frame.width(), panel.height());
    const QRect bandDevice = viewport.mapToDeviceCoordinatesAligned(bandLogical);
    const QRect bandTarget = viewport.mapToRenderTargetTexture(bandLogical).toAlignedRect();
    const QPoint offset = bandTarget.topLeft() - bandDevice.topLeft();
    const QRect panelTarget = viewport.mapToDeviceCoordinatesAligned(panel.translated(frame.topLeft()))
                                  .translated(offset);
    // Clip in device space first, then translate to the target. This preserves
    // the secondary-output / offscreen-target origin, not just output zero.
    QRegion visible;
    // Source captures use Region::infinite(); bound it before converting KWin's
    // coordinates to Qt's finite integer rectangles.
    const KWin::Region boundedClip = deviceClip & KWin::Region(KWin::Rect(bandDevice));
    for (const auto &rect : boundedClip.rects()) {
        visible += QRect(rect.x(), rect.y(), rect.width(), rect.height());
    }
    visible.translate(offset);
    const QRect targetBounds(QPoint(), renderTarget.transformedSize());
    for (int attempt = 0; attempt < 2; ++attempt) {
        m_rect = tintSampleRect(bandTarget, panelTarget, m_fallback).intersected(targetBounds);
        m_visible = visible.intersected(m_rect);
        qsizetype count = 0;
        for (const QRect &rect : m_visible) count += qsizetype(rect.width()) * rect.height();
        if (count >= TintHistogram::MinSamples) {
            return m_readback.enqueue(renderTarget, m_rect);
        }
        m_fallback = !m_fallback;
    }
    return false;
}

bool TitlebarSampler::take(bool *dark, QColor *color)
{
    QByteArray pixels;
    if (!m_readback.take(pixels)) return false;
    TintHistogram histogram;
    // Visit visible spans, not a QRegion::contains lookup for every pixel.
    for (const QRect &rect : m_visible) {
        for (int y = rect.y(); y < rect.y() + rect.height(); ++y) {
            const auto *row = reinterpret_cast<const uchar *>(pixels.constData())
                + qsizetype(y - m_rect.y()) * m_rect.width() * 4;
            for (int x = rect.x(); x < rect.x() + rect.width(); ++x) {
                histogram.add(row + (x - m_rect.x()) * 4);
            }
        }
    }
    const bool usable = histogram.tint(dark, color);
    // A transparent/unpainted local strip can fall back on the next attempt,
    // without a second transfer (or a synchronous wait) in this frame.
    m_fallback = usable ? false : !m_fallback;
    return usable;
}

} // namespace KOS
