#pragma once

#include <QString>
#include <QStringList>

namespace KosPlatform {

// Before registering KOS shortcuts, release overlapping keys from KWin
// actions while retaining their other keys. Actions whose default keys
// overlap are also re-presented to recover lost activation state.
// Unrelated actions and actions fully replaced by KOS are left untouched.
//
// Returns descriptions of repairs confirmed by KGlobalAccel's reply.
// Failures are reported through error; callers can still apply KOS shortcuts.
QStringList repairKWinKeyConflicts(const QStringList &combos,
                                   QString *error = nullptr);

} // namespace KosPlatform
