import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../../shared/qml/controls" as LiquidControls
import "../../../shared/qml/foundation" as Foundation
import "../../../shared/qml/i18n"

Rectangle {
    required property var colors
    property bool materialForm: false
    id: root
    required property string symbol
    required property color tint
    property bool highlighted: false
    property int size: 22
    readonly property bool flat: root.materialForm
    width: size
    height: size
    radius: flat ? 0 : size * 0.345
    color: flat ? "transparent" : tint
    LiquidControls.VectorIcon {
        anchors.centerIn: parent
        size: Math.round(parent.size * 0.58)
        name: ({"◈":"theme", "◇":"theme", "▧":"wallpaper", "⎍":"panel",
            "▰":"dock", "▭":"dock", "▣":"panel", "▦":"grid", "❖":"grid",
            "⌘":"keyboard", "✓":"check", "⚙":"settings", "♲":"trash",
            "↔":"arrows", "◉":"circle", "◌":"circle", "●":"circle",
            "◐":"contrast", "◔":"contrast", "◒":"contrast", "≈":"waves",
            "≋":"waves", "⧉":"copy", "⌂":"home", "⌕":"search",
            "⇲":"resize", "↺":"undo", "B":"bold",
            "▢":"corners", "◧":"shadow", "↓":"minimize", "×":"close"})[parent.symbol] || "settings"
        color: parent.flat
            ? (parent.highlighted ? colors.selectedForeground : colors.iconMuted)
            : colors.iconForeground
    }
}
