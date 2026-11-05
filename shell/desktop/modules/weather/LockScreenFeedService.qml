pragma Singleton

import QtQuick
import qs.desktop.modules.platform

// The greeter consumes a data-only QML object. The platform owns its fixed
// destination and atomic publication; no staged file or copy worker is involved.
QtObject {
    id: service

    readonly property int refreshMinutes: 5
    property bool _queued: false
    property bool _publishing: false

    function initialize() {
        write()
    }

    function payload() {
        if (!WeatherService.available || WeatherService.stale)
            return {
                weatherSymbol: "", weatherTemperature: "--°", weatherCity: "",
                weatherCondition: "", weatherApparent: "--°", weatherHumidity: "--"
            }
        return {
            weatherSymbol: WeatherService.conditionSymbol(WeatherService.weatherCode, WeatherService.isDay),
            weatherTemperature: WeatherService.temperature,
            weatherCity: WeatherService.cityName,
            weatherCondition: WeatherService.conditionText(WeatherService.weatherCode),
            weatherApparent: WeatherService.apparentTemperature,
            weatherHumidity: WeatherService.humidity
        }
    }

    function write() {
        _queued = true
        // Read the final values after a batch of weather property changes.
        Qt.callLater(service._drain)
    }

    function _drain() {
        if (_publishing || !_queued || !PlatformClient.connected) return
        _queued = false
        _publishing = true
        PlatformClient.request("lockscreen.weather-publish", payload(), function(response) {
            service._publishing = false
            if (!response?.ok)
                console.warn("[LockScreenFeed] publish failed: "
                    + (response?.error?.message || "platform unavailable"))
            if (service._queued) Qt.callLater(service._drain)
        })
    }

    property Timer _timer: Timer {
        interval: service.refreshMinutes * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: service.write()
    }

    property Connections _weather: Connections {
        target: WeatherService
        function onCurrentChanged() { service.write() }
        function onStaleChanged() { service.write() }
        function onAvailableChanged() { service.write() }
        function onLocationChanged() { service.write() }
        function onUnitsChanged() { service.write() }
    }

    property Connections _transport: Connections {
        target: PlatformClient
        function onTransportChanged(connected) { service.write() }
    }
}
