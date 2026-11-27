import QtQuick
import ".." as Shared

Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property int spanCols: (widgetSize && widgetSize.length >= 2) ? Number(widgetSize[0]) : 2
    readonly property bool compact: spanCols <= 1
    property string shapeOverride: ""
    readonly property string surfaceShape: compact ? (shapeOverride || "roundedRect") : "roundedRect"

    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property var activityData: liveMode ? (host.activity ?? snapshot) : snapshot
    readonly property var pal: appearance?.palette ?? ({})
    readonly property color onSurface: pal.onSurface ?? appearance?.foreground ?? "#1e293b"
    readonly property color onSurfaceVariant: pal.onSurfaceVariant ?? "#64748b"

    Shared.ActivityContent {
        anchors.fill: parent
        anchors.topMargin: root.compact ? (root.surfaceShape === "arch" ? 16 : root.surfaceShape === "cookie" ? 10 : 0) : 0
        anchors.leftMargin: root.compact ? (root.surfaceShape === "arch" ? 10 : root.surfaceShape === "cookie" ? 10 : 0) : 0
        anchors.rightMargin: root.compact ? (root.surfaceShape === "arch" ? 10 : root.surfaceShape === "cookie" ? 10 : 0) : 0
        anchors.bottomMargin: root.compact ? (root.surfaceShape === "arch" ? 4 : root.surfaceShape === "cookie" ? 10 : 0) : 0
        widgetSize: root.widgetSize
        appearance: root.appearance
        activityData: root.activityData
        headerInk: root.onSurface
        primaryInk: root.onSurface
        subtleInk: root.onSurfaceVariant
        heatmapBaseColor: root.pal.primary ?? "#2563eb"
        heatmapEmptyColor: root.pal.surfaceContainerHighest ?? (root.appearance?.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
        barTrackColor: root.pal.surfaceContainerHighest ?? (root.appearance?.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08))
        badgeFillColor: root.pal.primaryContainer ?? "#dbeafe"
        badgeInk: root.pal.onPrimaryContainer ?? root.onSurface
    }
}
