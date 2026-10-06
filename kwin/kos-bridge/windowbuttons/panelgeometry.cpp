#include "panelgeometry.h"

#include <algorithm>

namespace KOS
{

namespace
{

qreal clamp(qreal value, qreal low, qreal high)
{
    return std::min(std::max(value, low), high);
}

// The panel is exactly the three lights plus the padding around them, on every
// window, so the lights inside it line up with each other from one window to the
// next.
qreal panelWidth(const PanelGeometry &geometry)
{
    return 3 * geometry.buttonSize + 2 * geometry.buttonSpacing
        + 2 * effectivePanelPaddingX(geometry);
}

qreal panelHeight(const PanelGeometry &geometry)
{
    return geometry.buttonSize + 2 * geometry.panelPadding;
}

} // namespace

qreal effectivePanelPaddingX(const PanelGeometry &geometry)
{
    return geometry.panelPaddingX >= 0 ? geometry.panelPaddingX
                                       : geometry.panelPadding;
}

QPointF panelOrigin(const PanelGeometry &geometry, const QSizeF &windowSize)
{
    // `offset` is measured from the edge `position` names, so the panel is
    // pinned to that corner of the window and stays there whatever the
    // application's own controls do.
    const qreal x = geometry.position == ButtonPosition::Left
        ? geometry.offset.x
        : windowSize.width() - geometry.offset.x - panelWidth(geometry);
    return QPointF(x, geometry.offset.y);
}

QRectF panelRectUnclipped(const PanelGeometry &geometry, const QSizeF &windowSize)
{
    return QRectF(panelOrigin(geometry, windowSize),
                  QSizeF(panelWidth(geometry), panelHeight(geometry)));
}

QRectF panelRect(const PanelGeometry &geometry, const QSizeF &windowSize)
{
    // Keep the panel on the window. On a window too small to hold it that eats
    // into the panel rather than hanging it off the edge.
    return panelRectUnclipped(geometry, windowSize)
        .intersected(QRectF(QPointF(0, 0), windowSize));
}

QRectF dotRect(const QSizeF &panelSize, const PanelGeometry &geometry, int index)
{
    const qreal size = geometry.buttonSize;
    const qreal total = 3 * size + 2 * geometry.buttonSpacing;
    const qreal x = (panelSize.width() - total) / 2.0
        + index * (size + geometry.buttonSpacing);
    const qreal y = (panelSize.height() - size) / 2.0;
    return QRectF(x, y, size, size);
}

QRectF gripRect(const PanelGeometry &geometry, PanelEdge edge)
{
    const qreal w = panelWidth(geometry);
    const qreal h = panelHeight(geometry);
    // Lying along its edge and hugging it, with its middle at the middle of the
    // edge: the two side grips are vertical bars against the left and right
    // edges, the other two horizontal bars across the top and the bottom.
    const qreal along = GripLength / 2.0;

    switch (edge) {
    case PanelEdge::Left:
        return QRectF(0, h / 2.0 - along, GripThickness, GripLength);
    case PanelEdge::Right:
        return QRectF(w - GripThickness, h / 2.0 - along, GripThickness, GripLength);
    case PanelEdge::Top:
        return QRectF(w / 2.0 - along, 0, GripLength, GripThickness);
    case PanelEdge::Bottom:
        return QRectF(w / 2.0 - along, h - GripThickness, GripLength, GripThickness);
    }
    return QRectF();
}

QRectF gripHitRect(const PanelGeometry &geometry, PanelEdge edge)
{
    return gripRect(geometry, edge)
        .adjusted(-GripSlack, -GripSlack, GripSlack, GripSlack);
}

std::optional<PanelEdge> gripAt(const PanelGeometry &geometry,
                                const QPointF &localPos)
{
    // The width grips are checked first: they are the two the panel is fitted to
    // an application with -- an application's own controls are what the panel has
    // to cover, and their width is what varies -- so on a panel too small to keep
    // the four apart, a press where two grips overlap is a press about the width.
    for (const PanelEdge edge : {PanelEdge::Left, PanelEdge::Right,
                                 PanelEdge::Top, PanelEdge::Bottom}) {
        if (gripHitRect(geometry, edge).contains(localPos)) {
            return edge;
        }
    }
    return std::nullopt;
}

PanelGeometry panelGeometryFromTopLeft(PanelGeometry geometry,
                                       const QSizeF &windowSize,
                                       const QPointF &topLeft)
{
    const qreal width = panelWidth(geometry);
    const qreal height = panelHeight(geometry);

    // Where the panel was asked to go, as far as the window allows. On a window
    // too small to hold the panel the only place left is the top-left corner,
    // and the drawn rect is cut down to the window from there.
    const qreal x = clamp(topLeft.x(), 0.0,
                          std::max(0.0, windowSize.width() - width));
    const qreal y = clamp(topLeft.y(), 0.0,
                          std::max(0.0, windowSize.height() - height));

    if (x < (windowSize.width() - width) / 2.0) {
        geometry.position = ButtonPosition::Left;
        geometry.offset.x = x;
    } else {
        geometry.position = ButtonPosition::Right;
        geometry.offset.x = windowSize.width() - x - width;
    }
    geometry.offset.y = y;
    return geometry;
}

PanelGeometry nudged(const PanelGeometry &geometry, const QSizeF &windowSize,
                     const QPointF &delta)
{
    // The same path a drag takes, so a nudge and a drag cannot disagree about
    // where the edge of the window is.
    return panelGeometryFromTopLeft(geometry, windowSize,
                                    panelOrigin(geometry, windowSize) + delta);
}

PanelGeometry resized(const PanelGeometry &geometry, GeometryField field,
                      qreal steps)
{
    PanelGeometry out = geometry;
    switch (field) {
    case GeometryField::DotSize:
        out.buttonSize =
            clamp(geometry.buttonSize + steps, MinButtonSize, MaxButtonSize);
        break;
    case GeometryField::Spacing:
        out.buttonSpacing =
            clamp(geometry.buttonSpacing + steps, 0.0, MaxButtonSpacing);
        break;
    case GeometryField::Padding:
        out.panelPadding =
            clamp(geometry.panelPadding + steps, 0.0, MaxPanelPadding);
        // A horizontal padding that was left at "same as panelPadding" follows
        // it. One that was set explicitly is a decision of its own, and resizing
        // the vertical padding is not a reason to move it.
        break;
    }
    // `offset` is untouched, so the panel grows away from the edge it is pinned
    // to rather than away from its own middle.
    return out;
}

PanelGeometry resizedByEdge(const PanelGeometry &geometry, PanelEdge edge,
                            const QPointF &delta)
{
    PanelGeometry out = geometry;

    if (edge == PanelEdge::Top || edge == PanelEdge::Bottom) {
        // Vertical padding is the panel's height, so this is the height grip.
        //
        // A horizontal padding that was still following it is pinned first:
        // dragging the bottom edge of the panel down is not a reason for its
        // width to change too, and on a right-pinned panel the width would grow
        // to the left, away from the edge being dragged.
        out.panelPaddingX = effectivePanelPaddingX(geometry);

        const qreal requested = edge == PanelEdge::Top ? -delta.y() : delta.y();
        const qreal padding =
            clamp(geometry.panelPadding + requested / 2.0, 0.0, MaxPanelPadding);

        // The top edge is the one `offset.y` holds, so dragging it moves the
        // offset -- without this the panel would grow downwards from a top edge
        // the pointer is dragging. That is also what bounds it: the top edge
        // stops at the top of the window, and the movement stops with it rather
        // than going on into the height. The bottom edge is free, and is bounded
        // only by the padding.
        const qreal moved = 2.0 * (padding - geometry.panelPadding);
        const qreal applied = edge == PanelEdge::Top && moved > 0
            ? std::min(moved, geometry.offset.y)
            : moved;

        out.panelPadding = geometry.panelPadding + applied / 2.0;
        if (edge == PanelEdge::Top) {
            out.offset.y = clamp(geometry.offset.y - applied, 0.0, MaxOffset);
        }
        return out;
    }

    // Width, which lives in the horizontal padding: how much of the panel is not
    // lights.
    const qreal oldPaddingX = effectivePanelPaddingX(geometry);
    // The dragged edge's own delta, in padding. `panelPaddingX` appears twice in
    // the panel's width, once at each end, and the grip moves one of them.
    const qreal requested =
        (edge == PanelEdge::Right ? delta.x() : -delta.x()) / 2.0;
    // Whether the edge being dragged is the one the panel is pinned by, and so
    // the case where `offset` has to carry the movement.
    const bool pinnedEdge = (edge == PanelEdge::Right)
        == (geometry.position == ButtonPosition::Right);
    // Which way `offset.x` has to move for the panel's pinned edge to move
    // outwards, away from the window's edge: it shrinks, whichever edge it is
    // measured from.
    const qreal sign = geometry.position == ButtonPosition::Left ? 1.0 : -1.0;

    qreal paddingX = clamp(oldPaddingX + requested, 0.0, MaxPanelPaddingX);

    if (pinnedEdge) {
        // The pinned edge's distance from the window's edge is exactly `offset.x`,
        // and moving that edge moves the offset by twice what it moves the
        // padding. The window's edge is where it stops -- and it has to stop the
        // *whole* movement, not just the offset: a width that went on growing
        // would push the panel's other edge out from under a pointer that is
        // trying to push the pinned one off the window.
        const qreal moved = (edge == PanelEdge::Right ? 1.0 : -1.0)
            * 2.0 * (paddingX - oldPaddingX);
        const qreal shifted = sign * moved;
        const qreal allowed =
            shifted < 0 ? -std::min(geometry.offset.x, -shifted) : shifted;

        // Back into a padding. The two edges that can be pinned are the two the
        // sign and the direction disagree about, so `allowed` is always
        // `-2 * (paddingX - oldPaddingX)` and the same subtraction undoes it
        // either way round.
        paddingX = oldPaddingX - allowed / 2.0;
        out.offset.x = clamp(geometry.offset.x + allowed, 0.0, MaxOffset);
    }

    out.panelPaddingX = paddingX;
    return out;
}

PanelGeometry clamped(const PanelGeometry &geometry)
{
    PanelGeometry out = geometry;
    out.buttonSize =
        clamp(geometry.buttonSize, MinButtonSize, MaxButtonSize);
    out.buttonSpacing =
        clamp(geometry.buttonSpacing, 0.0, MaxButtonSpacing);
    out.panelPadding =
        clamp(geometry.panelPadding, 0.0, MaxPanelPadding);
    out.panelPaddingX = geometry.panelPaddingX < 0
        ? geometry.panelPaddingX
        : clamp(geometry.panelPaddingX, 0.0, MaxPanelPaddingX);
    out.offset.x = clamp(geometry.offset.x, 0.0, MaxOffset);
    out.offset.y = clamp(geometry.offset.y, 0.0, MaxOffset);
    out.position = geometry.position == ButtonPosition::Left
        ? ButtonPosition::Left
        : ButtonPosition::Right;
    return out;
}

bool sameGeometry(const PanelGeometry &a, const PanelGeometry &b)
{
    constexpr qreal Tolerance = 0.01;
    const auto close = [](qreal x, qreal y) {
        return std::abs(x - y) <= Tolerance;
    };

    return a.position == b.position && close(a.offset.x, b.offset.x)
        && close(a.offset.y, b.offset.y) && close(a.buttonSize, b.buttonSize)
        && close(a.buttonSpacing, b.buttonSpacing)
        && close(a.panelPadding, b.panelPadding)
        && close(effectivePanelPaddingX(a), effectivePanelPaddingX(b));
}

} // namespace KOS
