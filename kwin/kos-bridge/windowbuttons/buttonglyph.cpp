#include "buttonglyph.h"

#include <QPainter>
#include <QPainterPath>

namespace KOS
{

QColor dotColor(Type type, bool active)
{
    if (!active) {
        return QColor(0x9a, 0x9a, 0x9e);
    }
    switch (type) {
    case Close: return QColor(0xff, 0x5f, 0x57);
    case Minimize: return QColor(0xfe, 0xbc, 0x2e);
    case Maximize: return QColor(0x28, 0xc8, 0x40);
    // Not a light, the sentinel the loops count to. Named rather than left to a
    // `default:` so that a fourth light is a warning here rather than a colour
    // nobody chose.
    case TypeCount: break;
    }
    return QColor(0x9a, 0x9a, 0x9e);
}

void drawLight(QPainter &painter, const QRectF &dot, Type type, bool active,
               bool maximized)
{
    // The dot is square and is the button size, so its width is the one length
    // every proportion below is taken against.
    const qreal size = dot.width();

    painter.setPen(QPen(QColor(0, 0, 0, 0x33), 0.75));
    painter.setBrush(dotColor(type, active));
    painter.drawEllipse(dot);

    // The two maximize states use different box sizes so their triangular
    // arrows have the same visible leg length, about 5.4 px in a 14 px dot.
    // The restore pair needs most of the disc to do that without its
    // inward-pointing arrows touching in the middle. Both boxes are smaller
    // than the disc by more than the other two marks are, which is what keeps
    // the pair reading as one mark rather than as two corners of the button.
    //
    // The restore box is what holds the leg length equal now that its arm is
    // larger: leg = arm * box, so a closer pair has to sit in a smaller box to
    // stay the same size. 0.72 * 0.54 = 0.48 * 0.81.
    //
    // The X and the bar take the default box. The X's is the one with a floor
    // under it -- its arms run corner to corner, so the four openings between
    // them survive only while the box stays wide enough for the stroke, and a
    // heavier pen pushes that floor up. At the weight below this is that floor.
    qreal inset = size * 0.28;
    if (type == Maximize) {
        inset = size * (maximized ? 0.095 : 0.23);
    }
    const QRectF glyph = dot.adjusted(inset, inset, -inset, -inset);

    // One weight for the X and the bar. The wedges do not consult it at all --
    // they are filled paths, not strokes -- so this is the whole of what the
    // pen decides. The two marks it does draw are both a single stroke, and at
    // one width they read as one weight: the bar is the shorter of the two, not
    // the lighter one.
    //
    // Black ink, and the alpha is the whole of the softening: the marks are
    // drawn over a saturated light rather than over a surface, so one at full
    // strength reads as a hole punched in the dot. White was tried here and
    // measured worse on every one of the three -- 2.0, 1.4 and 1.8 against the
    // red, yellow and green where these are 4.0, 5.3 and 6.4 -- and the yellow
    // light is the reason it cannot be rescued by tuning: white on #febc2e is
    // 1.7 even at full opacity, because the dot is as light as the mark.
    QPen pen(QColor(0, 0, 0, 0xA0));
    pen.setWidthF(size * 0.16);
    pen.setCapStyle(Qt::RoundCap);
    painter.setPen(pen);
    painter.setBrush(Qt::NoBrush);

    switch (type) {
    case Close:
        painter.drawLine(glyph.topLeft(), glyph.bottomRight());
        painter.drawLine(glyph.topRight(), glyph.bottomLeft());
        break;
    case Minimize:
        painter.drawLine(QPointF(glyph.left(), glyph.center().y()),
                          QPointF(glyph.right(), glyph.center().y()));
        break;
    case Maximize: {
        painter.setPen(Qt::NoPen);
        painter.setBrush(QColor(0, 0, 0, 0xC0));

        // The arm is a fraction of the glyph box, and the two states cannot
        // share one. Each wedge is a right triangle whose legs run along two
        // edges of the box: outward (not maximized) the right angle sits on
        // the corner and the wedge fills it, inward (maximized) the right
        // angle sits `arm` in from the corner and the wedge fills the part
        // nearer the centre instead.
        //
        // That puts the two states on opposite sides of the same inequality,
        // and only one of them stays disjoint across the whole range. Let
        // `side` be the box and take the diagonal x + y. Outward, the wedges
        // are x + y <= arm and x + y >= 2 * side - arm: they never meet, for
        // any arm at all. Inward they are x + y >= arm and x + y <=
        // 2 * side - arm, which meet the moment the arm passes the box's
        // centre -- and at the 0.72 the two states used to share, both
        // wedges covered the middle, overlapped by half their own ink, and
        // rendered as one solid mass with no readable shape. 0.48 leaves the
        // pair a gap of half a pixel at the shipped 14 px dot, which is as
        // close as they can come: at 0.50 the two tips meet and the pair reads
        // as one mark again, which is the bug this replaced.
        const qreal armX = glyph.width() * (maximized ? 0.48 : 0.72);
        const qreal armY = glyph.height() * (maximized ? 0.46 : 0.72);

        // Two wedges on the diagonal, and the two states are the two halves
        // of the same pair of squares: not maximized they fill the outer
        // corners and point out of the button, maximized they point at each
        // other instead. Which one is drawn is decided by what clicking the
        // dot would do, so the mark is the same statement the button makes
        // -- an "expand" arrow left on a window that is already maximized
        // would be pointing at a state the window is in.
        QPainterPath tl;
        QPainterPath br;
        if (maximized) {
            tl.moveTo(glyph.left() + armX, glyph.top());
            tl.lineTo(glyph.left(), glyph.top() + armY);
            tl.lineTo(glyph.left() + armX, glyph.top() + armY);

            br.moveTo(glyph.right() - armX, glyph.bottom());
            br.lineTo(glyph.right(), glyph.bottom() - armY);
            br.lineTo(glyph.right() - armX, glyph.bottom() - armY);
        } else {
            tl.moveTo(glyph.topLeft());
            tl.lineTo(glyph.left() + armX, glyph.top());
            tl.lineTo(glyph.left(), glyph.top() + armY);

            br.moveTo(glyph.bottomRight());
            br.lineTo(glyph.right() - armX, glyph.bottom());
            br.lineTo(glyph.right(), glyph.bottom() - armY);
        }
        tl.closeSubpath();
        br.closeSubpath();

        painter.drawPath(tl);
        painter.drawPath(br);
        break;
    }
    default:
        break;
    }
}

} // namespace KOS
