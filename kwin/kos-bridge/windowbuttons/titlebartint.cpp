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
    // Transparent/unpainted pixels are not evidence of a black title bar.
    if (p[3] < 128) return;
    auto &bin = m_bins[(54 * p[0] + 183 * p[1] + 19 * p[2]) >> 8];
    ++bin.count;
    bin.red += p[0];
    bin.green += p[1];
    bin.blue += p[2];
    ++m_count;
}

bool TintHistogram::tint(bool *dark, QColor *color) const
{
    if (m_count < MinSamples) return false;
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
    constexpr int MaxWidth = 160;
    constexpr int MaxHeight = 64;
    const bool onRight = panel.center().x() >= band.center().x();
    int left = band.x();
    int right = band.x() + band.width();
    if (!fallback) {
        if (onRight) {
            right = std::min(right, panel.x());
            left = std::max(left, right - MaxWidth);
        } else {
            left = std::max(left, panel.x() + panel.width());
            right = std::min(right, left + MaxWidth);
        }
    } else if (onRight) {
        right = std::min({right, left + MaxWidth, left + band.width() / 3, panel.x()});
    } else {
        left = std::max({left, right - MaxWidth, right - band.width() / 3,
                         panel.x() + panel.width()});
    }
    const int height = std::min(MaxHeight, band.height());
    return QRect(left, band.y() + (band.height() - height) / 2,
                 std::max(0, right - left), height);
}

std::chrono::milliseconds TitlebarTintState::interval() const
{
    // A pending change must be confirmed at the fast cadence, not another
    // multi-second idle poll later. One-frame flashes still cannot take over.
    return pending || warmupReads < WarmupReads ? WarmupInterval : RecheckInterval;
}

void TitlebarTintState::attempted(Clock::time_point now)
{
    lastRead = now;
    warmupReads = std::min(warmupReads + 1, WarmupReads);
}

bool TitlebarTintState::accept(bool sampledDark, const QColor &sampledColor,
                              Clock::time_point now)
{
    if (!known) {
        known = true;
        dark = sampledDark;
        color = sampledColor;
        pending = false;
        return true;
    }
    if (sampledDark == dark && sameColor(sampledColor, color)) {
        pending = false;
        return false;
    }
    if (!pending || sampledDark != pendingDark || !sameColor(sampledColor, pendingColor)) {
        pending = true;
        pendingDark = sampledDark;
        pendingColor = sampledColor;
        pendingSince = now;
        return false;
    }
    if (now - pendingSince < ConfirmTime) return false;
    dark = sampledDark;
    color = sampledColor;
    pending = false;
    return true;
}

} // namespace KOS
