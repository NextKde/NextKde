#include <QImage>
#include <QRect>
#include <QString>
#include <iostream>
#include <stdexcept>

static void check(bool ok, const char *message) {
    if (!ok) throw std::runtime_error(message);
}
static QImage image(const QString &directory, const char *name) {
    QImage result(directory + "/" + name + ".png");
    check(!result.isNull(), "missing shader render");
    check(result.width() * 650 == result.height() * 1100, "glass render changed aspect ratio");
    return result;
}
static QRect bounds(const QImage &image, int threshold = 127) {
    QRect result;
    for (int y = 0; y < image.height(); ++y)
        for (int x = 0; x < image.width(); ++x)
            if (image.pixelColor(x, y).alpha() > threshold)
                result = result.united(QRect(x, y, 1, 1));
    return result;
}
static int alpha(const QImage &image, int x, int y) {
    const qreal scale = image.width() / 1100.0;
    return image.pixelColor(int(x * scale), int(y * scale)).alpha();
}
int main(int argc, char **argv) {
    try {
        check(argc == 2, "pass the captured image directory");
        const QString directory = QString::fromLocal8Bit(argv[1]);
        const QImage closed = image(directory, "closed");
        check(bounds(closed, 0).isEmpty(), "closed glass still paints a capsule");
        const QImage half = image(directory, "half");
        check(alpha(half, 550, 50) == 0 && alpha(half, 100, 630) == 0,
              "half-open mask leaked outside the bottom-centered shape");
        check(alpha(half, 550, 630) > 240, "half-open shape missing at the bottom");
        const QRect halfBounds = bounds(half);
        const qreal scale = half.width() / 1100.0;
        check(qAbs(halfBounds.left() / scale - 235) <= 1.5
            && qAbs(halfBounds.top() / scale - 292.5) <= 1.5,
            "half-open SDF has the wrong position or size");
        const QImage opened = image(directory, "open");
        check(alpha(opened, 50, 100) > 240 && alpha(opened, 550, 50) > 240,
              "expanded plate did not fill its final rectangle");
        check(alpha(opened, 0, 0) == 0, "rounded corner was not clipped");
        const QImage animated = image(directory, "animated");
        const QRect animatedBounds = bounds(animated);
        check(!animatedBounds.isEmpty() && animatedBounds.width() > 160 * scale
            && animatedBounds.width() < 1100 * scale && animatedBounds.top() > 0,
            "UniformAnimator did not produce an intermediate rendered shape");
        check(animatedBounds.bottom() >= animated.height() - 2,
              "animated shape lost its bottom anchor");
        std::cout << "PASS: closed, half, full and in-flight SDF pixels\n";
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
