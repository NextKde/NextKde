import QtQuick
import qs.desktop.modules.common

Item {
    id: root
    property bool wifiEnabled: true
    property bool connected: false
    property int signalStrength: -1
    property real size: 20
    property color glyphColor: AppearanceTokens.content.glassInk()
    property color color: glyphColor
    property real lineWidth: 1.55 // compatibility, font owns weight
    property real outlineWidth: 1.1
    property bool outlined: false
    property color outlineColor: "transparent"
    readonly property int signalLevel: !wifiEnabled || !connected || signalStrength < 0
        ? 0 : signalStrength < 30 ? 1 : signalStrength < 60 ? 2 : 3
    implicitWidth: size
    implicitHeight: size

    BundledIcon {
        anchors.fill: parent
        size: Math.min(root.width, root.height)
        name: root.wifiEnabled ? "network.wifi.full" : "network.wifi.disabled"
        color: root.color
        opacity: root.wifiEnabled ? 0.22 : 0.5
        outlined: root.outlined
        outlineColor: root.outlineColor
    }
    BundledIcon {
        anchors.fill: parent
        size: Math.min(root.width, root.height)
        visible: root.signalLevel > 0
        name: root.signalLevel === 1 ? "network.wifi.weak"
            : root.signalLevel === 2 ? "network.wifi.medium" : "network.wifi.strong"
        color: root.color
        outlined: root.outlined
        outlineColor: root.outlineColor
    }
}
