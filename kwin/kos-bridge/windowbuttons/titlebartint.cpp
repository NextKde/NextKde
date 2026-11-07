#include "titlebartint.h"

#include <algorithm>
#include <cmath>

namespace KOS
{
namespace
{
bool sameColor(const QColor &a, const QColor &b)
{
    return std::abs(a.red() - b.red()) <= 2
        && std::abs(a.green() - b.green()) <= 2
        && std::abs(a.blue() - b.blue()) <= 2;
}
}

void TintHistogram::add(const uchar *p)
{
    // Only opaque pixels carry the titlebar's actual RGB. Translucent source
    // pixels are premultiplied and would turn a fade-in into a dark tint.
    if (p[3] != 255) return;
    auto &bin = m_bins[(54 * p[0] + 183 * p[1] + 19 * p[2]) >> 8];
    ++bin.count;
    bin.red += p[0];
    bin.green += p[1];
    bin.blue += p[2];
    ++m_count;
}

bool TintHistogram::tint(bool *dark, QColor *color, quint64 minimumSamples) const
{
    if (m_count < std::max(quint64(MinSamples), minimumSamples)) return false;
    quint64 count = 0;
    int median = 0;
    for (; median < 255; ++median) {
        count += m_bins[median].count;
        if (count > m_count / 2) break;
    }
    Bin cluster;
    for (int i = std::max(0, median - 3); i <= std::min(255, median + 3); ++i) {
        cluster.count += m_bins[i].count;
        cluster.red += m_bins[i].red;
        cluster.green += m_bins[i].green;
        cluster.blue += m_bins[i].blue;
    }
    *dark = median < 128;
    *color = QColor(int(cluster.red / cluster.count), int(cluster.green / cluster.count),
                    int(cluster.blue / cluster.count));
    return true;
}

QRect tintSampleRect(const QRect &band, const QRect &panel, bool fallback)
{
    if (band.isEmpty()) return {};
    // Keep the preferred median close to the cover seam. A wide strip can
    // contain mostly a filled toolbar widget (e.g. Steam's account/balance),
    // whose perfectly valid pixels are still the wrong background color.
    const int maxWidth = fallback ? 160 : 32;
    // Use a narrow upper background gutter. The middle of the controls band
    // can contain avatars, labels or a second toolbar on shorter title bars.
    constexpr int MaxHeight = 8;
    const bool onRight = panel.center().x() >= band.center().x();
    int left = band.x();
    int right = band.x() + band.width();
    if (!fallback) {
        if (onRight) {
            right = std::min(right, panel.x());
            left = std::max(left, right - maxWidth);
        } else {
            left = std::max(left, panel.x() + panel.width());
            right = std::min(right, left + maxWidth);
        }
    } else if (onRight) {
        right = std::min({right, left + maxWidth, left + band.width() / 3, panel.x()});
    } else {
        left = std::max({left, right - maxWidth, right - band.width() / 3,
                         panel.x() + panel.width()});
    }
    const int height = std::min(band.height(), std::clamp(band.height() / 6, 2, MaxHeight));
    return QRect(left, band.y() + std::min(band.height() - height, band.height() / 8),
                 std::max(0, right - left), height);
}

int tintBackgroundBottom(const uchar *rgba, int width, int height,
                         const QColor &background, int startRow, int minimumRun)
{
    if (!rgba || width <= 0 || height <= 0 || width > TintProbeWidth
        || height > TintProbeHeight) return height;
    // Eight horizontal groups suppress small icons. Row profiles and scratch
    // arrays live on the stack; no per-pixel objects or heap allocations.
    struct Row { std::array<int, 3> rgb{}; bool valid = false; };
    std::array<Row, TintProbeHeight> rows{};
    for (int y = 0; y < height; ++y) {
        std::array<std::array<int, 8>, 3> groups{};
        int validGroups = 0;
        for (int group = 0; group < 8; ++group) {
            std::array<int, 3> sum{};
            int count = 0;
            const int begin = group * width / 8, end = (group + 1) * width / 8;
            for (int x = begin; x < end; ++x) {
                const auto *p = rgba + (qsizetype(y) * width + x) * 4;
                if (p[3] < 128) continue;
                for (int c = 0; c < 3; ++c) sum[c] += p[c];
                ++count;
            }
            if (!count || count * 4 < (end - begin) * 3) continue;
            for (int c = 0; c < 3; ++c) groups[c][validGroups] = (sum[c] + count / 2) / count;
            ++validGroups;
        }
        if (validGroups < 6) continue;
        rows[y].valid = true;
        for (int c = 0; c < 3; ++c) {
            std::sort(groups[c].begin(), groups[c].begin() + validGroups);
            rows[y].rgb[c] = groups[c][validGroups / 2];
        }
    }
    const int run = std::clamp(minimumRun, 3, 12);
    const auto section = [&](int begin, int channel, int &median, int &noise) {
        std::array<int, 12> values{};
        for (int i = 0; i < run; ++i) {
            if (!rows[begin + i].valid) return false;
            values[i] = rows[begin + i].rgb[channel];
        }
        std::sort(values.begin(), values.begin() + run);
        median = values[run / 2];
        for (int i = 0; i < run; ++i) values[i] = std::abs(values[i] - median);
        std::sort(values.begin(), values.begin() + run);
        noise = values[run / 2];
        return true;
    };
    for (int y = std::max(run, startRow); y + run <= height; ++y) {
        int channel = -1, strongest = 0, direction = 0;
        for (int c = 0; c < 3; ++c) {
            int above, below, aboveNoise, belowNoise;
            if (!section(y - run, c, above, aboveNoise)
                || !section(y, c, below, belowNoise)) continue;
            const int contrast = std::abs(below - above);
            const int noise = std::max(aboveNoise, belowNoise);
            // A flat 2-level step can be evidence; a sloping gradient or noisy
            // content must exceed its own variation by a larger margin.
            if (contrast < 2 + 3 * noise || contrast <= strongest) continue;
            const int anchor = c == 0 ? background.red() : c == 1 ? background.green() : background.blue();
            if (std::abs(above - anchor) > 2 + 3 * aboveNoise) continue;
            channel = c;
            strongest = contrast;
            direction = below > above ? 1 : -1;
        }
        if (channel < 0) continue;
        int coherent = 0;
        for (int x = 0; x < width; ++x) {
            const auto *a = rgba + (qsizetype(y - run / 2 - 1) * width + x) * 4;
            const auto *b = rgba + (qsizetype(y + run / 2) * width + x) * 4;
            if (a[3] >= 128 && b[3] >= 128
                && direction * (int(b[channel]) - a[channel]) >= std::max(2, strongest / 2)) ++coherent;
        }
        if (coherent * 4 >= width * 3) {
            // Window medians establish the two surfaces; the strongest local
            // row step places the edge without trimming half a run too early.
            int edge = y, jump = 0;
            for (int step = y; step < y + run; ++step) {
                const int delta = direction * (rows[step].rgb[channel] - rows[step - 1].rgb[channel]);
                if (delta > jump) { jump = delta; edge = step; }
            }
            return edge;
        }
    }
    return height;
}

std::chrono::milliseconds TitlebarTintState::interval() const
{
    // A pending change must be confirmed at the fast cadence, not another
    // multi-second idle poll later. One-frame flashes still cannot take over.
    if (pending || warmupReads < WarmupReads) return WarmupInterval;
    // Stable windows back off to one observation per second, even if their
    // document/video keeps generating unrelated client damage.
    return std::min(IdleInterval, RecheckInterval * (1 << std::min(stableReads / 2, 3)));
}

void TitlebarTintState::attempted(Clock::time_point now)
{
    lastRead = now;
    sampleRevision = contentRevision;
    warmupReads = std::min(warmupReads + 1, WarmupReads);
}

void TitlebarTintState::requestRefresh()
{
    // Keep the last validated RGB while focus/geometry catches up. Never
    // replace it with an uninitialized palette or the previous transfer.
    refreshRequested = true;
    pending = false;
    warmupReads = 0;
    stableReads = 0;
    lastRead = {};
}

bool TitlebarTintState::accept(bool sampledDark, const QColor &sampledColor,
                              Clock::time_point sampledAt)
{
    if (!sampledColor.isValid() || sampledColor.alpha() != 255) {
        rejectSample();
        return false;
    }
    if (known && sampledDark == dark && sameColor(sampledColor, color)) {
        pending = false;
        stableReads = std::min(stableReads + 1, StableReads);
        refreshRequested = sampleRevision != contentRevision;
        return false;
    }
    stableReads = 0;
    if (!pending || sampledDark != pendingDark || !sameColor(sampledColor, pendingColor)) {
        pending = true;
        pendingDark = sampledDark;
        pendingColor = sampledColor;
        pendingSince = sampledAt;
        return false;
    }
    if (sampledAt - pendingSince < ConfirmTime) return false;
    dark = sampledDark;
    color = sampledColor;
    known = true;
    refreshRequested = sampleRevision != contentRevision;
    pending = false;
    return true;
}

} // namespace KOS
