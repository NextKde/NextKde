#include "titlebarmetrics.h"

#include <effect/effectwindow.h>
#include <core/region.h>
#include <core/rendertarget.h>
#include <core/renderviewport.h>
#include <opengl/glframebuffer.h>

#include <QByteArray>
#include <QRect>
#include <QSize>

#include <algorithm>
#include <vector>

#include <epoxy/gl.h>

namespace KOS
{
namespace
{

// Fewest pixels worth taking a median of. Below this the sample is a handful
// of glyph edges or antialiased corners rather than a background.
constexpr int MinSamples = 64;

// A pixel counts as dark below this luma. Same threshold QColor uses for
// QColor::lightness() < 128, so a "dark" panel is the one a theme would call
// dark.
constexpr int DarkThreshold = 128;

// A pixel below this alpha is not part of any window.
//
// The scene's render target is cleared to transparent, so a window that has
// been mapped but has not painted yet -- or a region no window covers -- reads
// back as (0, 0, 0, 0). By luma alone that is indistinguishable from a
// genuinely black title bar, and taking it would decide "dark" for a window
// whose bar is white. Alpha is what tells the two apart, so a sample has to
// have one. A target without an alpha channel reads back as fully opaque and
// is unaffected.
constexpr int MinAlpha = 128;

// Rec.709 luma, matching PixelBlock. GL_RGBA readback is R,G,B,A.
int lumaOf(const uchar *p)
{
    return (54 * p[0] + 183 * p[1] + 19 * p[2]) >> 8;
}

// Read a rect out of the render target currently bound, in the render target's
// own coordinates. `readRect` receives the rect actually read, which is `rect`
// clipped to the target.
bool readPixels(const KWin::RenderTarget &renderTarget, const QRect &rect,
                QByteArray &out, QRect *readRect)
{
    const QSize targetSize = renderTarget.transformedSize();
    const QRect r = rect.intersected(QRect(QPoint(0, 0), targetSize));
    if (r.isEmpty()) {
        return false;
    }

    if (auto *fbo = renderTarget.framebuffer()) {
        glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo->handle());
    }

    out.resize(r.width() * r.height() * 4);
    // No y-flip. KWin renders the scene into its render targets y-down -- row 0
    // of the target is the top row of the output -- and glReadPixels' row
    // argument is that same row index. The usual "OpenGL's origin is
    // bottom-left" rule belongs to client textures and to the default
    // framebuffer, and applying it here is not a harmless slip: it mirrors the
    // band about the middle of the target, so the tint gets read from whatever
    // happens to sit at the mirrored position -- usually the desktop below the
    // window, which is why panels came out dark on light title bars.
    glReadPixels(r.x(), r.y(), r.width(), r.height(), GL_RGBA, GL_UNSIGNED_BYTE,
                 out.data());
    *readRect = r;
    return true;
}

} // namespace

bool sampleTitlebarTint(const KWin::RenderTarget &renderTarget,
                        const KWin::RenderViewport &viewport,
                        KWin::EffectWindow *window,
                        const KWin::Region &deviceClip,
                        const QRectF &panelRect,
                        bool *dark)
{
    if (!window || !dark || panelRect.height() < 2.0) {
        return false;
    }

    const QRectF frame = window->frameGeometry();
    if (frame.width() < 8.0 || frame.height() < 8.0) {
        return false;
    }

    // The panel's own rows, across the whole window: the bar's background
    // dominates that band even when the caption and the application's controls
    // are inside it, and the two of them are excluded below anyway.
    const QRectF bandLogical(frame.x(), frame.y() + panelRect.y(),
                             frame.width(), panelRect.height());
    const QRectF panelLogical(frame.x() + panelRect.x(),
                              frame.y() + panelRect.y(),
                              panelRect.width(), panelRect.height());

    // Two mappings of the same rectangle, because two spaces are in play.
    // `deviceClip` comes from the compositor, so the clip test has to be in
    // device coordinates; the read has to be in the render target's own
    // coordinates. On a single output the two coincide, which is exactly what
    // makes mixing them up look like it works -- so ask KWin for each instead
    // of deriving one from the other.
    const QRect bandDevice =
        viewport.mapToDeviceCoordinatesAligned(bandLogical);
    const QRect bandTarget =
        viewport.mapToRenderTargetTexture(bandLogical).toAlignedRect();
    const QRect panelDevice =
        viewport.mapToDeviceCoordinatesAligned(panelLogical);
    if (bandTarget.width() < 8 || bandTarget.height() < 2) {
        return false;
    }

    QByteArray pixels;
    QRect readTarget;
    if (!readPixels(renderTarget, bandTarget, pixels, &readTarget)) {
        return false;
    }

    // Where the part that was actually read sits in device space: everything
    // the read gave up (clipping to the target) is relative to the request, so
    // the shift between the two mappings is what carries over.
    const QPoint shift = readTarget.topLeft() - bandTarget.topLeft();
    const QRect readDevice(bandDevice.topLeft() + shift,
                           QSize(readTarget.width(), readTarget.height()));

    // Whatever the panel will cover is not a sample of the bar, and neither is
    // the caption, whose glyphs are far higher contrast than the background
    // they sit on.
    const int panelFrom = panelDevice.x() - readDevice.x();
    const int panelTo = panelFrom + panelDevice.width();
    const int third = readTarget.width() / 3;

    std::vector<int> samples;
    samples.reserve(size_t(readTarget.width()) * size_t(readTarget.height()));
    for (int y = 0; y < readTarget.height(); ++y) {
        const uchar *row = reinterpret_cast<const uchar *>(pixels.constData())
            + size_t(y) * size_t(readTarget.width()) * 4;
        const int deviceY = readDevice.y() + y;
        for (int x = 0; x < readTarget.width(); ++x) {
            const uchar *p = row + size_t(x) * 4;
            if (p[3] < MinAlpha) {
                continue;
            }
            if (x >= panelFrom && x < panelTo) {
                continue;
            }
            if (third > 4 && x >= third && x < 2 * third) {
                continue;
            }
            // Pixels outside the visible region belong to whatever window is
            // stacked above, not to this title bar. Reading past them would
            // tint the panel from a different window.
            if (!deviceClip.contains(QPoint(readDevice.x() + x, deviceY))) {
                continue;
            }
            samples.push_back(lumaOf(p));
        }
    }
    if (int(samples.size()) < MinSamples) {
        return false;
    }

    const size_t middle = samples.size() / 2;
    std::nth_element(samples.begin(), samples.begin() + middle, samples.end());
    *dark = samples[middle] < DarkThreshold;
    return true;
}

} // namespace KOS
