import QtQuick
import Quickshell
import qs.desktop.modules.weather
import qs.desktop.modules.common
import qs.desktop.modules.platform

ShellRoot {
    id: test
    property int created: 0
    property int removed: 0
    property int emptyReadings: 0
    property bool watching: false

    Item {
        Repeater {
            model: WeatherService.forecastDays.slice(0, 7)
            delegate: Item {
                Component.onCompleted: test.created++
                Component.onDestruction: test.removed++
            }
        }
    }
    Connections {
        target: WeatherService
        function onAvailableChanged() {
            if (test.watching && !WeatherService.available) test.emptyReadings++
        }
    }
    function check(ok, message) {
        if (!ok) throw new Error(message)
    }
    function forecast(city, temperature) {
        return {
            schemaVersion: 1, status: "ready", units: "metric",
            location: { id: city, name: city }, locations: [{ id: city }],
            current: { temperature: temperature, weatherCode: 0, isDay: true },
            hourly: [{ time: "2026-11-06T12:00", temperature: temperature }],
            daily: [{ date: "2026-11-06", weatherCode: 0,
                temperatureMaximum: 20, temperatureMinimum: 10 }],
            fetchedAt: Date.now(), staleAt: Date.now() + 7200000
        }
    }
    Timer {
        interval: 100
        running: true
        onTriggered: {
            try {
                IndependentAppWidgetService.weather = { state: "not-installed" }
                WeatherService.applyWeather(test.forecast("city-a", 18))
                test.watching = true
                const initialCreated = test.created
                const initialRemoved = test.removed
                const days = WeatherService.daily
                const hours = WeatherService.hourly
                for (let i = 0; i < 3; i++) {
                    IndependentAppWidgetService.weather = { state: "not-installed" }
                    WeatherService.applyWeather(test.forecast("city-a", 18))
                }
                test.check(WeatherService.daily === days && WeatherService.hourly === hours,
                    "identical forecasts preserve array models")
                test.check(test.created === initialCreated && test.removed === initialRemoved,
                    "polling must not recreate forecast delegates")
                DataClient.transportChanged(false)
                test.check(WeatherService.available && WeatherService.stale,
                    "core disconnect retains cached weather")
                DataClient.transportChanged(true)
                test.check(WeatherService.available, "core reconnect retains weather")
                IndependentAppWidgetService.weather = { state: "unavailable", queryError: true }
                test.check(WeatherService.available && WeatherService.stale,
                    "inspection failure retains cached weather")
                IndependentAppWidgetService.weather = { state: "loading" }
                IndependentAppWidgetService.weather = { state: "not-installed" }
                test.check(WeatherService.available, "core source recovery retains weather")
                const incomplete = test.forecast("city-a", 18)
                incomplete.current = null
                incomplete.status = "loading"
                WeatherService.applyWeather(incomplete)
                test.check(WeatherService.temperature === "18°", "loading keeps the last reading")
                incomplete.status = "error"
                WeatherService.applyWeather(incomplete)
                test.check(WeatherService.temperature === "18°", "failed refresh keeps the last reading")
                test.check(test.emptyReadings === 0, "refreshes never expose an empty reading")
                test.watching = false

                IndependentAppWidgetService.weather = {
                    state: "ready", sourceToken: "app-a", payload: test.forecast("city-a", 19)
                }
                test.watching = true
                IndependentAppWidgetService.weather = { state: "unavailable" }
                IndependentAppWidgetService.weather = { state: "invalid", sourceToken: "app-a" }
                IndependentAppWidgetService.weather = {
                    state: "stale", sourceToken: "app-a", payload: test.forecast("city-a", 19)
                }
                test.check(test.emptyReadings === 0 && WeatherService.temperature === "19°",
                    "same app source survives failures and stale recovery")
                test.watching = false
                IndependentAppWidgetService.weather = { state: "missing", sourceToken: "app-b" }
                test.check(!WeatherService.available, "confirmed source change clears old weather")
                WeatherService.applyWeather(test.forecast("city-a", 20))
                incomplete.location.id = "city-b"
                WeatherService.applyWeather(incomplete)
                test.check(!WeatherService.available, "different city cannot retain old reading")
                WeatherService.applyWeather(test.forecast("city-a", 20))
                incomplete.location.id = "city-a"
                incomplete.units = "imperial"
                WeatherService.applyWeather(incomplete)
                test.check(!WeatherService.available, "different units cannot retain old reading")
                WeatherService.applyWeather(test.forecast("city-a", 20))
                WeatherService.applyWeather({ schemaVersion: 1, status: "idle", locations: [] })
                test.check(!WeatherService.available && WeatherService.forecastDays.length === 0,
                    "explicit empty selection clears weather")
                IndependentAppWidgetService.weather = { state: "unavailable" }
                test.check(!WeatherService.available && !WeatherService.loading,
                    "failed startup inspection reports an error without pretending to load")
                IndependentAppWidgetService.weather = {
                    state: "ready", sourceToken: "app-c", payload: test.forecast("city-c", 13)
                }
                test.check(WeatherService.available && !WeatherService.stale
                    && WeatherService.cityName === "city-c" && WeatherService.temperature === "13°",
                    "a valid app summary recovers an empty startup failure")
                console.log("WEATHER_REFRESH_PASS: core polls, delegate stability, reconnects, inspection failures, app recovery, source/city/units changes, empty selection, startup recovery")
            } catch (error) {
                console.error("WEATHER_REFRESH_FAIL: " + error)
            }
            Qt.quit()
        }
    }
}
