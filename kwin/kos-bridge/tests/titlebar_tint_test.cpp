#include "windowbuttons/titlebartint.h"

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
                uchar(random() % 256)};
            histogram.add(p.data());
            if (p[3] >= 128) reference.push_back({p[0], p[1], p[2], (54*p[0]+183*p[1]+19*p[2]) >> 8});
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
                        CHECK(rect.width() <= 160 && rect.height() <= 64);
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
    CHECK(tintSampleRect({}, {}).isEmpty());
    CHECK(tintSampleRect(QRect(0, 0, 100, 30), QRect(0, 0, 100, 30)).isEmpty());
}

void timingTests()
{
    TitlebarTintState state;
    const auto start = TitlebarTintState::Clock::time_point{} + 1s;
    const QColor first(30, 30, 30), next(200, 180, 160);
    CHECK(state.interval() == 250ms);
    CHECK(state.accept(true, first, start));
    CHECK(state.known && !state.pending);
    for (int i = 0; i < 8; ++i) state.attempted(start + i * 250ms);
    CHECK(state.warmupReads == 4);
    CHECK(state.interval() == 750ms);
    CHECK(!state.accept(false, next, start + 2s));
    CHECK(state.pending && state.interval() == 250ms);
    CHECK(!state.accept(false, next, start + 2250ms));
    CHECK(state.color == first);
    CHECK(state.accept(false, next, start + 2500ms));
    CHECK(state.color == next && !state.dark && !state.pending);
    CHECK(state.interval() == 750ms);
    // Dither does not mutate the displayed RGB.
    CHECK(!state.accept(false, QColor(202, 179, 160), start + 3s));
    CHECK(state.color == next);
    // A transient that returns to the displayed color cancels confirmation.
    CHECK(!state.accept(true, first, start + 4s));
    CHECK(!state.accept(false, next, start + 4250ms));
    CHECK(!state.pending);
    // Conflicting observations restart the confirmation clock.
    CHECK(!state.accept(true, first, start + 5s));
    CHECK(!state.accept(true, QColor(60, 60, 60), start + 5500ms));
    CHECK(!state.accept(true, QColor(60, 60, 60), start + 5750ms));
    CHECK(state.accept(true, QColor(60, 60, 60), start + 6s));
}
}

int main()
{
    histogramTests();
    geometryTests();
    timingTests();
    std::printf("%d checks, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}
