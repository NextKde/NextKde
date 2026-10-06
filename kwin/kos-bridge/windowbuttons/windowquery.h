#pragma once

#include <effect/effectwindow.h>

#include "windowrules.h"

namespace KOS
{

// The four things a rule can be matched against, read off a window.
//
// `windowRole()` is empty on Wayland -- KWin's Wayland backend has no window
// role to report (`waylandwindow.cpp`) -- which is why a rule that sets a role
// simply never matches here and why the adjust gesture never writes one.
inline WindowQuery windowQueryFor(const KWin::EffectWindow *window)
{
    WindowQuery query;
    if (!window) {
        return query;
    }
    query.windowClass = window->windowClass();
    query.caption = window->caption();
    query.role = window->windowRole();
    query.type = window->windowTypeInt();
    return query;
}

} // namespace KOS
