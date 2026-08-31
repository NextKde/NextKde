import QtQuick

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
    readonly property color _hi: Qt.rgba(
        row.foregroundColor.r, row.foregroundColor.g, row.foregroundColor.b,
        itemEnabled ? 0.24 : 0.20)

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
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: 14
        color: (row._hover && row.itemEnabled && !row.separator) ? row._hi : "transparent"
        Behavior on color { ColorAnimation { duration: 90 } }
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 9
        visible: !row.separator

        Text {
            width: 18
            text: row.icon
            font.family: "Font Awesome 7 Free"
            font.pixelSize: 13
            color: row.foregroundColor
            opacity: 0.85
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: row.label
            elide: Text.ElideRight
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: row.foregroundColor
            opacity: row.itemEnabled ? 1.0 : 0.6
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // Trailing checkmark or submenu chevron.
    Text {
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
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        enabled: row.itemEnabled && !row.separator
        onClicked: row.clicked()
    }
}
