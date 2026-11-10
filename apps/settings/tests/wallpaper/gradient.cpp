#include "../../src/WallpaperGradient.h"
#include <QCoreApplication>
#include <QDebug>

static void check(bool condition, const char *message) {
  if (!condition)
    qFatal("%s", message);
}

int main(int argc, char **argv) {
  QCoreApplication app(argc, argv);
  using namespace WallpaperGradient;
  for (const QColor color :
       {QColor("#000000"), QColor("#FFFFFF"), QColor("#FF0000"),
        QColor("#00FF00"), QColor("#0000FF"), QColor("#70A0F5")}) {
    const auto rgb = toSrgb(toLab(color));
    check(std::abs(rgb.r - color.redF()) < 1.0 / 255 &&
              std::abs(rgb.g - color.greenF()) < 1.0 / 255 &&
              std::abs(rgb.b - color.blueF()) < 1.0 / 255,
          "sRGB round trip changed the color");
  }
  const Lab saturated{0.7, 0.4, -0.3};
  const auto rgb = toSrgb(saturated);
  const Lab mapped = toLab(QColor::fromRgbF(rgb.r, rgb.g, rgb.b));
  check(std::abs(mapped.l - saturated.l) < 0.002,
        "gamut mapping changed lightness");
  check(std::abs(std::atan2(mapped.b, mapped.a) -
                 std::atan2(saturated.b, saturated.a)) < 0.002,
        "gamut mapping changed hue");
  const QImage solid =
      render(QColor("#A8C8F0"), QColor("#A8C8F0"), 90, QSize(16, 16));
  for (int y = 0; y < solid.height(); ++y)
    for (int x = 0; x < solid.width(); ++x)
      check(solid.pixelColor(x, y) == QColor("#A8C8F0"),
            "solid color acquired shading/noise");
  const QColor dark("#303030"), light("#E0E0E0");
  for (int angle : {0, 45, 90, 180, 270}) {
    const QImage image = render(dark, light, angle, QSize(320, 180));
    check(image == render(dark, light, angle, image.size()),
          "dither must be deterministic");
    check(image.colorSpace() == QColorSpace(QColorSpace::SRgb),
          "missing sRGB profile");
    const auto red = [&image](int x, int y) {
      return image.pixelColor(x, y).red();
    };
    const int horizontal = red(310, 90) - red(10, 90);
    const int vertical = red(160, 170) - red(160, 10);
    if (angle == 0)
      check(horizontal > 140 && std::abs(vertical) < 10, "0 degree direction");
    if (angle == 90)
      check(vertical > 140 && std::abs(horizontal) < 10, "90 degree direction");
    if (angle == 180)
      check(horizontal < -140, "180 degree direction");
    if (angle == 270)
      check(vertical < -140, "270 degree direction");
    if (angle == 45)
      check(horizontal > 60 && vertical > 30, "diagonal direction");
    for (int y = 0; y < image.height(); ++y)
      for (int x = 0; x < image.width(); ++x) {
        const auto c = image.pixelColor(x, y);
        check(c.red() == c.green() && c.green() == c.blue(),
              "neutral gradient acquired a tint");
      }
  }
  const QStringList palette{"#7CABFF", "#F5A1E4", "#67EAE5"};
  const QImage rich = render(QColor("#906CCB"), QColor("#77DFFF"), 90,
                             QSize(320, 180), palette);
  const auto left = rich.pixelColor(10, 90), right = rich.pixelColor(310, 90);
  check(std::abs(left.red() - right.red()) +
                std::abs(left.green() - right.green()) +
                std::abs(left.blue() - right.blue()) >
            40,
        "independent accents must produce visible horizontal color separation");
  auto changedPalette = palette;
  for (int i = 0; i < 3; ++i) {
    changedPalette = palette;
    changedPalette[i] = "#F6B980";
    check(rich != render(QColor("#906CCB"), QColor("#77DFFF"), 90,
                         QSize(320, 180), changedPalette),
          "each palette color must affect the image");
  }
  const QImage equalEnds = render(QColor("#7CABFF"), QColor("#7CABFF"), 90,
                                  QSize(320, 180), palette);
  check(equalEnds.pixelColor(10, 90) != equalEnds.pixelColor(310, 90),
        "equal endpoints must not discard independent accent colors");
  qInfo("wallpaper renderer: round trips, gamut, solids, angles, neutral "
        "colors, profile and deterministic dither passed");
}
