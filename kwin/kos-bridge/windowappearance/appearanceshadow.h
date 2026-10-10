#pragma once

#include <QColor>
#include <QImage>
#include <QSizeF>

#include "contour.h"

namespace KOS::WindowAppearance
{

// Everything here renders into premultiplied ARGB images in device pixels.
// They are uploaded once and cached by the renderer; nothing here touches a
// compositor, so the same builders can feed an offline preview later.
// The corner radii passed in are device pixels already -- multiply the
// logical radii by the viewport scale before calling.

// A soft shadow around the contour: the path stroked in concentric layers
// whose alpha falls off like a gaussian, which is what a one-pass blur would
// produce without costing one. The returned image is centred on the window
// rect and extends `margin` device pixels beyond it on every side, which the
// caller needs to know to place and clip the texture.
struct ShadowImage
{
    QImage image;
    // Device pixels the image extends beyond the window rect, on each side.
    qreal margin = 0.0;
};

ShadowImage shadowImage(const QSizeF &logicalSize, qreal scale,
                        const CornerRadii &radii, qreal smoothness,
                        qreal blur, qreal spread, const QColor &color);

// The edge overlay: the outer frame band (a filled ring just outside the
// window rect, following the same contour) plus the outline stroke centred on
// the window contour itself. Either width may be zero. The image is centred
// on the window rect and extends `margin` device pixels beyond it.
struct EdgeImage
{
    QImage image;
    qreal margin = 0.0;
};

struct EdgeStyle
{
    qreal frameWidth = 0.0;   // logical
    qreal outlineWidth = 0.0; // logical
    QColor frameColor;
    QColor outlineColor;
};

qreal shadowMargin(qreal scale, qreal blur, qreal spread);
qreal edgeMargin(qreal scale, const EdgeStyle &style);

EdgeImage edgeOverlayImage(const QSizeF &logicalSize, qreal scale,
                           const CornerRadii &radii, qreal smoothness,
                           const EdgeStyle &style);

} // namespace KOS::WindowAppearance
