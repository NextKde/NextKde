#pragma once

#include <QRectF>
#include <algorithm>
#include <cmath>

namespace KOS {

struct LiquidMotion {
    QRectF geometry;
    qreal iconOpacity;
    qreal topRadius;
    qreal bottomRadius;
    qreal dockMergeOpacity;
    qreal windowOpacity() const { return 1.0 - iconOpacity; }
    qreal artworkOpacity() const { return iconOpacity * dockMergeOpacity; }
};

// Canonical window -> icon progress. Restore traverses precisely the same
// poses backwards, including when a Dock click reverses a running animation.
inline LiquidMotion liquidMotion(const QRectF &window, const QRectF &icon, qreal progress, int minimizeDurationMs = 240)
{
    const qreal p = std::clamp(progress, 0.0, 1.0);
    // Keep window content throughout the flight; replace it only during
    // the final 80ms of canonical minimize time. Use the same poses backwards.
    const qreal tail = std::clamp(80.0 / std::max(80, minimizeDurationMs), 0.02, 0.5);
    const qreal handoffStart = 1.0 - tail;
    const qreal handoffEnd = handoffStart + tail * (25.0 / 80.0);
    const qreal blend = std::clamp((p - handoffStart) / (handoffEnd - handoffStart), 0.0, 1.0);
    const qreal alpha = blend * blend * (3.0 - 2.0 * blend);
    // Hold the full icon for 35ms before merging into the permanent Dock icon.
    const qreal mergeStart = 1.0 - tail * (20.0 / 80.0);
    const qreal merge = std::clamp((p - mergeStart) / (1.0 - mergeStart), 0.0, 1.0);
    const qreal dockMergeOpacity = 1.0 - merge * merge * (3.0 - 2.0 * merge);
    // Position and size share one continuous easing. The artwork inherits
    // the current window footprint instead of becoming Dock-sized mid-flight.
    const qreal travel = p;
    // Responsive departure, with zero velocity at arrival.
    const qreal position = 1.0 - std::pow(1.0 - travel, 1.35);
    const QSizeF size(std::lerp(window.width(), icon.width(), position),
                      std::lerp(window.height(), icon.height(), position));
    const QPointF center(std::lerp(window.center().x(), icon.center().x(), position),
                         std::lerp(window.center().y(), icon.center().y(), position));
    QRectF geometry(QPointF(), size);
    geometry.moveCenter(center);
    const qreal shortSide = std::min(size.width(), size.height());
    // Modest, symmetric corners. Avoid turning the window into a capsule
    // halfway through its flight; meet the cached icon's corner ratio at arrival.
    const qreal originalRadius = std::min(20.0, shortSide * 0.24);
    const qreal radius = std::lerp(originalRadius, shortSide * 0.24, position);
    return {geometry, alpha, radius, radius, dockMergeOpacity};
}

} // namespace KOS
