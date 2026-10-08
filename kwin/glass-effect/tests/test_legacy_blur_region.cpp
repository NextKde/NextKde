#include "../src/legacyblurregion.h"

#include <QCoreApplication>
#include <QDebug>
#include <stdexcept>

using namespace KWin;

static void check(bool condition, const char *message)
{
    if (!condition) {
        throw std::runtime_error(message);
    }
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    try {
        SurfaceShape left, right;
        left.geometry = QRectF(20, 217, 144, 44);
        right.geometry = QRectF(172, 217, 144, 44);
        QVector<SurfaceShape> cards{left, right};
        auto region = legacySurfaceBlurRegion(std::nullopt, cards);
        check(region.has_value(), "declared glass cards must request blur without ext-background-effect");
        check(region->contains(QPoint(40, 230)) && region->contains(QPoint(200, 230)), "both cards must blur");
        check(!region->contains(QPoint(168, 230)) && !region->contains(QPoint(10, 230)), "gaps and unused panel area must remain clear");

        cards[0].geometry.translate(0, 52);
        cards[1].enabled = false;
        region = legacySurfaceBlurRegion(std::nullopt, cards);
        check(region && region->contains(QPoint(40, 282)), "moving a card must move its blur");
        check(!region->contains(QPoint(40, 230)) && !region->contains(QPoint(200, 230)), "old geometry and disabled cards must not leave blur");
        cards[0].enabled = false;
        check(!legacySurfaceBlurRegion(std::nullopt, cards), "hiding all cards must remove the fallback request");
        check(!legacySurfaceBlurRegion(std::nullopt, {}), "destroying the last shape must remove the request");

        const QRegion requested(QRect(5, 5, 10, 10));
        check(legacySurfaceBlurRegion(requested, {left, right}) == requested, "legacy KDE blur requests must take precedence");
        const auto empty = legacySurfaceBlurRegion(QRegion(), {left, right});
        check(empty && empty->isEmpty(), "explicit empty region must keep KDE full-surface semantics");
        right.geometry = QRectF(10, 10, 0, 44);
        check(!legacySurfaceBlurRegion(std::nullopt, {right}), "invalid geometry must not trigger whole-surface blur");
        left.geometry = QRectF(1.25, 2.5, 10.5, 11.25);
        check(legacySurfaceBlurRegion(std::nullopt, {left})->boundingRect() == left.geometry.toAlignedRect(), "fractional bounds must cover the declared shape");
        qInfo("Legacy glass blur region tests passed");
    } catch (const std::exception &error) {
        qCritical("%s", error.what());
        return 1;
    }
    return 0;
}
