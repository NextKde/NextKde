#pragma once

#include <QString>
#include <QStringList>

namespace KosPlatform {

// KWin keeps several of its actions on *two* keys at once — "Walk Through
// Windows" ships as {Alt+Tab, Meta+Tab}, its variant as {Alt+Shift+Tab,
// Meta+Shift+Tab}, the exposes as {Ctrl+F9, Meta+F9} and so on. When another
// component takes one of those keys, KGlobalAccel marks the *whole* KWin
// action as not present (`setInactive` is exactly `setIsPresent(false)`), so
// the keys KOS never touched die with it: taking Meta+Tab for the workspace
// overview silently kills Alt+Tab. The registry keeps reporting the action
// and its keys, and only a `setShortcut` carrying the SetPresent flag can
// revive it — the state is otherwise indistinguishable from a working
// binding, which is why this failure is so hard to spot from a bug report.
//
// `releaseKWinKeyConflicts` runs before the KOS shortcut set is (re)applied:
// for every combo, it asks KGlobalAccel who holds the key, and for KWin
// actions that still hold other keys it rewrites the action to the remaining
// keys with SetPresent set — the action stays active, the KOS key is free,
// and an action that an earlier conflict had already deactivated heals on
// the next shell start. Single-key actions are left alone: KOS taking that
// key fully replaces the action, and KGlobalAccel's own conflict handling
// already covers that case.
//
// Returns human-readable lines describing every repair (empty when there was
// nothing to do). A failure to talk to KGlobalAccel is reported through
// `error` and never aborts the caller — a broken conflict repair must not
// stop the KOS shortcuts themselves from being applied.
QStringList releaseKWinKeyConflicts(const QStringList &combos,
                                    QString *error = nullptr);

} // namespace KosPlatform
