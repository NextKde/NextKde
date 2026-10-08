#pragma once

#include "surfaceshapemanager.h"

#include <QRegion>
#include <optional>

namespace KWin
{
// KWin 6.6 cannot receive Quickshell's ext-background-effect-v1 request.
// An enabled KOS shape is an explicit glass opt-in; keep the spaces between
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
            region += shape.geometry.toAlignedRect();
        }
    }
    if (region.isEmpty()) {
        return std::nullopt;
    }
    return region;
}
}
