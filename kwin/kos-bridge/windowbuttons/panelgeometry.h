#pragma once

#include <QPointF>
#include <QRectF>
#include <QSizeF>

#include <optional>

namespace KOS
{

enum class ButtonPosition {
    Right,  // panel sits against the window's right edge
    Left,
};

// Distance from the window's edges to the panel, in logical pixels. `x` is
// measured from the edge named by `position`.
struct AppOffset {
    qreal x = 10.0;
    qreal y = 6.0;
};

// Everything about where the panel is and how big it is -- and nothing else.
//
// These six values are the whole of what the adjust gesture changes and the
// whole of what a machine-written rule stores (see WindowRuleStore): a window
// whose panel has been dragged keeps the geometry that was dragged into place,
// and a hand-written offset in window-buttons.json stops reaching it. Everything
// else about the panel -- whether it is drawn at all, its tint, how far around
// it takes the pointer -- is a preference that is written rather than dragged,
// and stays the user's to write.
struct PanelGeometry {
    ButtonPosition position = ButtonPosition::Right;
    AppOffset offset;
    qreal buttonSize = 14.0;
    qreal buttonSpacing = 14.0;
    qreal panelPadding = 4.5;
    // Horizontal padding. Negative means "same as panelPadding".
    qreal panelPaddingX = -1.0;
};

// Bounds for the values above. They are enforced by the gesture and again on
// every read, because the rules file is a text file a user may edit, and an
// edit must not be able to produce a ten-thousand-pixel panel.
inline constexpr qreal MinButtonSize = 6.0;
inline constexpr qreal MaxButtonSize = 40.0;
inline constexpr qreal MaxButtonSpacing = 40.0;
// The vertical padding is bounded tightly because it sets how tall the panel is
// on every window -- past this the panel is a bar rather than a chip. The
// horizontal one is bounded loosely because it is the value an application's own
// controls are fitted with: a GTK header bar's controls are wide, a Qt one's are
// narrow, and the panel has to be able to cover either.
inline constexpr qreal MaxPanelPadding = 20.0;
inline constexpr qreal MaxPanelPaddingX = 60.0;
// A bound on nonsense rather than a layout rule: past this the panel is off the
// window and is clipped away anyway.
inline constexpr qreal MaxOffset = 4000.0;

// The horizontal padding, with the "same as panelPadding" sentinel resolved.
qreal effectivePanelPaddingX(const PanelGeometry &);

// The panel's rect in window-local logical pixels, before it is cut down to the
// window. The gesture derives `offset` from this, and the intersection in
// panelRect() below would make that derivation lossy.
QRectF panelRectUnclipped(const PanelGeometry &, const QSizeF &windowSize);
// The rect that is actually drawn: the above, kept inside the window.
QRectF panelRect(const PanelGeometry &, const QSizeF &windowSize);
// The panel's top-left inside the window, unclipped.
QPointF panelOrigin(const PanelGeometry &, const QSizeF &windowSize);
// Where one of the three lights sits inside a panel of this size, in
// panel-local logical pixels. drawPanel() and hitTest() both go through this, so
// the two cannot drift apart.
QRectF dotRect(const QSizeF &panelSize, const PanelGeometry &, int index);

// One edge of the panel. Dragging one moves that edge and leaves the opposite
// one where it is -- see resizedByEdge().
enum class PanelEdge { Left, Right, Top, Bottom };

// The resize grips: one on each edge, in panel-local logical pixels. They are
// what makes the panel's width and height adjustable on their own. The renderer
// draws them while a panel is being adjusted and the adjust session hit-tests
// them through gripAt(); both go through these rects, so what is drawn and what
// is dragged cannot drift apart.
//
// Each is a bar hugging its edge rather than a handle centred on it: the panel is
// only as tall as its lights, so a centred handle would be half outside the rect
// the renderer draws into, and a bar along the edge reads as "this edge moves"
// without any of that.
inline constexpr qreal GripLength = 9.0;
inline constexpr qreal GripThickness = 3.0;
// Grips are hit with a little slack: a drag aimed at an edge should not have to
// land on the bar exactly. The slack stays inside the panel's intercept margin,
// so a grip can never take a press the panel would not have taken anyway.
inline constexpr qreal GripSlack = 3.5;
QRectF gripRect(const PanelGeometry &, PanelEdge);
QRectF gripHitRect(const PanelGeometry &, PanelEdge);
// The grip under a point in panel-local coordinates, if any.
std::optional<PanelEdge> gripAt(const PanelGeometry &, const QPointF &localPos);

// The geometry that puts the panel's top-left here, as far as the window allows.
//
// `position` is derived rather than dragged. The panel's width is fixed by the
// other five values, so there is only one free horizontal coordinate, and
// choosing the side the panel's centre falls on is continuous through the flip
// -- both branches meet at x = (windowWidth - panelWidth) / 2 -- so dragging
// across the middle of a window changes the side without a jump.
PanelGeometry panelGeometryFromTopLeft(PanelGeometry, const QSizeF &windowSize,
                                       const QPointF &topLeft);
// The same geometry moved by `delta`, as far as the window allows.
PanelGeometry nudged(const PanelGeometry &, const QSizeF &windowSize,
                     const QPointF &delta);

// Which of the panel's measurements a wheel step changes.
enum class GeometryField { DotSize, Spacing, Padding };

PanelGeometry resized(const PanelGeometry &, GeometryField, qreal steps);
// The geometry with one edge dragged by `delta` (window coordinates, logical
// pixels), as far as the bounds allow.
//
// The dragged edge follows the pointer and the opposite edge stays where it is,
// whichever of the two the panel is pinned by: on a right-pinned panel that
// makes the right edge the offset and the left edge the width, and on a
// left-pinned panel the other way round. Height is `panelPadding` and width is
// `panelPaddingX`, so neither the lights nor the gaps between them move -- and a
// width that was still following `panelPadding` is pinned to the value it
// currently resolves to, so that only the edge that was dragged moves.
//
// A pinned edge dragged outwards stops at the edge of the window, and the
// movement stops with it: the panel does not go on widening past a pointer that
// can no longer move the edge it is holding.
PanelGeometry resizedByEdge(const PanelGeometry &, PanelEdge, const QPointF &delta);
// Every value inside the bounds above, with panelPaddingX's sentinel left as it
// is.
PanelGeometry clamped(const PanelGeometry &);

// Whether two geometries draw the same panel. The sentinel in `panelPaddingX` is
// resolved first and the values are compared with a tolerance, because they
// arrive from JSON and from pointer motion and a hundredth of a pixel is not a
// difference anyone can see.
bool sameGeometry(const PanelGeometry &, const PanelGeometry &);

} // namespace KOS
