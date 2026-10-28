pragma Singleton

import QtQuick

// The form the shared controls should draw in.
//
// A host application sets this once and every control follows, instead of each
// call site passing a flag -- or worse, each control testing the shell style
// itself. This module must stay portable (it cannot import Quickshell or the
// shell's tokens), so the *form* crosses that boundary rather than the colour
// scheme: the host keeps the palette and hands colours down as it already does.
QtObject {
    // False: the liquid-glass form these controls were originally drawn as.
    // True: the Material 3 form.
    property bool materialForm: false
}
