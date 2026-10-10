#pragma once

#include "appearanceconfig.h"

#include <KDecoration3/DecorationShadow>
#include <QCache>
#include <QHash>
#include <QImage>
#include <scene/item.h>
#include <array>
#include <memory>

namespace KWin { class ImageItem; }

namespace KOS::WindowAppearance
{

// One small atlas, independent of window width/height. Its corners are kept
// at their original size; only the straight strips stretch. No screen readback.
struct ShadowAtlas
{
    QImage image;
    QRect innerRect;
    qreal scale = 1.0;
    qreal padding = 0.0;
    std::array<QImage, 8> tiles;
    std::shared_ptr<KDecoration3::DecorationShadow> decorationShadow;
};

class ShadowAtlasCache
{
public:
    std::shared_ptr<const ShadowAtlas> get(const CornerRadii &radii,
        qreal frameWidth, qreal scale, const ShadowSettings &settings,
        bool active, bool forDecoration);
    void clear() { m_cache.clear(); m_live.clear(); }
private:
    // Costs in KiB, including the fallback tiles. Active scene nodes retain
    // their own shared references when an unused cache entry is evicted.
    QCache<QString, std::shared_ptr<const ShadowAtlas>> m_cache{32 * 1024};
    // Non-owning lookup for atlases still held by windows after LRU eviction.
    // Expired entries are pruned on allocation; this is not a second cache
    // retaining all historical geometry variants.
    QHash<QString, std::weak_ptr<const ShadowAtlas>> m_live;
};

// CSD fallback uses native scene ImageItems, so KWin owns occlusion, damage,
// output transforms and texture lifetime. SSD uses DecorationShadow instead.
class SceneShadowItem : public KWin::Item
{
public:
    explicit SceneShadowItem(KWin::Item *parent);
    void setAtlas(const std::shared_ptr<const ShadowAtlas> &atlas);
    void setWindowSize(const QSizeF &size);
private:
    void layout();
    std::array<KWin::ImageItem *, 8> m_tiles;
    std::shared_ptr<const ShadowAtlas> m_atlas;
    QSizeF m_windowSize;
};

} // namespace KOS::WindowAppearance
