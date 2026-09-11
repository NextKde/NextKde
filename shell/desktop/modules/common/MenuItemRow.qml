import QtQuick
import qs.desktop.modules.dock
import qs.desktop.modules.common

// A row in a ContextMenu: icon + label, with optional checkmark (checkable),
// submenu chevron, and a thin separator variant. Hover only changes the row's
// visual highlight; navigation is owned by ContextMenu's click handler.
Item {
    id: row

    property string label: ""
    property string icon: ""
    property color foregroundColor: "#ffffff"
    property bool itemEnabled: true
    property bool hasSubmenu: false
    property bool checkable: false
    property bool checked: false
    property bool separator: false
    signal clicked()

    // Bind directly to MouseArea.containsMouse instead of maintaining a
    // transient flag.  Delegates are replaced when entering a submenu, and a
    // flag set by onEntered/onExited can otherwise be stale or miss the first
    // hover event in a PopupWindow.
    readonly property bool _hover: pointer.containsMouse
    readonly property color _hi: AppearanceTokens.isMaterial
        ? (itemEnabled ? AppearanceTokens.state.hover
            : AppearanceTokens.state.disabled)
        : Qt.rgba(row.foregroundColor.r, row.foregroundColor.g,
            row.foregroundColor.b,
            itemEnabled ? (ThemeService.isDark ? 0.22 : 0.10) : 0.05)

    height: row.separator ? 1 : 38
    visible: row.separator || label.length > 0
    width: parent ? parent.width : 0

    // Separator line.
    Rectangle {
        visible: row.separator
        x: 10
        width: parent.width - 20
        height: 1
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(row.foregroundColor.r, row.foregroundColor.g,
            row.foregroundColor.b, 0.12)
    }

    // Hover background (behind all other content).
    GlassInteractionLayer {
        anchors.fill: parent
        radius: AppearanceTokens.shape.medium
        color: (row._hover && row.itemEnabled && !row.separator) ? row._hi : "transparent"
        Behavior on color { ColorAnimation { duration: 90 } }
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: row.icon.length > 0 ? 9 : 0
        visible: !row.separator

        GlassText {
            visible: row.icon.length > 0
            width: visible ? 18 : 0
            text: row.icon
            font.family: "Font Awesome 7 Free"
            font.pixelSize: 13
            color: row.foregroundColor
            opacity: 0.85
            anchors.verticalCenter: parent.verticalCenter
        }
        GlassText {
            text: row.label
            elide: Text.ElideRight
            font.family: "SF Pro Display, Noto Sans CJK SC, sans-serif"
            font.pixelSize: 13
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            color: row.foregroundColor
            opacity: row.itemEnabled ? 1.0 : 0.6
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, (row.width - 24) - (row.icon.length > 0 ? 27 : 0) - ((row.checked || row.hasSubmenu) ? 24 : 0))
        }
    }

    // Trailing checkmark or submenu chevron.
    GlassText {
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        visible: !row.separator && (row.checked || row.hasSubmenu)
        text: row.checked ? "✓" : "›"
        color: row.checked ? row.foregroundColor
            : Qt.rgba(row.foregroundColor.r, row.foregroundColor.g,
                row.foregroundColor.b, 0.55)
        font.pixelSize: row.checked ? 12 : 16
        font.weight: Font.Bold
        renderType: Text.NativeRendering
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        enabled: row.itemEnabled && !row.separator
        onClicked: row.clicked()
    }
}
