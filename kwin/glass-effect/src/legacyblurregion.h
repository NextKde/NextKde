#pragma once

#include "surfaceshapemanager.h"

#include <QRegion>
#include <optional>

namespace KWin
{
// KWin 6.6 cannot receive ext-background-effect-v1; on newer APIs a remapped
// surface can also lack that separate request. An enabled KOS shape is an
// explicit glass opt-in; keep the spaces between
// cards clear, and preserve an existing KDE blur request (including empty).
inline std::optional<QRegion> legacySurfaceBlurRegion(
    const std::optional<QRegion> &requested, const QVector<SurfaceShape> &shapes)
{
    if (requested.has_value()) {
        return requested;
    }
    QRegion region;
    for (const SurfaceShape &shape : shapes) {
        if (shape.enabled && shape.geometry.width() > 0 && shape.geometry.height() > 0) {
            region += surfaceCaptureBounds(shape).toAlignedRect();
        }
    }
    if (region.isEmpty()) {
        return std::nullopt;
    }
    return region;
}
}
