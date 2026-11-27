import QtQuick

// Hover detail: time, date, sunrise and sunset. Host owns the popup shell
// (fixed 300px width); this file only declares content and height.
Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property var clockData: liveMode ? (host.clock ?? snapshot) : snapshot
    readonly property var weatherData: liveMode ? host.weather : snapshot
    readonly property bool format24h: host?.settings?.format24h !== false
    readonly property bool material: appearance?.style === "material"
    readonly property bool isZh: String(appearance?.locale ?? "").toLowerCase().startsWith("zh")
    readonly property var pal: material ? (appearance?.palette ?? ({})) : ({})
    readonly property color ink: material
        ? (pal.onSurface ?? appearance?.foreground ?? "#1e293b")
        : (appearance?.foreground ?? (appearance?.isDark ? "#fbfcff" : "#0e1015"))

    function pad(n) { return (n < 10 ? "0" : "") + n }
    function sunValue(live, sample) {
        const v = liveMode ? live : sample
        return v && String(v).length > 0 ? String(v) : "--:--"
    }

    readonly property string weekdayText: {
        const zh = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        const en = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return (isZh ? zh : en)[(((Number(clockData?.weekday ?? 0)) % 7) + 7) % 7]
    }
    readonly property var rows: [
        { label: isZh ? "时间" : "Time",
            value: String((format24h ? clockData?.time24h : clockData?.time12h) ?? "--:--")
                + (format24h ? ":" + pad(Number(clockData?.seconds ?? 0)) : "") },
        { label: isZh ? "日期" : "Date",
            value: String(clockData?.isoDate ?? "") + " " + weekdayText },
        { label: isZh ? "日出" : "Sunrise", value: sunValue(weatherData?.sunriseTime, snapshot?.sunriseTime) },
        { label: isZh ? "日落" : "Sunset", value: sunValue(weatherData?.sunsetTime, snapshot?.sunsetTime) }
    ]

    implicitHeight: col.implicitHeight + 28

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 6

        Text {
            text: root.isZh ? "时钟" : "Clock"
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
