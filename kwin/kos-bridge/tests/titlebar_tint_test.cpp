#include "windowbuttons/titlebartint.h"
#include "windowbuttons/painttransform.h"

#include <QElapsedTimer>

#include <algorithm>
#include <array>
#include <cstdio>
#include <random>
#include <vector>

using namespace KOS;
using namespace std::chrono_literals;
namespace
{
int checks = 0, failures = 0;
#define CHECK(expr) do { ++checks; if (!(expr)) { ++failures; std::fprintf(stderr, "%d: %s\n", __LINE__, #expr); } } while (false)

void histogramTests()
{
    TintHistogram empty;
    bool dark = false;
    QColor color;
    CHECK(!empty.tint(&dark, &color));
    const uchar transparent[] = {0, 0, 0, 0};
    const uchar background[] = {32, 33, 36, 255};
    const uchar glyph[] = {255, 255, 255, 255};
    for (int i = 0; i < 1000; ++i) empty.add(transparent);
    for (int i = 0; i < 63; ++i) empty.add(background);
    CHECK(!empty.tint(&dark, &color));
    empty.add(background);
    for (int i = 0; i < 20; ++i) empty.add(glyph);
    CHECK(empty.tint(&dark, &color));
    CHECK(dark);
    CHECK(color == QColor(32, 33, 36));
    // A valid pixel minimum alone would accept the sparse glyphs of a mostly
    // transparent/undrawn strip. Sampling requires representative coverage.
    CHECK(!empty.tint(&dark, &color, 128));

    // Equivalence to the old sort+median+cluster algorithm, including alpha
    // rejection, the upper median for even counts, and clamped +/-3 bins.
    std::mt19937 random(42);
    for (int trial = 0; trial < 300; ++trial) {
        TintHistogram histogram;
        struct Pixel { int r, g, b, luma; };
        std::vector<Pixel> reference;
        for (int i = 0; i < 500; ++i) {
            const bool extreme = trial < 2;
            const uchar value = trial == 0 ? 0 : 255;
            const std::array<uchar, 4> p{extreme ? value : uchar(random() % 256),
                extreme ? value : uchar(random() % 256), extreme ? value : uchar(random() % 256),
                uchar(i % 2 ? 255 : random() % 255)};
            histogram.add(p.data());
            if (p[3] == 255) reference.push_back({p[0], p[1], p[2], (54*p[0]+183*p[1]+19*p[2]) >> 8});
        }
        std::sort(reference.begin(), reference.end(), [](auto a, auto b) { return a.luma < b.luma; });
        const int median = reference[reference.size()/2].luma;
        int r = 0, g = 0, b = 0, count = 0;
        for (auto p : reference) if (std::abs(p.luma - median) <= 3) {
            r += p.r; g += p.g; b += p.b; ++count;
        }
        CHECK(histogram.tint(&dark, &color));
        CHECK(dark == (median < 128));
        CHECK(color == QColor(r/count, g/count, b/count));
    }
}

void startupPixelsTests()
{
    bool dark = false;
    QColor color;
    for (int alpha : {0, 64, 127, 128, 200, 254}) {
        TintHistogram histogram;
        const uchar faded[] = {uchar(alpha / 2), uchar(alpha / 2), uchar(alpha / 2), uchar(alpha)};
        for (int i = 0; i < 96; ++i) histogram.add(faded);
        CHECK(!histogram.tint(&dark, &color));
    }
    TintHistogram opaque;
    const uchar black[] = {0, 0, 0, 255};
    for (int i = 0; i < 96; ++i) opaque.add(black);
    CHECK(opaque.tint(&dark, &color));
    CHECK(dark && color == QColor(0, 0, 0));
}

void paintTransformTests()
{
    CHECK(PaintTransform{}.canSampleTitlebar()); // Neutral offscreen source.
    for (auto member : {&PaintTransform::xScale, &PaintTransform::yScale,
                        &PaintTransform::opacity, &PaintTransform::brightness,
                        &PaintTransform::saturation}) {
        PaintTransform transform;
        transform.*member = 0.5;
        CHECK(!transform.canSampleTitlebar());
    }
    for (auto member : {&PaintTransform::xTranslate, &PaintTransform::yTranslate}) {
        PaintTransform transform;
        transform.*member = 8;
        CHECK(!transform.canSampleTitlebar());
    }
    PaintTransform rotated;
    rotated.transformed = true;
    CHECK(!rotated.canSampleTitlebar());
}

void geometryTests()
{
    for (int width : {200, 1920, 3840, 7680}) {
        for (int height : {24, 48, 96, 192}) {
            for (int origin : {-1920, 0, 3840}) {
                const QRect band(origin, 150, width, height);
                for (bool right : {false, true}) {
                    const QRect panel(right ? band.right() - 109 : origin, 150, 110, height);
                    for (bool fallback : {false, true}) {
                        const QRect rect = tintSampleRect(band, panel, fallback);
                        CHECK(rect.width() <= (fallback ? 160 : 32) && rect.height() <= 64);
                        CHECK(rect.isEmpty() || band.contains(rect));
                        CHECK(!rect.intersects(panel));
                        if (fallback) {
                            const QRect caption(origin + width/3, 150, width/3, height);
                            CHECK(!rect.intersects(caption));
                        }
                    }
                }
            }
        }
    }
    // Independent cover expands left while sampling rows remain on the buttons.
    const QRect band(0, 6, 1920, 23);
    const QRect controls(1830, 6, 80, 23), cover(1730, 0, 190, 60);
    CHECK(tintSampleRect(band, controls).intersects(cover)); // Former wrong exclusion.
    CHECK(!tintSampleRect(band, cover).intersects(cover));
    CHECK(!tintSampleRect(band, cover, true).intersects(cover));
    CHECK(tintSampleRect({}, {}).isEmpty());
    CHECK(tintSampleRect(QRect(0, 0, 100, 30), QRect(0, 0, 100, 30)).isEmpty());
}

void neighboringWidgetTests()
{
    const QColor background(23, 29, 37), widget(39, 45, 55);
    const QColor oppositeEnd(60, 65, 70), icon(103, 112, 123);
    for (int scale : {1, 2, 3}) {
        const QRect band(-300, 150, 700 * scale, 23 * scale);
        for (bool right : {false, true}) {
            const QRect cover(right ? band.x() + band.width() - 110 * scale : band.x(),
                              band.y() - 5 * scale, 110 * scale, 33 * scale);
            const QRect sample = tintSampleRect(band, cover);
            TintHistogram histogram;
            // Steam-like layout: a filled account/balance widget occupies most
            // of the old 160px strip. A small monitor glyph sits in the gap
            // beside the cover. The far end has a different background, so
            // switching to the fallback unconditionally is also incorrect.
            for (int y = sample.top(); y <= sample.bottom(); ++y) {
                for (int x = sample.left(); x <= sample.right(); ++x) {
                    const int distance = right ? cover.left() - 1 - x : x - cover.right() - 1;
                    QColor pixel = distance >= 48 * scale ? widget : background;
                    if (distance >= 8 * scale && distance < 28 * scale
                        && y >= band.y() + 7 * scale && y < band.y() + 10 * scale) {
                        pixel = icon;
                    }
                    if (right ? x < band.x() + 160 : x >= band.x() + band.width() - 160) {
                        pixel = oppositeEnd;
                    }
                    const uchar rgba[] = {uchar(pixel.red()), uchar(pixel.green()),
                                          uchar(pixel.blue()), 255};
                    histogram.add(rgba);
                }
            }
            bool dark = false;
            QColor color;
            CHECK(histogram.tint(&dark, &color));
            CHECK(dark);
            CHECK(color == background);
        }
    }
}

void toolbarGutterTests()
{
    for (int scale : {1, 2, 3}) {
        const QRect band(0, 0, 700 * scale, 24 * scale);
        const QRect cover(590 * scale, 0, 110 * scale, 40 * scale);
        const QRect sample = tintSampleRect(band, cover);
        TintHistogram histogram;
        for (int y = sample.top(); y <= sample.bottom(); ++y) {
            for (int x = sample.left(); x <= sample.right(); ++x) {
                // Avatar / toolbar occupies the middle and lower rows.
                const uchar v = y >= 7 * scale ? 80 : 240;
                const uchar rgba[] = {v, v, v, 255};
                histogram.add(rgba);
            }
        }
        bool dark = true;
        QColor color;
        CHECK(histogram.tint(&dark, &color));
        CHECK(!dark && color == QColor(240, 240, 240));
    }
}

void backgroundBoundaryTests()
{
    for (int scale : {1, 2, 3}) {
        const int width = 160, height = 45 * scale, boundary = 30 * scale;
        std::vector<uchar> pixels(width * height * 4, 255);
        for (int y = 0; y < height; ++y) {
            for (int x = 0; x < width; ++x) {
                auto *p = pixels.data() + (y * width + x) * 4;
                // QQ's short black bar, then image content. A small toolbar
                // icon must not be mistaken for the full-width boundary.
                const uchar value = y >= boundary ? 75 : (x < 20 && y > 8 * scale ? 220 : 17);
                p[0] = p[1] = p[2] = value;
            }
        }
        CHECK(tintBackgroundBottom(pixels.data(), width, height, QColor(17, 17, 17),
                                   5 * scale, 3 * scale) == boundary);
        CHECK(tintBackgroundBottom(pixels.data(), width, boundary, QColor(17, 17, 17),
                                   5 * scale, 3 * scale) == boundary);
        // One horizontal line is insufficient evidence to trim a cover.
        for (int x = 0; x < width; ++x) {
            auto *p = pixels.data() + (6 * scale * width + x) * 4;
            p[0] = p[1] = p[2] = 255;
        }
        CHECK(tintBackgroundBottom(pixels.data(), width, height, QColor(17, 17, 17),
                                   5 * scale, 3 * scale) == boundary);
    }
    std::vector<uchar> gradient(160 * 60 * 4, 255);
    for (int y = 0; y < 60; ++y) for (int x = 0; x < 160; ++x) {
        auto *p = gradient.data() + (y * 160 + x) * 4;
        p[0] = p[1] = p[2] = 20 + y;
    }
    CHECK(tintBackgroundBottom(gradient.data(), 160, 60, QColor(20,20,20), 5, 3) == 60);

}

void subtleBoundaryTests()
{
    for (int scale : {1, 2, 3}) {
        for (int delta : {2, 3, 5, 8, 12}) {
            const int width = 160, height = 60 * scale, boundary = 35 * scale;
            std::vector<uchar> pixels(width * height * 4, 255);
            for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x) {
                auto *p = pixels.data() + (y * width + x) * 4;
                p[0] = p[1] = p[2] = y < boundary ? 19 : 19 + delta;
                // A small glyph should not defeat the low-contrast boundary.
                if (x < 16 && y >= 10 * scale && y < 20 * scale)
                    p[0] = p[1] = p[2] = 200;
            }
            CHECK(tintBackgroundBottom(pixels.data(), width, height, QColor(19,19,19),
                                       5 * scale, 3 * scale) == boundary);
            // An isolated low-contrast separator must not be mistaken for a
            // new persistent surface.
            for (int y = boundary + 1; y < height; ++y)
                for (int x = 0; x < width; ++x) {
                    auto *p = pixels.data() + (y * width + x) * 4;
                    p[0] = p[1] = p[2] = 19;
                }
            CHECK(tintBackgroundBottom(pixels.data(), width, height, QColor(19,19,19),
                                       5 * scale, 3 * scale) == height);
        }
    }
    // Transparent rows cannot supply evidence of a new background.
    std::vector<uchar> empty(160 * 60 * 4, 0);
    CHECK(tintBackgroundBottom(empty.data(), 160, 60, QColor(19,19,19), 5, 3) == 60);
}


void boundaryBenchmark()
{
    std::vector<uchar> pixels(TintProbeWidth * TintProbeHeight * 4, 255);
    for (int y = 0; y < TintProbeHeight; ++y) for (int x = 0; x < TintProbeWidth; ++x) {
        auto *p = pixels.data() + (y * TintProbeWidth + x) * 4;
        p[0] = p[1] = p[2] = y < 160 ? 19 : 27;
    }
    constexpr int iterations = 5000;
    int checksum = 0;
    QElapsedTimer timer;
    timer.start();
    for (int i = 0; i < iterations; ++i)
        checksum += tintBackgroundBottom(pixels.data(), TintProbeWidth, TintProbeHeight,
                                         QColor(19,19,19), 5, 3);
    std::printf("160x192 boundary CPU: %.2f us/scan (%d scans, checksum %d); excludes GPU/readback/repaint\n",
                timer.nsecsElapsed() / 1000.0 / iterations, iterations, checksum);
}


void startupTimingTests()
{
    using Clock = TitlebarTintState::Clock;
    const auto start = Clock::time_point{} + 1s;
    const QColor color(240, 240, 240);
    TitlebarTintState state;
    state.attempted(start);
    CHECK(state.readbackPollInterval(start) == 4ms);
    CHECK(state.readbackPollInterval(start + 32ms) == 16ms); // Slow GPU backs off.
    // First read completes after 16ms, second after 4ms. Poll-time separation
    // is only 20ms, but the two captured frames are already 32ms apart.
    CHECK(!state.accept(false, color, state.lastRead));
    state.attempted(start + 32ms);
    CHECK(state.accept(false, color, state.lastRead));
    CHECK(state.known && state.color == color);
    CHECK(state.readbackPollInterval(start + 36ms) == 16ms);

    TitlebarTintState late;
    for (int i = 0; i < 12; ++i) {
        late.attempted(start + i * 1s);
        late.rejectSample();
    }
    CHECK(!late.known && late.interval() == 1000ms);
    late.contentChanged(); // The client's real first frame finally arrives.
    CHECK(late.interval() == 32ms && late.needsFollowup());
    CHECK(late.lastRead == start + 11s); // Damage cannot bypass the throttle.
    late.attempted(start + 12s);
    CHECK(!late.accept(false, color, late.lastRead));
    late.attempted(start + 12s + 32ms);
    CHECK(late.accept(false, color, late.lastRead));
}

void timingTests()
{
    TitlebarTintState state;
    const auto start = TitlebarTintState::Clock::time_point{} + 1s;
    const QColor first(30, 30, 30), next(200, 180, 160), black(0, 0, 0);
    CHECK(state.interval() == 32ms);
    // A single startup black frame must never appear as a black cover.
    CHECK(!state.accept(true, black, start));
    CHECK(!state.known);
    CHECK(!state.accept(true, first, start + 32ms));
    CHECK(!state.known);
    CHECK(state.accept(true, first, start + 64ms));
    CHECK(state.known && state.color == first && !state.pending);
    for (int i = 0; i < 8; ++i) state.attempted(start + i * 32ms);
    CHECK(state.warmupReads == 4);
    CHECK(state.interval() == 125ms);
    CHECK(!state.accept(false, next, start + 2s));
    CHECK(state.pending && state.interval() == 32ms);
    CHECK(!state.accept(false, next, start + 2016ms));
    CHECK(state.color == first);
    CHECK(state.accept(false, next, start + 2032ms));
    CHECK(state.color == next && !state.dark && !state.pending);
    CHECK(state.interval() == 125ms);
    CHECK(!state.accept(false, QColor(202, 179, 160), start + 3s));
    CHECK(state.color == next);
    CHECK(!state.accept(true, black, start + 4s));
    CHECK(!state.accept(false, next, start + 4032ms));
    CHECK(!state.pending && state.color == next);
    // Invalid/transparent reads retain validated RGB and break confirmation.
    CHECK(!state.accept(true, first, start + 5s));
    CHECK(!state.accept(true, QColor(), start + 5032ms));
    CHECK(!state.pending && state.color == next);
    CHECK(!state.accept(true, first, start + 5064ms));
    CHECK(!state.accept(true, QColor(0, 0, 0, 0), start + 5096ms));
    CHECK(!state.pending && state.color == next);
    // Real opaque black remains supported after two consistent observations.
    CHECK(!state.accept(true, black, start + 6s));
    CHECK(state.accept(true, black, start + 6032ms));
    CHECK(state.color == black);
    // Both gain and loss of focus re-enter a bounded fast phase, preserving
    // the previous color until the new active/inactive titlebar is validated.
    state.requestRefresh();
    CHECK(state.known && state.color == black && !state.pending);
    CHECK(state.lastRead == TitlebarTintState::Clock::time_point{});
    CHECK(state.interval() == 32ms && state.needsFollowup());
    CHECK(!state.accept(false, next, start + 7s));
    CHECK(state.accept(false, next, start + 7032ms));
    CHECK(state.color == next && !state.pending);
    for (int i = 0; i < 4; ++i) state.attempted(start + 7100ms + i * 32ms);
    CHECK(!state.needsFollowup());
    // Damage during an in-flight read cannot be swallowed by its old RGB.
    state.contentChanged();
    CHECK(state.needsFollowup());
    state.attempted(start + 7500ms);
    state.contentChanged();
    CHECK(!state.accept(false, next, start + 7516ms));
    CHECK(state.needsFollowup());
    state.attempted(start + 7625ms);
    CHECK(!state.accept(false, next, start + 7641ms));
    CHECK(!state.needsFollowup());
    // Occluded/failed refreshes do not create an unlimited fast retry loop.
    state.requestRefresh();
    for (int i = 0; i < 4; ++i) state.attempted(start + 8s + i * 32ms);
    state.rejectSample();
    CHECK(state.interval() == 125ms && !state.needsFollowup());
    CHECK(state.known && state.color == next);
    state.requestRefresh();
    for (int i = 0; i < 12; ++i) {
        state.attempted(start + 9s + i * 1s);
        state.accept(true, black, start + 9s + i * 1s + 32ms);
    }
    CHECK(state.interval() == 1000ms);
    state.contentChanged();
    CHECK(state.interval() == 1000ms); // Scrolling does not restore 8Hz polling.
    CHECK(!state.accept(false, next, start + 22s));
    CHECK(state.interval() == 32ms); // Observed change confirms promptly.

    state.requestRefresh();
    for (int i = 0; i < 12; ++i) {
        state.attempted(start + 23s + i * 1s);
        state.rejectSample();
    }
    CHECK(state.interval() == 1000ms); // Persistent occlusion also backs off.
    CHECK(!state.needsFollowup());

}

}

int main(int argc, char **argv)
{
    if (argc > 1 && QString::fromUtf8(argv[1]) == QStringLiteral("--benchmark")) boundaryBenchmark();
    histogramTests();
    startupPixelsTests();
    paintTransformTests();
    startupTimingTests();
    geometryTests();
    neighboringWidgetTests();
    toolbarGutterTests();
    backgroundBoundaryTests();
    subtleBoundaryTests();
    timingTests();
    std::printf("%d checks, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}
