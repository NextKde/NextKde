// Ported from the old project's src/renderer/utils/appleDynamicCover/hls.ts:
// HLS master playlist parsing and variant picking. Prefers H.264 (AVC)
// variants because HEVC decoding is not guaranteed on every Windows machine.

#pragma once

#include <QString>
#include <QStringList>

#include <vector>

namespace listenfree::online::apple_hls {

struct HlsVariant {
    QString uri;
    QString codecs;
    QString resolution;
    qint64 bandwidth{0};
    int width{0};
    int height{0};
};

// Resolves `reference` (variant URI) against `masterUrl`, mirroring
// resolveVariantMediaUrl's URL constructor fallback.
QString resolveUrl(const QString& reference, const QString& masterUrl);

// Parses every #EXT-X-STREAM-INF entry of a master playlist.
std::vector<HlsVariant> parseMasterPlaylist(const QString& content);

// Picks the best variant for the requested maximum edge (e.g. 640 or 1080):
// prefers AVC variants at or below the cap (highest edge below the cap wins),
// otherwise the mid-resolution variant as a downgrade.
HlsVariant pickBestVariant(const QString& content, const QString& masterUrl, int maxEdge);

} // namespace listenfree::online::apple_hls
