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
    QSet<QString> pending;
    const QSet<QString> wanted{QStringLiteral("existing"), QStringLiteral("late")};
    const QSet<QString> registered{QStringLiteral("existing")};
    KWin::updateStageOpaquePending(pending, true, wanted, registered);
    assert(pending == QSet<QString>{QStringLiteral("late")});
    // A second read of the same desktop must retain the unresolved card.
    KWin::updateStageOpaquePending(pending, false, wanted, registered);
    assert(pending.contains(QStringLiteral("late")));
    pending.remove(QStringLiteral("late")); // Registration consumes the intent.
    KWin::updateStageOpaquePending(pending, false, wanted, wanted);
    assert(pending.isEmpty());
    KWin::updateStageOpaquePending(pending, true, wanted, registered);
    KWin::updateStageOpaquePending(pending, false, registered, registered);
    assert(pending.isEmpty()); // Withdrawn cards cannot inherit stale intent.
    KWin::updateStageOpaquePending(pending, true, wanted, registered);
    const QSet<QString> next{QStringLiteral("next")};
    KWin::updateStageOpaquePending(pending, true, next, {});
    assert(pending == next); // Another desktop supersedes the previous handoff.
}
