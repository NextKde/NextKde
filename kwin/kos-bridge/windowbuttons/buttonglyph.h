#pragma once

#include <QColor>
#include <QRectF>

class QPainter;

namespace KOS
{

// One of the three lights. `Type` is what a light *is* -- its colour, its mark,
// the action it performs -- and where it sits is a separate decision, which
// lives in ButtonRenderer::typeAt and nowhere else, so the same three lights can
// be laid out in any order without touching any of this.
enum Type { Close = 0, Minimize = 1, Maximize = 2, TypeCount = 3 };

// The dot's fill. `active` is whether the panel's window is the active window;
// the lights of an inactive one are all the same grey, so which light is which
// has to be read from its position rather than from its colour.
QColor dotColor(Type type, bool active);

// Draw one light -- the dot and the mark inside it -- filling `dot`.
//
// `maximized` selects the green light's mark and is ignored by the other two: a
// window that is maximized offers to restore, so the mark is what clicking the
// dot would do.
//
// Deliberately free of KWin headers, like panelgeometry.h and windowrules.h.
// The mark inside a light is pure QPainter geometry over a rectangle, and being
// able to draw it without a compositor is the point of it being a unit of its
// own: preview/glyph_preview.cpp renders these lights to a PNG in about a
// second, with no effect to build, install, or restart a compositor for. That
// loop is the reason the code lives here rather than inline in buildPanel() --
// a mark that can only be looked at by installing the effect is a mark that
// gets tuned blind.
void drawLight(QPainter &painter, const QRectF &dot, Type type, bool active,
               bool maximized);

} // namespace KOS
