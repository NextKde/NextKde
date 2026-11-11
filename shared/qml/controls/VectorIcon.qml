import QtQuick
import "../../Icons" as Symbols

// Compatibility facade: no paths, image rendering or platform icon fallback.
Symbols.Icon {
    name: "check"
    // Deprecated compatibility input; the font has a designed fixed weight.
    property real strokeWidth: 2
}
