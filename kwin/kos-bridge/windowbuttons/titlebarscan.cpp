#include "titlebarscan.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <numeric>
#include <vector>

namespace KOS
{
namespace
{

// Shortest believable title bar, in logical pixels.
constexpr double MinTitlebarHeight = 16.0;
// Two heuristics agree when their answers are within this many device pixels.
constexpr int AgreementPx = 2;
// Narrowest believable control cluster, in logical pixels.
constexpr double MinClusterWidth = 24.0;
// How far a gap between two controls may be bridged, in logical pixels.
// Self-drawn title bars space their controls much further apart than toolkit
// ones: three round GTK buttons sit 6px apart, while DingTalk's own controls
// are 24px apart.
constexpr int ClusterGapPx = 26;
// Widest believable control cluster, as a share of the window's width. A
// window's controls occupy a corner; anything spanning more of the bar than
// this is a toolbar, an illustration or a half-painted frame, and drawing a
// panel over it is how a small panel turns into one the width of the window.
constexpr double MaxClusterFraction = 0.35;
// A column counts as changing across a row boundary when it differs by at
// least this much. Used by the edge profiles, which count columns.
constexpr int LineLumaTolerance = 6;
constexpr int LineRgbTolerance = 12;
// Rows either side of y that the edge profiles compare. A soft edge -- an
// antialiased separator, or a theme that fades the bar into the content --
// spreads over several rows, and no single adjacent-row step clears the
// tolerance. Comparing across a band sees the whole transition at once.
constexpr int BandRadius = 2;
// How far a pixel must differ from the title bar's own colour to count as part
// of a control, in luma.
constexpr int ControlLumaTolerance = 24;
// Share of the window's width a row must differ over to be a separator line
// rather than part of a control. A line spans the window; a control does not.
constexpr double FullWidthLineFraction = 0.9;
// Controls sit near an edge of the title bar. A cluster further in than this
// share of the window's width is the caption, not controls.
constexpr double MaxEdgeInsetFraction = 0.25;

double median(std::vector<int> values)
{
    if (values.empty()) {
        return 0.0;
    }
    const size_t middle = values.size() / 2;
    std::nth_element(values.begin(), values.begin() + middle, values.end());
    return values[middle];
}

// Candidate rows for the title bar's bottom edge, each from a formulation that
// fails differently from the others. The caller takes the consensus rather
// than trusting any single one.
//
// Columns in [skipFrom, skipTo) are ignored. That range holds the caption,
// whose glyphs are far higher contrast than the bar's own bottom edge and
// would otherwise win every one of these profiles.
std::vector<int> bottomEdgeCandidates(const PixelBlock &block, int firstRow,
                                      int lastRow, int skipFrom, int skipTo)
{
    const int w = block.width;
    const int h = block.height;
    if (h < 3) {
        return {};
    }

    std::vector<double> lineLuma(h, 0.0);
    std::vector<double> lineRgb(h, 0.0);
    std::vector<double> rowMean(h, 0.0);
    std::vector<double> rowVar(h, 0.0);

    int counted = 0;
    for (int x = 0; x < w; ++x) {
        if (x >= skipFrom && x < skipTo) {
            continue;
        }
        ++counted;
    }
    if (counted < 8) {
        counted = w;
        skipFrom = 0;
        skipTo = 0;
    }

    for (int y = 0; y < h; ++y) {
        double sum = 0.0;
        for (int x = 0; x < w; ++x) {
            if (x >= skipFrom && x < skipTo) {
                continue;
            }
            sum += block.luma(x, y);
        }
        rowMean[y] = sum / counted;

        double var = 0.0;
        for (int x = 0; x < w; ++x) {
            if (x >= skipFrom && x < skipTo) {
                continue;
            }
            const double d = block.luma(x, y) - rowMean[y];
            var += d * d;
        }
        rowVar[y] = var / counted;
    }

    // Counting the columns that change, rather than summing how much they
    // change, is what separates the title bar's own bottom edge from the
    // controls inside it: the edge spans the whole window, a control spans a
    // few percent of it. Summing lets one high-contrast control outvote the
    // edge that actually delimits the bar. Comparing across a band rather than
    // between adjacent rows keeps a soft edge visible.
    std::vector<double> meanJump(h, 0.0);
    std::vector<double> varJump(h, 0.0);
    for (int y = BandRadius; y + BandRadius < h; ++y) {
        int lumaChanged = 0;
        int rgbChanged = 0;
        for (int x = 0; x < w; ++x) {
            if (x >= skipFrom && x < skipTo) {
                continue;
            }
            if (std::abs(block.luma(x, y + BandRadius)
                         - block.luma(x, y - BandRadius)) > LineLumaTolerance) {
                ++lumaChanged;
            }
            if (block.rgbDistance(x, y - BandRadius, x, y + BandRadius)
                > LineRgbTolerance) {
                ++rgbChanged;
            }
        }
        lineLuma[y] = lumaChanged;
        lineRgb[y] = rgbChanged;
        meanJump[y] = std::abs(rowMean[y + BandRadius] - rowMean[y - BandRadius]);
        varJump[y] = std::abs(rowVar[y + BandRadius] - rowVar[y - BandRadius]);
    }

    // A profile of all zeros yields no candidate, which is what we want: an
    // unusable signal should abstain rather than vote for row 0.
    const auto argMaxInRange = [&](const std::vector<double> &profile) {
        int best = -1;
        double bestValue = 0.0;
        for (int y = std::max(firstRow, BandRadius);
             y <= lastRow && y + BandRadius < h; ++y) {
            if (profile[y] > bestValue) {
                bestValue = profile[y];
                best = y;
            }
        }
        if (best < 0) {
            return best;
        }
        // A soft edge scores equally across the rows it spans. The bar's edge
        // is the bottom of that plateau, not its top: reporting the top would
        // place the bar's end above where the content actually begins.
        const double epsilon = std::max(1e-9, bestValue * 1e-6);
        for (int y = best + 1; y <= lastRow && y + BandRadius < h; ++y) {
            if (profile[y] < bestValue - epsilon) {
                break;
            }
            best = y;
        }
        return best;
    };

    std::vector<int> candidates;
    for (const std::vector<double> *profile :
         {&lineLuma, &lineRgb, &meanJump, &varJump}) {
        const int y = argMaxInRange(*profile);
        if (y >= 0) {
            candidates.push_back(y);
        }
    }
    if (getenv("KOS_SCAN_DEBUG")) {
        std::fprintf(stderr, "  candidates: lineLuma=%d lineRgb=%d meanJump=%d varJump=%d (skip %d..%d)\n",
                     argMaxInRange(lineLuma), argMaxInRange(lineRgb),
                     argMaxInRange(meanJump), argMaxInRange(varJump),
                     skipFrom, skipTo);
    }
    return candidates;
}

struct Consensus {
    bool ok = false;
    int row = 0;
    double agreement = 0.0;
};

// The largest group of candidates that landed within AgreementPx of each
// other. Two agreeing signals out of four is enough to be worth looking at,
// but the ratio is reported so callers can see how weak the agreement is.
Consensus consensusOf(std::vector<int> candidates, int total)
{
    Consensus result;
    if (candidates.size() < 2) {
        return result;
    }
    std::sort(candidates.begin(), candidates.end());

    size_t bestStart = 0;
    size_t bestCount = 0;
    for (size_t i = 0; i < candidates.size();) {
        size_t j = i;
        while (j + 1 < candidates.size()
               && candidates[j + 1] - candidates[i] <= AgreementPx) {
            ++j;
        }
        const size_t count = j - i + 1;
        if (count > bestCount) {
            bestCount = count;
            bestStart = i;
        }
        i = j + 1;
    }

    if (bestCount < 2) {
        return result;
    }
    result.ok = true;
    result.row = candidates[bestStart + bestCount / 2];
    result.agreement = double(bestCount) / double(total);
    return result;
}

struct Cluster {
    bool found = false;
    int x0 = 0;
    int x1 = 0;
    int y0 = 0;
    int y1 = 0;
};

// Walk inwards from one edge of the title bar looking for the window's own
// controls.
//
// The profile is "how much of this column differs from the bar's own colour",
// not an edge gradient. A filled circular control has almost no vertical
// gradient -- its boundary is horizontal at the top and bottom -- so an
// edge-based profile misses it entirely and finds the caption instead.
Cluster findClusterFromSide(const PixelBlock &block, int headerbarBottom,
                            bool fromRight, double scale, int barLuma)
{
    Cluster result;
    const int w = block.width;
    if (w < 4 || headerbarBottom < 1) {
        return result;
    }

    // The bar's own bottom edge, and the separator under it, span the window:
    // counting them would make every column look like it carries a control.
    // The detected edge sits BandRadius rows below the last row of the bar
    // (the profiles compare across a band), so the exclusion has to cover that
    // plus the edge and the separator themselves.
    const int inkRows = std::max(1, headerbarBottom - (BandRadius + 2));

    // How far a column's pixels stray from the bar's own colour.
    //
    // Taking the largest deviation rather than counting differing rows is what
    // makes thin glyphs visible: a close button drawn as an X crosses any
    // given column in two or three rows, so a count of differing rows stays
    // near zero and finds nothing, while the deviation is as large as the
    // stroke is dark. A column through the bar alone deviates by the bar's own
    // gradient, which is far smaller; a gradient centred on the bar's median
    // deviates in both directions and so never clears the tolerance at all.
    std::vector<int> ink(w, 0);
    for (int x = 0; x < w; ++x) {
        int worst = 0;
        for (int y = 0; y < inkRows; ++y) {
            worst = std::max(worst, std::abs(block.luma(x, y) - barLuma));
        }
        ink[x] = worst;
    }

    const auto dbg = [&](const char *why, int outerX, int x0v, int x1v, int topv,
                         int botv) {
        if (!getenv("KOS_SCAN_DEBUG")) {
            return;
        }
        std::fprintf(stderr,
                     "  cluster[%s] barLuma=%d tol=%d bottom=%d outer=%d x=[%d,%d) "
                     "w=%d top=%d bot=%d -> %s\n",
                     fromRight ? "R" : "L", barLuma, ControlLumaTolerance,
                     headerbarBottom, outerX, x0v, x1v, x1v - x0v, topv, botv, why);
    };

    int outer = -1;
    if (fromRight) {
        for (int x = w - 1; x >= 0; --x) {
            if (ink[x] > ControlLumaTolerance) {
                outer = x;
                break;
            }
        }
    } else {
        for (int x = 0; x < w; ++x) {
            if (ink[x] > ControlLumaTolerance) {
                outer = x;
                break;
            }
        }
    }
    if (outer < 0) {
        dbg("no column reaches minInk", outer, 0, 0, -1, -1);
        return result;
    }

    // Controls hug an edge. Anything this far in is the caption, which is not
    // something to cover.
    const double inset = fromRight ? double(w - 1 - outer) : double(outer);
    if (inset > w * MaxEdgeInsetFraction) {
        dbg("cluster starts too far from the edge", outer, 0, 0, -1, -1);
        return result;
    }

    // Extend inwards while the structure continues, bridging the gaps between
    // individual controls.
    int inner = outer;
    int gap = 0;
    if (fromRight) {
        for (int x = outer; x >= 0; --x) {
            if (ink[x] > ControlLumaTolerance) {
                inner = x;
                gap = 0;
            } else if (++gap > int(ClusterGapPx * scale)) {
                break;
            }
        }
    } else {
        for (int x = outer; x < w; ++x) {
            if (ink[x] > ControlLumaTolerance) {
                inner = x;
                gap = 0;
            } else if (++gap > int(ClusterGapPx * scale)) {
                break;
            }
        }
    }

    const int x0 = std::min(outer, inner);
    const int x1 = std::max(outer, inner) + 1;
    if (x1 - x0 < MinClusterWidth * scale) {
        dbg("cluster narrower than MinClusterWidth", outer, x0, x1, -1, -1);
        return result;
    }
    if (x1 - x0 > w * MaxClusterFraction) {
        dbg("cluster spans too much of the window", outer, x0, x1, -1, -1);
        return result;
    }

    // Vertical extent: a row belongs to the controls when it carries any part
    // of one. Asking for a share of the cluster's columns instead would miss
    // controls drawn as outlines, whose strokes are only a few pixels wide
    // however wide the cluster around them is.
    int top = -1;
    int bottom = -1;
    const int minColumns = std::max(2, int(2 * scale));
    const int fullWidth = int(w * FullWidthLineFraction);
    for (int y = 0; y < headerbarBottom; ++y) {
        // A separator line spans the window; controls do not. Without this the
        // 1px line under the bar reads as a row of controls and drags the
        // vertical extent down to the bottom of the bar.
        int acrossWindow = 0;
        for (int x = 0; x < w; ++x) {
            if (std::abs(block.luma(x, y) - barLuma) > ControlLumaTolerance) {
                ++acrossWindow;
            }
        }
        if (acrossWindow >= fullWidth) {
            continue;
        }

        int differing = 0;
        for (int x = x0; x < x1; ++x) {
            if (std::abs(block.luma(x, y) - barLuma) > ControlLumaTolerance) {
                ++differing;
            }
        }
        if (differing >= minColumns) {
            if (top < 0) {
                top = y;
            }
            bottom = y;
        }
    }
    if (top < 0 || bottom <= top) {
        dbg("no row carries enough of the cluster", outer, x0, x1, top, bottom);
        return result;
    }

    result.found = true;
    result.x0 = x0;
    result.x1 = x1;
    result.y0 = top;
    result.y1 = bottom + 1;
    dbg("accepted", outer, x0, x1, top, bottom);
    return result;
}

} // namespace

ScanResult scanTitlebar(const PixelBlock &block, ScanSide side, double scale)
{
    ScanResult result;
    if (!block.isValid()) {
        return result;
    }

    const int firstRow = std::max(1, int(MinTitlebarHeight * scale));
    const int lastRow = block.height - 2;
    if (lastRow <= firstRow) {
        return result;
    }

    // The caption sits in the middle of the bar and is far higher contrast
    // than the bar's own bottom edge, so it is excluded from the edge
    // profiles. Both the controls and the caption live away from there.
    const int third = block.width / 3;
    const int skipFrom = third > 8 ? third : 0;
    const int skipTo = third > 8 ? 2 * third : 0;

    const Consensus consensus = consensusOf(
        bottomEdgeCandidates(block, firstRow, lastRow, skipFrom, skipTo), 4);
    if (!consensus.ok) {
        return result;
    }

    // The title bar's own colour: the median luma of the strip above the edge
    // is dominated by the background, because the controls and the caption
    // occupy a minority of it.
    std::vector<int> barLumaSamples;
    barLumaSamples.reserve(size_t(block.width) * size_t(consensus.row + 1));
    for (int y = 0; y <= consensus.row; ++y) {
        for (int x = 0; x < block.width; ++x) {
            barLumaSamples.push_back(block.luma(x, y));
        }
    }
    const int barLuma = int(median(barLumaSamples));

    // Prefer the side the caller asks for. Under Auto the right edge wins
    // whenever it yields a cluster at all, and the left is consulted only when
    // it does not: window controls sit on the right in every layout these
    // applications follow, while the left end of a self-drawn bar is far more
    // often the application's own logo or avatar -- and a logo is a *stronger*
    // cluster than the controls are, so a contest of strength picks the wrong
    // side.
    Cluster best;
    bool buttonsOnRight = true;
    if (side != ScanSide::Left) {
        best = findClusterFromSide(block, consensus.row + 1, true, scale, barLuma);
    }
    if (side != ScanSide::Right && !best.found) {
        const Cluster left =
            findClusterFromSide(block, consensus.row + 1, false, scale, barLuma);
        if (left.found) {
            best = left;
            buttonsOnRight = false;
        }
    }
    if (!best.found) {
        return result;
    }

    result.valid = true;
    result.buttonsOnRight = buttonsOnRight;
    result.confidence = consensus.agreement;
    result.headerbarBottom = consensus.row + 1;
    result.buttonBox = QRect(best.x0, best.y0, best.x1 - best.x0,
                             best.y1 - best.y0);

    // Tint from the title bar's own pixels, sampled away from both the controls
    // and the caption. This is the only colour source that reflects what the
    // application actually drew: KWin's window palette follows kdeglobals,
    // which a GTK or self-drawn title bar has nothing to do with.
    std::vector<int> background;
    const int textLeft = block.width / 3;
    const int textRight = 2 * block.width / 3;
    for (int y = 0; y <= consensus.row; ++y) {
        for (int x = 0; x < block.width; ++x) {
            if (x >= best.x0 && x < best.x1) {
                continue;
            }
            if (x >= textLeft && x < textRight) {
                continue;
            }
            background.push_back(block.luma(x, y));
        }
    }
    if (background.size() < 16) {
        background = barLumaSamples;
    }
    result.dark = median(background) < 128.0;

    return result;
}

} // namespace KOS
