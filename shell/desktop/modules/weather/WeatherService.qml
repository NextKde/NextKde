pragma Singleton

import QtQuick
import "../../../shared/qml/i18n"
import qs.desktop.modules.platform

// Weather network, location, unit and cache state is owned by
// kos-data-service. This adapter keeps the established shell-facing API while
// consuming the shared versioned JSONL protocol.
QtObject {
    id: service

    property var location: ({})
    property var locations: []
    property var current: null
    property var hourly: []
    property var daily: []
    property string units: "metric"
    property string status: "idle"
    property string errorMessage: ""
    property date fetchedAt: new Date(0)
    property real staleAt: 0
    property real nextRefreshAt: 0
    property real clockNow: Date.now()
    property bool ready: false

    readonly property string cityName: String(location?.name ?? "--")
    readonly property real latitude: Number(location?.latitude ?? 0)
    readonly property real longitude: Number(location?.longitude ?? 0)
    readonly property bool loading: status === "loading"
    readonly property bool available: current !== null
    readonly property bool stale: available && staleAt > 0 && clockNow >= staleAt
    readonly property string temperature: available
        ? Math.round(Number(current.temperature)) + "°" : "--°"
    readonly property string apparentTemperature: available
        ? Math.round(Number(current.apparentTemperature)) + "°" : "--°"
    readonly property int weatherCode: available ? Number(current.weatherCode) : -1
    readonly property bool isDay: available ? Boolean(current.isDay) : true
    readonly property string humidity: available
        ? Math.round(Number(current.relativeHumidity)) + "%" : "--"
    readonly property string windSpeed: available
        ? Math.round(Number(current.windSpeed)) + (units === "imperial" ? " mph" : " km/h")
        : "--"
    readonly property string windDirection: available
        ? Math.round(Number(current.windDirection)) + "°" : "--"
    readonly property string sunriseTime: dailyTime("sunrise")
    readonly property string sunsetTime: dailyTime("sunset")
    readonly property var forecastDays: {
        const days = []
        const source = Array.isArray(daily) ? daily : []
        for (let index = 0; index < Math.min(7, source.length); index++) {
            const day = source[index]
            days.push({
                date: String(day?.date ?? ""),
                code: Number(day?.weatherCode ?? -1),
                high: Math.round(Number(day?.temperatureMaximum ?? 0)),
                low: Math.round(Number(day?.temperatureMinimum ?? 0))
            })
        }
        return days
    }

    function dailyTime(field) {
        if (!Array.isArray(daily) || daily.length === 0)
            return "--:--"
        const match = String(daily[0]?.[field] ?? "").match(/T(\d{2}:\d{2})/)
        return match ? match[1] : "--:--"
    }

    function conditionText(code) {
        if (code === 0) return I18n.tr("Clear sky")
        if (code === 1) return I18n.tr("Mostly clear")
        if (code === 2) return I18n.tr("Partly cloudy")
        if (code === 3) return I18n.tr("Overcast")
        if (code === 45 || code === 48) return I18n.tr("Fog")
        if (code >= 51 && code <= 57) return I18n.tr("Drizzle")
        if (code >= 61 && code <= 67) return I18n.tr("Rain")
        if (code >= 71 && code <= 77) return I18n.tr("Snow")
        if (code >= 80 && code <= 82) return I18n.tr("Rain showers")
        if (code >= 85 && code <= 86) return I18n.tr("Snow showers")
        if (code >= 95) return I18n.tr("Thunderstorm")
        return I18n.tr("Unknown weather")
    }

    function conditionSymbol(code, day) {
        if (code === 0) return day ? "☀" : "☾"
        if (code === 1 || code === 2) return day ? "⛅" : "☁"
        if (code === 3) return "☁"
        if (code === 45 || code === 48) return "≋"
        if (code >= 51 && code <= 67) return "☔"
        if (code >= 80 && code <= 82) return "☔"
        if ((code >= 71 && code <= 77) || (code >= 85 && code <= 86)) return "❄"
        if (code >= 95) return "ϟ"
        return "?"
    }

    function forecastLabel(isoDate, index) {
        if (index === 0)
            return I18n.tr("Today")
        if (index === 1)
            return I18n.tr("Tomorrow")
        const weekdays = [I18n.tr("Sun"), I18n.tr("Mon"), I18n.tr("Tue"), I18n.tr("Wed"),
            I18n.tr("Thu"), I18n.tr("Fri"), I18n.tr("Sat")]
        const parsed = new Date(String(isoDate) + "T12:00:00")
        return Number.isNaN(parsed.getTime()) ? String(isoDate) : weekdays[parsed.getDay()]
    }

    function reload() {
        DataClient.request("weather.snapshot", {}, function(response) {
            if (!response.ok) {
                if (!available)
                    errorMessage = String(response.error?.message ?? I18n.tr("Weather data service is not ready"))
                return
            }
            applyWeather(response.result?.weather ?? {})
        })
    }

    function applyWeather(weather) {
        if (Number(weather.schemaVersion) !== 1)
            return
        location = weather.location ?? ({})
        locations = Array.isArray(weather.locations) ? weather.locations : []
        current = weather.current ?? null
        hourly = Array.isArray(weather.hourly) ? weather.hourly : []
        daily = Array.isArray(weather.daily) ? weather.daily : []
        units = weather.units === "imperial" ? "imperial" : "metric"
        status = String(weather.status ?? "idle")
        errorMessage = String(weather.error ?? "")
        fetchedAt = new Date(Number(weather.fetchedAt ?? 0))
        staleAt = Number(weather.staleAt ?? 0)
        nextRefreshAt = Number(weather.nextRefreshAt ?? 0)
        ready = true
    }

    function refresh() {
        DataClient.request("weather.refresh", {}, function(response) {
            if (!response.ok)
                errorMessage = String(response.error?.message ?? I18n.tr("Weather refresh failed"))
        })
    }

    property Connections dataEvents: Connections {
        target: DataClient
        function onEventReceived(eventName, payload) {
            if (eventName === "weather.changed")
                service.reload()
        }
        function onTransportChanged(connected) {
            if (connected)
                service.reload()
        }
    }

    // weather.changed events already drive reloads; this timer is only a
    // floor for a missed event, so five minutes is plenty.
    property Timer fallbackReload: Timer {
        interval: 300000
        repeat: true
        running: DataClient.socket.connected
        triggeredOnStart: true
        onTriggered: service.reload()
    }

    property Timer freshnessClock: Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: service.clockNow = Date.now()
    }

    Component.onCompleted: reload()
}
