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
    readonly property var systemData: liveMode ? (host.system ?? snapshot) : snapshot
    readonly property var pal: appearance?.palette ?? ({})
    readonly property color onSurface: pal.onSurface ?? appearance?.foreground ?? "#1e293b"
    readonly property color onSurfaceVariant: pal.onSurfaceVariant ?? "#64748b"

    Shared.SystemContent {
        anchors.fill: parent
        anchors.margins: (root.compact && root.surfaceShape !== "roundedRect") ? 8 : 0
        widgetSize: root.widgetSize
        appearance: root.appearance
        systemData: root.systemData
        cpuColor: root.pal.primary ?? "#ff375f"
        memoryColor: root.pal.tertiary ?? "#30d158"
        storageColor: root.pal.secondary ?? "#64d2ff"
        ringTrackColor: root.pal.outlineVariant ?? (root.appearance?.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12))
        primaryInk: root.onSurface
        subtleInk: root.onSurfaceVariant
        dividerColor: root.pal.outlineVariant ?? (root.appearance?.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12))
        heavyRings: true
    }
}
