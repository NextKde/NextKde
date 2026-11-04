#include "../src/stage-desktop-policy.h"

#undef NDEBUG
#include <cassert>

int main()
{
    const int slide = 1, cube = 2, fade = 3, overview = 4, logout = 5;
    const std::array<const int *, 3> desktopEffects{&slide, &cube, &fade};
    assert(KWin::stageOverlayAllowed<int>(false, nullptr, desktopEffects));
    for (const auto *effect : desktopEffects) {
        assert(KWin::stageOverlayAllowed(false, effect, desktopEffects));
        assert(!KWin::stageOverlayAllowed(true, effect, desktopEffects));
    }
    assert(!KWin::stageOverlayAllowed(false, &overview, desktopEffects));
    assert(!KWin::stageOverlayAllowed(false, &logout, desktopEffects));
    assert(!KWin::stageOverlayAllowed<int>(true, nullptr, desktopEffects));
    assert(!KWin::stageOverlayAllowed<int>(false, &overview, {nullptr, nullptr, nullptr}));
    assert(KWin::stageOverlayAllowed<int>(false, nullptr, {nullptr, nullptr, nullptr}));
}
