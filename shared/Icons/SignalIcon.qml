import QtQuick
Item {
    id: root
    property bool wifiEnabled: true
    property bool connected: false
    property int signalStrength: -1
    property color color: "white"
    property real size: 20
    property bool outlined: false
    property color outlineColor: "transparent"
    readonly property int signalLevel: !wifiEnabled || !connected || signalStrength < 0
        ? 0 : signalStrength < 30 ? 1 : signalStrength < 60 ? 2 : 3
    implicitWidth: size; implicitHeight: size
    Icon {
        anchors.fill: parent
        size: Math.min(root.width, root.height)
        name: root.wifiEnabled ? "wifi" : "wifi_slash"
        color: root.color
        opacity: root.wifiEnabled ? 0.22 : 0.5
        outlined: root.outlined; outlineColor: root.outlineColor
    }
    Icon {
        anchors.fill: parent
        size: Math.min(root.width, root.height)
        visible: root.signalLevel > 0
        name: root.signalLevel === 1 ? "wifi_1" : root.signalLevel === 2 ? "wifi_2" : "wifi"
        color: root.color
        outlined: root.outlined; outlineColor: root.outlineColor
    }
}
