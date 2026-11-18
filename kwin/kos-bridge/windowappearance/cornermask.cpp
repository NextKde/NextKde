#include "cornermask.h"

#include <QtMath>
#include <algorithm>
#include <cmath>

namespace KOS::WindowAppearance
{
namespace
{
// One texel of replicated border around every atlas region. Scaled draws
// sample the mask between texel centers; without the border a linear lookup at
// a region edge would blend in the empty atlas pixels and leave a dark line.
constexpr int Gutter = 1;

struct Coverage
{
    float shape = 0;
    float band = 0;
    float frame = 0;
    float shadow = 0;
};

// Mirrors kosDistance() from the contour shader for a point whose distances
// to the corner's two edges are (a, b). Positive values are inside the frame.
qreal cornerDistance(qreal a, qreal b, qreal radius, qreal exponent)
{
    const qreal qx = radius - a;
    const qreal qy = radius - b;
    if (radius <= 0.0 || std::min(qx, qy) <= 0.0) {
        return std::max(qx, qy) - radius;
    }
    const qreal vx = std::max(qx / radius, 0.0);
    const qreal vy = std::max(qy / radius, 0.0);
    const qreal norm = std::pow(std::pow(vx, exponent) + std::pow(vy, exponent),
        1.0 / exponent);
    const qreal gx = std::pow(vx / std::max(norm, 0.0001), exponent - 1.0);
    const qreal gy = std::pow(vy / std::max(norm, 0.0001), exponent - 1.0);
    return radius * (norm - 1.0) / std::max(std::hypot(gx, gy), 0.0001);
}

// The shader's antialiasing width is fwidth(distance). The normalized
// distance field has a unit gradient, so at one device pixel per texel this is
// exactly one pixel.
Coverage coverageFor(qreal distance, qreal shadowDistance,
                     const CornerMaskStyle &style)
{
    constexpr qreal aa = 1.0;
    const qreal inside = 1.0 - std::clamp(0.5 + distance / aa, 0.0, 1.0);
    const qreal inner = 1.0 - std::clamp(0.5 + (distance + style.stroke) / aa, 0.0, 1.0);
    const qreal outer = 1.0 - std::clamp(0.5 + (distance - style.frameWidth) / aa, 0.0, 1.0);
    Coverage c;
    c.shape = float(inside);
    c.band = float(std::clamp(inside - inner, 0.0, 1.0));
    c.frame = float(std::max(0.0, outer - inside));
    // The shifted shadow only moves the falloff; `outer` stays on the frame so
    // the near half of the shift is still clipped out of the window interior.
    const qreal d = std::max(0.0, shadowDistance - style.frameWidth);
    const qreal contactSigma = std::max(style.contactSigma, 0.0001);
    const qreal ambientSigma = std::max(style.ambientSigma, 0.0001);
    const qreal contact = style.contactOpacity
        * std::exp(-0.5 * d * d / (contactSigma * contactSigma));
    const qreal ambient = style.ambientOpacity
        * std::exp(-0.5 * d * d / (ambientSigma * ambientSigma));
    const qreal shadow = (1.0 - (1.0 - contact) * (1.0 - ambient)) * (1.0 - outer);
    c.shadow = float(std::clamp(shadow, 0.0, 1.0));
    return c;
}

void store(uchar *pixel, const Coverage &c)
{
    pixel[0] = uchar(qRound(c.shape * 255.0));
    pixel[1] = uchar(qRound(c.band * 255.0));
    pixel[2] = uchar(qRound(c.frame * 255.0));
    pixel[3] = uchar(qRound(c.shadow * 255.0));
}
} // namespace

CornerMaskAtlas bakeCornerMask(const CornerMaskStyle &style)
{
    const int padding = int(std::ceil(std::max<qreal>(style.padding, 1.0)));
    const int band = int(std::ceil(std::max<qreal>(style.extent,
        style.stroke + style.frameWidth + 2.0)));
    const int cell = padding + band;

    CornerMaskAtlas atlas;
    atlas.cell = cell;
    atlas.padding = padding;
    atlas.band = band;
    // Content coordinates: a texel sampled at mask coordinate q lives at
    // (origin + q), so the dimensions below include the gutter and callers do
    // not have to know about it.
    atlas.topBlockX = Gutter;
    atlas.topBlockY = Gutter;
    atlas.bottomBlockX = Gutter;
    atlas.bottomBlockY = atlas.topBlockY + cell + Gutter * 2;
    atlas.sideProfileX = Gutter;
    atlas.sideProfileY = atlas.bottomBlockY + cell + Gutter;
    atlas.topProfileX = Gutter;
    atlas.topProfileY = atlas.sideProfileY + 1;
    atlas.bottomProfileX = Gutter;
    atlas.bottomProfileY = atlas.topProfileY + 1;
    atlas.centerX = Gutter;
    atlas.centerY = atlas.bottomProfileY + 1;
    atlas.width = cell + Gutter * 2;
    atlas.height = atlas.centerY + 1;

    QImage image(atlas.width, atlas.height, QImage::Format_RGBA8888_Premultiplied);
    image.fill(Qt::transparent);

    // Corner block. Local texel t <-> mask-space distance a = -padding + t + 0.5.
    // The shift only moves the shadow: the chrome channels keep the unshifted
    // contour, while the shadow is evaluated at the translated one. Sampling
    // the shifted corner distance moves both of that corner's axes, which is
    // exactly the rigid translation of the contour.
    const auto fillBlock = [&](int ox, int oy, qreal shiftY) {
        for (int j = 0; j < cell; ++j) {
            uchar *row = image.scanLine(oy + j);
            const qreal b = -padding + j + 0.5;
            for (int i = 0; i < cell; ++i) {
                const qreal a = -padding + i + 0.5;
                const qreal d = cornerDistance(a, b, style.radius, style.exponent);
                const qreal sd = cornerDistance(a, b + shiftY,
                                                style.radius, style.exponent);
                store(row + (ox + i) * 4, coverageFor(d, sd, style));
            }
        }
        // Replicate the first/last column and row into the gutter.
        const int blockWidth = cell + Gutter * 2;
        for (int j = 0; j < cell; ++j) {
            uchar *row = image.scanLine(oy + j);
            std::copy_n(row + ox * 4, 4, row + (ox - Gutter) * 4);
            std::copy_n(row + (ox + cell - 1) * 4, 4,
                row + (ox + cell) * 4);
        }
        std::copy_n(image.scanLine(oy), blockWidth * 4,
            image.scanLine(oy - Gutter));
        std::copy_n(image.scanLine(oy + cell - 1), blockWidth * 4,
            image.scanLine(oy + cell));
    };
    // Top corners look for the shadow further above; bottom corners find it
    // close, because the cast shape moved toward them.
    fillBlock(atlas.topBlockX, atlas.topBlockY, -style.offsetY);
    fillBlock(atlas.bottomBlockX, atlas.bottomBlockY, style.offsetY);

    // Straight-edge profile. The signed distance of a mid-edge fragment is
    // exactly minus its inward distance. A vertical shift does not change the
    // side distance; it only pushes the horizontal edges' shadow away (top) or
    // toward (bottom), so the three profiles differ by the shadow distance.
    const auto fillProfile = [&](int pxx, int pyy, qreal shiftY) {
        uchar *profile = image.scanLine(pyy);
        for (int i = 0; i < cell; ++i) {
            const qreal a = -padding + i + 0.5;
            store(profile + (pxx + i) * 4,
                coverageFor(-a, -a + shiftY, style));
        }
        std::copy_n(profile + pxx * 4, 4, profile + (pxx - Gutter) * 4);
        std::copy_n(profile + (pxx + cell - 1) * 4, 4,
            profile + (pxx + cell) * 4);
    };
    fillProfile(atlas.sideProfileX, atlas.sideProfileY, 0.0);
    fillProfile(atlas.topProfileX, atlas.topProfileY, style.offsetY);
    fillProfile(atlas.bottomProfileX, atlas.bottomProfileY, -style.offsetY);

    // Interior: fully opaque shape, no chrome.
    uchar *center = image.scanLine(atlas.centerY) + atlas.centerX * 4;
    center[0] = 255;
    center[1] = 0;
    center[2] = 0;
    center[3] = 0;

    atlas.image = std::move(image);
    return atlas;
}

} // namespace KOS::WindowAppearance
