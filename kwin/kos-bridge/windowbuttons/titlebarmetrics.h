#pragma once

#include "titlebarreadback.h"
#include <QColor>
#include <QRectF>
#include <QRegion>

namespace KWin
{
class EffectWindow;
class RenderTarget;
class RenderViewport;
class Region;
}

namespace KOS
{

// Asynchronous counterpart of the upstream readTitlebarPixels helper. Enqueue
// accepts untransformed, top-down texture coordinates; take normalizes the
// captured FBO's flip/rotation back to that same orientation. The GL context
// must be current throughout this object's lifetime, including destruction.
class TitlebarPixelReadback
{
public:
    bool enqueue(const KWin::RenderTarget &target, const QRect &rect);
    bool take(QByteArray &pixels);
    bool pending() const { return m_readback.pending(); }
    void discard() { m_readback.discard(); }
    QRect rect() const { return m_rect; }

private:
    TitlebarReadback m_readback;
    QRect m_rect;
    QRect m_bufferRect;
    QPoint m_origin, m_stepX, m_stepY;
    QByteArray m_rawPixels;
};

// Per-window, bounded asynchronous readback. The panel's position remains
// configuration-driven; only its tint is measured, never inferred controls.
class TitlebarSampler
{
public:
    ~TitlebarSampler();
    bool enqueue(const KWin::RenderTarget &renderTarget,
                 const KWin::RenderViewport &viewport,
                 KWin::EffectWindow *window, const KWin::Region &deviceClip,
                 const QRectF &panel, const QRectF &cover);
    bool take(bool *dark, QColor *color);
    bool pending() const { return m_readback.pending(); }
    void discard() { m_readback.discard(); }
    qreal backgroundBottom() const { return m_backgroundBottom; }
    QRectF probeRect() const { return m_probeRect; }

private:
    TitlebarPixelReadback m_readback;
    QRect m_rect;
    QRegion m_visible;
    bool m_fallback = false;
    QRect m_tintRect;
    qreal m_deviceScale = 1;
    qreal m_probeTop = 0;
    qreal m_backgroundBottom = -1;
    QRectF m_probeRect;
    QByteArray m_pixels;
};

} // namespace KOS
