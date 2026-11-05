#pragma once

#include <algorithm>
#include <array>
#include <QSet>
#include <QString>

namespace KWin {

// Keep the fixed overlay during desktop navigation, while other fullscreen
// effects (overview, lock/logout, etc.) retain exclusive screen ownership.
template<typename Effect>
bool stageOverlayAllowed(bool locked, const Effect *active,
                         const std::array<const Effect *, 3> &desktopEffects)
{
    return !locked && (!active
        || std::find(desktopEffects.begin(), desktopEffects.end(), active) != desktopEffects.end());
}

// Keep handoff intent across reloads until the card can actually register.
inline void updateStageOpaquePending(QSet<QString> &pending, bool desktopChanged,
                                     const QSet<QString> &wanted,
                                     const QSet<QString> &registered)
{
    if (desktopChanged)
        pending = wanted - registered;
    pending.intersect(wanted);
}

} // namespace KWin
