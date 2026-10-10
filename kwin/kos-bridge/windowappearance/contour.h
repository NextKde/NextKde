#pragma once

#include <QPainterPath>
#include <QRectF>
#include <QSizeF>
#include <QVector4D>

namespace KOS::WindowAppearance
{

// The unified window contour: one geometry definition shared by everything
// that has to follow the same curve -- the stroke, the outer frame band, the
// shadow and (through the same radius numbers) KWin's own window rounding.
// Nothing else in this module derives corner geometry independently; the
// contour is decided here and nowhere else.

// The four corner radii a window ends up with, after clamping and after the
// state constraints have been applied. Continuous paths interpret these as
// tangent extents; cornerExtent() converts a requested visual radius. The
// order matches KWin::BorderRadius.
struct CornerRadii
{
    qreal topLeft = 0.0;
    qreal topRight = 0.0;
    qreal bottomRight = 0.0;
    qreal bottomLeft = 0.0;

    bool isZero() const;
    QVector4D toVector() const;
};

// Largest radius a window of this size can carry: half the shorter edge.
qreal clampedRadius(const QSizeF &size, qreal radius);

// The superellipse exponent for a continuous amount in [0, 1]: 2 is the
// circle, higher values give zero curvature at the straight-edge joins. This mapping is shared
// by the contour paths (CPU) and the clip shader (GPU) so both draw the same
// curve; it is also the uniform the shader receives.
qreal curveExponent(qreal smoothness);

// A continuous corner starts bending earlier, while keeping the same
// diagonal inset as an arc of the requested radius.
qreal cornerExtent(qreal radius, qreal smoothness);

// The contour path for one rectangle. `smoothness` is the continuous-corner
// amount in [0, 1]: 0 gives plain quarter arcs, higher values draw the
// corner as cubic segments of a superellipse quadrant. Whether this approximation or a
// richer one becomes the shipped curve is decided by the sample review; it
// must not be described as Apple's private curve either way.
QPainterPath contourPath(const QRectF &rect, const CornerRadii &radii,
                         qreal smoothness);

// The contour path with one radius for all four corners.
QPainterPath contourPath(const QRectF &rect, qreal radius, qreal smoothness);

// The inset that keeps an axis-aligned rectangle fully inside the curve: how
// far from each edge the largest inscribed rectangle must stop. This is the
// number the content-protection modes hang off (protect mode pads by at least
// this much; compact mode knowingly goes without it). The circular-arc value
// is used as a conservative bound even for smoother corners, where the curve
// bulges outward and actually needs less.
qreal safeCornerInset(qreal radius);

} // namespace KOS::WindowAppearance
