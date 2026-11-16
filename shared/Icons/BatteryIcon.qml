import QtQuick
Item {
    id: root
    property real level: 0
    property bool charging: false
    property color color: "white"
    property color fillColor: color
    property color chargeColor: color
    property real size: 18
    implicitWidth: size; implicitHeight: size
    readonly property real side: Math.min(width, height)
    Item {
        anchors.centerIn: parent
        width: root.side; height: root.side
        Icon { anchors.fill: parent; size: root.side; name: "battery_0"; color: root.color }
        Item {
            visible: !root.charging && root.level > 0
            // Clip only the font's fill contour, preserving continuous charge.
            width: parent.width * (48 + 364 * Math.max(0, Math.min(1, root.level))) / 512
            height: parent.height
            clip: true
            Icon { width: root.side; height: root.side; size: root.side; name: "battery_fill"; color: root.fillColor }
        }
        Icon {
            anchors.centerIn: parent
            visible: root.charging
            name: "bolt_fill"
            size: root.side * 0.5
            color: root.chargeColor
        }
    }
}
