#include "contour.h"

#include <QVector4D>

#include <algorithm>
#include <cmath>
#include <utility>

namespace KOS::WindowAppearance
{

qreal curveExponent(qreal smoothness)
{
    // 2 is the circle; the mapping gives 4 at full smoothness, the usual
    // squircle territory. Glass clamps the exponent the same way.
    const qreal clamped = std::min(std::max(smoothness, 0.0), 1.0);
    return 2.0 + 2.0 * clamped;
}

qreal cornerExtent(qreal radius, qreal smoothness)
{
    return radius * (1.0 - std::sqrt(0.5))
        / (1.0 - std::pow(0.5, 1.0 / curveExponent(smoothness)));
}

namespace
{

// Control-point distance of a quarter-circle approximated by one cubic
// Bézier: r * 4/3 * tan(pi/8), the classic kappa.
constexpr qreal CircleKappa = 0.5522847498307936;

// One corner, drawn from the end of the incoming straight edge to the start
// of the outgoing one. `corner` is the un-rounded corner point; `inDir`/
// `outDir` are the unit directions along the edges into and out of the corner
// (so the curve sits inside the rectangle).
void contourCorner(QPainterPath &path, const QPointF &corner, qreal radius,
                   qreal smoothness, const QPointF &inDir, const QPointF &outDir)
{
    if (radius <= 0.0) {
        // A square corner is the edge itself: no curve to add, the path just
        // passes through the corner point.
        path.lineTo(corner);
        return;
    }
    if (smoothness <= 0.0) {
        // The circular corner: one cubic with the classic kappa control
        // distance, which closely approximates the quarter arc.
        const QPointF start = corner - inDir * radius;
        const QPointF end = corner + outDir * radius;
        path.lineTo(start);
        path.cubicTo(start + inDir * (radius * CircleKappa),
                     end - outDir * (radius * CircleKappa), end);
        return;
    }

    // Cubic Hermite segments of the same superellipse used by the GPU.
    // Parameterize each half by its well-behaved coordinate, avoiding the
    // singular derivatives of the sin/cos parameterization at the endpoints.
    // For n > 2 curvature tends to zero at the straight-edge joins.
    const QPointF origin = corner - inDir * radius + outDir * radius;
    const qreal n = curveExponent(smoothness);
    path.lineTo(corner - inDir * radius);
    const qreal diagonal = std::pow(0.5, 1.0 / n);
    constexpr int segments = 8;
    const qreal step = diagonal / segments;
    for (int half = 0; half < 2; ++half) {
        auto pointAndTangent = [&](qreal t) {
            const qreal a = half == 0 ? t : diagonal - t;
            const qreal b = std::pow(std::max(0.0, 1.0 - std::pow(a, n)), 1.0 / n);
            const qreal slope = std::pow(a / b, n - 1.0);
            const qreal x = half == 0 ? a : b;
            const qreal y = half == 0 ? b : a;
            return std::pair{origin + radius * (inDir * x - outDir * y),
                radius * (half == 0 ? inDir + outDir * slope : inDir * slope + outDir)};
        };
        for (int k = 0; k < segments; ++k) {
            const auto [p0, tangent0] = pointAndTangent(k * step);
            const auto [p1, tangent1] = pointAndTangent((k + 1) * step);
            path.cubicTo(p0 + tangent0 * (step / 3.0),
                         p1 - tangent1 * (step / 3.0), p1);
        }
    }
}

} // namespace

bool CornerRadii::isZero() const
{
    return topLeft <= 0.0 && topRight <= 0.0 && bottomRight <= 0.0
        && bottomLeft <= 0.0;
}

QVector4D CornerRadii::toVector() const
{
    return QVector4D(topLeft, topRight, bottomRight, bottomLeft);
}

qreal clampedRadius(const QSizeF &size, qreal radius)
{
    if (radius <= 0.0 || size.isEmpty()) {
        return 0.0;
    }
    // Two corners meeting on the shorter edge must not overlap; that is the
    // only geometric limit there is. Covers the very small windows (and the
    // popup-shaped ones) where the configured radius would be nonsense.
    return std::min(radius, std::min(size.width(), size.height()) / 2.0);
}

QPainterPath contourPath(const QRectF &rect, const CornerRadii &radii,
                         qreal smoothness)
{
    QPainterPath path;
    if (rect.isEmpty()) {
        return path;
    }

    // Clockwise from the top edge. Every straight edge is a lineTo issued by
    // the corner before it (or by the moveTo for the first one), so the path
    // is exactly four edges and four corners in the order a pen would draw
    // them.
    path.moveTo(rect.left() + radii.topLeft, rect.top());
    contourCorner(path, rect.topRight(), radii.topRight, smoothness,
                QPointF(1, 0), QPointF(0, 1));
    contourCorner(path, rect.bottomRight(), radii.bottomRight, smoothness,
                QPointF(0, 1), QPointF(-1, 0));
    contourCorner(path, rect.bottomLeft(), radii.bottomLeft, smoothness,
                QPointF(-1, 0), QPointF(0, -1));
    contourCorner(path, rect.topLeft(), radii.topLeft, smoothness,
                QPointF(0, -1), QPointF(1, 0));
    path.closeSubpath();
    return path;
}

QPainterPath contourPath(const QRectF &rect, qreal radius, qreal smoothness)
{
    CornerRadii radii;
    radii.topLeft = radius;
    radii.topRight = radius;
    radii.bottomRight = radius;
    radii.bottomLeft = radius;
    return contourPath(rect, radii, smoothness);
}

qreal safeCornerInset(qreal radius)
{
    if (radius <= 0.0) {
        return 0.0;
    }
    // For a circular corner the contour on the corner diagonal sits
    // r * (1 - 1/sqrt(2)) from the corner point, so an axis-aligned content
    // rectangle inset by that much on every side stays clear of all four
    // curves. Smoother corners bulge outward and need less, so the circular
    // value is the safe bound to promise.
    return radius * 0.2928932188134524;
}

} // namespace KOS::WindowAppearance
