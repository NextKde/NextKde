import QtQuick

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
    readonly property bool isDark: Boolean(appearance?.isDark)
    readonly property color inkColor: isDark ? "#ffffff" : "#242126"
    readonly property var backgroundSpec: isDark
        ? ({ startColor: "#536783", endColor: "#35465f" })
        : ({ startColor: "#fafafa", endColor: "#ffffff" })

    ClockContent {
        anchors.fill: parent
        widgetSize: root.widgetSize
        appearance: root.appearance
        clockData: root.clockData
        clockStyle: "digital"
        format24h: root.format24h
        inDock: root.inDock
        verticalDock: root.verticalDock
        digitalTimeColor: root.inkColor
        digitalSubtleColor: root.inkColor
        digitalRingColor: root.inkColor
        digitalCornerRadius: 24
    }
}
