import QtQuick
import "../../../shared/Icons" as Symbols
import qs.desktop.modules.common
Symbols.SignalIcon {
    property color glyphColor: AppearanceTokens.content.glassInk()
    property real lineWidth: 1.55 // compatibility, font owns weight
    property real outlineWidth: 1.1
    color: glyphColor
}
