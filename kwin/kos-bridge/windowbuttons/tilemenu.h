#pragma once

#include <QPointF>
#include <QRectF>
#include <QSizeF>

#include <array>
#include <optional>

namespace KOS
{

// The tiling menu that the zoom light opens under the panel.
//
// What one cell does to the window, in the order the cells are laid out: two
// rows of four, reading order. `tilePresetAt` is the only place that order
// lives -- the pictograms, the hit testing and the actions all follow it, the
// same way ButtonRenderer::typeAt is the only place the three lights' order
// lives.
//
// Which of them is native and which is not is the difference the menu has to
// live with: KWin tiles halves and maximizes, and has no notion of a third at
// all, so those four are placements this effect makes itself. See
// tilePresetRect.
enum class TilePreset {
    Fill,  // the whole work area
    LeftHalf,
    RightHalf,
    Restore,  // leave whatever whole-window state the window is in
    LeftThird,
    LeftTwoThirds,
    RightTwoThirds,
    RightThird,
    Count,
};

inline constexpr int TilePresetCount = static_cast<int>(TilePreset::Count);

// Which preset the cell at `index` (reading order) holds.
TilePreset tilePresetAt(int index);

// The menu's geometry, in logical pixels. The cells are square so that the
// pictograms in them are the same size whichever way round they are, and the
// gap is what separates them -- there is no separator line, the cells are
// simply apart from each other.
inline constexpr int TileMenuColumns = 4;
inline constexpr int TileMenuRows = 2;
inline constexpr qreal TileMenuCell = 30.0;
inline constexpr qreal TileMenuPadding = 5.0;
inline constexpr qreal TileMenuGap = 3.0;
// How far the menu stays from the window's own edges.
inline constexpr qreal TileMenuInset = 6.0;
inline constexpr qreal TileMenuRadius = 10.0;

QSizeF tileMenuSize();
using TileMenuCells = std::array<QRectF, TilePresetCount>;

// Where the menu goes, or nothing when it does not fit.
//
// Its top edge is on the panel's bottom edge -- not a few pixels below it -- so
// that the walk from the light that opened it down into the menu never leaves
// the menu and the panel between them. `anchor` is the light's centre: the menu
// is centred on it and then slid back inside the window, so the anchor stays
// within the menu's columns wherever the menu had to end up.
//
// Nothing is returned when the menu would be wider than the window or would not
// fit between the panel and the bottom of the window: a menu that opens clipped
// is worse than one that does not open, and a window that short has no room for
// any of the placements anyway.
std::optional<QRectF> tileMenuRect(const QRectF &panelRect,
                                  const QRectF &windowRect, const QPointF &anchor);

// The cells of a menu box, in reading order.
TileMenuCells tileMenuCells(const QRectF &menuRect);
// The preset of the cell under a point, if it is in one: the padding and the
// gaps between the cells are not part of any cell.
std::optional<TilePreset> tileMenuPresetAt(const QRectF &menuRect,
                                           const QPointF &point);

// The rectangle a preset puts the window in, within the work area the window
// may occupy -- **only for the four thirds**, which are the presets this effect
// places itself. Everything else comes back empty, because it is not a
// rectangle: the halves and the whole area are KWin's own tiling and
// maximizing, and Restore puts back a rectangle that was remembered rather than
// computed. An empty answer is how a preset that has no placement cannot
// accidentally be given one.
//
// The thirds are rounded to whole logical pixels and the two that complement
// each other are derived from the same rounding -- the second is the remainder
// -- so a third and its complement tile the work area exactly: two windows
// placed that way meet with no seam and no overlap.
QRectF tilePresetRect(TilePreset, const QRectF &workArea);

} // namespace KOS
