// Offline harness for the title-bar scan.
//
// The scan is pure geometry over a pixel block, so it can be exercised here
// against synthetic title bars that reproduce the layouts we care about --
// toolkit-drawn headerbars and self-drawn ones -- without a compositor.
//
// Build:  cmake -S . -B build -DKOS_BRIDGE_BUILD_TESTS=ON && cmake --build build
// Run:    QT_QPA_PLATFORM=offscreen build/scan_titlebar [screenshot.png]
//
// A PNG argument scans that image instead of the synthetic cases, which is how
// a captured title bar can be checked without a compositor.

#include "../windowbuttons/titlebarscan.h"

#include <QGuiApplication>
#include <QImage>
#include <QPainter>
#include <QRect>
#include <QString>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <vector>

namespace
{

struct Case {
    const char *name;
    int scale = 1;
    int barHeight = 46;      // logical
    QColor barColor;
    QColor contentColor;
    bool buttonsOnRight = true;
    int buttonCount = 3;
    int buttonSize = 24;     // logical
    int buttonSpacing = 6;   // logical
    int edgeMargin = 6;      // logical, window edge to the first button
    bool roundButtons = true;
    bool drawCaption = true;
    int windowWidth = 1200;  // logical
    // What the scan is expected to conclude.
    bool expectValid = true;
    bool expectDark = false;
    bool expectButtonsOnRight = true;
};

QImage render(const Case &c, QRect *expectedBox)
{
    const int w = c.windowWidth * c.scale;
    const int barH = c.barHeight * c.scale;
    const int h = (c.barHeight + 200) * c.scale;

    QImage image(w, h, QImage::Format_ARGB32_Premultiplied);
    image.fill(c.contentColor);

    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing, true);

    // The title bar itself, with the usual 1px separator under it.
    painter.setPen(Qt::NoPen);
    painter.setBrush(c.barColor);
    painter.drawRect(QRect(0, 0, w, barH));
    painter.setPen(c.barColor.darker(140));
    painter.drawLine(0, barH - 1, w, barH - 1);

    // The window's own controls.
    const int total =
        (c.buttonCount * c.buttonSize + (c.buttonCount - 1) * c.buttonSpacing)
        * c.scale;
    const int margin = c.edgeMargin * c.scale;
    const int x0 = c.buttonsOnRight ? (w - margin - total) : margin;
    const int y0 = (barH - c.buttonSize * c.scale) / 2;
    const int size = c.buttonSize * c.scale;

    painter.setPen(Qt::NoPen);
    for (int i = 0; i < c.buttonCount; ++i) {
        const QRect r(x0 + i * (size + c.buttonSpacing * c.scale), y0, size, size);
        painter.setBrush(QColor(0xff, 0x5f, 0x57));
        if (c.roundButtons) {
            painter.drawEllipse(r);
        } else {
            painter.drawRoundedRect(r, size * 0.2, size * 0.2);
        }
    }

    // A caption in the middle, which the scan must not mistake for controls.
    if (c.drawCaption) {
        QFont font = painter.font();
        font.setPixelSize(13 * c.scale);
        painter.setFont(font);
        painter.setPen(c.barColor.lightness() < 128 ? Qt::white : Qt::black);
        painter.drawText(QRect(0, 0, w, barH), Qt::AlignCenter,
                         QStringLiteral("kos-bridge window title"));
    }

    painter.end();

    *expectedBox = QRect(x0, y0, total, size);
    return image;
}

bool near(int a, int b, int tolerance)
{
    return std::abs(a - b) <= tolerance;
}

int failures = 0;

void check(const char *what, bool ok, const QString &detail)
{
    if (ok) {
        std::printf("    ok    %s\n", what);
        return;
    }
    std::printf("    FAIL  %s -- %s\n", what, qPrintable(detail));
    ++failures;
}

void run(const Case &c)
{
    QRect expected;
    const QImage image = render(c, &expected);

    const KOS::PixelBlock block{
        .data = image.constBits(),
        .width = image.width(),
        .height = image.height(),
        .stride = int(image.bytesPerLine()),
    };

    const KOS::ScanResult r = KOS::scanTitlebar(block, KOS::ScanSide::Auto, c.scale);

    std::printf("%s (scale %d, bar %dpx, %s buttons)\n", c.name, c.scale,
                c.barHeight, c.buttonsOnRight ? "right" : "left");

    if (!c.expectValid) {
        check("reported invalid", !r.valid,
              QStringLiteral("got valid=%1 bottom=%2 box=%3,%4 %5x%6")
                  .arg(r.valid).arg(r.headerbarBottom)
                  .arg(r.buttonBox.x()).arg(r.buttonBox.y())
                  .arg(r.buttonBox.width()).arg(r.buttonBox.height()));
        std::printf("\n");
        return;
    }

    if (!r.valid) {
        check("reported valid", false, QStringLiteral("scan found nothing"));
        std::printf("\n");
        return;
    }

    const int expectedBottom = c.barHeight * c.scale;
    check("headerbar bottom", near(r.headerbarBottom, expectedBottom, 3),
          QStringLiteral("got %1, want ~%2").arg(r.headerbarBottom).arg(expectedBottom));

    check("buttons on right", r.buttonsOnRight == c.expectButtonsOnRight,
          QStringLiteral("got %1").arg(r.buttonsOnRight ? "right" : "left"));

    check("dark", r.dark == c.expectDark,
          QStringLiteral("got %1, want %2")
              .arg(r.dark ? "dark" : "light")
              .arg(c.expectDark ? "dark" : "light"));

    check("box x", near(r.buttonBox.x(), expected.x(), 4),
          QStringLiteral("got %1, want %2").arg(r.buttonBox.x()).arg(expected.x()));
    check("box width", near(r.buttonBox.width(), expected.width(), 8),
          QStringLiteral("got %1, want %2")
              .arg(r.buttonBox.width()).arg(expected.width()));
    check("box y", near(r.buttonBox.y(), expected.y(), 4),
          QStringLiteral("got %1, want %2").arg(r.buttonBox.y()).arg(expected.y()));
    check("box height", near(r.buttonBox.height(), expected.height(), 6),
          QStringLiteral("got %1, want %2")
              .arg(r.buttonBox.height()).arg(expected.height()));

    std::printf("    (confidence %.2f, bottom %d, box %d,%d %dx%d)\n\n", r.confidence,
                r.headerbarBottom, r.buttonBox.x(), r.buttonBox.y(),
                r.buttonBox.width(), r.buttonBox.height());
}

// Scan a real screenshot of a window.
//
// The compositor only ever hands the scan the top of the window, so a
// screenshot is cropped the same way -- otherwise the rest of the window would
// be searched for a bottom edge too, and the answer would be meaningless.
void scanFile(const QString &path, double scale)
{
    QImage image(path);
    if (image.isNull()) {
        std::printf("could not load %s\n", qPrintable(path));
        return;
    }
    image = image.convertToFormat(QImage::Format_ARGB32_Premultiplied);

    const int probe = int(KOS::TitlebarProbeHeight * scale);
    const int strip = std::min(image.height(), probe);
    std::printf("%s: %dx%d, scanning the top %d rows at scale %g\n",
                qPrintable(path), image.width(), image.height(), strip, scale);
    if (strip < image.height()) {
        image = image.copy(0, 0, image.width(), strip);
    }

    const KOS::PixelBlock block{
        .data = image.constBits(),
        .width = image.width(),
        .height = image.height(),
        .stride = int(image.bytesPerLine()),
    };
    const KOS::ScanResult r = KOS::scanTitlebar(block, KOS::ScanSide::Auto, scale);
    std::printf("  valid=%d bottom=%d box=(%d,%d %dx%d) dark=%d right=%d conf=%.2f\n",
                r.valid, r.headerbarBottom, r.buttonBox.x(), r.buttonBox.y(),
                r.buttonBox.width(), r.buttonBox.height(), r.dark,
                r.buttonsOnRight, r.confidence);
    if (!r.valid) {
        std::printf("  (no panel would be drawn for this window)\n");
    }
}

// Write a whole synthetic window -- title bar plus content -- so the offline
// path can be exercised end to end, crop included.
void emitSample(const QString &path)
{
    const Case c{.name = "sample",
                 .barColor = QColor(0xf2, 0xf2, 0xf5),
                 .contentColor = QColor(0xff, 0xff, 0xff)};
    QRect expected;
    const QImage image = render(c, &expected);
    if (!image.save(path)) {
        std::printf("could not write %s\n", qPrintable(path));
        return;
    }
    std::printf("wrote %s (%dx%d); controls drawn at %d,%d %dx%d\n",
                qPrintable(path), image.width(), image.height(), expected.x(),
                expected.y(), expected.width(), expected.height());
}

} // namespace

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);

    const QStringList args = app.arguments().mid(1);
    if (args.size() >= 2 && args.at(0) == QLatin1String("--emit-sample")) {
        emitSample(args.at(1));
        return 0;
    }
    if (!args.isEmpty()) {
        const double scale = args.size() >= 2 ? args.at(1).toDouble() : 1.0;
        scanFile(args.at(0), scale > 0.0 ? scale : 1.0);
        return 0;
    }

    // GTK4 under Breeze: a 46px headerbar, light, three round controls inset
    // 6px from the right edge. This is the layout the old fixed-offset panel
    // got wrong by six pixels vertically.
    run({.name = "GTK4 headerbar, light",
         .barColor = QColor(0xf2, 0xf2, 0xf5),
         .contentColor = QColor(0xff, 0xff, 0xff),
         .expectDark = false});

    run({.name = "GTK4 headerbar, dark",
         .barColor = QColor(0x2a, 0x2a, 0x2e),
         .contentColor = QColor(0x1e, 0x1e, 0x22),
         .expectDark = true});

    // Controls on the left, as a GTK app configured for a macOS layout would
    // draw them.
    run({.name = "GTK4 headerbar, controls left",
         .barColor = QColor(0xf2, 0xf2, 0xf5),
         .contentColor = QColor(0xff, 0xff, 0xff),
         .buttonsOnRight = false,
         .expectButtonsOnRight = false});

    // A self-drawn title bar: taller, square-ish controls, tighter inset.
    run({.name = "self-drawn bar, square controls",
         .barHeight = 40,
         .barColor = QColor(0x20, 0x20, 0x24),
         .contentColor = QColor(0x18, 0x18, 0x1c),
         .buttonSize = 28,
         .buttonSpacing = 2,
         .edgeMargin = 4,
         .roundButtons = false,
         .expectDark = true});

    // Same bar at 2x, which is what a HiDPI output feeds the scan.
    run({.name = "self-drawn bar at 2x",
         .scale = 2,
         .barHeight = 40,
         .barColor = QColor(0x20, 0x20, 0x24),
         .contentColor = QColor(0x18, 0x18, 0x1c),
         .buttonSize = 28,
         .buttonSpacing = 2,
         .edgeMargin = 4,
         .roundButtons = false,
         .expectDark = true});

    // A taller bar with the controls well inboard, so the cluster cannot be
    // found by assuming a fixed inset from the edge.
    run({.name = "wide bar, deep inset",
         .barHeight = 64,
         .barColor = QColor(0x33, 0x33, 0x38),
         .contentColor = QColor(0x28, 0x28, 0x2c),
         .buttonSize = 20,
         .buttonSpacing = 10,
         .edgeMargin = 24,
         .expectDark = true});

    // Controls drawn small and far apart, the way self-drawn title bars do it.
    // DingTalk's own controls are about 11px wide and 21px apart, against the
    // 24px-and-6px-apart shape a toolkit draws. An assumption of tightly
    // packed full-sized controls finds no cluster at all here, and the window
    // gets no panel.
    run({.name = "self-drawn bar, small widely-spaced controls",
         .barHeight = 36,
         .barColor = QColor(0xe2, 0xe2, 0xe6),
         .contentColor = QColor(0xff, 0xff, 0xff),
         .buttonSize = 11,
         .buttonSpacing = 21,
         .edgeMargin = 5,
         .expectDark = false});

    // Nothing to find: a caption but no controls at all.
    run({.name = "caption, no controls",
         .barColor = QColor(0xf2, 0xf2, 0xf5),
         .contentColor = QColor(0xff, 0xff, 0xff),
         .buttonCount = 0,
         .expectValid = false});

    // A window that has not been painted yet reads as a flat block.
    run({.name = "unpainted (flat)",
         .barColor = QColor(0x00, 0x00, 0x00),
         .contentColor = QColor(0x00, 0x00, 0x00),
         .buttonCount = 0,
         .drawCaption = false,
         .expectValid = false});

    std::printf("%s (%d failed)\n", failures ? "FAILURES" : "all passed", failures);
    return failures ? 1 : 0;
}
