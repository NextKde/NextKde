#include "sceneshadow.h"

#include <scene/imageitem.h>
#include <algorithm>
#include <cmath>

namespace KOS::WindowAppearance
{
namespace
{

std::shared_ptr<ShadowAtlas> makeAtlas(const CornerRadii &radii,
    qreal frameWidth, qreal scale, const ShadowSettings &settings,
    bool active, bool forDecoration)
{
    auto atlas = std::make_shared<ShadowAtlas>();
    atlas->scale = scale;
    const qreal contactSigma = settings.contactBlur * scale;
    const qreal ambientSigma = (active ? settings.activeBlur
                                       : settings.inactiveBlur) * scale;
    const int padding = int(std::ceil(3.0 * std::max(contactSigma, ambientSigma)
                                      + frameWidth * scale + 1.0));
    const int corner = int(std::ceil(std::max({radii.topLeft, radii.topRight,
        radii.bottomRight, radii.bottomLeft}) * scale));
    const int coreSize = 2 * corner + 2;
    const int imageSize = coreSize + 2 * padding;
    atlas->image = QImage(imageSize, imageSize,
                         QImage::Format_ARGB32_Premultiplied);
    if (atlas->image.isNull()) {
        return atlas;
    }
    atlas->padding = qreal(padding) / scale;
    atlas->innerRect = QRect(padding + corner, padding + corner, 2, 2);
    const qreal halfExtent = coreSize / 2.0 + frameWidth * scale;
    const qreal center = imageSize / 2.0;
    for (int y = 0; y < imageSize; ++y) {
        auto *row = reinterpret_cast<QRgb *>(atlas->image.scanLine(y));
        for (int x = 0; x < imageSize; ++x) {
            const qreal px = x + 0.5 - center;
            const qreal py = y + 0.5 - center;
            const qreal r = (py < 0
                ? (px < 0 ? radii.topLeft : radii.topRight)
                : (px < 0 ? radii.bottomLeft : radii.bottomRight)) * scale
                + frameWidth * scale;
            const qreal qx = std::abs(px) - (halfExtent - r);
            const qreal qy = std::abs(py) - (halfExtent - r);
            const qreal distance = std::hypot(std::max(0.0, qx),
                                             std::max(0.0, qy))
                + std::min(0.0, std::max(qx, qy)) - r;
            const qreal d = std::max(0.0, distance);
            const qreal contact = settings.contactOpacity
                * std::exp(-0.5 * d * d / (contactSigma * contactSigma));
            const qreal ambient = settings.ambientOpacity
                * std::exp(-0.5 * d * d / (ambientSigma * ambientSigma));
            // Composite two soft layers, then remove the window interior.
            // The half-pixel ramp matches the antialiased circular contour.
            const qreal coverage = std::clamp(distance + 0.5, 0.0, 1.0);
            const int alpha = qRound(255 * coverage
                * (1.0 - (1.0 - contact) * (1.0 - ambient)));
            row[x] = qRgba(0, 0, 0, std::clamp(alpha, 0, 255));
        }
    }
    const int cut = padding + corner;
    const int far = cut + 2;
    const std::array<QRect, 8> sources = {
        QRect(0, 0, cut, cut), QRect(cut, 0, 2, cut),
        QRect(far, 0, cut, cut), QRect(far, cut, cut, 2),
        QRect(far, far, cut, cut), QRect(cut, far, 2, cut),
        QRect(0, far, cut, cut), QRect(0, cut, cut, 2),
    };
    if (forDecoration) {
        // KWin's DecorationShadow tile geometry is in logical pixels and
        // samples the raw atlas coordinates. Do not attach a HiDPI DPR to
        // this image; native KWin scales its blurred tiles per viewport.
        atlas->decorationShadow = std::make_shared<KDecoration3::DecorationShadow>();
        atlas->decorationShadow->setShadow(atlas->image);
        atlas->decorationShadow->setInnerShadowRect(atlas->innerRect);
        atlas->decorationShadow->setPadding(QMarginsF(atlas->padding,
            atlas->padding, atlas->padding, atlas->padding));
    } else {
        for (size_t i = 0; i < sources.size(); ++i) {
            atlas->tiles[i] = atlas->image.copy(sources[i]);
        }
    }
    return atlas;
}

} // namespace

std::shared_ptr<const ShadowAtlas> ShadowAtlasCache::get(const CornerRadii &radii,
    qreal frameWidth, qreal scale, const ShadowSettings &settings,
    bool active, bool forDecoration)
{
    // Native DecorationShadow is logical-resolution; CSD tiles are built at
    // the current output's device scale. Both use the same contour and falloff.
    scale = forDecoration ? 1.0 : std::max(0.01, scale);
    const qreal ambientBlur = active ? settings.activeBlur : settings.inactiveBlur;
    const QString key = QStringLiteral("%1,%2,%3,%4/%5/%6/%7/%8/%9/%10/%11")
        .arg(radii.topLeft, 0, 'f', 4).arg(radii.topRight, 0, 'f', 4)
        .arg(radii.bottomRight, 0, 'f', 4).arg(radii.bottomLeft, 0, 'f', 4)
        .arg(frameWidth, 0, 'f', 4).arg(scale, 0, 'f', 4)
        .arg(settings.contactBlur, 0, 'f', 4).arg(ambientBlur, 0, 'f', 4)
        .arg(settings.contactOpacity, 0, 'f', 4)
        .arg(settings.ambientOpacity, 0, 'f', 4).arg(forDecoration);
    if (const auto *cached = m_cache.object(key)) {
        return *cached;
    }
    if (const auto it = m_live.constFind(key); it != m_live.cend()) {
        if (auto atlas = it.value().lock()) {
            return atlas;
        }
    }
    for (auto it = m_live.begin(); it != m_live.end();) {
        if (it.value().expired()) {
            it = m_live.erase(it);
        } else {
            ++it;
        }
    }
    auto atlas = makeAtlas(radii, frameWidth, scale, settings, active, forDecoration);
    if (atlas->image.isNull()) {
        return {};
    }
    qsizetype bytes = atlas->image.sizeInBytes();
    for (const QImage &tile : atlas->tiles) {
        bytes += tile.sizeInBytes();
    }
    auto *entry = new std::shared_ptr<const ShadowAtlas>(atlas);
    m_live.insert(key, atlas);
    m_cache.insert(key, entry, int(std::max<qsizetype>(1, (bytes + 1023) / 1024)));
    return atlas;
}

SceneShadowItem::SceneShadowItem(KWin::Item *parent)
    : KWin::Item(parent)
{
    setParent(parent);
    for (auto &tile : m_tiles) {
        tile = new KWin::ImageItem(this);
        tile->setParent(this);
    }
}

void SceneShadowItem::setAtlas(const std::shared_ptr<const ShadowAtlas> &atlas)
{
    if (m_atlas == atlas) {
        return;
    }
    m_atlas = atlas;
    for (size_t i = 0; i < m_tiles.size(); ++i) {
        m_tiles[i]->setImage(atlas ? atlas->tiles[i] : QImage());
    }
    layout();
}

void SceneShadowItem::setWindowSize(const QSizeF &size)
{
    if (m_windowSize != size) {
        m_windowSize = size;
        layout();
    }
}

void SceneShadowItem::layout()
{
    if (!m_atlas || m_windowSize.isEmpty()) {
        setVisible(false);
        return;
    }
    const qreal p = m_atlas->padding;
    const qreal cut = m_atlas->innerRect.x() / m_atlas->scale;
    const qreal left = -p, top = -p;
    const qreal right = m_windowSize.width() + p;
    const qreal bottom = m_windowSize.height() + p;
    const qreal cx = std::min(cut, (right - left) / 2.0);
    const qreal cy = std::min(cut, (bottom - top) / 2.0);
    const qreal middleW = std::max(0.0, right - left - 2 * cx);
    const qreal middleH = std::max(0.0, bottom - top - 2 * cy);
    const std::array<KWin::RectF, 8> rects = {
        KWin::RectF(left, top, cx, cy), KWin::RectF(left + cx, top, middleW, cy),
        KWin::RectF(right - cx, top, cx, cy), KWin::RectF(right - cx, top + cy, cx, middleH),
        KWin::RectF(right - cx, bottom - cy, cx, cy), KWin::RectF(left + cx, bottom - cy, middleW, cy),
        KWin::RectF(left, bottom - cy, cx, cy), KWin::RectF(left, top + cy, cx, middleH),
    };
    for (size_t i = 0; i < rects.size(); ++i) {
        m_tiles[i]->setGeometry(rects[i]);
        m_tiles[i]->setVisible(!rects[i].isEmpty());
    }
    setVisible(true);
}

} // namespace KOS::WindowAppearance
