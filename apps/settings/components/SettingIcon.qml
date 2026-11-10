import QtQuick
import "../../../shared/qml/controls" as LiquidControls

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
    gradient: Gradient {
        GradientStop { position: 0; color: root.flat ? "transparent" : Qt.lighter(root.tint, 1.16) }
        GradientStop { position: 1; color: root.flat ? "transparent" : root.tint }
    }
    border.width: flat ? 0 : 0.5
    border.color: Qt.darker(tint, 1.12)
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
            ? (parent.highlighted ? root.colors.selectedForeground : root.colors.iconMuted)
            : root.colors.iconForeground
    }
}
