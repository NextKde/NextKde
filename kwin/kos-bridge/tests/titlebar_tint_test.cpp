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
    // Independent cover expands left while sampling rows remain on the buttons.
    const QRect band(0, 6, 1920, 23);
    const QRect controls(1830, 6, 80, 23), cover(1730, 0, 190, 60);
    CHECK(tintSampleRect(band, controls).intersects(cover)); // Former wrong exclusion.
    CHECK(!tintSampleRect(band, cover).intersects(cover));
    CHECK(!tintSampleRect(band, cover, true).intersects(cover));
    CHECK(tintSampleRect({}, {}).isEmpty());
    CHECK(tintSampleRect(QRect(0, 0, 100, 30), QRect(0, 0, 100, 30)).isEmpty());
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
