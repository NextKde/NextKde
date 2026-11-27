import QtQuick

// Hover detail: temperatures and resource usage. Host owns the popup shell.
Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property var sys: liveMode ? (host.system ?? snapshot) : snapshot
    readonly property bool material: appearance?.style === "material"
    readonly property bool isZh: String(appearance?.locale ?? "").toLowerCase().startsWith("zh")
    readonly property var pal: material ? (appearance?.palette ?? ({})) : ({})
    readonly property color ink: material
        ? (pal.onSurface ?? appearance?.foreground ?? "#1e293b")
        : (appearance?.foreground ?? (appearance?.isDark ? "#fbfcff" : "#0e1015"))

    function pct(v) { return Math.round(Math.max(0, Math.min(1, Number(v))) * 100) + "%" }
    function deg(milliC) {
        return Number(milliC) >= 0 ? Math.round(Number(milliC) / 1000) + "°" : "--°"
    }

    readonly property var rows: [
        { label: isZh ? "平均温度" : "Avg temperature", value: deg(sys?.temperatureMilliC ?? -1) },
        { label: isZh ? "最高温度" : "Max temperature", value: deg(sys?.temperatureMaxMilliC ?? -1) },
        { label: "CPU", value: pct(sys?.cpuUsage ?? 0) },
        { label: isZh ? "内存" : "Memory",
            value: Number(sys?.memoryTotalBytes ?? 0) > 0
                ? pct(Number(sys.memoryUsedBytes) / Number(sys.memoryTotalBytes)) : "--" },
        { label: isZh ? "存储" : "Storage",
            value: Number(sys?.diskTotalBytes ?? 0) > 0
                ? pct(Number(sys.diskUsedBytes) / Number(sys.diskTotalBytes)) : "--" }
    ]

    implicitHeight: col.implicitHeight + 28

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 6

        Text {
            text: root.isZh ? "资源占用" : "Resource Usage"
            color: root.ink
            font { pixelSize: 14; weight: Font.DemiBold }
        }
        Rectangle { width: parent.width; height: 1; color: root.ink; opacity: 0.12 }

        Repeater {
            model: root.rows
            delegate: Item {
                required property var modelData
                width: col.width
                height: 20
                Text {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: modelData.label
                    color: root.ink
                    opacity: 0.72
                    font { pixelSize: 12; weight: Font.Medium }
                }
                Text {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: modelData.value
                    color: root.ink
                    font { pixelSize: 13; weight: Font.DemiBold }
                }
            }
        }
    }
}
