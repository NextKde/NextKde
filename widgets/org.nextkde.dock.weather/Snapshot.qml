import QtQml

QtObject {
    function getSnapshot(size) {
        return {
            status: "ready",
            available: true,
            locationName: "Shanghai",
            temperatureText: "22°",
            apparentTemperature: "21°",
            weatherCode: 0,
            isDay: true,
            conditionSymbol: "☀",
            conditionText: "Clear",
            humidity: "48%",
            windSpeed: "12 km/h"
        }
    }
}
