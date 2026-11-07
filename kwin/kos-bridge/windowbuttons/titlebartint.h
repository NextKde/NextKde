#pragma once

#include <QColor>
#include <QRect>
#include <algorithm>
#include <array>
#include <chrono>

namespace KOS
{

// Fixed storage: a read no longer allocates/copies/sorts one object per pixel.
class TintHistogram
{
public:
    static constexpr int MinSamples = 64;
    void add(const uchar *rgba);
    bool tint(bool *dark, QColor *color, quint64 minimumSamples = MinSamples) const;

private:
    struct Bin {
        quint64 count = 0, red = 0, green = 0, blue = 0;
    };
    std::array<Bin, 256> m_bins{};
    quint64 m_count = 0;
};

// Device-pixel bounds, independent of the output/window width and scale.
// The preferred strip stays within 32px of the cover seam, avoiding neighboring
// filled toolbar widgets. A narrow upper gutter avoids central icons. The 160px fallback is at the opposite end, outside
// the caption's middle third. Neither includes the panel itself.
QRect tintSampleRect(const QRect &band, const QRect &panel, bool fallback = false);

inline constexpr int TintProbeWidth = 160;
inline constexpr int TintProbeHeight = 192;

// Find a coherent step relative to local row noise, including low contrast.
// Returns height when the strip contains no unambiguous boundary.
int tintBackgroundBottom(const uchar *rgba, int width, int height,
                         const QColor &background, int startRow, int minimumRun);

struct TitlebarTintState {
    using Clock = std::chrono::steady_clock;
    static constexpr auto ConfirmTime = std::chrono::milliseconds(32);
    static constexpr auto WarmupInterval = std::chrono::milliseconds(32);
    static constexpr auto RecheckInterval = std::chrono::milliseconds(125);
    static constexpr auto IdleInterval = std::chrono::milliseconds(1000);
    static constexpr auto StartupDuration = std::chrono::seconds(5);
    static constexpr int StableReads = 8;
    static constexpr int WarmupReads = 4;

    bool known = false;
    bool dark = true;
    QColor color;
    bool pending = false;
    bool pendingDark = false;
    QColor pendingColor;
    Clock::time_point pendingSince{};
    Clock::time_point firstRead{};
    Clock::time_point lastRead{};
    int warmupReads = 0;
    int stableReads = 0;
    bool refreshRequested = true;
    quint64 contentRevision = 0, sampleRevision = 0;

    std::chrono::milliseconds interval() const;
    void requestRefresh();
    bool startingUp(Clock::time_point now) const {
        return firstRead != Clock::time_point{} && now >= firstRead
            && now - firstRead < StartupDuration;
    }
    void contentChanged(Clock::time_point now = Clock::now()) {
        ++contentRevision;
        refreshRequested = true;
        // Cold starts can confirm a placeholder before drawing the titlebar.
        // Track subsequent client frames promptly even with a known tint, but
        // never extend the startup deadline on damage, focus or resize.
        if (!known || startingUp(now)) { warmupReads = 0; stableReads = 0; }
    }
    std::chrono::milliseconds readbackPollInterval(Clock::time_point now) const {
        // Only startup/confirmation needs a sub-frame poll. A slow transfer
        // returns to the regular cadence after the first warm-up interval.
        return (!known || pending || startingUp(now)) && now - lastRead < WarmupInterval
            ? std::chrono::milliseconds(4) : std::chrono::milliseconds(16);
    }
    void rejectSample() {
        pending = false;
        stableReads = std::min(stableReads + 1, StableReads);
        refreshRequested = warmupReads < WarmupReads || sampleRevision != contentRevision;
    }
    bool needsFollowup() const { return pending || refreshRequested || warmupReads < WarmupReads; }
    void attempted(Clock::time_point now);
    // sampledAt is the capture time, not the asynchronous completion time.
    // Returns true only when the displayed color actually changes. Near-equal
    // samples must not drift the cached RGB and create more texture variants.
    bool accept(bool sampledDark, const QColor &sampledColor, Clock::time_point sampledAt);
};

} // namespace KOS
