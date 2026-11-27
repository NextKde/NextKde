import QtQuick
import ".." as Shared

Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property var weatherData: liveMode ? (host.weather ?? snapshot) : snapshot

    function themeFor(code, isDay) {
        const value = Number(code)
        let cat = "overcast"
        if (value === 0) cat = "clear"
        else if (value >= 1 && value <= 2) cat = "partlyCloudy"
        else if (value === 3) cat = "overcast"
        else if (value === 45 || value === 48) cat = "fog"
        else if ((value >= 51 && value <= 67) || (value >= 80 && value <= 82)) cat = "rain"
        else if ((value >= 71 && value <= 77) || value === 85 || value === 86) cat = "snow"
        else if (value >= 95) cat = "storm"

        switch (cat) {
        case "clear":
            return isDay
                ? { primary: "#62b8ee", secondary: "#2c72bb", end: "#1d5394", accent: "#ffe36a" }
                : { primary: "#293d78", secondary: "#15204a", end: "#0c122c", accent: "#c8d9ff" }
        case "partlyCloudy":
            return isDay
                ? { primary: "#718fb0", secondary: "#3d5d82", end: "#2a4362", accent: "#ffe07a" }
                : { primary: "#3b4b70", secondary: "#202a4c", end: "#131932", accent: "#c4d3f1" }
        case "overcast":
            return { primary: "#687786", secondary: "#3f4b5a", end: "#2a333f", accent: "#d8e0e8" }
        case "fog":
            return { primary: "#8e9ba6", secondary: "#5d6a76", end: "#414c56", accent: "#e3e8eb" }
        case "rain":
            return { primary: "#4f789a", secondary: "#213a57", end: "#142438", accent: "#caebff" }
        case "snow":
            return { primary: "#7394ab", secondary: "#405970", end: "#2a3e50", accent: "#f4fbff" }
        case "storm":
            return { primary: "#36416a", secondary: "#1a1f39", end: "#0f1122", accent: "#e0ccff" }
        }
        return { primary: "#687786", secondary: "#3f4b5a", end: "#2a333f", accent: "#d8e0e8" }
    }

    readonly property var weatherTheme: themeFor(weatherData?.weatherCode ?? 0, weatherData?.isDay !== false)
    readonly property var backgroundSpec: ({
        orientation: "horizontal",
        startColor: weatherTheme.primary,
        midColor: weatherTheme.secondary,
        midPosition: 0.58,
        endColor: Qt.darker(weatherTheme.secondary, 1.16)
    })

    Shared.WeatherContent {
        anchors.fill: parent
        widgetSize: root.widgetSize
        appearance: root.appearance
        weatherData: root.weatherData
        host: root.host
        showAmbientArtwork: !Boolean(root.appearance?.transparent)
        primaryInk: root.appearance?.transparent ? (root.appearance?.foreground ?? "#ffffff") : "#ffffff"
        subtleInk: root.appearance?.transparent
            ? Qt.rgba((root.appearance?.foreground?.r ?? 1), (root.appearance?.foreground?.g ?? 1), (root.appearance?.foreground?.b ?? 1), 0.78)
            : Qt.rgba(1, 1, 1, 0.78)
        accentInk: root.appearance?.transparent ? (root.appearance?.foreground ?? "#ffffff") : root.weatherTheme.accent
    }
}
