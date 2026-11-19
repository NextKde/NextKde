/*
    SPDX-FileCopyrightText: 2026 NextKDE contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QColor>
#include <QRectF>

namespace KWin
{

// Immutable snapshot of one committed shape. Geometry is surface-local logical.
struct GlassShape
{
    QRectF geometry;
    QRectF captureGeometry;
    qreal radius = 0;
    qreal exponent = 3.0;
    bool enabled = true;

    quint32 effect = 0; // 0 liquid, 1 frosted
    quint32 material = 1; // 0 clear, 1 regular, 2 thick
    qreal materialOpacity = 1.0;

    quint32 tintMode = 0;
    QColor tint = Qt::black;
    qreal tintOpacity = 0.0;

    bool scrimEnabled = false;
    quint32 scrimTint = 0;
    qreal scrimCap = 0.0;
    qreal scrimDecay = 1.0;

    // Pointer interaction mask (protocol v9): bit 0 hover light, bit 1 lens
    // parallax, bit 2 click ripple. Pre-v9 clients never send it, so the
    // historical "every effect on" value is the default.
    quint32 pointerEffects = 0x7;

    bool blurEnabled = false;
    quint32 blurLevel = 0;
    // Presence matters: v8 clients always send a sigma, and 0 is the explicit
    // "show the backdrop undisturbed" request. Pre-v8 clients never send it
    // and must keep the strength-level behaviour.
    bool blurSigmaSet = false;
    qreal blurSigma = 0.0;

    QRectF captureBounds() const
    {
        return captureGeometry.isValid() && captureGeometry.width() > 0
                && captureGeometry.height() > 0
            ? captureGeometry
            : geometry;
    }

    bool hasArea() const
    {
        return enabled && materialOpacity > 0.0
            && geometry.width() > 0.0 && geometry.height() > 0.0;
    }
};

} // namespace KWin
