import QtQuick
import ".." as Shared

Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property var activityData: liveMode ? (host.activity ?? snapshot) : snapshot
    readonly property bool transparentMode: Boolean(appearance?.transparent)
    readonly property color glassInk: appearance?.foreground ?? "#ffffff"

    readonly property var backgroundSpec: ({
        startColor: "#40506a",
        endColor: "#29364e"
    })

    Shared.ActivityContent {
        anchors.fill: parent
        widgetSize: root.widgetSize
        appearance: root.appearance
        activityData: root.activityData
        headerInk: root.transparentMode ? root.glassInk : Qt.rgba(1, 1, 1, 0.88)
        primaryInk: root.transparentMode ? root.glassInk : Qt.rgba(1, 1, 1, 0.80)
        subtleInk: root.transparentMode
            ? Qt.rgba(root.glassInk.r, root.glassInk.g, root.glassInk.b, 0.65)
            : Qt.rgba(1, 1, 1, 0.50)
        heatmapBaseColor: root.transparentMode ? root.glassInk : Qt.rgba(0.33, 0.84, 0.58, 1.0)
        heatmapEmptyColor: root.transparentMode
            ? Qt.rgba(root.glassInk.r, root.glassInk.g, root.glassInk.b, 0.14)
            : Qt.rgba(1, 1, 1, 0.08)
        barTrackColor: root.transparentMode
            ? Qt.rgba(root.glassInk.r, root.glassInk.g, root.glassInk.b, 0.16)
            : Qt.rgba(1, 1, 1, 0.12)
        badgeFillColor: Qt.rgba(1, 1, 1, 0.18)
        badgeInk: root.transparentMode ? root.glassInk : "#ffffff"
    }
}
