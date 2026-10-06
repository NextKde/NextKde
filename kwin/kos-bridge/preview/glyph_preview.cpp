// Offline preview of the window-button panel.
//
// The panel is pure QPainter geometry over a rectangle, so it can be rendered
// without a compositor, without the effect, and without touching a running
// KWin. That is the whole point: the alternative loop is build -> install to
// /usr -> restart KWin, and a KWin restart takes every Wayland client with it.
// Hot-loading a replaced plugin .so is not a way out either -- it is the
// operation that has crashed KWin before, which is why kosctl's
// reload_kwin_effects() is deliberately called by no command.
//
//   cmake -S kwin/kos-bridge -B build -DKOS_BRIDGE_BUILD_PREVIEW=ON
//   cmake --build build --target glyph_preview
//   QT_QPA_PLATFORM=offscreen build/glyph_preview panel.png
//
// What it draws, top to bottom:
//
//   row 1-2  the whole panel at 1:1, both maximize states, light and dark --
//            what the panel actually looks like on screen, at its actual size
//   row 3-4  the green light alone, at every button size the configuration
//            accepts, magnified to a common on-screen size so the two marks can
//            be compared shape for shape rather than by area
//
// The magnification is what makes this worth running: at the shipped 14 px the
// green light is 14 px across and the mark inside it is 8 or 13 px, which is
// not a thing anyone can judge from a screenshot.

#include "../windowbuttons/buttonglyph.h"
#include "../windowbuttons/panelgeometry.h"

#include <QGuiApplication>
#include <QImage>
#include <QPainter>
#include <QString>

#include <array>
#include <cstdio>

using namespace KOS;

namespace
{

// Matches ButtonRenderer's own supersampling, so what is rendered here is
// rasterised exactly the way the effect rasterises it.
constexpr int Supersample = 4;

// The panel as the effect draws it: an opaque rounded chip, with the three
// lights on it. The hover ring and the adjust ring are deliberately absent --
// they are affordances of a panel that has a pointer on it, and this one does
// not.
QImage buildPanel(const PanelGeometry &geometry, bool maximized, bool dark)
{
    const QSizeF panel =
        panelRectUnclipped(geometry, QSizeF(100000, 100000)).size();
    QImage image(qRound(panel.width() * Supersample),
                 qRound(panel.height() * Supersample),
                 QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);

    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.scale(Supersample, Supersample);

    painter.setPen(Qt::NoPen);
    painter.setBrush(dark ? QColor(28, 28, 32) : QColor(242, 242, 245));
    painter.drawRoundedRect(QRectF(QPointF(0, 0), panel), panel.height() / 2.0,
                            panel.height() / 2.0);

    for (int i = 0; i < TypeCount; ++i) {
        // The order the panel is laid out in, which ButtonRenderer::typeAt owns.
        // Repeated here rather than shared because the preview must be able to
        // show a panel whose order is being reconsidered, and a preview that
        // reads the order out of the thing it is previewing cannot do that.
        constexpr Type Order[TypeCount] = {Maximize, Minimize, Close};
        drawLight(painter, dotRect(panel, geometry, i), Order[i], true,
                  maximized);
    }

    painter.end();
    return image;
}

} // namespace

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    const QString path = argc > 1 ? QString::fromLocal8Bit(argv[1])
                                  : QStringLiteral("panel.png");

    // Everything the configuration accepts, so the marks are checked at the
    // sizes a user can actually drag the panel to rather than only at the
    // shipped default.
    constexpr std::array<qreal, 6> Sizes{6.0, 10.0, 14.0, 20.0, 28.0, 40.0};
    constexpr qreal Cell = 118.0;      // on-screen box for one magnified light
    constexpr qreal RowH = Cell + 30.0;

    PanelGeometry geometry;
    const QSizeF defaultPanel =
        panelRectUnclipped(geometry, QSizeF(100000, 100000)).size();

    const qreal stripW = Cell * qreal(Sizes.size()) + 20.0;
    const qreal headerH = defaultPanel.height() * 2.0 + 90.0;

    QImage sheet(int(std::max(stripW, defaultPanel.width() * 2 + 60) + 40),
                 int(headerH + RowH * 2 + 30), QImage::Format_RGB32);
    sheet.fill(QColor(58, 62, 70));

    QPainter p(&sheet);
    p.setRenderHint(QPainter::Antialiasing, true);
    p.setRenderHint(QPainter::SmoothPixmapTransform, true);
    QFont font = p.font();
    font.setPixelSize(12);
    p.setFont(font);

    // --- the panel at its actual size -------------------------------------
    p.setPen(QColor(210, 215, 225));
    p.drawText(QPointF(20, 22),
               QStringLiteral("the panel at 1:1 — left: maximized=false "
                              "(expand)   right: maximized=true (restore)"));
    qreal y = 34.0;
    for (bool dark : {false, true}) {
        const QImage left = buildPanel(geometry, false, dark);
        const QImage right = buildPanel(geometry, true, dark);
        p.drawImage(QRectF(20, y, defaultPanel.width(), defaultPanel.height()),
                    left);
        p.drawImage(QRectF(20 + defaultPanel.width() + 16, y,
                           defaultPanel.width(), defaultPanel.height()),
                    right);
        y += defaultPanel.height() + 12;
    }

    // --- the green light across the range of button sizes -----------------
    y += 24.0;
    p.setPen(QColor(210, 215, 225));
    p.drawText(QPointF(20, y - 8),
               QStringLiteral("the green light, magnified — top: maximized="
                              "false   bottom: maximized=true"));
    y += 4.0;

    for (bool maximized : {false, true}) {
        for (std::size_t i = 0; i < Sizes.size(); ++i) {
            PanelGeometry sized;
            sized.buttonSize = Sizes[i];
            const QImage panel = buildPanel(sized, maximized, false);
            const QRectF dot = dotRect(
                panelRectUnclipped(sized, QSizeF(100000, 100000)).size(), sized,
                0);
            // A common on-screen size per cell, so the two marks are compared
            // shape for shape rather than by area -- which is exactly the
            // comparison that is impossible at 1:1. drawImage scales the source
            // rect into the cell, so the magnification is implicit in the two
            // rectangles and there is no factor to name.
            const QRectF cell(20 + Cell * qreal(i), y, Cell, Cell);
            p.drawImage(cell, panel,
                        QRectF(dot.x() * Supersample, dot.y() * Supersample,
                               dot.width() * Supersample,
                               dot.height() * Supersample));
            p.setPen(QColor(150, 156, 168));
            p.drawText(QPointF(cell.left(), cell.bottom() + 14),
                       QString::number(int(Sizes[i])) + QStringLiteral("px"));
        }
        y += RowH;
    }

    p.end();
    sheet.save(path);
    std::printf("wrote %s\n", qPrintable(path));
    return 0;
}
