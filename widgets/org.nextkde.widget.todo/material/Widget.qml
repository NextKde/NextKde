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
    readonly property var pimData: liveMode ? (host.pim ?? snapshot) : snapshot
    readonly property var pal: appearance?.palette ?? ({})
    readonly property color onSurface: pal.onSurface ?? appearance?.foreground ?? "#1e293b"
    readonly property color onSurfaceVariant: pal.onSurfaceVariant ?? "#64748b"

    Shared.TodoContent {
        anchors.fill: parent
        anchors.topMargin: root.compact ? (root.surfaceShape === "arch" ? 16 : root.surfaceShape === "clover" ? 12 : 0) : 0
        anchors.leftMargin: root.compact ? (root.surfaceShape === "arch" ? 10 : root.surfaceShape === "clover" ? 12 : 0) : 0
        anchors.rightMargin: root.compact ? (root.surfaceShape === "arch" ? 10 : root.surfaceShape === "clover" ? 12 : 0) : 0
        anchors.bottomMargin: root.compact ? (root.surfaceShape === "arch" ? 4 : root.surfaceShape === "clover" ? 12 : 0) : 0
        widgetSize: root.widgetSize
        appearance: root.appearance
        pimData: root.pimData
        host: root.host
        accentColor: root.pal.primary ?? "#2563eb"
        iconForeground: root.pal.onPrimary ?? "#ffffff"
        primaryInk: root.onSurface
        subtleInk: root.onSurfaceVariant
        circleBorderColor: root.pal.outline ?? "#94a3b8"
        hairlineColor: root.pal.outlineVariant ?? (root.appearance?.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10))
        overdueInk: root.pal.error ?? "#ef4444"
    }
}
