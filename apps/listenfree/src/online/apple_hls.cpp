#include "online/apple_hls.h"

#include <QRegularExpression>
#include <QUrl>

#include <algorithm>

namespace listenfree::online::apple_hls {
namespace {

bool isAvc(const QString& codecs) {
    static const QRegularExpression pattern(QStringLiteral("avc1|avc3|mp4v"), QRegularExpression::CaseInsensitiveOption);
    return pattern.match(codecs).hasMatch();
}

QStringList splitLines(const QString& content) {
    QStringList lines = content.split(QLatin1Char('\n'));
    for (QString& line : lines) {
        if (line.endsWith(QLatin1Char('\r'))) line.chop(1);
    }
    return lines;
}

} // namespace

QString resolveUrl(const QString& reference, const QString& masterUrl) {
    const QUrl resolved = QUrl(masterUrl).resolved(QUrl(reference));
    return resolved.isValid() ? resolved.toString() : reference;
}

std::vector<HlsVariant> parseMasterPlaylist(const QString& content) {
    std::vector<HlsVariant> variants;
    const QStringList lines = splitLines(content);
    static const QRegularExpression codecsPattern(QStringLiteral("CODECS=\"([^\"]*)\""));
    static const QRegularExpression resolutionPattern(QStringLiteral("RESOLUTION=(\\d+x\\d+)"));
    static const QRegularExpression bandwidthPattern(QStringLiteral("BANDWIDTH=(\\d+)"));

    for (int index = 0; index < lines.size(); ++index) {
        const QString& line = lines.at(index);
        if (!line.startsWith(QStringLiteral("#EXT-X-STREAM-INF"))) continue;

        // The next non-empty, non-comment line is the variant URI.
        QString uri;
        for (int next = index + 1; next < lines.size(); ++next) {
            const QString candidate = lines.at(next).trimmed();
            if (candidate.isEmpty()) continue;
            if (candidate.startsWith(QLatin1Char('#'))) break;
            uri = candidate;
            break;
        }
        if (uri.isEmpty()) continue;

        HlsVariant variant;
        variant.uri = uri;
        variant.codecs = codecsPattern.match(line).captured(1);
        variant.resolution = resolutionPattern.match(line).captured(1);
        variant.bandwidth = bandwidthPattern.match(line).captured(1).toLongLong();
        if (variant.resolution.contains(QLatin1Char('x'))) {
            const QStringList edges = variant.resolution.split(QLatin1Char('x'));
            variant.width = edges.value(0).toInt();
            variant.height = edges.value(1).toInt();
        }
        variants.push_back(std::move(variant));
    }
    return variants;
}

HlsVariant pickBestVariant(const QString& content, const QString& masterUrl, int maxEdge) {
    std::vector<HlsVariant> variants = parseMasterPlaylist(content);
    if (variants.empty()) return {};

    std::vector<HlsVariant> avcList;
    std::copy_if(variants.begin(), variants.end(), std::back_inserter(avcList),
                 [](const HlsVariant& variant) { return isAvc(variant.codecs); });
    if (!avcList.empty()) {
        // Take the highest available edge at or below the cap per display scene.
        std::vector<HlsVariant> withResolution;
        std::copy_if(avcList.begin(), avcList.end(), std::back_inserter(withResolution),
                     [](const HlsVariant& variant) { return variant.width > 0 && variant.height > 0; });
        if (withResolution.empty()) withResolution = avcList;
        std::vector<HlsVariant> withinTarget;
        std::copy_if(withResolution.begin(), withResolution.end(), std::back_inserter(withinTarget),
                     [&](const HlsVariant& variant) { return std::max(variant.width, variant.height) <= maxEdge; });
        const auto& pool = !withinTarget.empty() ? withinTarget : withResolution;
        const auto best = std::max_element(pool.begin(), pool.end(), [&](const HlsVariant& a, const HlsVariant& b) {
            const int edgeA = std::max(a.width, a.height);
            const int edgeB = std::max(b.width, b.height);
            if (edgeA != edgeB) return withinTarget.empty() ? edgeA < edgeB : edgeA > edgeB;
            return a.bandwidth < b.bandwidth;
        });
        return *best;
    }

    // No AVC: keep the mid-resolution downgrade strategy of the original.
    std::sort(variants.begin(), variants.end(), [](const HlsVariant& a, const HlsVariant& b) {
        const qint64 areaA = static_cast<qint64>(a.width) * a.height;
        const qint64 areaB = static_cast<qint64>(b.width) * b.height;
        if (areaA != areaB) return areaA > areaB;
        return a.bandwidth > b.bandwidth;
    });
    const auto middle = variants.begin() + static_cast<std::ptrdiff_t>(variants.size() / 2);
    return *middle;
}

} // namespace listenfree::online::apple_hls
