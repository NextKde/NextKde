#include "appearanceshadow.h"

#include <QPainter>
#include <QPainterPath>

#include <algorithm>
#include <cmath>

namespace KOS::WindowAppearance
{

qreal shadowMargin(qreal scale, qreal blur, qreal spread)
{
    return std::ceil((blur * 1.1 + spread + 2.0) * scale);
}

qreal edgeMargin(qreal scale, const EdgeStyle &style)
{
    return std::ceil((std::max<qreal>(0.0, style.frameWidth)
                      + std::max<qreal>(0.0, style.outlineWidth) / 2.0 + 2.0)
                     * scale);
}

namespace
{

// The shadow is stroked in layers from the outside in, into a DOWNSAMPLED
// image: the blur it simulates is smoother than the downsample factor, so
// the texture is built at a quarter of the device resolution and the GPU's
// linear filter upscales it on the way to the screen. A full-resolution
// raster of a maximized window's shadow is tens of megabytes stroked in
// dozens of antialiased passes -- built synchronously in the paint pass it
// stalls the compositor for hundreds of milliseconds per window, which
// reads as the session hanging. At a quarter resolution the cost drops by
// roughly that squared, the falloff only gets smoother, and no banding
// survives the upscale.
constexpr int ShadowLayers = 14;
constexpr int ShadowDownsample = 4;

// The falloff the shadow follows, as a function of the distance beyond the
// contour, in units of the extent. This is the shape a one-pass gaussian
// blur of a hard-edged shape produces: half coverage at the edge itself,
// falling to effectively nothing at the truncation point.
constexpr qreal FalloffTruncation = 2.6;
qreal falloff(qreal fraction)
{
    const qreal z = fraction * FalloffTruncation;
    return 0.5 * std::exp(-0.5 * z * z);
}

} // namespace

ShadowImage shadowImage(const QSizeF &logicalSize, qreal scale,
                        const CornerRadii &radii, qreal smoothness,
                        qreal blur, qreal spread, const QColor &color)
{
    ShadowImage result;
    if (logicalSize.isEmpty() || (blur <= 0.0 && spread <= 0.0)
        || color.alpha() <= 0) {
        return result;
    }

    // The shadow reaches blur/2 meaningfully in each direction (the falloff
    // is cut where it drops under 8-bit alpha) plus the spread. A little
    // slack keeps the antialiased edge of the outermost stroke inside the
    // image.
    const qreal margin = shadowMargin(scale, blur, spread);
    result.margin = margin;

    const QSizeF scaledSize = logicalSize * scale;
    const QSizeF deviceSize(scaledSize.width() + 2.0 * margin,
                            scaledSize.height() + 2.0 * margin);
    // The raster is built at 1/ShadowDownsample of the device size; the
    // caller's blit stretches it back over the full texture rect and the
    // GL_LINEAR filter does the upscale. Everything below is therefore
    // drawn in full device coordinates and shrunk by the painter transform,
    // so the geometry, the pen widths and the margins keep their meaning.
    const QSize rasterSize(std::max(1, int(deviceSize.width())
                                       / ShadowDownsample),
                           std::max(1, int(deviceSize.height())
                                       / ShadowDownsample));
    QImage image(rasterSize, QImage::Format_ARGB32_Premultiplied);
    if (image.isNull()) {
        result.image = QImage();
        result.margin = 0.0;
        return result;
    }
    image.fill(Qt::transparent);

    // The rect the shadow contour lives in, inside the image: the window
    // rect moved in by the margin, and grown by the spread -- spreading a
    // shadow means moving the contour outward, not softening it further.
    const QRectF windowRect(margin, margin, scaledSize.width(),
                            scaledSize.height());
    const qreal spreadDevice = std::max<qreal>(0.0, spread) * scale;
    const QRectF shadowRect = spreadDevice > 0.0
        ? windowRect.adjusted(-spreadDevice, -spreadDevice, spreadDevice,
                              spreadDevice)
        : windowRect;
    const CornerRadii spreadRadii{
        radii.topLeft + spreadDevice, radii.topRight + spreadDevice,
        radii.bottomRight + spreadDevice, radii.bottomLeft + spreadDevice};
    const QPainterPath contour =
        WindowAppearance::contourPath(shadowRect, spreadRadii, smoothness);

    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.setPen(Qt::NoPen);
    painter.scale(1.0 / ShadowDownsample, 1.0 / ShadowDownsample);

    // Strokes from the outermost (widest, faintest) inward. The strokes
    // over-blend, so each layer's alpha is not the falloff value itself but
    // the increment that carries the ACCUMULATED alpha to the falloff at
    // this layer's outer reach: stroking the gaussian weights directly
    // saturates to a near-opaque rim at the contour, which is not a falloff
    // at all. What shows beyond the contour at distance d is the composite
    // of every layer whose reach exceeds d -- a half-covered soft edge
    // fading out over the extent, exactly what a one-pass blur gives.
    QColor layerColor = color;
    const qreal extent = std::max<qreal>(0.0, blur) * 1.1 * scale;
    qreal transparency = 1.0;
    for (int i = ShadowLayers; i >= 1; --i) {
        const qreal fraction = qreal(i) / qreal(ShadowLayers);
        const qreal halfWidth = extent * fraction;
        const qreal target = falloff(fraction);
        // The composite after this layer must read `target`; the layers
        // outside it already composite to `1 - transparency`.
        const qreal alpha =
            qBound(0.0, 1.0 - (1.0 - target) / transparency, 1.0);
        if (alpha <= 0.0) {
            continue;
        }
        layerColor.setAlphaF(color.alphaF() * alpha);
        QPen pen(layerColor);
        pen.setWidthF(std::max(1.0, halfWidth * 2.0));
        pen.setCapStyle(Qt::FlatCap);
        pen.setJoinStyle(Qt::RoundJoin);
        painter.setPen(pen);
        painter.drawPath(contour);
        transparency *= 1.0 - alpha;
    }

    // The shadow exists only outside the contour. The strokes cover the
    // inside of it too, and whatever lands there shows through the corner
    // notches the rounding cuts out of the window and through any
    // translucent content -- a band of shadow drawn over pixels that belong
    // to the window. Cut the interior away: what remains is an outer shadow,
    // the shape a box shadow has, with the falloff outside the contour
    // untouched.
    painter.setCompositionMode(QPainter::CompositionMode_DestinationOut);
    painter.setPen(Qt::NoPen);
    painter.fillPath(contour, QColor(Qt::black));
    painter.setCompositionMode(QPainter::CompositionMode_SourceOver);
    painter.end();

    result.image = image;
    return result;
}

EdgeImage edgeOverlayImage(const QSizeF &logicalSize, qreal scale,
                           const CornerRadii &radii, qreal smoothness,
                           const EdgeStyle &style)
{
    EdgeImage result;
    const qreal frameWidth = std::max<qreal>(0.0, style.frameWidth);
    const qreal outlineWidth = std::max<qreal>(0.0, style.outlineWidth);
    if (logicalSize.isEmpty()
        || (frameWidth <= 0.0 && outlineWidth <= 0.0)) {
        return result;
    }

    // The frame band lives entirely outside the window rect; the outline is
    // centred on the window contour, so half of it is outside too. The image
    // must hold the frame band plus the outer half of the outline.
    const qreal margin = edgeMargin(scale, style);
    result.margin = margin;

    const QSizeF scaledSize = logicalSize * scale;
    const QSizeF deviceSize(scaledSize.width() + 2.0 * margin,
                            scaledSize.height() + 2.0 * margin);
    QImage image(deviceSize.toSize(), QImage::Format_ARGB32_Premultiplied);
    if (image.isNull()) {
        result.image = QImage();
        result.margin = 0.0;
        return result;
    }
    image.fill(Qt::transparent);

    const QRectF windowRect(margin, margin, scaledSize.width(),
                            scaledSize.height());
    const QPainterPath contour =
        WindowAppearance::contourPath(windowRect, radii, smoothness);

    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.setPen(Qt::NoPen);

    if (frameWidth > 0.0) {
        // The band: the contour of the rectangle grown by the frame width,
        // minus the window contour itself. The subtraction is what keeps the
        // band off the window's own pixels -- the window is drawn after this
        // overlay anyway, but a hollow band also means the outline and the
        // band compose like two strokes instead of one overpainting the
        // other.
        const QRectF outerRect = windowRect.adjusted(
            -frameWidth * scale, -frameWidth * scale, frameWidth * scale,
            frameWidth * scale);
        // The outer contour carries the inner radius grown by the band
        // width: the offset curve of the inner contour, which is what makes
        // the band read as a uniform-width ring following one curve rather
        // than two unrelated ones.
        const CornerRadii outerRadii{
            radii.topLeft + frameWidth * scale,
            radii.topRight + frameWidth * scale,
            radii.bottomRight + frameWidth * scale,
            radii.bottomLeft + frameWidth * scale,
        };
        const QPainterPath outerContour =
            WindowAppearance::contourPath(outerRect, outerRadii, smoothness);

        QColor bandColor = style.frameColor;
        bandColor.setAlphaF(std::min<qreal>(1.0, bandColor.alphaF()));
        painter.fillPath(outerContour, bandColor);
        // Hollow the band out along the window contour.
        painter.setCompositionMode(QPainter::CompositionMode_DestinationOut);
        painter.fillPath(contour, QColor(Qt::black));
        painter.setCompositionMode(QPainter::CompositionMode_SourceOver);
    }

    if (outlineWidth > 0.0) {
        QColor strokeColor = style.outlineColor;
        QPen pen(strokeColor);
        pen.setWidthF(outlineWidth * scale);
        pen.setCapStyle(Qt::FlatCap);
        pen.setJoinStyle(Qt::RoundJoin);
        painter.setPen(pen);
        painter.setBrush(Qt::NoBrush);
        painter.drawPath(contour);
    }
    painter.end();

    result.image = image;
    return result;
}

} // namespace KOS::WindowAppearance
