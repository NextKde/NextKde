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
        SurfaceShape expanding;
        expanding.captureGeometry = QRectF(100, 50, 832, 632);
        for (int frame = 0; frame <= 60; ++frame) {
            const qreal progress = frame / 60.0;
            const qreal width = 176 + 624 * progress;
            const qreal height = 48 + 552 * progress;
            expanding.geometry = QRectF(116 + (800 - width) / 2, 66 + 600 - height, width, height);
            const auto capture = legacySurfaceBlurRegion(std::nullopt, {expanding});
            check(capture && capture->boundingRect() == expanding.captureGeometry.toAlignedRect(),
                  "expanding and offset outlines must retain the complete fixed capture");
            check(capture->contains(expanding.geometry.toAlignedRect()), "capture must contain every animation frame");
        }
        expanding.enabled = false;
        check(!legacySurfaceBlurRegion(std::nullopt, {expanding}), "closing a fixed-capture shape must remove its request");
        expanding.enabled = true;
        expanding.geometry = QRectF(90, 40, 900, 700);
        check(surfaceCaptureBounds(expanding).contains(expanding.geometry), "an out-of-bounds outline must not sample outside its allocation");
        expanding.captureGeometry = QRectF();
        check(surfaceCaptureBounds(expanding) == expanding.geometry, "clearing fixed capture must restore the legacy policy");
        qInfo("Legacy glass blur region tests passed");
    } catch (const std::exception &error) {
        qCritical("%s", error.what());
        return 1;
    }
    return 0;
}
