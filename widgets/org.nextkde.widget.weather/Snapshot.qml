import QtQml

QtObject {
    function getSnapshot(size) {
        return {
            status: "ready",
            available: true,
            loading: false,
            locationId: "shanghai",
            locationName: "Shanghai",
            temperature: 22,
            temperatureText: "22°",
            weatherCode: 0,
            isDay: true,
            conditionSymbol: "☀",
            conditionText: "Clear",
            humidity: "48%",
            windSpeed: "12 km/h",
            units: "metric",
            errorMessage: "",
            sourceMessage: "",
            forecastDays: [
                { date: "2026-11-26", label: "Today", code: 0, symbol: "☀", high: 24, low: 15 },
                { date: "2026-11-27", label: "Fri", code: 2, symbol: "⛅", high: 22, low: 14 },
                { date: "2026-11-28", label: "Sat", code: 3, symbol: "☁", high: 19, low: 13 },
                { date: "2026-11-29", label: "Sun", code: 61, symbol: "🌧", high: 17, low: 12 },
                { date: "2026-11-30", label: "Mon", code: 0, symbol: "☀", high: 21, low: 11 },
                { date: "2026-12-01", label: "Tue", code: 1, symbol: "🌤", high: 23, low: 13 },
                { date: "2026-12-02", label: "Wed", code: 0, symbol: "☀", high: 24, low: 14 }
            ]
        }
    }
}
