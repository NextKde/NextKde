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
    // The usual output transform only flips GL's row order. Normalize that
    // in place, retaining the caller's allocation between observations.
    const bool straight = m_stepX == QPoint(1, 0) && m_bufferRect.size() == m_rect.size();
    if (straight && m_stepY == QPoint(0, 1) && m_origin == QPoint())
        return m_readback.take(pixels);
    if (straight && m_stepY == QPoint(0, -1) && m_origin == QPoint(0, m_rect.height() - 1)) {
        if (!m_readback.take(pixels)) return false;
        const qsizetype stride = qsizetype(m_rect.width()) * 4;
        auto *data = pixels.data();
        for (int y = 0; y < m_rect.height() / 2; ++y)
            std::swap_ranges(data + y * stride, data + (y + 1) * stride,
                             data + (m_rect.height() - y - 1) * stride);
        return true;
    }
    if (!m_readback.take(m_rawPixels)) return false;
    pixels.resize(m_rect.width() * m_rect.height() * 4);
    for (int y = 0; y < m_rect.height(); ++y) {
        for (int x = 0; x < m_rect.width(); ++x) {
            const QPoint source = m_origin + x * m_stepX + y * m_stepY;
            const qsizetype offset = (qsizetype(source.y()) * m_bufferRect.width() + source.x()) * 4;
            std::copy_n(m_rawPixels.constData() + offset, 4,
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
                              const QRectF &panel, const QRectF &cover)
{
    if (pending() || !window || panel.height() < 2) return false;
    const QRectF frame = window->frameGeometry();
    if (frame.width() < 8 || frame.height() < 8) return false;
    // The background gutter is anchored to the window top, not to the
    // controls' offset: that offset may land on an avatar or a second toolbar.
    const qreal probeHeight = std::min(frame.height(), std::max(panel.bottom(), cover.bottom()) + 4);
    const QRectF bandLogical(frame.x(), frame.y(), frame.width(), probeHeight);
    const QRect bandDevice = viewport.mapToDeviceCoordinatesAligned(bandLogical);
    const QRect bandTarget = viewport.mapToRenderTargetTexture(bandLogical).toAlignedRect();
    const QPoint offset = bandTarget.topLeft() - bandDevice.topLeft();
    m_deviceScale = bandTarget.height() / bandLogical.height();
    const QRect gutter(bandTarget.x(), bandTarget.y() + qRound(2 * m_deviceScale),
                       bandTarget.width(), std::max(2, qRound(3 * m_deviceScale)));
    // Exclude the entire independent cover, including all expanded edges,
    // even though the RGB gutter is anchored above the controls.
    const QRect panelTarget = viewport.mapToDeviceCoordinatesAligned(cover.translated(frame.topLeft()))
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
        m_tintRect = tintSampleRect(gutter, panelTarget, m_fallback).intersected(targetBounds);
        // Read a bounded vertical strip once, for both RGB and the cover's
        // bottom boundary. Never include the cover's own columns.
        const bool right = panelTarget.center().x() >= bandTarget.center().x();
        const int left = right ? std::max(bandTarget.left(), m_tintRect.right() - TintProbeWidth + 1) : m_tintRect.left();
        const int end = right ? m_tintRect.right() + 1 : std::min(bandTarget.right() + 1, left + TintProbeWidth);
        m_rect = QRect(left, bandTarget.y(), std::max(0, end - left),
                       std::min(TintProbeHeight, bandTarget.height())).intersected(targetBounds);
        m_probeTop = (m_rect.y() - bandTarget.y()) / m_deviceScale;
        m_probeRect = QRectF((m_rect.x() - bandTarget.x()) / m_deviceScale,
                             m_probeTop, m_rect.width() / m_deviceScale,
                             m_rect.height() / m_deviceScale);
        m_visible = visible.intersected(m_rect);
        qsizetype count = 0;
        for (const QRect &rect : m_visible) count += qsizetype(rect.width()) * rect.height();
        // A few damaged glyph pixels are not a representative titlebar strip.
        // Request a complete band on the next bounded refresh rather than
        // accepting a mostly occluded/undrawn strip as a black background.
        const quint64 required = std::max(quint64(TintHistogram::MinSamples),
            (quint64(m_rect.width()) * m_rect.height() * 3 + 3) / 4);
        if (quint64(count) >= required) {
            return m_readback.enqueue(renderTarget, m_rect);
        }
        m_fallback = !m_fallback;
    }
    return false;
}

bool TitlebarSampler::take(bool *dark, QColor *color)
{
    if (!m_readback.take(m_pixels)) return false;
    TintHistogram histogram;
    // Visit visible spans, not a QRegion::contains lookup for every pixel.
    for (const QRect &rect : m_visible.intersected(m_tintRect)) {
        for (int y = rect.y(); y < rect.y() + rect.height(); ++y) {
            const auto *row = reinterpret_cast<const uchar *>(m_pixels.constData())
                + qsizetype(y - m_rect.y()) * m_rect.width() * 4;
            for (int x = rect.x(); x < rect.x() + rect.width(); ++x) {
                histogram.add(row + (x - m_rect.x()) * 4);
            }
        }
    }
    const quint64 tintArea = quint64(m_tintRect.width()) * m_tintRect.height();
    const bool usable = histogram.tint(dark, color, (tintArea * 3 + 3) / 4);
    m_backgroundBottom = -1;
    if (usable && QRegion(m_rect).subtracted(m_visible).isEmpty()) {
        const int bottom = tintBackgroundBottom(reinterpret_cast<const uchar *>(m_pixels.constData()),
            m_rect.width(), m_rect.height(), *color, m_tintRect.bottom() - m_rect.y() + 1,
            qRound(3 * m_deviceScale));
        if (bottom < m_rect.height()) m_backgroundBottom = bottom / m_deviceScale + m_probeTop;
    }
    // A transparent/unpainted local strip can fall back on the next attempt,
    // without a second transfer (or a synchronous wait) in this frame.
    m_fallback = usable ? false : !m_fallback;
    return usable;
}

} // namespace KOS
