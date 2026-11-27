import QtQuick

// Hover detail: weather rows. Host owns the popup shell (300px wide).
Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property var weatherData: liveMode ? (host.weather ?? snapshot) : snapshot
    readonly property bool material: appearance?.style === "material"
    readonly property bool isZh: String(appearance?.locale ?? "").toLowerCase().startsWith("zh")
    readonly property var pal: material ? (appearance?.palette ?? ({})) : ({})
    readonly property color ink: material
        ? (pal.onSurface ?? appearance?.foreground ?? "#1e293b")
        : (appearance?.foreground ?? (appearance?.isDark ? "#fbfcff" : "#0e1015"))

    readonly property var rows: [
        { label: isZh ? "天气" : "Weather", value: String(weatherData?.conditionText || "--") },
        { label: isZh ? "温度" : "Temperature", value: String(weatherData?.temperatureText || "--°") },
        { label: isZh ? "体感" : "Feels like", value: String(weatherData?.apparentTemperature || "--°") },
        { label: isZh ? "湿度" : "Humidity", value: String(weatherData?.humidity || "--") },
        { label: isZh ? "风速" : "Wind speed", value: String(weatherData?.windSpeed || "--") }
    ]

    implicitHeight: col.implicitHeight + 28

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 6

        Row {
            spacing: 8
            Text {
                text: root.isZh ? "天气" : "Weather"
                color: root.ink
                font { pixelSize: 14; weight: Font.DemiBold }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: String(root.weatherData?.locationName || "")
                color: root.ink
                opacity: 0.62
                font { pixelSize: 11; weight: Font.Medium }
            }
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
