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
    readonly property string isoDate: liveMode ? String(host.clock?.isoDate ?? "") : String(snapshot?.today ?? "")
    readonly property bool transparentMode: Boolean(appearance?.transparent)
    readonly property color glassInk: appearance?.foreground ?? "#ffffff"

    readonly property var backgroundSpec: ({
        startColor: "#fff8fa",
        endColor: "#f3e8ed"
    })

    Shared.CalendarContent {
        anchors.fill: parent
        widgetSize: root.widgetSize
        appearance: root.appearance
        pimData: root.pimData
        isoDate: root.isoDate
        host: root.host
        headerBackground: root.transparentMode ? "transparent" : "#ff5d66"
        headerInk: root.transparentMode ? root.glassInk : "#ffffff"
        rightPaneBackground: root.transparentMode ? "transparent" : "#fafafa"
        dividerColor: root.transparentMode ? Qt.rgba(root.glassInk.r, root.glassInk.g, root.glassInk.b, 0.24) : Qt.rgba(0, 0, 0, 0.10)
        primaryInk: root.transparentMode ? root.glassInk : "#15151a"
        subtleInk: root.transparentMode
            ? Qt.rgba(root.glassInk.r, root.glassInk.g, root.glassInk.b, 0.78)
            : "#4d4d55"
        mutedInk: root.transparentMode
            ? Qt.rgba(root.glassInk.r, root.glassInk.g, root.glassInk.b, 0.58)
            : Qt.rgba(0.60, 0.60, 0.64, 0.72)
        weekdayInk: root.transparentMode
            ? Qt.rgba(root.glassInk.r, root.glassInk.g, root.glassInk.b, 0.80)
            : "#5d5d65"
        weekendInk: root.transparentMode
            ? Qt.rgba(root.glassInk.r, root.glassInk.g, root.glassInk.b, 0.90)
            : "#e95a63"
        dayInk: root.transparentMode ? root.glassInk : "#29292f"
        todayCircleColor: root.transparentMode
            ? Qt.rgba(root.glassInk.r, root.glassInk.g, root.glassInk.b, 0.24)
            : "#ef5661"
        todayInk: root.transparentMode ? root.glassInk : "#ffffff"
        cardCornerRadius: 24
    }
}
