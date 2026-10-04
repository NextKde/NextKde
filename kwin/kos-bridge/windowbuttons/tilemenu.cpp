#include "tilemenu.h"

#include <algorithm>

namespace KOS
{

namespace
{
constexpr int CellCount = TileMenuColumns * TileMenuRows;

// One third of a width, in whole logical pixels.
//
// Rounded here and subtracted rather than rounded twice: a third and its
// complement then add up to the whole exactly, which is what lets two windows
// placed with a pair of these meet with no seam and no overlap between them.
qreal thirdOf(qreal width)
{
    return std::max<qreal>(0.0, qRound(width / 3.0));
}
} // namespace

TilePreset tilePresetAt(int index)
{
    // The cell at each position, in reading order. The same order as the enum,
    // which is why this looks redundant -- it is the one place the layout is
    // decided, so reordering the menu is reordering this table and nothing
    // else: the pictograms, the hit testing and the actions all ask here.
    constexpr TilePreset Order[CellCount] = {
        TilePreset::Fill,          TilePreset::LeftHalf,
        TilePreset::RightHalf,     TilePreset::Restore,
        TilePreset::LeftThird,     TilePreset::LeftTwoThirds,
        TilePreset::RightTwoThirds, TilePreset::RightThird,
    };
    static_assert(CellCount == TilePresetCount,
                  "the menu's grid has to hold every preset");
    if (index < 0 || index >= CellCount) {
        return TilePreset::Fill;
    }
    return Order[index];
}

QSizeF tileMenuSize()
{
    return QSizeF(TileMenuPadding * 2.0 + TileMenuColumns * TileMenuCell
                      + (TileMenuColumns - 1) * TileMenuGap,
                  TileMenuPadding * 2.0 + TileMenuRows * TileMenuCell
                      + (TileMenuRows - 1) * TileMenuGap);
}

std::optional<QRectF> tileMenuRect(const QRectF &panelRect,
                                   const QRectF &windowRect, const QPointF &anchor)
{
    const QSizeF size = tileMenuSize();

    // The menu lives inside the window, inset from its edges like everything
    // else this effect draws, and below the panel.
    const qreal left = windowRect.left() + TileMenuInset;
    const qreal right = windowRect.right() - TileMenuInset;
    if (right - left < size.width()) {
        return std::nullopt;
    }
    const qreal top = panelRect.bottom();
    if (top + size.height() > windowRect.bottom() - TileMenuInset) {
        return std::nullopt;
    }

    // Centred on the anchor -- the light that opened it -- and then slid back
    // inside the window. The anchor only leaves the menu's columns when the
    // window is too narrow to hold the menu under the light at all, and the
    // caller's region check covers that.
    const qreal x = std::clamp(anchor.x() - size.width() / 2.0, left,
                               right - size.width());
    return QRectF(QPointF(x, top), size);
}

TileMenuCells tileMenuCells(const QRectF &menuRect)
{
    TileMenuCells cells;
    for (int i = 0; i < TilePresetCount; ++i) {
        const int column = i % TileMenuColumns;
        const int row = i / TileMenuColumns;
        cells[i] = QRectF(menuRect.left() + TileMenuPadding
                              + column * (TileMenuCell + TileMenuGap),
                          menuRect.top() + TileMenuPadding
                              + row * (TileMenuCell + TileMenuGap),
                          TileMenuCell, TileMenuCell);
    }
    return cells;
}

std::optional<TilePreset> tileMenuPresetAt(const QRectF &menuRect,
                                           const QPointF &point)
{
    if (menuRect.isEmpty() || !menuRect.contains(point)) {
        return std::nullopt;
    }
    const TileMenuCells cells = tileMenuCells(menuRect);
    for (int i = 0; i < TilePresetCount; ++i) {
        if (cells[i].contains(point)) {
            return tilePresetAt(i);
        }
    }
    // The padding around the cells or one of the gaps between them: part of the
    // menu, but not part of any cell.
    return std::nullopt;
}

QRectF tilePresetRect(TilePreset preset, const QRectF &workArea)
{
    const qreal third = thirdOf(workArea.width());
    const qreal twoThirds = workArea.width() - third;

    switch (preset) {
    case TilePreset::LeftThird:
        return QRectF(workArea.left(), workArea.top(), third, workArea.height());
    case TilePreset::LeftTwoThirds:
        return QRectF(workArea.left(), workArea.top(), twoThirds,
                      workArea.height());
    case TilePreset::RightTwoThirds:
        return QRectF(workArea.right() - twoThirds, workArea.top(), twoThirds,
                      workArea.height());
    case TilePreset::RightThird:
        return QRectF(workArea.right() - third, workArea.top(), third,
                      workArea.height());

    // Not placements. The halves and the whole area are KWin's own tiling and
    // maximizing, and Restore puts back a rectangle this effect remembered --
    // none of the three is a rectangle to compute, and none of them comes
    // through here. Named rather than left to a `default:` so that a fifth
    // placement is a warning at this spot rather than a silent empty rect.
    case TilePreset::Fill:
    case TilePreset::LeftHalf:
    case TilePreset::RightHalf:
    case TilePreset::Restore:
    case TilePreset::Count:
        break;
    }
    return QRectF();
}

} // namespace KOS
