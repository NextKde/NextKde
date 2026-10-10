#pragma once

#include <QRect>

namespace KOS
{

// A block of composited pixels, RGBA8, tightly packed or strided.
//
// This is deliberately a plain view over memory: the scan below is pure
// geometry, with no KWin or GL dependency, so it can be exercised
// against captured screenshots outside the compositor.
struct PixelBlock {
    const uchar *data = nullptr;
    int width = 0;
    int height = 0;
    int stride = 0; // bytes per row

    bool isValid() const
    {
        return data && width > 0 && height > 0 && stride >= width * 4;
    }

    const uchar *row(int y) const { return data + size_t(y) * size_t(stride); }

    int luma(int x, int y) const
    {
        const uchar *p = row(y) + x * 4;
        return (54 * p[0] + 183 * p[1] + 19 * p[2]) >> 8;
    }

    int rgbDistance(int x0, int y0, int x1, int y1) const
    {
        const uchar *a = row(y0) + x0 * 4;
        const uchar *b = row(y1) + x1 * 4;
        return std::abs(a[0] - b[0]) + std::abs(a[1] - b[1]) + std::abs(a[2] - b[2]);
    }
};

enum class ScanSide { Auto = -1, Left = 0, Right = 1 };

// Tallest title bar the scan looks for, in logical pixels. Callers should hand
// it a strip at least this tall, so the edge is never cut off.
inline constexpr double TitlebarProbeHeight = 80.0;

struct ScanResult {
    // False when the heuristics did not agree, or no controls were found.
    bool valid = false;

    // Bottom edge of the title bar, in block-local pixels.
    int headerbarBottom = 0;

    // The window's own controls, in block-local pixels.
    QRect buttonBox;

    // Median luma of the bar outside the controls and the caption.
    bool dark = true;

    // Share of the independent heuristics that agreed, 0..1.
    double confidence = 0.0;

    bool buttonsOnRight = true;
};

// Locate the title bar's bottom edge and the window's own controls in a strip
// of composited pixels taken from the top of a window.
//
// `scale` converts the logical-pixel thresholds to the block's device pixels.
ScanResult scanTitlebar(const PixelBlock &block, ScanSide side, double scale);

} // namespace KOS
