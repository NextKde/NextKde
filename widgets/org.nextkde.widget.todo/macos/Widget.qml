import QtQuick
import ".." as Shared

Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property var pimData: liveMode ? (host.pim ?? snapshot) : snapshot
    readonly property bool transparentMode: Boolean(appearance?.transparent)
    readonly property color glassInk: appearance?.foreground ?? "#ffffff"

    readonly property var backgroundSpec: ({
        startColor: "#ffffff",
        endColor: "#ffffff"
    })

    Shared.TodoContent {
        anchors.fill: parent
        widgetSize: root.widgetSize
        appearance: root.appearance
        pimData: root.pimData
        host: root.host
        accentColor: root.transparentMode ? root.glassInk : "#007aff"
        iconForeground: "#ffffff"
        primaryInk: root.transparentMode ? root.glassInk : "#1c1c1e"
        subtleInk: root.transparentMode
            ? Qt.rgba(root.glassInk.r, root.glassInk.g, root.glassInk.b, 0.72)
            : "#8e8e93"
        circleBorderColor: root.transparentMode
            ? Qt.rgba(root.glassInk.r, root.glassInk.g, root.glassInk.b, 0.65)
            : "#c7c7cc"
        hairlineColor: root.transparentMode
            ? Qt.rgba(root.glassInk.r, root.glassInk.g, root.glassInk.b, 0.22)
            : "#e5e5ea"
        overdueInk: root.transparentMode ? root.glassInk : "#ff3b30"
    }
}
