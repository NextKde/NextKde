#pragma once

#include <QString>
#include <QStringList>

namespace KosPlatform {

// KWin keeps several of its actions on *two* keys at once — "Walk Through
// Windows" ships as {Alt+Tab, Meta+Tab}, its reverse / per-application
// variants also carry a Meta second key. Two things can go wrong around such
// an action, and both end with the key silently dead:
//
// 1. KOS takes the Meta key (the workspace overview owns Meta+Tab). The
//    taken key has to be released from the KWin action while its other keys
//    stay registered and present.
// 2. The daemon's per-shortcut "present" state can be lost — `GlobalShortcut`
//    starts out non-present, `setInactive` is `setIsPresent(false)`, and
//    nothing in the daemon ever sets it back except a `setShortcut` carrying
//    the SetPresent flag. A non-present shortcut stops firing while the
//    registry still lists the action, its keys and its component, so the
//    failure is invisible from every query — the only reviver is the same
//    SetPresent call System Settings makes when a shortcut is re-recorded.
//    (Observed on Plasma 6.7.4 after nested KWin instances from test runs
//    churn the `kwin` component; the main compositor's actions came back
//    dead while everything in the registry looked untouched.)
//
// `repairKWinKeyConflicts` runs before the KOS shortcut set is (re)applied.
// It walks the `kwin` component's shortcuts once and touches exactly the
// actions whose default keys involve one of the KOS combos — those are the
// ones a KOS key can ever collide with. For each of them the active keys are
// rewritten to "everything except the KOS combos" with SetPresent set: the
// conflict is released, the action stays (or becomes) present, and an action
// that lost its present state is healed on the next shell start. Actions KOS
// never collides with, and actions fully replaced by KOS (their only key is
// a KOS key — KGlobalAccel's own conflict semantics own that case), are left
// alone.
//
// Returns human-readable lines describing every repair (empty when there was
// nothing to do). A failure to talk to KGlobalAccel is reported through
// `error` and never aborts the caller — a broken repair must not stop the
// KOS shortcuts themselves from being applied.
QStringList repairKWinKeyConflicts(const QStringList &combos,
                                   QString *error = nullptr);

} // namespace KosPlatform
