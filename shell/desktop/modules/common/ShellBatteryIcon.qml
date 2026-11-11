import QtQuick

Item {
    id: root
    property real level: 0
    property bool charging: false
    property color color: "white"
    property color fillColor: color
    property color chargeColor: color
    property real size: 18
    implicitWidth: size
    implicitHeight: size
    readonly property real side: Math.min(width, height)

    Item {
        anchors.centerIn: parent
        width: root.side
        height: root.side
        BundledIcon {
            anchors.fill: parent
            size: root.side
            name: "battery.outline"
            color: root.color
        }
        Item {
            visible: !root.charging && root.level > 0
            // The pinned font's fill contour runs from x=48 to x=412 in a 512-unit em.
            width: parent.width * (48 + 364 * Math.max(0, Math.min(1, root.level))) / 512
            height: parent.height
            clip: true
            BundledIcon {
                width: root.side
                height: root.side
                size: root.side
                name: "battery.fill"
                color: root.fillColor
            }
        }
        BundledIcon {
            anchors.centerIn: parent
            visible: root.charging
            name: "battery.charging"
            size: root.side * 0.5
            color: root.chargeColor
        }
    }
}
