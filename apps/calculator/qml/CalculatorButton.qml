import QtQuick

// One key. It knows only its own box, its shape and its colours — the cell
// geometry, the row/column a key sits in and the gap between neighbours all
// come from the keypad, so the two keypads can lay out the same key at
// different sizes without either of them owning a radius that belongs to the
// window.
Item {
    id: root

    property real cellWidth: 80
    property real cellHeight: 80
    property int colSpan: 1
    property int rowSpan: 1

    // A round key on the basic keypad, a small-radius square on the
    // scientific one.
    property bool round: true
    property real cornerRadius: 2
    property real gap: 5

    property string label: ""
    property real fontSize: 32

    // The wide key turns into the calculator badge while the history column is
    // open; it draws a glyph instead of a label.
    property string iconName: ""

    property color fill: "#383838"
    property color textColor: "#FFFFFF"
    property bool checked: false

    signal clicked()

    implicitWidth: colSpan * cellWidth - 2 * gap
    implicitHeight: rowSpan * cellHeight - 2 * gap

    // The reference has no hover or press art, so the feedback is derived from
    // the key's own lightness: dark keys and the orange operators lift, the
    // light grey function keys deepen. Marked extrapolated in the ledger.
    readonly property color hoverFill: fill.hslLightness > 0.6
        ? Qt.darker(fill, 1.06) : Qt.lighter(fill, 1.22)
    readonly property color pressFill: fill.hslLightness > 0.6
        ? Qt.darker(fill, 1.12) : Qt.lighter(fill, 1.42)

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: root.round ? height / 2 : root.cornerRadius
        color: !root.enabled ? root.fill
            : mouse.pressed ? root.pressFill
            : mouse.containsMouse || root.checked ? root.hoverFill
            : root.fill
        antialiasing: true

        Behavior on color { ColorAnimation { duration: 90 } }

        Text {
            anchors.centerIn: parent
            visible: root.iconName.length === 0
            text: root.label
            color: root.enabled ? root.textColor : Qt.rgba(root.textColor.r,
                                                           root.textColor.g,
                                                           root.textColor.b, 0.4)
            font.pixelSize: root.fontSize
            font.weight: Font.Normal
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        CalculatorIcon {
            anchors.centerIn: parent
            visible: root.iconName.length > 0
            name: root.iconName
            color: root.textColor
            // The glyph inks out at 44% of the key in the reference; the path
            // fills 90% of its own box, so the box is a size up from that.
            size: Math.round(Math.min(surface.width, surface.height) * 0.49)
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clicked()
        }
    }
}
