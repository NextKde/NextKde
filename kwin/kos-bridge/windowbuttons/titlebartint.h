#pragma once

#include <QColor>
#include <QRect>
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
    bool tint(bool *dark, QColor *color) const;

private:
    struct Bin {
        quint64 count = 0, red = 0, green = 0, blue = 0;
    };
    std::array<Bin, 256> m_bins{};
    quint64 m_count = 0;
};

// Device-pixel bounds, independent of the output/window width and scale.
// The preferred strip is beside the controls. The fallback is at the opposite
// end, outside the caption's middle third. Neither includes the panel itself.
QRect tintSampleRect(const QRect &band, const QRect &panel, bool fallback = false);

struct TitlebarTintState {
    using Clock = std::chrono::steady_clock;
    static constexpr auto ConfirmTime = std::chrono::milliseconds(32);
    static constexpr auto WarmupInterval = std::chrono::milliseconds(32);
    static constexpr auto RecheckInterval = std::chrono::milliseconds(125);
    static constexpr int WarmupReads = 4;

    bool known = false;
    bool dark = true;
    QColor color;
    bool pending = false;
    bool pendingDark = false;
    QColor pendingColor;
    Clock::time_point pendingSince{};
    Clock::time_point lastRead{};
    int warmupReads = 0;
    bool refreshRequested = true;
    quint64 contentRevision = 0, sampleRevision = 0;

    std::chrono::milliseconds interval() const;
    void requestRefresh();
    void contentChanged() { ++contentRevision; refreshRequested = true; }
    void rejectSample() { pending = false; refreshRequested = warmupReads < WarmupReads || sampleRevision != contentRevision; }
    bool needsFollowup() const { return pending || refreshRequested || warmupReads < WarmupReads; }
    void attempted(Clock::time_point now);
    // Returns true only when the displayed color actually changes. Near-equal
    // samples must not drift the cached RGB and create more texture variants.
    bool accept(bool sampledDark, const QColor &sampledColor, Clock::time_point now);
};

} // namespace KOS
