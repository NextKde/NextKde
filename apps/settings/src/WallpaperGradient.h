#pragma once

#include <QColor>
#include <QColorSpace>
#include <QImage>
#include <QPointF>
#include <QStringList>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <vector>

namespace WallpaperGradient {

struct Lab {
  double l, a, b;
};
struct Rgb {
  double r, g, b;
};

// Oklab matrices: Björn Ottosson, https://bottosson.github.io/posts/oklab/.
// Decode sRGB before the matrix transform; encode only after interpolation.
inline double linear(double c) {
  return c <= 0.04045 ? c / 12.92 : std::pow((c + 0.055) / 1.055, 2.4);
}

inline Lab toLab(const QColor &color) {
  const double r = linear(color.redF()), g = linear(color.greenF()),
               b = linear(color.blueF());
  if (r == g && g == b)
    return {std::cbrt(r), 0, 0};
  const double l =
      std::cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const double m =
      std::cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const double s =
      std::cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return {0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
          1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
          0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s};
}

inline Rgb toLinear(Lab c) {
  const double l = std::pow(c.l + 0.3963377774 * c.a + 0.2158037573 * c.b, 3);
  const double m = std::pow(c.l - 0.1055613458 * c.a - 0.0638541728 * c.b, 3);
  const double s = std::pow(c.l - 0.0894841775 * c.a - 1.2914855480 * c.b, 3);
  return {4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
          -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
          -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s};
}

inline bool inGamut(Rgb c) {
  constexpr double epsilon = 1e-6;
  return std::min({c.r, c.g, c.b}) >= -epsilon &&
         std::max({c.r, c.g, c.b}) <= 1 + epsilon;
}

inline double encode(double c) {
  c = std::clamp(c, 0.0, 1.0);
  return c <= 0.0031308 ? 12.92 * c : 1.055 * std::pow(c, 1 / 2.4) - 0.055;
}

inline Rgb toSrgb(Lab c) {
  if (c.a == 0 && c.b == 0) {
    const double gray = encode(c.l * c.l * c.l);
    return {gray, gray, gray};
  }
  // Reduce chroma at constant lightness/hue instead of clipping individual
  // channels, which flattens saturated blue, yellow and custom colors.
  Rgb rgb = toLinear(c);
  if (!inGamut(rgb)) {
    double low = 0, high = 1;
    for (int i = 0; i < 14; ++i) {
      const double scale = (low + high) / 2;
      if (inGamut(toLinear({c.l, c.a * scale, c.b * scale})))
        low = scale;
      else
        high = scale;
    }
    rgb = toLinear({c.l, c.a * low, c.b * low});
  }
  return {encode(rgb.r), encode(rgb.g), encode(rgb.b)};
}

inline Lab mix(Lab a, Lab b, double t) {
  return {a.l + (b.l - a.l) * t, a.a + (b.a - a.a) * t, a.b + (b.b - a.b) * t};
}

inline double smooth(double t) { return t * t * (3 - 2 * t); }

inline QImage render(const QColor &start, const QColor &end, int angle,
                     QSize size = QSize(1920, 1080),
                     const QStringList &colors = {}) {
  QImage image(size, QImage::Format_RGB32);
  image.setColorSpace(QColorSpace::SRgb);
  if (start == end && colors.isEmpty()) {
    image.fill(start);
    return image;
  }
  const Lab first = toLab(start), last = toLab(end);
  Lab middle = mix(first, last, 0.52);
  // A fuller color in the middle, with a spacious, pale lower light field.
  middle.a *= 1.12;
  middle.b *= 1.12;
  const bool multicolor = colors.size() == 3;
  if (multicolor)
    middle = toLab(QColor(colors[0]));
  const auto baseColor = [first, middle, last](double t) {
    return t < 0.53 ? mix(first, middle, smooth(t / 0.53))
                    : mix(middle, last, smooth((t - 0.53) / 0.47));
  };
  constexpr int samples = 4096;
  std::array<Rgb, samples> ramp;
  for (int i = 0; i < samples; ++i) {
    const double t = double(i) / (samples - 1);
    ramp[i] = toSrgb(baseColor(t));
  }
  // Precompute a perceptual two-dimensional color field. The grid is only
  // used during PNG generation; the desktop still displays one static image.
  constexpr int columns = 160, rows = 160;
  std::vector<Rgb> colorField;
  if (multicolor) {
    colorField.resize((columns + 1) * (rows + 1));
    const Lab left = toLab(QColor(colors[1])), right = toLab(QColor(colors[2]));
    for (int y = 0; y <= rows; ++y) {
      const double t = double(y) / rows;
      for (int x = 0; x <= columns; ++x) {
        const double u = double(x) / columns;
        const double lx = (u - 0.10) / 0.95, ly = (t - 0.34) / 0.62;
        const double rx = (u - 0.95) / 0.95, ry = (t - 0.76) / 0.65;
        const double leftWeight =
            smooth(std::max(0.0, 1 - lx * lx - ly * ly)) * 0.48;
        const double rightWeight =
            smooth(std::max(0.0, 1 - rx * rx - ry * ry)) * 0.46;
        const Lab base = baseColor(t);
        // Normalize simultaneously: swapping the two accents must not change
        // how strongly either one contributes in overlapping regions.
        const double baseWeight = 1 - leftWeight - rightWeight;
        colorField[y * (columns + 1) + x] = toSrgb(
            {base.l * baseWeight + left.l * leftWeight + right.l * rightWeight,
             base.a * baseWeight + left.a * leftWeight + right.a * rightWeight,
             base.b * baseWeight + left.b * leftWeight +
                 right.b * rightWeight});
      }
    }
  }
  const double radians = angle * 3.14159265358979323846 / 180;
  const QPointF direction(std::cos(radians), std::sin(radians));
  const double extent = std::abs(direction.x()) * size.width() / 2 +
                        std::abs(direction.y()) * size.height() / 2;
  for (int y = 0; y < size.height(); ++y) {
    auto *row = reinterpret_cast<QRgb *>(image.scanLine(y));
    const double ny = (y + 0.5) / size.height();
    for (int x = 0; x < size.width(); ++x) {
      const double nx = (x + 0.5) / size.width();
      const double t = 0.5 + ((x + 0.5 - size.width() / 2.0) * direction.x() +
                              (y + 0.5 - size.height() / 2.0) * direction.y()) /
                                 (2 * extent);
      // Broad off-centre light, without a visible circle or dark vignette.
      const double dx = (nx - 0.72) / 0.9, dy = (ny - 0.78) / 0.85;
      const double field = std::max(0.0, 1 - dx * dx - dy * dy);
      const double glow = smooth(field) * (multicolor ? 0.012 : 0.055);
      Rgb c = ramp[std::clamp(int(t * (samples - 1)), 0, samples - 1)];
      if (multicolor) {
        const double cross =
            0.5 + ((nx - 0.5) * direction.y() - (ny - 0.5) * direction.x()) /
                      (std::abs(direction.x()) + std::abs(direction.y()));
        const double gx = std::clamp(cross, 0.0, 1.0) * columns;
        const double gy = std::clamp(t, 0.0, 1.0) * rows;
        const int ix = std::min(int(gx), columns - 1),
                  iy = std::min(int(gy), rows - 1);
        const double fx = gx - ix, fy = gy - iy;
        const auto blend = [](Rgb a, Rgb b, double w) {
          return Rgb{a.r + (b.r - a.r) * w, a.g + (b.g - a.g) * w,
                     a.b + (b.b - a.b) * w};
        };
        c = blend(blend(colorField[iy * (columns + 1) + ix],
                        colorField[iy * (columns + 1) + ix + 1], fx),
                  blend(colorField[(iy + 1) * (columns + 1) + ix],
                        colorField[(iy + 1) * (columns + 1) + ix + 1], fx),
                  fy);
      }
      // Stable, sub-LSB noise breaks quantization bands in the 8-bit PNG.
      uint32_t hash = uint32_t(x) * 374761393u + uint32_t(y) * 668265263u;
      hash = (hash ^ (hash >> 13)) * 1274126177u;
      hash ^= hash >> 16;
      const double noise = (double(hash & 65535) / 65535 - 0.5) * 0.85;
      const auto channel = [glow, noise](double v) {
        return std::clamp(int(std::lround((v + (1 - v) * glow) * 255 + noise)),
                          0, 255);
      };
      row[x] = qRgb(channel(c.r), channel(c.g), channel(c.b));
    }
  }
  return image;
}

} // namespace WallpaperGradient
