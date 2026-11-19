#pragma once

#include <QImage>

namespace KOS::WindowAppearance
{

// Everything the continuous contour shader used to evaluate per fragment.
// All lengths are in source-device pixels (logical values multiplied by the
// output scale).
struct CornerMaskStyle
{
    qreal radius = 0; // visual radius at the diagonal
    qreal exponent = 2; // superellipse exponent
    qreal stroke = 0;
    qreal frameWidth = 0;
    qreal contactSigma = 0;
    qreal ambientSigma = 0;
    qreal contactOpacity = 0;
    qreal ambientOpacity = 0;
    // Distance from the corner where the straight edge starts, plus the
    // shadow margin outside the frame.
    qreal extent = 0;
    qreal padding = 0;
    // Downward shadow shift in device pixels. The chrome channels stay
    // centered on the frame; only the shadow coverage is sampled at the
    // shifted contour.
    qreal offsetY = 0;
};

// A tiny 9-slice atlas: two corner blocks (the shadow shift makes the top and
// bottom corners different), three straight-edge profiles and one interior
// texel. The mask does not depend on the window size, so every window with the
// same style shares it.
//
// Channels: R = shape coverage (source factor), G = inner outline coverage,
// B = frame band coverage, A = shadow coverage. Colors and their animated
// opacities stay uniforms. Values match the previous per-fragment math with
// aa = 1 device pixel.
struct CornerMaskAtlas
{
    QImage image; // RGBA8888_Premultiplied, raw mask values
    int width = 0;
    int height = 0;
    int cell = 0; // corner block and edge profile length
    // Top and bottom corners sample differently shifted shadows; left/right
    // pairs share a block through horizontal mirroring.
    int topBlockX = 0;
    int topBlockY = 0;
    int bottomBlockX = 0;
    int bottomBlockY = 0;
    // Horizontal edges sample the shifted profiles; vertical edges keep the
    // unshifted one (a vertical shift does not change their distance).
    int sideProfileX = 0;
    int sideProfileY = 0;
    int topProfileX = 0;
    int topProfileY = 0;
    int bottomProfileX = 0;
    int bottomProfileY = 0;
    int centerX = 0;
    int centerY = 0;
    // ceil(padding) used for the block origin and
    // ceil(max(extent, stroke + frameWidth + 2)) used for the strip length.
    int padding = 0;
    int band = 0;
};

CornerMaskAtlas bakeCornerMask(const CornerMaskStyle &style);

} // namespace KOS::WindowAppearance
