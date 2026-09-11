import QtQuick
import qs.desktop.modules.common
import qs.desktop.modules.dock

Item {
    id: widget
    property int iconSize: 44
    property int dockHeight: 60
    property int widthUnits: 4
    readonly property real backgroundGap: iconSize * 0.1
    readonly property real contentWidth: iconSize * widthUnits
    readonly property bool compact: iconSize < 32
    function tone(color) {
        return IconAppearanceService.styledColor(color)
    }

    function backgroundStart(code, day) {
        if (code === 0) return day ? Qt.rgba(0.18, 0.54, 0.94, 0.58) : Qt.rgba(0.10, 0.15, 0.38, 0.66)
        if (code === 1 || code === 2) return Qt.rgba(0.36, 0.58, 0.76, 0.56)
        // Overcast: cold grey-blue dissolving into cloud white.
        if (code === 3) return Qt.rgba(0.35, 0.43, 0.52, 0.62)
        if (code === 45 || code === 48) return Qt.rgba(0.38, 0.45, 0.49, 0.60)
        if (code >= 51 && code <= 67) return Qt.rgba(0.20, 0.35, 0.49, 0.64)
        if (code >= 71 && code <= 86) return Qt.rgba(0.54, 0.68, 0.78, 0.58)
        if (code >= 95) return Qt.rgba(0.24, 0.23, 0.40, 0.70)
        return Qt.rgba(0.32, 0.44, 0.58, 0.58)
    }

    function backgroundEnd(code, day) {
        if (code === 0) return day ? Qt.rgba(1.0, 0.72, 0.30, 0.42) : Qt.rgba(0.36, 0.42, 0.70, 0.38)
        if (code === 1 || code === 2) return Qt.rgba(0.88, 0.90, 0.91, 0.46)
        if (code === 3) return Qt.rgba(0.92, 0.94, 0.95, 0.48)
        if (code === 45 || code === 48) return Qt.rgba(0.82, 0.85, 0.85, 0.44)
        if (code >= 51 && code <= 67) return Qt.rgba(0.58, 0.68, 0.73, 0.40)
        if (code >= 71 && code <= 86) return Qt.rgba(0.94, 0.98, 1.0, 0.50)
        if (code >= 95) return Qt.rgba(0.57, 0.54, 0.72, 0.46)
        return Qt.rgba(0.76, 0.82, 0.86, 0.42)
    }

    width: contentWidth + backgroundGap * 2
    height: iconSize

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: -widget.backgroundGap
        width: widget.width
        height: widget.iconSize + widget.backgroundGap * 2
        radius: widget.iconSize * 0.35
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: widget.tone(widget.backgroundStart(WeatherService.weatherCode,
                                                          WeatherService.isDay))
            }
            GradientStop {
                position: 1.0
                color: widget.tone(widget.backgroundEnd(WeatherService.weatherCode,
                                                        WeatherService.isDay))
            }
        }

        // Keep ambient weather decoration static while the Dock is idle.
        // Infinite property animations force a full scene-graph update at the
        // display refresh rate and were the dominant source of idle render
        // work. The weather state itself still updates with WeatherService.
        Item {
            id: cloudLayer
            anchors.fill: parent
            clip: true
            visible: WeatherService.weatherCode === 1 || WeatherService.weatherCode === 2
                || WeatherService.weatherCode === 3 || WeatherService.weatherCode === 45
                || WeatherService.weatherCode === 48

            Item {
                id: cloudBack
                width: parent.width * 0.58
                height: parent.height * 0.42
                y: parent.height * 0.10
                x: -width
                opacity: 0.16
                Image {
                    anchors.fill: parent
                    source: Qt.resolvedUrl("../../assets/weather-cloud.svg")
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
            }
            Item {
                id: cloudFront
                width: parent.width * 0.48
                height: parent.height * 0.48
                y: parent.height * 0.42
                x: parent.width
                opacity: 0.21
                Image {
                    anchors.fill: parent
                    source: Qt.resolvedUrl("../../assets/weather-cloud-wide.svg")
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
            }
        }

        Item {
            id: sunLayer
            anchors.fill: parent
            visible: WeatherService.weatherCode === 0 && WeatherService.isDay
            opacity: 0.24
            Item {
                id: sunRays
                width: 54
                height: 54
                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                Repeater {
                    model: 8
                    delegate: Rectangle {
                        required property int index
                        width: 2
                        height: 10
                        radius: 1
                        color: widget.tone(Qt.rgba(1.0, 0.969, 0.761, 1.0))
                        x: sunRays.width / 2 - width / 2
                        y: 1
                        transform: Rotation { origin.x: 1; origin.y: 26; angle: index * 45 }
                    }
                }
                Rectangle { anchors.centerIn: parent; width: 22; height: 22; radius: 11; color: widget.tone(Qt.rgba(1.0, 0.949, 0.643, 1.0)) }
            }
        }

        Item {
            id: rainLayer
            anchors.fill: parent
            clip: true
            visible: (WeatherService.weatherCode >= 51 && WeatherService.weatherCode <= 67)
                || (WeatherService.weatherCode >= 80 && WeatherService.weatherCode <= 82)
            opacity: 0.32
            Repeater {
                model: 7
                delegate: Rectangle {
                    required property int index
                    width: 1
                    height: 10
                    radius: 1
                    color: widget.tone(Qt.rgba(0.851, 0.945, 1.0, 1.0))
                    x: rainLayer.width * (index + 0.35) / 7
                    y: -height
                    rotation: -13
                }
            }
        }
        z: -1
    }
    Row {
        id: weatherRow
        anchors.centerIn: parent
        visible: !widget.compact
        // Keep the telemetry column clear of the rounded right edge. Because
        // the row remains centred, this also shifts it gently left as a unit.
        width: widget.contentWidth - Math.round(widget.iconSize * 0.4)
        spacing: Math.round(widget.iconSize * 0.09)
        // Row contributes one spacing value on either side of the filler.
        // Together they form an exact 10px divider-to-metrics gap.
        readonly property int metricGapFiller: Math.max(0, 10 - spacing * 2)
        Text {
            width: Math.round(widget.iconSize * 0.82)
            text: WeatherService.conditionSymbol(WeatherService.weatherCode, WeatherService.isDay)
            color: ThemeService.foregroundColor
            font.pixelSize: Math.round(widget.iconSize * 0.70)
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
        }
        Column {
            width: weatherRow.width - Math.round(widget.iconSize * 0.82)
                - Math.round(widget.iconSize * 0.78) - 1 - weatherRow.spacing * 4
                - weatherRow.metricGapFiller
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text { width: parent.width; text: WeatherService.temperature; color: ThemeService.foregroundColor; font.pixelSize: Math.max(16, widget.iconSize * 0.42); font.weight: Font.Bold }
            Text { width: parent.width; text: WeatherService.cityName + " · " + WeatherService.conditionText(WeatherService.weatherCode); color: ThemeService.foregroundColor; opacity: 0.75; font.pixelSize: Math.max(9, widget.iconSize * 0.20); elide: Text.ElideRight }
        }
        // Preserve the original column split without drawing a visible rule.
        Item {
            width: 1
            height: Math.round(widget.iconSize * 0.48)
        }
        Item { width: weatherRow.metricGapFiller; height: 1 }
        Column {
            width: Math.round(widget.iconSize * 0.78)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                width: parent.width
                text: "体感 " + WeatherService.apparentTemperature
                color: ThemeService.foregroundColor
                opacity: 0.88
                font.pixelSize: Math.max(8, widget.iconSize * 0.19)
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: parent.width
                text: "湿度 " + WeatherService.humidity
                color: ThemeService.foregroundColor
                opacity: 0.74
                font.pixelSize: Math.max(8, widget.iconSize * 0.19)
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    Row {
        anchors.centerIn: parent
        visible: widget.compact
        height: parent.height
        spacing: Math.max(2, Math.round(widget.iconSize * 0.08))

        Text {
            text: WeatherService.conditionSymbol(WeatherService.weatherCode,
                                                 WeatherService.isDay)
            color: "white"
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: Math.max(9, Math.round(widget.iconSize * 0.55))
        }
        Text {
            text: WeatherService.temperature
            color: "white"
            anchors.verticalCenter: parent.verticalCenter
            font {
                pixelSize: Math.max(9, Math.round(widget.iconSize * 0.48))
                weight: Font.DemiBold
            }
        }
        Text {
            text: "· 体感 " + WeatherService.apparentTemperature
            color: "white"
            opacity: 0.68
            anchors.verticalCenter: parent.verticalCenter
            font {
                pixelSize: Math.max(6, Math.round(widget.iconSize * 0.28))
                weight: Font.Medium
            }
        }
    }
}
