import QtQuick
import ".." as Shared

Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property bool inDock: host?.container === "dock"
    readonly property bool verticalDock: inDock && host?.orientation === "vertical"
    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property var clockData: liveMode ? (host.clock ?? snapshot) : snapshot
    readonly property bool format24h: host?.settings?.format24h !== false
    readonly property var backgroundSpec: ({
        startColor: "#536783",
        endColor: "#35465f"
    })

    Shared.ClockContent {
        anchors.fill: parent
        widgetSize: root.widgetSize
        appearance: root.appearance
        clockData: root.clockData
        clockStyle: "analog"
        format24h: root.format24h
        inDock: root.inDock
        verticalDock: root.verticalDock
        dialFaceColor: "#fafafa"
        dialRimColor: Qt.rgba(0xde / 255, 0xde / 255, 0xde / 255, 0.42)
        numeralColor: "#242126"
        markColor: "#171717"
        hourColor: "#171717"
        minuteColor: "#171717"
        secondColor: "#ee7659"
        hubColor: "#ee7659"
    }
}
