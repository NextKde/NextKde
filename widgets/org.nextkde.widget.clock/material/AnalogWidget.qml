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
    property string shapeOverride: ""
    readonly property string surfaceShape: inDock ? "roundedRect" : (shapeOverride || "roundedRect")

    readonly property var pal: appearance?.palette ?? ({})
    readonly property color onSurface: pal.onSurface ?? appearance?.foreground ?? "#1e293b"
    readonly property color onSurfaceVariant: pal.onSurfaceVariant ?? "#64748b"
    readonly property color primaryColor: pal.primary ?? "#3b82f6"
    readonly property color secondaryColor: pal.secondary ?? "#ee7659"
    readonly property color tertiaryColor: pal.tertiary ?? "#6366f1"

    Shared.ClockContent {
        anchors.fill: parent
        anchors.margins: root.inDock ? 0 : (root.surfaceShape === "roundedRect" ? 4 : 8)
        widgetSize: root.widgetSize
        appearance: root.appearance
        clockData: root.clockData
        clockStyle: "analog"
        format24h: root.format24h
        inDock: root.inDock
        verticalDock: root.verticalDock
        dialFaceColor: "transparent"
        dialRimColor: "transparent"
        numeralColor: root.onSurface
        markColor: root.onSurfaceVariant
        hourColor: root.primaryColor
        minuteColor: root.tertiaryColor
        secondColor: root.secondaryColor
        hubColor: root.primaryColor
    }
}
