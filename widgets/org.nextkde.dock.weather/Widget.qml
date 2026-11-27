import QtQuick

// Dock weather card: restored original DockWeatherWidget 3-column layout
// (symbol + temp/city·condition + feels-like/humidity) plus subtle sunny rays.
Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property bool vertical: host?.orientation === "vertical"
    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property var weatherData: liveMode ? (host.weather ?? snapshot) : snapshot
    readonly property bool material: appearance?.style === "material"
    readonly property var pal: appearance?.palette ?? ({})
    readonly property color ink: material ? (pal.onSurface ?? "#1e293b") : "white"
    readonly property bool isZh: String(appearance?.locale ?? "").toLowerCase().startsWith("zh")
    readonly property bool ready: Boolean(weatherData?.available)
    readonly property int code: Number(weatherData?.weatherCode ?? 0)
    readonly property bool day: weatherData?.isDay !== false

    function startColor(c, d) {
        if (c === 0) return d ? Qt.rgba(0.18, 0.54, 0.94, 0.58) : Qt.rgba(0.10, 0.15, 0.38, 0.66)
        if (c === 1 || c === 2) return Qt.rgba(0.36, 0.58, 0.76, 0.56)
        if (c === 3) return Qt.rgba(0.35, 0.43, 0.52, 0.62)
        if (c === 45 || c === 48) return Qt.rgba(0.38, 0.45, 0.49, 0.60)
        if (c >= 51 && c <= 67) return Qt.rgba(0.20, 0.35, 0.49, 0.64)
        if (c >= 71 && c <= 86) return Qt.rgba(0.54, 0.68, 0.78, 0.58)
        if (c >= 95) return Qt.rgba(0.24, 0.23, 0.40, 0.70)
        return Qt.rgba(0.32, 0.44, 0.58, 0.58)
    }
    function endColor(c, d) {
        if (c === 0) return d ? Qt.rgba(1.0, 0.72, 0.30, 0.42) : Qt.rgba(0.36, 0.42, 0.70, 0.38)
        if (c === 1 || c === 2) return Qt.rgba(0.88, 0.90, 0.91, 0.46)
        if (c === 3) return Qt.rgba(0.92, 0.94, 0.95, 0.48)
        if (c === 45 || c === 48) return Qt.rgba(0.82, 0.85, 0.85, 0.44)
        if (c >= 51 && c <= 67) return Qt.rgba(0.58, 0.68, 0.73, 0.40)
        if (c >= 71 && c <= 86) return Qt.rgba(0.94, 0.98, 1.0, 0.50)
        if (c >= 95) return Qt.rgba(0.57, 0.54, 0.72, 0.46)
        return Qt.rgba(0.76, 0.82, 0.86, 0.42)
    }

    readonly property var backgroundSpec: ({
        startColor: startColor(code, day),
        endColor: endColor(code, day),
        orientation: "horizontal"
    })

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.liveMode) root.host.invokeAction("app.open-weather", {})
    }

    // Subtle static sunny rays layer on the trailing edge
    Item {
        visible: !root.vertical && root.code === 0 && root.day
        anchors.fill: parent
        clip: true
        opacity: root.material ? 0.12 : 0.20

        Item {
            width: Math.round(root.height * 1.1)
            height: width
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            Repeater {
                model: 8
                Rectangle {
                    required property int index
                    width: 2
                    height: Math.round(parent.height * 0.24)
                    radius: 1
                    color: root.ink
                    x: parent.width / 2 - width / 2
                    y: parent.height / 2 - parent.height * 0.44
                    transform: Rotation {
                        origin.x: 1
                        origin.y: Math.round(parent.height * 0.44)
                        angle: index * 45
                    }
                }
            }
        }
    }

    // ── Horizontal 3-column Weather Row ──────────────────────────────────
    Item {
        visible: !root.vertical
        anchors { fill: parent; leftMargin: 6; rightMargin: 6 }

        Text {
            id: symText
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: Math.round(root.height * 0.76)
            horizontalAlignment: Text.AlignHCenter
            text: String(root.weatherData?.conditionSymbol || "☀")
            color: root.ink
            font.pixelSize: Math.max(14, Math.round(root.height * 0.68))
        }

        Column {
            id: midCol
            anchors {
                left: symText.right
                leftMargin: Math.max(4, Math.round(root.height * 0.10))
                right: rightMetricsCol.left
                rightMargin: Math.max(4, Math.round(root.height * 0.12))
                verticalCenter: parent.verticalCenter
            }
            spacing: 1

            Text {
                width: parent.width
                text: String(root.weatherData?.temperatureText || "--°")
                color: root.ink
                font { pixelSize: Math.max(15, Math.round(root.height * 0.43)); weight: Font.Bold }
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: {
                    const city = String(root.weatherData?.locationName || "")
                    const cond = String(root.weatherData?.conditionText || (root.isZh ? "天气" : "Weather"))
                    return city.length > 0 ? (city + " · " + cond) : cond
                }
                color: root.ink
                opacity: 0.76
                font { pixelSize: Math.max(8, Math.round(root.height * 0.21)); weight: Font.Medium }
            }
        }

        Column {
            id: rightMetricsCol
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: Math.max(46, Math.round(parent.width * 0.30))
            spacing: 2

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: (root.isZh ? "体感 " : "Feels ")
                    + String(root.weatherData?.apparentTemperature || "--°")
                color: root.ink
                opacity: 0.88
                font { pixelSize: Math.max(8, Math.round(root.height * 0.20)); weight: Font.Medium }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: (root.isZh ? "湿度 " : "Hum ")
                    + String(root.weatherData?.humidity || "--")
                color: root.ink
                opacity: 0.74
                font { pixelSize: Math.max(8, Math.round(root.height * 0.20)); weight: Font.Medium }
            }
        }
    }

    // ── Side Dock ────────────────────────────────────────────────────────
    Text {
        visible: root.vertical
        anchors.centerIn: parent
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: String(root.weatherData?.temperatureText || "--°")
        color: root.ink
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: 6
        font { pixelSize: Math.max(10, Math.round(root.height * 0.5)); weight: Font.DemiBold }
    }
}
