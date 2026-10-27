import QtQuick
import qs.desktop.modules.weather
import "../../../shared/qml/i18n"

// IslandWeatherWidget — ported from NookX's WeatherCurrentTempView /
// WeatherFeelsLikeView / WeatherHumidityView / WeatherIconView.
//
// The original drives its island widgets from its own weather store; the
// Linux equivalent is the shell's shared WeatherService (the data-service
// weather.snapshot the weather app and dock already use). When the service
// has no reading the widget renders the original's failure state
// ("获取失败") instead of inventing values — the screenshot this port is
// modelled on shows exactly that state.
Rectangle {
    id: root

    color: "transparent"

    readonly property bool available: WeatherService.available
    readonly property bool loading: WeatherService.loading && !available

    // WMO weather interpretation codes -> short labels. The common ones
    // reuse the shell weather module's existing vocabulary; the rest extend
    // it at the same granularity as the original's condition line.
    readonly property var codeLabels: ({
        "0": "Clear sky", "1": "Mostly clear", "2": "Partly cloudy", "3": "Overcast",
        "45": "Fog", "48": "Rime fog",
        "51": "Light drizzle", "53": "Drizzle", "55": "Dense drizzle",
        "56": "Freezing drizzle", "57": "Freezing drizzle",
        "61": "Light rain", "63": "Rain", "65": "Heavy rain",
        "66": "Freezing rain", "67": "Freezing rain",
        "71": "Light snow", "73": "Snow", "75": "Heavy snow", "77": "Snow grains",
        "80": "Rain showers", "81": "Rain showers", "82": "Violent showers",
        "85": "Snow showers", "86": "Snow showers",
        "95": "Thunderstorm", "96": "Thunderstorm, hail", "99": "Thunderstorm, hail"
    })

    function codeLabel(code) {
        const table = root.codeLabels
        const key = String(code)
        return table[key] !== undefined ? I18n.tr(table[key]) : I18n.tr("Unknown weather")
    }

    Column {
        anchors.centerIn: parent
        spacing: 2

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !root.available
            text: root.loading ? "..." : I18n.tr("Fetch failed")
            color: Qt.rgba(1, 1, 1, 0.5)
            font.pixelSize: 11
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.available
            text: WeatherService.temperature
            color: "white"
            font.pixelSize: 22
            font.bold: true
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.available
            text: root.codeLabel(WeatherService.weatherCode)
            color: Qt.rgba(1, 1, 1, 0.75)
            font.pixelSize: 10
            elide: Text.ElideRight
            width: root.width - 8
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.available
            text: I18n.tr("Feels like %1").arg(WeatherService.apparentTemperature)
                 + "  " + I18n.tr("Humidity %1").arg(WeatherService.humidity)
            color: Qt.rgba(1, 1, 1, 0.5)
            font.pixelSize: 9
            elide: Text.ElideRight
            width: root.width - 8
        }
    }
}
