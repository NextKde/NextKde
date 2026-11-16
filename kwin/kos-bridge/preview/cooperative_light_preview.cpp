// VM-only raster acceptance for the production cooperative-button texture.
#include "../windowbuttons/buttonglyph.h"
#include <QGuiApplication>
#include <QPainter>
#include <cstdio>
#include <cmath>

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    QImage sheet(800, 400, QImage::Format_ARGB32_Premultiplied);
    sheet.fill(QColor(35,35,40));
    QPainter painter(&sheet);
    int row = 0;
    for (qreal scale : {1., 1.25, 1.5, 2.}) {
        painter.setPen(Qt::white);
        painter.drawText(10, row*100+18, QStringLiteral("scale %1: normal / hover (enlarged)").arg(scale));
        int column = 0;
        for (bool hovered : {false, true}) {
            for (auto type : {KOS::Close, KOS::Minimize, KOS::Maximize}) {
                const QImage image = KOS::renderCooperativeLight(QSizeF(14,14), scale, type, true, hovered, false, false);
                // A transparent border prevents clipped strokes and GL edge
                // clamping from stretching colored pixels into flat sides.
                for (int i = 0; i < image.width(); ++i) {
                    if (qAlpha(image.pixel(i,0)) || qAlpha(image.pixel(i,image.height()-1))
                        || qAlpha(image.pixel(0,i)) || qAlpha(image.pixel(image.width()-1,i))) {
                        std::fprintf(stderr,"Clipped circle/halo at scale %.2f\n",scale); return 1;
                    }
                }
                double total=0, asymmetry=0;
                for (int y=0;y<image.height();++y) for(int x=0;x<image.width();++x) {
                    total += qAlpha(image.pixel(x,y));
                    asymmetry += std::abs(qAlpha(image.pixel(x,y))-qAlpha(image.pixel(y,x)));
                }
                if (!total || asymmetry/total > .02) return 2;
                painter.setRenderHint(QPainter::SmoothPixmapTransform, false);
                painter.drawImage(QRectF(10+column*125,row*100+24,72,72),image);
                ++column;
            }
        }
        ++row;
    }
    painter.end();
    if (argc>1 && !sheet.save(QString::fromLocal8Bit(argv[1]))) return 3;
    std::puts("PASS: transparent circle/halo edges and radial symmetry at 1x, 1.25x, 1.5x, 2x");
}
