import QtQuick
import ".." as Shared

Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property var systemData: liveMode ? (host.system ?? snapshot) : snapshot
    readonly property bool transparentMode: Boolean(appearance?.transparent)
    readonly property color glassInk: appearance?.foreground ?? "#ffffff"

    readonly property var backgroundSpec: ({
        startColor: "#f5f8fc",
        endColor: "#e6edf6"
    })

    Shared.SystemContent {
        anchors.fill: parent
        widgetSize: root.widgetSize
        appearance: root.appearance
        systemData: root.systemData
        cpuColor: root.transparentMode ? root.glassInk : "#ff375f"
        memoryColor: root.transparentMode ? root.glassInk : "#30d158"
        storageColor: root.transparentMode ? root.glassInk : "#64d2ff"
        ringTrackColor: root.transparentMode
            ? Qt.rgba(root.glassInk.r, root.glassInk.g, root.glassInk.b, 0.25)
            : Qt.rgba(0.19, 0.17, 0.20, 0.12)
        primaryInk: root.transparentMode ? root.glassInk : "#4c4a54"
        subtleInk: root.transparentMode
            ? Qt.rgba(root.glassInk.r, root.glassInk.g, root.glassInk.b, 0.78)
            : "#7d7782"
        dividerColor: root.transparentMode
            ? Qt.rgba(root.glassInk.r, root.glassInk.g, root.glassInk.b, 0.28)
            : Qt.rgba(0.19, 0.17, 0.20, 0.12)
        heavyRings: false
    }
}
