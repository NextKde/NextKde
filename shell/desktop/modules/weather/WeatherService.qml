pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Open-Meteo-backed current conditions for the Dock. This is deliberately a
// keyless provider: no credentials are present in QML, process arguments, or
// the persisted cache.
QtObject {
    id: service

    readonly property string cityName: "长沙"
    readonly property real latitude: 28.2282
    readonly property real longitude: 112.9388
    readonly property int refreshIntervalMs: 60 * 60 * 1000
    readonly property string cacheDir: Quickshell.stateDir + "/weather"
    readonly property string cachePath: cacheDir + "/current.json"

    property bool loading: false
    property string errorMessage: ""
    property date fetchedAt: new Date(0)
    property var current: null
    property var daily: null

    readonly property bool available: current !== null
    readonly property bool stale: available
        && (Date.now() - fetchedAt.getTime() > refreshIntervalMs * 2)
    readonly property string temperature: available
        ? Math.round(Number(current.temperature_2m)) + "°" : "--°"
    readonly property string apparentTemperature: available
        ? Math.round(Number(current.apparent_temperature)) + "°" : "--°"
    readonly property int weatherCode: available ? Number(current.weather_code) : -1
    readonly property bool isDay: available ? Number(current.is_day) === 1 : true
    readonly property string humidity: available
        ? Math.round(Number(current.relative_humidity_2m)) + "%" : "--"
    readonly property string windSpeed: available
        ? Math.round(Number(current.wind_speed_10m)) + " km/h" : "--"
    readonly property string windDirection: available
        ? Math.round(Number(current.wind_direction_10m)) + "°" : "--"
    readonly property string sunriseTime: dailyTime("sunrise")
    readonly property string sunsetTime: dailyTime("sunset")
    readonly property var forecastDays: {
        if (!daily || !daily.time || !daily.weather_code
                || !daily.temperature_2m_max || !daily.temperature_2m_min)
            return []
        const days = []
        const count = Math.min(7, daily.time.length)
        for (let index = 0; index < count; index++) {
            days.push({
                date: daily.time[index],
                code: Number(daily.weather_code[index]),
                high: Math.round(Number(daily.temperature_2m_max[index])),
                low: Math.round(Number(daily.temperature_2m_min[index]))
            })
        }
        return days
    }

    function dailyTime(field) {
        const values = service.daily?.[field]
        if (!values || values.length === 0)
            return "--:--"
        // With timezone=auto Open-Meteo returns local ISO values such as
        // 2026-08-24T06:03. Keep the local clock portion without reparsing it
        // through JavaScript's system timezone.
        const match = String(values[0]).match(/T(\d{2}:\d{2})/)
        return match ? match[1] : "--:--"
    }

    function conditionText(code) {
        if (code === 0) return "晴"
        if (code === 1) return "大部晴朗"
        if (code === 2) return "局部多云"
        if (code === 3) return "阴"
        if (code === 45 || code === 48) return "雾"
        if (code >= 51 && code <= 57) return "毛毛雨"
        if (code >= 61 && code <= 67) return "雨"
        if (code >= 71 && code <= 77) return "雪"
        if (code >= 80 && code <= 82) return "阵雨"
        if (code >= 85 && code <= 86) return "阵雪"
        if (code >= 95) return "雷暴"
        return "天气未知"
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
            return "今天"
        if (index === 1)
            return "明天"
        const weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return weekdays[new Date(isoDate + "T12:00:00").getDay()]
    }

    function refresh() {
        if (loading)
            return
        loading = true
        errorMessage = ""
        const url = "https://api.open-meteo.com/v1/forecast?latitude="
            + latitude + "&longitude=" + longitude
            + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m,wind_direction_10m"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset"
            + "&timezone=auto&forecast_days=7"
        const proc = processFactory.createObject(service, {
            command: ["curl", "--compressed", "--fail", "--silent", "--show-error",
                      "--max-time", "15", url]
        })
        proc.exited.connect(function(code) {
            const output = proc.stdout?.text ?? ""
            const stderr = proc.stderr?.text ?? ""
            loading = false
            if (code === 0) {
                try {
                    const payload = JSON.parse(output)
                    if (!payload.current)
                        throw new Error("响应缺少 current")
                    current = payload.current
                    daily = payload.daily ?? null
                    fetchedAt = new Date()
                    saveCache()
                } catch (e) {
                    errorMessage = "天气数据格式无效"
                    console.warn("[Weather] parse failed: " + e)
                }
            } else {
                errorMessage = "天气更新失败"
                console.warn("[Weather] request failed code=" + code + " stderr=" + stderr)
            }
            proc.destroy()
        })
        proc.running = true
    }

    function saveCache() {
        const json = JSON.stringify({ fetchedAt: fetchedAt.toISOString(), current: current, daily: daily })
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c",
                      "mkdir -p \"$1\" && printf %s \"$2\" > \"$1/current.json.tmp\" && mv \"$1/current.json.tmp\" \"$1/current.json\"",
                      "weather-cache-save", cacheDir, json]
        })
        proc.exited.connect(function() { proc.destroy() })
        proc.running = true
    }

    function loadCache() {
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c", "cat \"$1\"", "weather-cache-load", cachePath]
        })
        proc.exited.connect(function(code) {
            if (code === 0) {
                try {
                    const cached = JSON.parse(proc.stdout?.text ?? "")
                    if (cached.current && cached.fetchedAt) {
                        current = cached.current
                        daily = cached.daily ?? null
                        fetchedAt = new Date(cached.fetchedAt)
                    }
                } catch (e) {
                    console.warn("[Weather] cache parse failed: " + e)
                }
            }
            proc.destroy()
            refresh()
        })
        proc.running = true
    }

    property Component processFactory: Component {
        Process {
            stdout: StdioCollector {}
            stderr: StdioCollector {}
        }
    }

    property Timer refreshTimer: Timer {
        interval: service.refreshIntervalMs
        running: true
        repeat: true
        onTriggered: service.refresh()
    }

    Component.onCompleted: loadCache()
}
