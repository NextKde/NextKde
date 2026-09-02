pragma Singleton

import QtQuick

// Visual-only mapping for every surface that presents weather. Data stays in
// WeatherService; this keeps day/night and WMO-code colour decisions shared.
QtObject {
    function category(code) {
        const value = Number(code)
        if (value === 0) return "clear"
        if (value >= 1 && value <= 2) return "partlyCloudy"
        if (value === 3) return "overcast"
        if (value === 45 || value === 48) return "fog"
        if ((value >= 51 && value <= 67) || (value >= 80 && value <= 82)) return "rain"
        if (value >= 71 && value <= 77 || value === 85 || value === 86) return "snow"
        if (value >= 95) return "storm"
        return "overcast"
    }

    function theme(code, isDay) {
        switch (category(code)) {
        case "clear":
            return isDay
                ? { primary: "#62b8ee", secondary: "#2c72bb", accent: "#ffe36a" }
                : { primary: "#293d78", secondary: "#111a3e", accent: "#c8d9ff" }
        case "partlyCloudy":
            return isDay
                ? { primary: "#718fb0", secondary: "#3d5d82", accent: "#ffe07a" }
                : { primary: "#3b4b70", secondary: "#202a4c", accent: "#c4d3f1" }
        case "overcast":
            return { primary: "#687786", secondary: "#3f4b5a", accent: "#d8e0e8" }
        case "fog":
            return { primary: "#9ba7b2", secondary: "#687582", accent: "#e3e8eb" }
        case "rain":
            return { primary: "#4f789a", secondary: "#213a57", accent: "#caebff" }
        case "snow":
            return { primary: "#7e9eb4", secondary: "#405970", accent: "#f4fbff" }
        case "storm":
            return { primary: "#36416a", secondary: "#16182d", accent: "#e0ccff" }
        }
        return { primary: "#687786", secondary: "#3f4b5a", accent: "#d8e0e8" }
    }

    function isFog(code) { return category(code) === "fog" }
    function isRain(code) { return category(code) === "rain" }
    function isSnow(code) { return category(code) === "snow" }
    function isStorm(code) { return category(code) === "storm" }
}
