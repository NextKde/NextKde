import QtQuick
import Kos.Icons as Symbols

// Navigation shares the platform font; the tile is ordinary host styling.
Rectangle {
    id: root
    required property var colors
    required property string iconName
    required property string symbol
    required property color tint
    property bool materialForm: false
    property bool highlighted: false
    property int size: 18
    width: size; height: size
    radius: materialForm ? 0 : size * 0.23
    color: materialForm ? "transparent" : tint
    Symbols.Icon {
        anchors.centerIn: parent
        size: root.materialForm ? root.size : root.size * 0.72
        name: ({"battery":"battery_100", "general":"gear_alt", "spotlight":"search",
            "menu-bar":"macwindow", "desktop-dock":"rectangle_dock", "appearance":"circle_lefthalf_fill",
            "notifications":"bell", "keyboard":"keyboard", "network":"globe", "system-settings":"gear_alt",
            "wallpaper":"photo"})[root.iconName] || root.symbol
        color: root.materialForm ? (root.highlighted ? colors.selectedForeground : colors.iconMuted) : colors.iconForeground
    }
}
