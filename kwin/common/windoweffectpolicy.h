// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QStringView>

namespace KOS
{

// Mime owns the Windows client's complete frame, including transparent margins
// and any client-drawn corners/shadows. Its SDL windows start as "mime"; an
// AppUserModelID changes that to "mime.<id>". Match identifiers, not captions or
// arbitrary substrings ("mimetype-editor" is not a Mime window).
// KWin exposes X11 WM_CLASS as "instance class", so inspect each whitespace-
// separated token as well as the single Wayland app ID, without per-frame
// allocations. Glass and Bridge must agree on this ownership boundary.
inline bool keepsClientAppearance(QStringView windowClass)
{
    qsizetype start = 0;
    while (start < windowClass.size()) {
        while (start < windowClass.size() && windowClass[start].isSpace()) {
            ++start;
        }
        qsizetype end = start;
        while (end < windowClass.size() && !windowClass[end].isSpace()) {
            ++end;
        }
        const auto token = windowClass.sliced(start, end - start);
        if (token.compare(u"mime", Qt::CaseInsensitive) == 0
            || (token.size() > 5 && token.startsWith(u"mime.", Qt::CaseInsensitive))) {
            return true;
        }
        start = end;
    }
    return false;
}

} // namespace KOS
