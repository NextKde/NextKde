pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Kos.Ui

KosApplicationWindow {
    id: root

    modernDesign: true
    visible: true
    title: qsTr("Weather")

    readonly property string temperatureUnit: backend.units === "imperial" ? "°F" : "°C"
    readonly property string speedUnit: backend.units === "imperial" ? qsTr("mph") : qsTr("km/h")
    readonly property string distanceUnit: backend.units === "imperial" ? qsTr("mi") : qsTr("km")
    readonly property var upcomingHours: upcomingForecast()
    property string pendingLocationId: ""
    readonly property int currentWeatherCode: number(backend.current, "weatherCode", -1)
    readonly property bool currentIsDay: Boolean(value(backend.current, "isDay", true))
    readonly property var skyStops: skyStopsFor(
        root.currentWeatherCode,
        root.currentIsDay)
    readonly property color skyText: "#ffffff"
    readonly property color skyTextMuted: Qt.rgba(1, 1, 1, 0.66)

    // ref-main 白天场景所有内容卡填充暗于周围天空（Pillow 实测：指标卡 (38.5,115.8,196.9)
    // vs 卡间天空 (54.7,124.3,197.0)；AQ 卡 (9.5,93.7,179.0) vs 缝隙 (38.3,101.7,175.9)），
    // 可拟合为 α~0.30 的深蓝玻璃 (0,96,210)。夜景无参考：维持白玻璃族不变。
    readonly property color cardGlassRgb: root.currentIsDay ? Qt.rgba(0, 0.376, 0.824, 1.0) : Qt.rgba(1, 1, 1, 1.0)
    readonly property real cardGlassAlpha: root.currentIsDay ? 0.30 : 0.16
    readonly property real cardGlassAlphaHot: root.currentIsDay ? 0.36 : 0.21
    readonly property int tileRadius: 16 // ref-main UV 瓦角部拟合 r≈10.5@814 × 1.46 窗比 ≈ 15.3，LEDGER WIND 瓦 r≈11±1 同证；AppTheme.smallRadius(12) 是 shared 基础件不动，weather 内显式覆盖

    // Liquid Glass circular button background (stage 3, style A) for the
    // sky top bar. `selected` shows the tinted glass disc, unselected stays
    // transparent until hover; `subtle` is the always-on action-button glass
    // (same family as KosSidebarToggle: fill white@0.14 + border white@0.22).
    component GlassCircleBg: Rectangle {
        property bool selected: false
        property bool pressed: false
        property bool hovered: false
        property bool subtle: false
        readonly property bool filled: selected || pressed || hovered || subtle
        radius: width / 2
        color: subtle ? Qt.rgba(1, 1, 1, 0.14)
            : (selected ? Qt.rgba(1, 1, 1, 0.27)
               : ((hovered || pressed) ? Qt.rgba(1, 1, 1, 0.14) : "transparent"))
        border.width: filled ? 1 : 0
        border.color: subtle ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.30)
        Rectangle {
            // specular top sheen, clipped to the circle
            visible: parent.filled
            anchors.fill: parent
            anchors.margins: 1
            radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.28) }
                GradientStop { position: 0.22; color: Qt.rgba(1, 1, 1, 0) }
            }
        }
    }
    readonly property bool nightClearSky:
        !Boolean(value(backend.current, "isDay", true))
        && (root.currentWeatherCode === 0 || root.currentWeatherCode === 1)
    readonly property bool dayClearSky:
        root.currentIsDay
        && (root.currentWeatherCode === 0 || root.currentWeatherCode === 1)
    readonly property bool rainySky: {
        const c = root.currentWeatherCode
        return (c >= 51 && c <= 67) || (c >= 80 && c <= 82) || c >= 95
    }
    readonly property bool snowySky: {
        const c = root.currentWeatherCode
        return (c >= 71 && c <= 77) || c === 85 || c === 86
    }
    readonly property bool cloudySky: {
        const c = root.currentWeatherCode
        return c === 2 || c === 3 || c === 45 || c === 48
    }
    readonly property bool thunderSky: root.currentWeatherCode >= 95
    readonly property var dailyRange: {
        let lo = Number.POSITIVE_INFINITY
        let hi = Number.NEGATIVE_INFINITY
        const rows = backend.daily ?? []
        for (let index = 0; index < rows.length; index++) {
            lo = Math.min(lo, number(rows[index], "temperatureMinimum", 0))
            hi = Math.max(hi, number(rows[index], "temperatureMaximum", 0))
        }
        return hi > lo ? { minimum: lo, maximum: hi } : { minimum: 0, maximum: 1 }
    }

    function clamp(value, minimum, maximum) {
        return Math.min(Math.max(value, minimum), maximum)
    }

    function mulberry32(seed) {
        let state = seed >>> 0
        return function() {
            state = (state + 0x6D2B79F5) >>> 0
            let t = state
            t = Math.imul(t ^ (t >>> 15), t | 1)
            t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
            return ((t ^ (t >>> 14)) >>> 0) / 4294967296
        }
    }

    // Star positions come from a fixed-seed PRNG so the layout is identical
    // on every launch; the twinkle phase (below) intentionally uses
    // Math.random() so each run animates from a different point.
    readonly property var starField: {
        const random = mulberry32(20261016)
        const stars = []
        for (let index = 0; index < 48; index++) {
            stars.push({
                xRatio: random(),
                yRatio: Math.pow(random(), 1.3) * 0.75,
                diameter: 1.2 + random() * 1.6,
                baseOpacity: 0.35 + random() * 0.6,
                twinkleMs: 2400 + random() * 4800
            })
        }
        return stars
    }

    // Rain streaks: fixed-seed PRNG like the stars so the layout is
    // identical on every launch; phase offsets stagger the fall start.
    readonly property var rainField: {
        const random = mulberry32(20261017)
        const drops = []
        for (let index = 0; index < 64; index++) {
            drops.push({
                xRatio: random(),
                length: 10 + random() * 10,
                opacity: 0.20 + random() * 0.28,
                fallMs: 1500 + random() * 800,
                phaseMs: random() * 2300
            })
        }
        return drops
    }

    // Snowflakes: fixed-seed PRNG like the stars/rain so the layout is
    // identical on every launch; slow drift + sideways sway (HIG ambient
    // loop 2-12s: one flake crossing the screen takes 6-11s).
    readonly property var snowField: {
        const random = mulberry32(20261018)
        const flakes = []
        for (let index = 0; index < 56; index++) {
            flakes.push({
                xRatio: random(),
                diameter: 2.0 + random() * 3.0,
                opacity: 0.35 + random() * 0.45,
                fallMs: 6000 + random() * 5000,
                swayAmp: 8 + random() * 14,
                swayMs: 2000 + random() * 2000,
                phaseMs: random() * 11000,
                swayPhaseMs: random() * 4000
            })
        }
        return flakes
    }

    // Cloud puffs: fixed-seed PRNG so the layout is identical on every
    // launch; each cloud drifts across the full screen (HIG ambient loop
    // 2-12s: one crossing takes 8-12s).
    readonly property var cloudField: {
        const random = mulberry32(20261019)
        const clouds = []
        for (let index = 0; index < 7; index++) {
            const cloudWidth = 160 + random() * 180
            const driftMs = 8000 + random() * 4000
            const puffs = []
            for (let puff = 0; puff < 4; puff++) {
                puffs.push({
                    cxRatio: 0.15 + random() * 0.7,
                    cyRatio: 0.35 + random() * 0.35,
                    rRatio: 0.28 + random() * 0.22,
                    alphaMul: 0.6 + random() * 0.4
                })
            }
            puffs.sort(function(a, b) { return a.cxRatio - b.cxRatio })
            clouds.push({
                xRatio: random(),
                yRatio: random() * 0.55,
                cloudWidth: cloudWidth,
                cloudHeight: cloudWidth * 0.38,
                opacity: 0.10 + random() * 0.14,
                driftMs: driftMs,
                phaseMs: random() * driftMs,
                puffs: puffs
            })
        }
        return clouds
    }

    // Static high cloud band for the clear day sky: a fixed-seed PRNG lays
    // out 5 soft white cloud banks hugging the top of the window (the Apple
    // Weather clear-day reference keeps clouds in the upper ~40% and fades
    // them out toward the horizon). Purely decorative, never animated.
    readonly property var clearSkyClouds: {
        const random = mulberry32(20261020)
        const clouds = []
        for (let index = 0; index < 5; index++) {
            const cloudWidth = 300 + random() * 160
            const puffs = []
            for (let puff = 0; puff < 4; puff++) {
                puffs.push({
                    cxRatio: 0.1 + random() * 0.8,
                    cyRatio: 0.3 + random() * 0.4,
                    rRatio: 0.28 + random() * 0.22,
                    alphaMul: 0.6 + random() * 0.4
                })
            }
            puffs.sort(function(a, b) { return a.cxRatio - b.cxRatio })
            clouds.push({
                xRatio: random(),
                yRatio: index * 0.085 + random() * 0.04,
                cloudWidth: cloudWidth,
                cloudHeight: cloudWidth * 0.3,
                opacity: 0.40 - index * 0.075 + random() * 0.05,
                puffs: puffs
            })
        }
        return clouds
    }

    // Static faint cloud band for the clear night sky, added per user ruling
    // 2026-10-18. No night reference image exists (refs are day-only), so
    // geometry/opacity is a programmatic approximation: 4 flatter wisps
    // (height = width * 0.24) at much lower opacity than the day band, since
    // the night sky is dark and the clouds must stay subtle. Purely
    // decorative, static texture, never animated (reduce-motion safe by
    // construction, no frame-diff obligation).
    readonly property var nightClearClouds: {
        const random = mulberry32(20261021)
        const clouds = []
        for (let index = 0; index < 4; index++) {
            const cloudWidth = 340 + random() * 180
            const puffs = []
            for (let puff = 0; puff < 5; puff++) {
                puffs.push({
                    cxRatio: 0.1 + random() * 0.8,
                    cyRatio: 0.3 + random() * 0.4,
                    rRatio: 0.28 + random() * 0.22,
                    alphaMul: 0.6 + random() * 0.4
                })
            }
            puffs.sort(function(a, b) { return a.cxRatio - b.cxRatio })
            clouds.push({
                xRatio: random(),
                yRatio: index * 0.085 + random() * 0.04,
                cloudWidth: cloudWidth,
                cloudHeight: cloudWidth * 0.24,
                opacity: 0.16 - index * 0.035 + random() * 0.02,
                puffs: puffs
            })
        }
        return clouds
    }

    // Static per-card cloud texture for sidebar city cards: the reference
    // sidebar (tile-sidebar) shows every city card carrying weather-
    // appropriate sky texture (white puffs on day cards, faint wisps on the
    // night card). Fixed-seed PRNG per card index so each card differs but
    // stays identical across launches. Purely decorative, never animated.
    // Shown on every card: the reference shows sky texture on all five
    // visible cards (day and night alike); the clear-day card form is an
    // extrapolation from the main-window clear-day band precedent.
    function sidebarCardClouds(cardIndex, isDay) {
        const random = mulberry32(20261022 + cardIndex * 97)
        const clouds = []
        for (let i = 0; i < 3; i++) {
            const cloudWidth = 70 + random() * 60
            const puffs = []
            for (let puff = 0; puff < 4; puff++) {
                puffs.push({
                    cxRatio: 0.1 + random() * 0.8,
                    cyRatio: 0.3 + random() * 0.4,
                    rRatio: 0.28 + random() * 0.22,
                    alphaMul: 0.6 + random() * 0.4
                })
            }
            puffs.sort(function(a, b) { return a.cxRatio - b.cxRatio })
            clouds.push({
                xRatio: random(),
                yRatio: i * 0.28 + random() * 0.18,
                cloudWidth: cloudWidth,
                cloudHeight: cloudWidth * 0.3,
                opacity: (isDay ? 0.32 : 0.13) - i * 0.07 + random() * 0.03,
                puffs: puffs
            })
        }
        return clouds
    }

    function skyStopsFor(code, isDay) {
        const c = Number(code)
        if (!isDay) {
            if (c >= 95) return ["#141a2c", "#1d2740", "#33415f"]
            if (c === 0 || c === 1) return ["#0c1a33", "#12294d", "#274d79"]
            if (c === 2) return ["#101f38", "#1a3355", "#31507a"]
            return ["#0f1826", "#1b2637", "#2e3c52"]
        }
        if (c >= 95) return ["#2a3752", "#3c4c6e", "#5a6b8c"]
        if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82))
            return ["#3d5a7d", "#2a4a70", "#5f83a8"]
        if ((c >= 71 && c <= 77) || c === 85 || c === 86)
            return ["#7b90a6", "#5d7690", "#a9bccd"]
        if (c === 3 || c === 45 || c === 48) return ["#6a7b90", "#4a5d75", "#8ba0b5"]
        return ["#4a74ab", "#1469bc", "#5a90c9"]   // clear / mainly clear / partly cloudy day
    }

    function tempColor(temperature) {
        const u = clamp((temperature - dailyRange.minimum)
                        / (dailyRange.maximum - dailyRange.minimum), 0, 1)
        const cold = Qt.rgba(0.353, 0.784, 0.980, 1)   // #5ac8fa
        const mid  = Qt.rgba(1, 0.839, 0.039, 1)       // #ffd60a
        const hot  = Qt.rgba(1, 0.624, 0.039, 1)       // #ff9f0a
        const first = u < 0.5
        const amount = first ? u * 2 : (u - 0.5) * 2
        const a = first ? cold : mid
        const b = first ? mid : hot
        return Qt.rgba(a.r + (b.r - a.r) * amount, a.g + (b.g - a.g) * amount,
                       a.b + (b.b - a.b) * amount, 1)
    }

    function activationOption(activationArgs, name) {
        const prefix = name + "="
        for (let index = 0; index < activationArgs.length; index++) {
            const argument = String(activationArgs[index])
            if (argument === name && index + 1 < activationArgs.length)
                return String(activationArgs[index + 1])
            if (argument.startsWith(prefix))
                return argument.slice(prefix.length)
        }
        return ""
    }

    function selectPendingLocation() {
        if (!pendingLocationId)
            return
        const source = backend.locations ?? []
        for (let index = 0; index < source.length; index++) {
            if (String(value(source[index], "id", "")) === pendingLocationId) {
                backend.selectLocation(source[index])
                pendingLocationId = ""
                return
            }
        }
    }

    function handleActivation(activationArgs, workingDirectory) {
        pendingLocationId = activationOption(activationArgs, "--location")
        selectPendingLocation()
    }

    function value(record, key, fallback) {
        if (record === null || record === undefined)
            return fallback
        const result = record[key]
        return result === null || result === undefined ? fallback : result
    }

    function number(record, key, fallback) {
        const result = Number(value(record, key, fallback))
        return Number.isFinite(result) ? result : fallback
    }

    function locationName(location) {
        return String(value(location, "name", qsTr("Unknown location")))
    }

    function locationDetail(location) {
        const region = String(value(location, "admin1", ""))
        const country = String(value(location, "country", ""))
        if (region.length > 0 && country.length > 0 && region !== country)
            return region + ", " + country
        return region.length > 0 ? region : country
    }

    function conditionText(code) {
        const weatherCode = Number(code)
        if (weatherCode === 0) return qsTr("Clear sky")
        if (weatherCode === 1) return qsTr("Mainly clear")
        if (weatherCode === 2) return qsTr("Partly cloudy")
        if (weatherCode === 3) return qsTr("Overcast")
        if (weatherCode === 45 || weatherCode === 48) return qsTr("Fog")
        if (weatherCode >= 51 && weatherCode <= 57) return qsTr("Drizzle")
        if (weatherCode >= 61 && weatherCode <= 67) return qsTr("Rain")
        if (weatherCode >= 71 && weatherCode <= 77) return qsTr("Snow")
        if (weatherCode >= 80 && weatherCode <= 82) return qsTr("Rain showers")
        if (weatherCode >= 85 && weatherCode <= 86) return qsTr("Snow showers")
        if (weatherCode >= 95) return qsTr("Thunderstorm")
        return qsTr("Unknown conditions")
    }

    function localTime(isoTime) {
        const match = String(isoTime ?? "").match(/T(\d{2}:\d{2})/)
        return match ? match[1] : "--:--"
    }

    function cardTimeText(isoTime) {
        try {
            const parsed = new Date(String(isoTime))
            if (!Number.isNaN(parsed.getTime()))
                return Qt.formatTime(parsed, "h:mmAP")
        } catch (error) {
        }
        return String(isoTime ?? "").slice(11, 16)
    }

    function dayLabel(isoDate, index) {
        if (index === 0)
            return qsTr("Today")
        if (index === 1)
            return qsTr("Tomorrow")
        const parsed = new Date(String(isoDate) + "T12:00:00")
        return Number.isNaN(parsed.getTime())
            ? String(isoDate) : AppTheme.formatDate(parsed, "dddd")
    }

    function upcomingForecast() {
        const result = []
        const points = backend.hourly ?? []
        const currentTime = String(value(backend.current, "time", ""))
        let start = 0
        if (currentTime.length > 0) {
            while (start < points.length
                   && String(value(points[start], "time", "")) < currentTime)
                start++
        }
        for (let index = start; index < Math.min(points.length, start + 10); index++)
            result.push(points[index])
        return result
    }

    component WeatherMetric: Rectangle {
        id: metric

        required property string symbol
        required property string labelText
        required property string valueText

        implicitHeight: 66
        radius: root.tileRadius
        // 昼夜分材质：ref-main 白天所有卡填充暗于周围天空，拟合为 α~0.30 深蓝玻璃 (0,96,210)；夜间维持白玻璃
        property bool hot: metricHover.hovered
        // unified with full-width cards (AQ/10-day): fill 0.16 + stroke 0.22; ref-main shows one shared card material
        property real hoverFill: hot ? root.cardGlassAlphaHot : root.cardGlassAlpha
        Behavior on hoverFill { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
        property real hoverStroke: hot ? 0.32 : 0.22
        Behavior on hoverStroke { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
        color: Qt.rgba(root.cardGlassRgb.r, root.cardGlassRgb.g, root.cardGlassRgb.b, hoverFill)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, hoverStroke)
        transform: Translate {
            y: AppTheme.reduceMotion ? 0 : (metric.hot ? -3 : 0)
            Behavior on y { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
        }
        Accessible.role: Accessible.StaticText
        Accessible.name: metric.labelText + ": " + metric.valueText

        HoverHandler { id: metricHover }
        ToolTip.visible: metricHover.hovered
        ToolTip.text: metric.labelText

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 9

            // ref-main SUNSET/UV 卡 glyph 直接放卡面上无盒子（4x 实测），白方块底系旧发明，TASK 阶段三 A 禁"半透明白方块"
            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                Label {
                    anchors.centerIn: parent
                    text: metric.symbol
                    color: root.skyTextMuted
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                    Accessible.ignored: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Label {
                    Layout.fillWidth: true
                    // 参考设计头部为全大写+字距（同 :1458 AQ 卡头）
                    text: metric.labelText.toLocaleUpperCase(Qt.locale())
                    color: root.skyTextMuted
                    font.pixelSize: 10
                    font.letterSpacing: 1.4
                    elide: Text.ElideRight
                    Accessible.ignored: true
                }

                Label {
                    Layout.fillWidth: true
                    text: metric.valueText
                    color: root.skyText
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Accessible.ignored: true
                }
            }
        }
    }

    WeatherClient {
        id: backend
        onSnapshotChanged: root.selectPendingLocation()
    }

    Timer {
        id: searchDebounce
        interval: 450
        onTriggered: backend.searchLocations(locationField.text)
    }

    KosSettingsDialog {
        id: settingsDialog
        settings: root.applicationSettings
        applicationName: qsTr("Weather")
    }

    Shortcut {
        sequences: [StandardKey.Refresh]
        onActivated: backend.refresh()
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.skyStops[0] }
            GradientStop { position: 0.45; color: root.skyStops[1] }
            GradientStop { position: 1.0; color: root.skyStops[2] }
        }
    }

    // Static procedural cirrus band for the clear day sky (see
    // clearSkyClouds). Painted once per canvas resize, never animated.
    // Clouds are kept to the right of the (opaque) sidebar so none of the
    // band is wasted behind it.
    Item {
        id: clearSkyCloudLayer
        anchors.fill: parent
        visible: root.dayClearSky
        clip: true
        readonly property real cloudLeft:
            root.compact ? AppTheme.compactSidebarWidth : AppTheme.sidebarWidth

        Repeater {
            model: root.clearSkyClouds

            delegate: Item {
                id: clearSkyCloud
                required property var modelData

                x: clearSkyCloudLayer.cloudLeft
                   + (clearSkyCloudLayer.width - clearSkyCloudLayer.cloudLeft - width)
                     * modelData.xRatio
                y: (clearSkyCloudLayer.height - height) * modelData.yRatio
                width: modelData.cloudWidth
                height: modelData.cloudHeight
                opacity: modelData.opacity
                Accessible.ignored: true

                Canvas {
                    anchors.fill: parent
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        for (let i = 0; i < modelData.puffs.length; i++) {
                            const p = modelData.puffs[i]
                            const cx = p.cxRatio * width
                            const cy = p.cyRatio * height
                            // Keep the gradient inside the canvas: alpha must
                            // reach 0 before any clipped edge, otherwise puffs
                            // show hard rectangular borders.
                            const r = Math.max(Math.min(p.rRatio * height * 1.2,
                                                        cy, height - cy,
                                                        cx, width - cx), 8)
                            const grad = ctx.createRadialGradient(cx, cy, 0, cx, cy, r)
                            grad.addColorStop(0, "rgba(255,255,255," + p.alphaMul.toFixed(3) + ")")
                            grad.addColorStop(1, "rgba(255,255,255,0)")
                            ctx.fillStyle = grad
                            ctx.beginPath()
                            ctx.arc(cx, cy, r, 0, Math.PI * 2)
                            ctx.fill()
                        }
                    }
                }
            }
        }
    }

    Item {
        id: sunGlowLayer
        anchors.fill: parent
        visible: root.dayClearSky
        clip: true
        opacity: 0.17

        Canvas {
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const cx = width * 0.65
                const cy = height * 0.14
                const r = Math.max(width * 0.55, height * 0.8)
                const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r)
                g.addColorStop(0, "rgba(255, 240, 200, 0.85)")
                g.addColorStop(0.4, "rgba(255, 240, 200, 0.35)")
                g.addColorStop(1, "rgba(255, 240, 200, 0)")
                ctx.fillStyle = g
                ctx.fillRect(0, 0, width, height)
            }
        }

        SequentialAnimation on opacity {
            running: root.dayClearSky && !AppTheme.reduceMotion
            loops: Animation.Infinite
            NumberAnimation { from: 0.10; to: 0.24; duration: 3500; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.24; to: 0.10; duration: 3500; easing.type: Easing.InOutSine }
        }
    }

    Item {
        id: starFieldLayer
        anchors.fill: parent
        visible: root.nightClearSky
        clip: true

        Repeater {
            model: root.starField

            delegate: Rectangle {
                required property var modelData

                x: (starFieldLayer.width - width) * modelData.xRatio
                y: (starFieldLayer.height - height) * modelData.yRatio
                width: modelData.diameter
                height: width
                radius: width / 2
                color: "white"
                opacity: modelData.baseOpacity
                Accessible.ignored: true

                SequentialAnimation on opacity {
                    running: root.nightClearSky && !AppTheme.reduceMotion
                    loops: Animation.Infinite

                    PauseAnimation {
                        duration: Math.random() * modelData.twinkleMs
                    }
                    NumberAnimation {
                        from: modelData.baseOpacity
                        to: modelData.baseOpacity * 0.35
                        duration: modelData.twinkleMs / 2
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        from: modelData.baseOpacity * 0.35
                        to: modelData.baseOpacity
                        duration: modelData.twinkleMs / 2
                        easing.type: Easing.InOutSine
                    }
                }
            }
        }
    }

    // Static procedural faint cloud band for the clear night sky (see
    // nightClearClouds), added per user ruling 2026-10-18. No night reference
    // image exists (refs are day-only), so geometry/opacity is a programmatic
    // approximation. Deliberately placed after starFieldLayer so the clouds
    // occlude the twinkling stars (real-world ordering). Static texture,
    // never animated (reduce-motion safe by construction, no frame-diff
    // obligation).
    Item {
        id: nightClearCloudLayer
        anchors.fill: parent
        visible: root.nightClearSky
        clip: true
        readonly property real cloudLeft:
            root.compact ? AppTheme.compactSidebarWidth : AppTheme.sidebarWidth

        Repeater {
            model: root.nightClearClouds

            delegate: Item {
                id: nightClearCloud
                required property var modelData

                x: nightClearCloudLayer.cloudLeft
                   + (nightClearCloudLayer.width - nightClearCloudLayer.cloudLeft - width)
                     * modelData.xRatio
                y: (nightClearCloudLayer.height - height) * modelData.yRatio
                width: modelData.cloudWidth
                height: modelData.cloudHeight
                opacity: modelData.opacity
                Accessible.ignored: true

                Canvas {
                    anchors.fill: parent
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        for (let i = 0; i < modelData.puffs.length; i++) {
                            const p = modelData.puffs[i]
                            const cx = p.cxRatio * width
                            const cy = p.cyRatio * height
                            // Keep the gradient inside the canvas: alpha must
                            // reach 0 before any clipped edge, otherwise puffs
                            // show hard rectangular borders.
                            const r = Math.max(Math.min(p.rRatio * height * 1.2,
                                                        cy, height - cy,
                                                        cx, width - cx), 8)
                            const grad = ctx.createRadialGradient(cx, cy, 0, cx, cy, r)
                            grad.addColorStop(0, "rgba(255,255,255," + p.alphaMul.toFixed(3) + ")")
                            grad.addColorStop(1, "rgba(255,255,255,0)")
                            ctx.fillStyle = grad
                            ctx.beginPath()
                            ctx.arc(cx, cy, r, 0, Math.PI * 2)
                            ctx.fill()
                        }
                    }
                }
            }
        }
    }

    Item {
        id: rainFieldLayer
        anchors.fill: parent
        visible: root.rainySky
        clip: true

        Repeater {
            model: root.rainField

            delegate: Rectangle {
                required property var modelData

                x: rainFieldLayer.width * modelData.xRatio
                y: -modelData.length - 10
                width: 1.4
                height: modelData.length
                color: "#dbe9ff"
                opacity: modelData.opacity
                Accessible.ignored: true

                SequentialAnimation on y {
                    running: root.rainySky && !AppTheme.reduceMotion
                    loops: Animation.Infinite

                    PauseAnimation {
                        duration: modelData.phaseMs
                    }
                    NumberAnimation {
                        from: -modelData.length - 10
                        to: rainFieldLayer.height + 10
                        duration: modelData.fallMs
                        easing.type: Easing.Linear
                    }
                }
            }
        }
    }

    Item {
        id: snowFieldLayer
        anchors.fill: parent
        visible: root.snowySky
        clip: true

        Repeater {
            model: root.snowField

            delegate: Rectangle {
                id: flake
                required property var modelData
                readonly property real xBase: snowFieldLayer.width * modelData.xRatio

                x: xBase
                y: -modelData.diameter - 10
                width: modelData.diameter
                height: width
                radius: width / 2
                color: "#ffffff"
                opacity: modelData.opacity
                Accessible.ignored: true

                SequentialAnimation on y {
                    running: root.snowySky && !AppTheme.reduceMotion
                    loops: Animation.Infinite

                    PauseAnimation {
                        duration: modelData.phaseMs
                    }
                    NumberAnimation {
                        from: -modelData.diameter - 10
                        to: snowFieldLayer.height + 10
                        duration: modelData.fallMs
                        easing.type: Easing.Linear
                    }
                }
                SequentialAnimation on x {
                    running: root.snowySky && !AppTheme.reduceMotion
                    loops: Animation.Infinite

                    PauseAnimation {
                        duration: modelData.swayPhaseMs
                    }
                    NumberAnimation {
                        from: flake.xBase - modelData.swayAmp
                        to: flake.xBase + modelData.swayAmp
                        duration: modelData.swayMs
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        from: flake.xBase + modelData.swayAmp
                        to: flake.xBase - modelData.swayAmp
                        duration: modelData.swayMs
                        easing.type: Easing.InOutSine
                    }
                }
            }
        }
    }

    Item {
        id: cloudFieldLayer
        anchors.fill: parent
        visible: root.cloudySky
        clip: true

        Repeater {
            model: root.cloudField

            delegate: Item {
                id: cloud
                required property var modelData
                readonly property real cloudW: Math.min(modelData.cloudWidth, cloudFieldLayer.width * 0.45)

                // Clouds start spread across the window per the seeded xRatio so the
                // sky is populated on the very first frame; reduce-motion leaves them
                // parked there as static content instead of an empty sky.
                property real entryX: modelData.xRatio * Math.max(cloudFieldLayer.width - cloudW, 0)
                x: cloud.entryX
                y: (cloudFieldLayer.height - height) * modelData.yRatio
                width: cloudW
                height: cloudW * 0.38
                opacity: modelData.opacity
                Accessible.ignored: true

                Canvas {
                    anchors.fill: parent
                    onWidthChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        for (let i = 0; i < modelData.puffs.length; i++) {
                            const p = modelData.puffs[i]
                            const cx = p.cxRatio * width
                            const cy = p.cyRatio * height
                            // Keep the gradient inside the canvas: alpha must
                            // reach 0 before any clipped edge, otherwise puffs
                            // show hard rectangular borders.
                            const r = Math.max(Math.min(p.rRatio * height * 1.2,
                                                        cy, height - cy,
                                                        cx, width - cx), 8)
                            const grad = ctx.createRadialGradient(cx, cy, 0, cx, cy, r)
                            grad.addColorStop(0, "rgba(255,255,255," + p.alphaMul.toFixed(3) + ")")
                            grad.addColorStop(1, "rgba(255,255,255,0)")
                            ctx.fillStyle = grad
                            ctx.beginPath()
                            ctx.arc(cx, cy, r, 0, Math.PI * 2)
                            ctx.fill()
                        }
                    }
                }

                SequentialAnimation on x {
                    running: root.cloudySky && !AppTheme.reduceMotion
                    loops: Animation.Infinite

                    // First pass runs from the seeded on-screen position; every later
                    // pass re-enters from the left edge after the staggered pause.
                    NumberAnimation {
                        from: cloud.entryX
                        to: cloudFieldLayer.width + 20
                        duration: modelData.driftMs
                        easing.type: Easing.Linear
                    }
                    ScriptAction { script: cloud.entryX = -cloud.cloudW - 20 }
                    PauseAnimation { duration: modelData.phaseMs }
                }
            }
        }
    }

    // Stage 3 motion B.1: thunderstorm lightning flash (weather codes >= 95).
    // A rare, brief double-strobe white wash over the whole window, in the
    // spirit of the Apple Weather instantaneous flash. Randomized idle pause
    // keeps the ambient cadence inside the HIG 2-12s loop range.
    Rectangle {
        id: flashLayer
        anchors.fill: parent
        visible: root.thunderSky
        color: "#ffffff"
        opacity: 0
        Accessible.ignored: true

        Timer {
            id: flashTimer
            interval: 4200
            repeat: true
            running: root.thunderSky && !AppTheme.reduceMotion
            onTriggered: {
                flashTimer.interval = 3500 + Math.random() * 5000
                flashSeq.restart()
            }
        }
        SequentialAnimation {
            id: flashSeq
            NumberAnimation { target: flashLayer; property: "opacity"; to: 0.32; duration: 70 }
            NumberAnimation { target: flashLayer; property: "opacity"; to: 0; duration: 90 }
            PauseAnimation { duration: 110 }
            NumberAnimation { target: flashLayer; property: "opacity"; to: 0.20; duration: 60 }
            NumberAnimation { target: flashLayer; property: "opacity"; to: 0; duration: 140 }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 0
        spacing: 8

        KosSidebar {
            id: sidebar
            objectName: "applicationSidebar"
            expanded: root.sidebarExpanded
            expandedWidth: root.compact ? AppTheme.compactSidebarWidth : AppTheme.sidebarWidth
            floating: false

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 10

                Item {
                    Layout.topMargin: 36
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredHeight: 30

                    KosTextField {
                        id: locationField
                        anchors.fill: parent
                        leftPadding: 34
                        cornerRadius: 15
                        // 阶段三功能层 Liquid Glass：specular 高光与细描边。
                        // 按参考图量得高光强度温和，用 liquidStrength 0.2 缩放。
                        // 实测：ref-main 搜索胶囊填充 vs 侧栏底 Δ(+24,+29,+38)≈白@0.13-0.15，
                        // 我方 0.22 时 Δ(+38,+36,+32) 对比 1.5 倍偏强；并与功能层
                        // 同层玻璃（⚙/↻ 盘、分段胶囊 白@0.14）统一。
                        materialForm: false
                        liquidFinish: true
                        liquidStrength: 0.2
                        glassColor: Qt.rgba(1, 1, 1, 0.15)
                        outlineColor: Qt.rgba(1, 1, 1, 0.30)
                        textColor: "#ffffff"
                        mutedTextColor: Qt.rgba(1, 1, 1, 0.66)
                        placeholderText: qsTr("Search")
                        Accessible.name: qsTr("Location search")
                        onAccepted: backend.searchLocations(text)
                        onTextChanged: {
                            if (text.trim().length >= 2)
                                searchDebounce.restart()
                            else {
                                searchDebounce.stop()
                                backend.clearSearch()
                            }
                        }
                    }

                    // 搜索放大镜：手绘确定性渲染，替代字体 ⌕ glyph（该字形
                    // 在当前字体里 bbox 仅 6px 且贴基线，视觉过小）。
                    // 手绘放大镜（参考图搜索胶囊左侧 magnifier；两笔确定性渲染，无字体依赖）
                    Item {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 13
                        height: 13
                        Accessible.ignored: true
                        Rectangle { // 镜片圆环
                            width: 10
                            height: 10
                            radius: 5
                            color: "transparent"
                            border.color: Qt.rgba(1, 1, 1, 0.72)
                            border.width: 1.4
                        }
                        Rectangle { // 手柄，45° 朝右下
                            x: 8.4
                            y: 8.4
                            width: 1.4
                            height: 5.2
                            radius: 0.7
                            color: Qt.rgba(1, 1, 1, 0.72)
                            rotation: -45
                            transformOrigin: Item.TopLeft
                        }
                    }
                }

                BusyIndicator {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    running: backend.searching
                    visible: running
                }

                ListView {
                    id: searchResults
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitWidth: 0
                    Layout.preferredHeight: visible ? Math.min(contentHeight, 220) : 0
                    visible: backend.searchResults.length > 0
                    clip: true
                    spacing: 3
                    model: backend.searchResults

                    delegate: KosItemDelegate {
                        id: searchResult

                        required property var modelData
                        width: searchResults.width
                        implicitHeight: 52
                        Accessible.name: root.locationName(modelData)
                        onClicked: {
                            backend.selectLocation(modelData)
                            locationField.clear()
                        }

                        contentItem: Column {
                            spacing: 2

                            Label {
                                width: parent.width
                                text: root.locationName(searchResult.modelData)
                                color: AppTheme.text
                                elide: Text.ElideRight
                            }

                            Label {
                                width: parent.width
                                text: root.locationDetail(searchResult.modelData)
                                color: AppTheme.mutedText
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                    }
                    KosKineticScroll { flickable: searchResults }
                }

                Item {
                    id: savedLocationsWrapper
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitWidth: 0
                    Layout.fillHeight: true

                    ListView {
                        id: savedLocations
                        anchors.fill: parent
                        clip: true
                        spacing: 6
                        model: backend.locations

                        delegate: KosItemDelegate {
                            id: savedLocation

                            required property var modelData
                            required property int index
                            readonly property var summary: root.value(modelData, "summary", null)
                            readonly property var cardStops: root.skyStopsFor(
                                savedLocation.summary ? savedLocation.summary.weatherCode : 2,
                                savedLocation.summary ? savedLocation.summary.isDay : true)
                            readonly property var cardClouds: root.sidebarCardClouds(
                                index,
                                savedLocation.summary ? savedLocation.summary.isDay : true)
                            readonly property real summaryHigh: root.number(
                                savedLocation.summary, "tempHigh", Number.NaN)
                            readonly property real summaryLow: root.number(
                                savedLocation.summary, "tempLow", Number.NaN)

                            width: savedLocations.width
                            implicitHeight: 74
                            topPadding: 5
                            bottomPadding: 5
                            highlighted: String(root.value(modelData, "id", ""))
                                === String(root.value(backend.location, "id", ""))
                            Accessible.name: savedLocation.summary
                                ? root.locationName(modelData) + ", "
                                  + root.conditionText(savedLocation.summary.weatherCode)
                                : root.locationName(modelData)
                            onClicked: backend.selectLocation(modelData)

                            background: Rectangle {
                                radius: 12
                                // ref-main sidebar cards have no stroke (selected or not) — sampled Mumbai/Chicago/Cupertino edges
                                border.width: 0
                                gradient: Gradient {
                                    GradientStop {
                                        position: 0.0; color: savedLocation.cardStops[0]
                                    }
                                    GradientStop {
                                        position: 0.45; color: savedLocation.cardStops[1]
                                    }
                                    GradientStop {
                                        position: 1.0; color: savedLocation.cardStops[2]
                                    }
                                }
                                Item {
                                    id: cardSkyTexture
                                    anchors.fill: parent
                                    clip: true
                                    Accessible.ignored: true

                                    Repeater {
                                        model: savedLocation.cardClouds

                                        delegate: Item {
                                            required property var modelData

                                            x: (cardSkyTexture.width - width)
                                               * modelData.xRatio
                                            y: (cardSkyTexture.height - height)
                                               * modelData.yRatio
                                            width: modelData.cloudWidth
                                            height: modelData.cloudHeight
                                            opacity: modelData.opacity

                                            Canvas {
                                                anchors.fill: parent
                                                onWidthChanged: requestPaint()
                                                onHeightChanged: requestPaint()
                                                onPaint: {
                                                    const ctx = getContext("2d")
                                                    ctx.clearRect(0, 0, width, height)
                                                    for (let i = 0; i < modelData.puffs.length; i++) {
                                                        const p = modelData.puffs[i]
                                                        const cx = p.cxRatio * width
                                                        const cy = p.cyRatio * height
                                                        const r = Math.max(Math.min(
                                                            p.rRatio * height * 1.2,
                                                            cy, height - cy, cx, width - cx), 4)
                                                        const grad = ctx.createRadialGradient(cx, cy, 0, cx, cy, r)
                                                        grad.addColorStop(0, "rgba(255,255,255," + p.alphaMul.toFixed(3) + ")")
                                                        grad.addColorStop(1, "rgba(255,255,255,0)")
                                                        ctx.fillStyle = grad
                                                        ctx.beginPath()
                                                        ctx.arc(cx, cy, r, 0, Math.PI * 2)
                                                        ctx.fill()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            contentItem: Item {
                                id: cardContent

                                RowLayout {
                                    id: cardTop
                                    height: 30
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        top: parent.top
                                    }
                                    spacing: 8

                                    Label {
                                        Layout.fillWidth: true
                                        text: root.locationName(savedLocation.modelData)
                                        color: "#ffffff"
                                        font.pixelSize: 17
                                        font.weight: Font.DemiBold
                                        lineHeight: 0.85
                                        lineHeightMode: Text.ProportionalHeight
                                        elide: Text.ElideRight
                                        style: Text.Raised
                                        styleColor: Qt.rgba(0, 0, 0, 0.22)
                                    }

                                    Label {
                                        text: savedLocation.summary
                                            ? Math.round(savedLocation.summary.temperature) + "°" : "—"
                                        color: "#ffffff"
                                        font.pixelSize: 30
                                        font.weight: Font.Light
                                        lineHeight: 0.85
                                        lineHeightMode: Text.ProportionalHeight
                                        style: Text.Raised
                                        styleColor: Qt.rgba(0, 0, 0, 0.22)
                                    }
                                }

                                Label {
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        top: cardTop.bottom
                                        topMargin: 0
                                    }
                                    text: savedLocation.highlighted
                                        ? qsTr("My Location")
                                        : savedLocation.summary
                                          && String(savedLocation.summary.time ?? "").length > 0
                                        ? root.cardTimeText(savedLocation.summary.time)
                                        : root.locationDetail(savedLocation.modelData)
                                    color: Qt.rgba(1, 1, 1, 0.72)
                                    font.pixelSize: 12
                                    lineHeight: 0.85
                                    lineHeightMode: Text.ProportionalHeight
                                    elide: Text.ElideRight
                                    visible: text.length > 0 && savedLocation.summary
                                    style: Text.Raised
                                    styleColor: Qt.rgba(0, 0, 0, 0.22)
                                }

                                RowLayout {
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        bottom: parent.bottom
                                    }
                                    spacing: 8

                                    Label {
                                        Layout.fillWidth: true
                                        text: savedLocation.summary
                                            ? root.conditionText(savedLocation.summary.weatherCode)
                                            : root.locationDetail(savedLocation.modelData)
                                        color: "#ffffff"
                                        font.pixelSize: 13
                                        lineHeight: 0.85
                                        lineHeightMode: Text.ProportionalHeight
                                        elide: Text.ElideRight
                                        visible: text.length > 0
                                        style: Text.Raised
                                        styleColor: Qt.rgba(0, 0, 0, 0.22)
                                    }

                                    Label {
                                        text: "H:" + Math.round(savedLocation.summaryHigh) + "° L:"
                                              + Math.round(savedLocation.summaryLow) + "°"
                                        color: Qt.rgba(1, 1, 1, 0.85)
                                        font.pixelSize: 12
                                        lineHeight: 0.85
                                        lineHeightMode: Text.ProportionalHeight
                                        visible: Number.isFinite(savedLocation.summaryHigh)
                                            && Number.isFinite(savedLocation.summaryLow)
                                        style: Text.Raised
                                        styleColor: Qt.rgba(0, 0, 0, 0.22)
                                    }
                                }
                            }
                        }
                        KosKineticScroll { flickable: savedLocations }
                    }

                    // 阶段三功能层 Liquid Glass：滚动边缘效果（HIG Materials——内容滚到侧栏下方时模糊并降不透明度）。
                    Item {
                        id: scrollEdgeTop
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 26
                        visible: savedLocations.contentY > 0.5
                        clip: true

                        MultiEffect {
                            width: savedLocations.width
                            height: savedLocations.height
                            source: savedLocations
                            blurEnabled: true
                            blurMax: 32
                            blur: 1.0
                            saturation: 0.2
                        }

                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                GradientStop {
                                    position: 0.0
                                    color: Qt.rgba(AppTheme.sidebar.r, AppTheme.sidebar.g, AppTheme.sidebar.b, 0.9)
                                }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                        }
                    }

                    // 底边滚动边缘效果：与 scrollEdgeTop 镜像对称（HIG Materials——列表下方还有未滚入内容时模糊并降不透明度）。
                    Item {
                        id: scrollEdgeBottom
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 26
                        visible: savedLocations.contentY + savedLocations.height < savedLocations.contentHeight - 0.5
                        clip: true

                        MultiEffect {
                            width: savedLocations.width
                            height: savedLocations.height
                            source: savedLocations
                            blurEnabled: true
                            blurMax: 32
                            blur: 1.0
                            saturation: 0.2
                        }

                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop {
                                    position: 1.0
                                    color: Qt.rgba(AppTheme.sidebar.r, AppTheme.sidebar.g, AppTheme.sidebar.b, 0.9)
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Accessible.name: qsTr("Units")

                    ButtonGroup { id: unitsGroup }

                    KosToolButton {
                        id: settingsButton
                        text: "⚙"
                        font.pixelSize: 16
                        Layout.preferredWidth: 34
                        Layout.alignment: Qt.AlignVCenter
                        background: GlassCircleBg { subtle: true }
                        contentItem: Label {
                            text: settingsButton.text
                            font: settingsButton.font
                            color: settingsButton.enabled
                                ? "white" : Qt.rgba(1, 1, 1, 0.38)
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        Accessible.name: qsTr("Weather settings")
                        ToolTip.visible: hovered
                        ToolTip.text: Accessible.name
                        onClicked: settingsDialog.open()
                    }

                    KosToolButton {
                        id: refreshButton
                        text: "↻"
                        font.pixelSize: 18
                        Layout.preferredWidth: 34
                        enabled: backend.connected && !backend.loading
                        background: GlassCircleBg { subtle: true }
                        contentItem: Label {
                            id: refreshGlyph
                            text: refreshButton.text
                            font: refreshButton.font
                            color: refreshButton.enabled
                                ? "white" : Qt.rgba(1, 1, 1, 0.38)
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            RotationAnimation on rotation {
                                running: backend.loading && !AppTheme.reduceMotion
                                loops: Animation.Infinite
                                duration: 1000
                                from: 0
                                to: 360
                                onRunningChanged: if (!running) refreshGlyph.rotation = 0
                            }
                        }
                        Accessible.name: qsTr("Refresh weather forecast")
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Refresh weather forecast")
                        onClicked: backend.refresh()
                    }

                    BusyIndicator {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        running: backend.loading
                        visible: running
                    }

                    Item { Layout.fillWidth: true }

                    KosButton {
                        id: metricButton
                        text: "°C"
                        checkable: true
                        leftPadding: 0
                        rightPadding: 0
                        Layout.preferredWidth: AppTheme.controlHeight
                        background: GlassCircleBg {
                            selected: metricButton.checked
                            pressed: metricButton.down
                            hovered: metricButton.hovered
                        }
                        contentItem: Label {
                            text: metricButton.text
                            font: metricButton.font
                            color: "white"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        ButtonGroup.group: unitsGroup
                        checked: backend.units === "metric"
                        Accessible.role: Accessible.RadioButton
                        Accessible.checked: checked
                        Accessible.name: qsTr("Use metric units")
                        onClicked: backend.setUnits("metric")
                    }

                    KosButton {
                        id: imperialButton
                        text: "°F"
                        checkable: true
                        leftPadding: 0
                        rightPadding: 0
                        Layout.preferredWidth: AppTheme.controlHeight
                        background: GlassCircleBg {
                            selected: imperialButton.checked
                            pressed: imperialButton.down
                            hovered: imperialButton.hovered
                        }
                        contentItem: Label {
                            text: imperialButton.text
                            font: imperialButton.font
                            color: "white"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        ButtonGroup.group: unitsGroup
                        checked: backend.units === "imperial"
                        Accessible.role: Accessible.RadioButton
                        Accessible.checked: checked
                        Accessible.name: qsTr("Use imperial units")
                        onClicked: backend.setUnits("imperial")
                    }
                }

                Label {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    text: backend.stale
                        ? "●  " + qsTr("Cached")
                        : (backend.connected
                            ? "●  Open-Meteo"
                            : "○  " + qsTr("Offline cache"))
                    color: backend.connected && !backend.stale
                        ? AppTheme.positive : AppTheme.warning
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    Accessible.name: backend.stale
                        ? qsTr("Weather service connected; showing cached data")
                        : (backend.connected
                            ? qsTr("Weather service connected")
                            : qsTr("Weather service disconnected; showing offline cache"))
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 20
            spacing: 16

            Flickable {
                id: mainFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: content.implicitHeight + AppTheme.pageMargin
                clip: true

                ScrollBar.vertical: ScrollBar {}

                ColumnLayout {
                    id: content
                    width: parent.width
                    spacing: 16

                    ColumnLayout {
                        id: heroColumn
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 2
                        // Stage 3 motion B.3: hero parallax + slight shrink while the main area
                        // scrolls. Scroll-linked mapping (no timed animation): the hero tracks
                        // contentY at half speed and scales down gently; reduce-motion pins both.
                        transform: Translate {
                            y: AppTheme.reduceMotion ? 0 : Math.max(0, mainFlick.contentY) * 0.5
                        }
                        scale: AppTheme.reduceMotion
                            ? 1.0
                            : Math.max(1.0 - Math.max(0, mainFlick.contentY) / 240 * 0.12, 0.88)
                        transformOrigin: Item.Top

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.locationDetail(backend.location).toUpperCase()
                            visible: text.length > 0
                            color: root.skyTextMuted
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1.4
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.locationName(backend.location)
                            color: root.skyText
                            // ref-main 城市名字高 15px/498 窗高 = 3.0-3.6%，×1.46 折算 ≈22-26px，取 26
                            font.pixelSize: 26
                            font.weight: Font.DemiBold
                        }

                        Row {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: -14 // ref 城市底→数字顶 gap 11px×1.46≈16px；默认行高 padding 多出 ~14px，负 topMargin 收紧（实测偏差下轮微调）
                            // 第 52 轮：按参考图实测缩放。ref-main（814x498 整窗）hero 数字字高 33px = 窗高 6.6%；
                            // tile-hero 切片数字 66px，按其比例折算 iPad 窗高亦 ≈6-6.6%。旧 160px 出自
                            // 80px/498 的单位错配测量，导致实测字高 115px = 窗高 15.8%（超标 2.4 倍）。
                            // 70px × 0.72（Plex Thin 字高/pixelSize 实测比）≈ 50px = 727 窗高的 6.9%，落入参考邻域。
                            spacing: -11 // 随字号按 70/160 缩放（旧 -25），目标 ° 与数字间隙 ~3-4px
                            Label {
                                id: heroTempDigits
                                text: Math.round(root.number(backend.current, "temperature", 0))
                                Accessible.name: text + "°"
                                color: root.skyText
                                font.family: "IBM Plex Sans"
                                font.pixelSize: 70
                                font.weight: Font.Thin
                            }
                            Label {
                                text: "°"
                                color: root.skyText
                                font.family: "IBM Plex Sans"
                                font.pixelSize: 44 // 保持旧 100/160=0.625 比例：70×0.625≈44
                                font.weight: Font.Thin
                                // 下移 8px（旧 19 按 70/160 缩放）使 ° 顶部与数字顶部对齐（Plex 字形度量）
                                y: 8
                                Accessible.ignored: true
                            }
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.conditionText(root.number(backend.current, "weatherCode", -1))
                            color: root.skyText
                            // ref 数字底→条件顶 gap 9px×1.46≈13px
                            Layout.topMargin: -14
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: backend.daily.length > 0
                                ? "H:" + Math.round(root.number(backend.daily[0], "temperatureMaximum", 0)) + "°  "
                                  + "L:" + Math.round(root.number(backend.daily[0], "temperatureMinimum", 0)) + "°"
                                : ""
                            color: root.skyTextMuted
                            // ref 条件底→H:L 顶 gap 6px×1.46≈9px
                            Layout.topMargin: -3
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: errorLabel.implicitHeight + 22
                        radius: AppTheme.smallRadius
                        color: AppTheme.withAlpha(AppTheme.warning, AppTheme.dark ? 0.16 : 0.12)
                        border.width: 1
                        border.color: AppTheme.withAlpha(AppTheme.warning, 0.38)
                        visible: backend.errorMessage.length > 0

                        Label {
                            id: errorLabel
                            anchors.fill: parent
                            anchors.margins: 11
                            text: qsTr("The latest update failed: %1").arg(backend.errorMessage)
                            color: AppTheme.text
                            wrapMode: Text.WordWrap
                        }
                    }

                    // 双列 masonry（ref-main 步骤 a+b+c）：GridLayout 内两个独立列容器 = 真 masonry——
                    // 行式布局曾把左列瓦片压到右列 Conditions 底下产生 86px 天窗；左列 AQ→指标瓦片、右列 Conditions→10 天卡各自独立堆叠；compact 窄窗回落单列
                    GridLayout {
                        Layout.fillWidth: true
                        columns: root.compact ? 1 : 2
                        // ref-main(814x498) y260 行实测 AQ 卡右缘 x505 → Conditions 卡左缘 x519 ≈13px 间隙 × 1.4598 窗高比 ≈ 19px
                        columnSpacing: 19
                        rowSpacing: 16
                        // ref-main 左列：AQ 卡 → 指标瓦片（独立堆叠，不随右列高度走；列缝 19 见 GridLayout）
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredWidth: 0
                            Layout.alignment: Qt.AlignTop
                            spacing: 16
                            KosCard {
                                id: airQualityCard
                                // 空态（快照无 airQuality 字段）下旧代码显示假 "0"、全宽渐变条与模板文案，属仍差 14a 收口；
                                // usAqi=0 是合法值（非负），故用 null 比较而非真值判断
                                readonly property bool hasAqi: root.value(backend.airQuality, "usAqi", null) !== null
                                Layout.fillWidth: true
                                // ref-main 两列等宽(239/241@814)：preferred 拉平让 GridLayout 等分剩余宽度
                                Layout.minimumWidth: 0
                                Layout.preferredWidth: 0
                                Layout.alignment: Qt.AlignTop

                                background: KosSurface {
                                    // ref-main Pillow 实测 Conditions 卡圆角 r≈14px@814 × 1.4598 窗高比 ≈ 20.4 → 20（同心圆角锚点，阶段三 A）
                                    radius: 20
                                    fillColor: Qt.rgba(root.cardGlassRgb.r, root.cardGlassRgb.g, root.cardGlassRgb.b, root.cardGlassAlpha)
                                    strokeWidth: 1
                                    strokeColor: Qt.rgba(1, 1, 1, 0.22)
                                    elevation: 0
                                }

                                contentItem: ColumnLayout {
                                    spacing: 10

                                    RowLayout {
                                        spacing: 6

                                        Canvas {
                                            width: 12
                                            height: 12

                                            onPaint: {
                                                const ctx = getContext("2d")
                                                ctx.clearRect(0, 0, width, height)
                                                // ref-main.png 实测：AQ 卡头部点阵图标最亮点 (284,213)=(52,124,205) vs 卡面 (27,98,175)
                                                // → 峰值 Δ≈+27；"AIR QUALITY" 文字最亮 (322,218)=(96,162,241) vs 同底 → Δ≈+66；
                                                // 图标/文字对比度比 ≈ 0.38-0.41。且点阵亮度沿对角渐变：
                                                // 右上 (row0,col2) 最亮、左下 (row2,col0) 最淡（视觉近消失）。
                                                // 原统一 alpha 0.6 使 Δ≈+121 vs 文字 Δ≈+119（比 0.92），过亮且无渐隐；
                                                // 现按对角渐隐：峰值 0.26×(255−背景)≈+47 ≈ 0.4× 文字 Δ。
                                                for (let row = 0; row < 3; ++row) {
                                                    for (let col = 0; col < 3; ++col) {
                                                        // 亮度沿 col−row 对角：右上 (row0,col2)=0.26 最亮、左下 (row2,col0)=0.10 最淡
                                                        const alpha = 0.10 + 0.16 * (col - row + 2) / 4
                                                        ctx.fillStyle = Qt.rgba(1, 1, 1, alpha)
                                                        ctx.beginPath()
                                                        ctx.arc(1.5 + col * 4.5, 1.5 + row * 4.5, 1.3, 0, Math.PI * 2)
                                                        ctx.fill()
                                                    }
                                                }
                                            }
                                        }

                                        Label {
                                            text: qsTr("Air Quality").toUpperCase()
                                            color: root.skyTextMuted
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            font.letterSpacing: 1.4
                                        }
                                    }

                                    Label {
                                        visible: airQualityCard.hasAqi
                                        text: Math.round(root.number(backend.airQuality, "usAqi", 0))
                                        color: root.skyText
                                        font.pixelSize: 22
                                        font.weight: Font.DemiBold
                                    }

                                    Label {
                                        text: root.value(backend.airQuality, "category", "")
                                        visible: text.length > 0
                                        color: root.skyText
                                        Layout.topMargin: -12 // ref-main 实测数字底→rating cap 顶 ink gap 7px×1.46≈10，改前 22px（spacing 10 + 两行字体行高 padding），-12 只抵消行高 padding
                                        font.pixelSize: 13
                                    }

                                    Item {
                                        visible: airQualityCard.hasAqi
                                        Layout.topMargin: 7 // ref-main 实测 rating cap 顶→条顶 22px×1.4598≈32，改前 25px（同口径），+7 补齐；本轮 Pillow 实测 rating 基线→条顶 我方 16.5px vs ref 16px×1.4598≈23.3
                                        Layout.fillWidth: true
                                        height: 9

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            height: 4
                                            radius: 2
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                // ref-main 实测：EPA 0-500 线性映射，0.72 起平直 #80172b（Pillow 逐点采样）
                                                stops: [
                                                    GradientStop { position: 0.00; color: "#00de72" },
                                                    GradientStop { position: 0.15; color: "#fde620" },
                                                    GradientStop { position: 0.22; color: "#ffac0b" },
                                                    GradientStop { position: 0.29; color: "#fd5e21" },
                                                    GradientStop { position: 0.36; color: "#f30f5e" },
                                                    GradientStop { position: 0.43; color: "#cd08b2" },
                                                    GradientStop { position: 0.50; color: "#a805fa" },
                                                    GradientStop { position: 0.58; color: "#9a0aae" },
                                                    GradientStop { position: 0.65; color: "#8b1062" },
                                                    GradientStop { position: 0.72; color: "#80172b" },
                                                    GradientStop { position: 1.00; color: "#80172b" }
                                                ]
                                            }
                                        }

                                        Rectangle {
                                            // ref-main Pillow 实测 AQI 40 白点在条 8.33% 处，0–500（EPA AQI 满量程）预测 8.0% 吻合，0–300 预测 13.3% 偏差 10.5px
                                            x: Math.max(0, Math.min(1, root.number(backend.airQuality, "usAqi", 0) / 500)) * (parent.width - 9)
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 9
                                            height: 9
                                            radius: 4.5
                                            color: "#ffffff"
                                        }
                                    }

                                    // ref-main 实测：说明文字峰值纯白 (255,255,255) 且重于 rating，Demibold 白字
                                    Label {
                                        visible: airQualityCard.hasAqi
                                        text: qsTr("Air quality index is %1, which is similar to yesterday at about this time.")
                                            .arg(Math.round(root.number(backend.airQuality, "usAqi", 0)))
                                        color: root.skyText
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            // 指标瓦片容器：参考图（ref-main）里指标卡（WIND/月相/UV/SUNSET 等）
                            // 是散在天空上的独立圆角卡，卡与卡之间直接透天空，无外层容器卡——
                            // 故本 Pane 只做布局，不带任何卡面 chrome（Pillow 实测 ref 指标卡
                            // 填充 (38.5,115.8,196.9) vs 卡间天空 (54.7,124.3,197.0)，无白玻璃亮层）。
                            KosCard {
                                id: conditionsCard
                                // ref-main：瓦片区入左列 AQ 卡下方（左列 x271-505，与 AQ 同列对齐）；右列 dailyCard 不动（masonry 步骤 b 第一半）
                                Layout.fillWidth: true
                                // 镜像 airQualityCard/dailyCard 同族等宽修正（步 a 先例）：preferred 拉平让 GridLayout 等分列宽
                                Layout.minimumWidth: 0
                                Layout.preferredWidth: 0
                                // ref-main Pillow 实测：WIND 卡左缘 x271 与 AQ 卡左缘 x271 同列对齐；
                                // 本卡 padding≈20 导致瓦片 x272 vs AQ 卡 x252，置零水平 padding 对齐；
                                // topPadding/bottomPadding 保持不动——:2401 的 topMargin:-16 抵消方案按 padding 20 校准，勿动
                                leftPadding: 0
                                rightPadding: 0

                                background: Item {}

                                contentItem: ColumnLayout {
                                    spacing: 12

                                    KosEmptyState {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        visible: !backend.ready
                                        symbol: backend.loading ? "↻" : "☁"
                                        titleColor: root.skyText
                                        descriptionColor: root.skyTextMuted
                                        title: backend.loading
                                            ? qsTr("Loading the forecast") : qsTr("No forecast available")
                                        description: backend.connected
                                            ? qsTr("Refresh or choose another saved location.")
                                            : qsTr("Start kos-data-service to fetch weather data.")
                                        actionText: backend.connected ? qsTr("Refresh") : ""
                                        actionEnabled: !backend.loading
                                        onActionTriggered: backend.refresh()
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        visible: backend.ready
                                        spacing: 12

                                        GridLayout {
                                            Layout.fillWidth: true
                                            Layout.topMargin: -16 // ref-main AQ 底→WIND 顶 14px@814 × 1.4598 ≈ 20px;改前 36px = content spacing 16 + 本卡 padding ~20,-16 抵消 padding 多余部分(描边-描边 20px)
                                            columns: 2 // ref-main 左列瓦片区两列排布，compact 原本就是 2 列故统一
                                            columnSpacing: 8
                                            rowSpacing: 8

                                            // ref-main WIND 124 / gap 8 / MOON 102 → 半宽并排（235/15/193）
                                            RowLayout {
                                                Layout.columnSpan: 2
                                                Layout.fillWidth: true
                                                spacing: 15

                                                Rectangle {
                                                    id: windCard
                                                    Layout.fillWidth: true
                                                    Layout.preferredWidth: 235
                                                    implicitHeight: 162
                                                    radius: root.tileRadius
                                                    // 昼夜分材质：ref-main 白天所有卡填充暗于天空（α~0.30 深蓝玻璃）；夜间维持白玻璃
                                                    property bool hot: windHover.hovered
                                                    property real hoverFill: hot ? root.cardGlassAlphaHot : root.cardGlassAlpha
                                                    Behavior on hoverFill { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                                                    property real hoverStroke: hot ? 0.32 : 0.22
                                                    Behavior on hoverStroke { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                                                    color: Qt.rgba(root.cardGlassRgb.r, root.cardGlassRgb.g, root.cardGlassRgb.b, hoverFill)
                                                    border.width: 1
                                                    border.color: Qt.rgba(1, 1, 1, hoverStroke)
                                                    transform: Translate {
                                                        y: AppTheme.reduceMotion ? 0 : (windCard.hot ? -3 : 0)
                                                        Behavior on y { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                                                    }

                                                    property real windDir: root.number(backend.current, "windDirection", 0)
                                                    // arrow points where the wind blows TO (Open-Meteo direction is where it comes FROM)
                                                    property real flowAngle: (windCard.windDir + 180) % 360
                                                    property real gustVal: root.number(backend.current, "windGust", Number.NaN)
                                                    property bool hasGust: Number.isFinite(gustVal)

                                                    onWindDirChanged: windCompass.requestPaint()
                                                    onFlowAngleChanged: windCompass.requestPaint()

                                                    HoverHandler { id: windHover }
                                                    ToolTip.visible: windHover.hovered
                                                    ToolTip.text: qsTr("Direction")
                                                    Accessible.role: Accessible.StaticText
                                                    Accessible.name: qsTr("Wind") + ": " + Math.round(root.number(
                                                        backend.current, "windSpeed", 0)) + " " + root.speedUnit
                                                        + ", " + qsTr("Direction") + " " + Math.round(windCard.windDir) + "° " + windCard.cardinal
                                                        + (windCard.hasGust
                                                            ? " " + qsTr("Gusts") + ": " + Math.round(windCard.gustVal) + " " + root.speedUnit
                                                            : "")

                                                    property string cardinal: {
                                                        var names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
                                                        return names[Math.round(windCard.windDir / 45) % 8]
                                                    }

                                                    // ref-main WIND 头部：左/上 inset 14/12px，11px DemiBold + 字距全大写（同瓦片头家族）
                                                    RowLayout {
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 14
                                                        anchors.top: parent.top
                                                        anchors.topMargin: 12
                                                        spacing: 8

                                                        Label {
                                                            text: "≋"
                                                            color: root.skyTextMuted
                                                            font.pixelSize: 11
                                                            font.weight: Font.DemiBold
                                                            Accessible.ignored: true
                                                        }

                                                        Label {
                                                            text: qsTr("Wind").toLocaleUpperCase(Qt.locale())
                                                            color: root.skyTextMuted
                                                            font.pixelSize: 11
                                                            font.letterSpacing: 1.4
                                                            Accessible.ignored: true
                                                        }
                                                    }

                                                    // ref-main 罗盘外径 72px@814 → 116×116，水平居中 y36
                                                    Item {
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        y: 36
                                                        width: 116
                                                        height: 116

                                                        Canvas {
                                                            id: windCompass
                                                            anchors.fill: parent
                                                            antialiasing: true
                                                            contextType: "2d"
                                                            onPaint: {
                                                                var ctx = getContext("2d")
                                                                ctx.reset()
                                                                var c = 58
                                                                // 内盘 r29 白 0.06（ref 内盘 (52,122,196) vs 卡面 (35,112,193) ≈ 白@0.06）
                                                                ctx.fillStyle = "rgba(255,255,255,0.06)"
                                                                ctx.beginPath()
                                                                ctx.arc(c, c, 29, 0, 2 * Math.PI)
                                                                ctx.fill()
                                                                // 刻度环带：tile-cards WIND 卡（538 宽切片，卡宽 ~223）实测参考为密集细刻度带
                                                                // r46→r57（0.206-0.256 卡宽比）；我方卡高 162 受 Gusts 行约束按高度缩放，
                                                                // 带取 r38→r46，密度取每 3°（120 根，ref 糊化不可数，密度系外推）
                                                                ctx.strokeStyle = "rgba(255,255,255,0.30)"
                                                                ctx.lineWidth = 1
                                                                for (var i = 0; i < 120; i++) {
                                                                    var a = i * Math.PI / 60
                                                                    ctx.beginPath()
                                                                    ctx.moveTo(c + Math.sin(a) * 38, c - Math.cos(a) * 38)
                                                                    ctx.lineTo(c + Math.sin(a) * 46, c - Math.cos(a) * 46)
                                                                    ctx.stroke()
                                                                }
                                                                // N/E/S/W 字母 r≈50；N 用实测亮蓝，W/E/S 白 0.65
                                                                ctx.font = "600 10px sans-serif"
                                                                ctx.textAlign = "center"
                                                                ctx.textBaseline = "middle"
                                                                ctx.fillStyle = "#6CB1E0"
                                                                ctx.fillText("N", c, c - 50)
                                                                ctx.fillStyle = "rgba(255,255,255,0.65)"
                                                                ctx.fillText("E", c + 50, c)
                                                                ctx.fillText("S", c, c + 50)
                                                                ctx.fillText("W", c - 50, c)
                                                                // 两段式留空指针（ref-main WIND 卡实测：指针不穿
                                                                // 中心文字——箭头段在流向侧近外圈 + 来向侧短尾针，
                                                                // r<30 让位环心数字/单位）
                                                                ctx.save()
                                                                ctx.translate(c, c)
                                                                ctx.rotate(windCard.flowAngle * Math.PI / 180)
                                                                ctx.strokeStyle = "#ffffff"
                                                                ctx.fillStyle = "#ffffff"
                                                                ctx.lineWidth = 1.6
                                                                ctx.beginPath()
                                                                ctx.moveTo(0, -30)
                                                                ctx.lineTo(0, -40)
                                                                ctx.stroke()
                                                                // 来向侧圆头短针（tile-cards WIND 卡 538 切片实测：气球形
                                                                // 圆头 ⌀~14@卡宽223 位于刻度带外缘 r~58 + 细杆向心 r51→36
                                                                // 宽 2-3px；我方卡高 162 竖向受限，与刻度带 r38-46 同族缩放
                                                                // ——圆头 r5 中心 r46=带外缘，杆 r30→41，内端 r30 让位环心单位文字）
                                                                ctx.beginPath()
                                                                ctx.moveTo(0, 30)
                                                                ctx.lineTo(0, 41)
                                                                ctx.stroke()
                                                                ctx.beginPath()
                                                                ctx.arc(0, 46, 5, 0, 2 * Math.PI)
                                                                ctx.fill()
                                                                ctx.beginPath()
                                                                ctx.moveTo(0, -46)      // tip
                                                                ctx.lineTo(-3, -41)
                                                                ctx.lineTo(3, -41)
                                                                ctx.closePath()
                                                                ctx.fill()
                                                                ctx.restore()
                                                            }
                                                        }

                                                        // 环心速度：数字+单位整体居中于罗盘中心
                                                        ColumnLayout {
                                                            anchors.centerIn: parent
                                                            spacing: 1

                                                            Label {
                                                                Layout.alignment: Qt.AlignHCenter
                                                                text: Math.round(root.number(
                                                                    backend.current, "windSpeed", 0))
                                                                color: root.skyText
                                                                font.pixelSize: 30
                                                                font.weight: Font.DemiBold
                                                                Accessible.ignored: true
                                                            }

                                                            Label {
                                                                Layout.alignment: Qt.AlignHCenter
                                                                text: root.speedUnit
                                                                color: root.skyTextMuted
                                                                font.pixelSize: 13
                                                                // 单位墨底实测距刻度内缘仅 10px（patrol-1792322227：墨底 y500 vs 内缘 y510），上移 10px 贴 ref（tile-cards 数字→单位墨距 ~5px、单位全在环内）
                                                                transform: Translate { y: -10 }
                                                                Accessible.ignored: true
                                                            }
                                                        }
                                                    }

                                                    // ref-main Gusts 行：距卡底 9px@814、左 inset 12px@814
                                                    Label {
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 17
                                                        anchors.bottom: parent.bottom
                                                        anchors.bottomMargin: 12
                                                        visible: windCard.hasGust
                                                        text: qsTr("Gusts: ") + Math.round(windCard.gustVal) + " " + root.speedUnit
                                                              + " " + windCard.cardinal
                                                        color: root.skyText
                                                        font.pixelSize: 13
                                                        font.weight: Font.DemiBold
                                                        elide: Text.ElideRight
                                                        Accessible.ignored: true
                                                    }
                                                }

                                                Rectangle {
                                                    id: moonCard
                                                    Layout.fillWidth: true
                                                    Layout.preferredWidth: 193
                                                    implicitHeight: 162
                                                    radius: root.tileRadius
                                                    // 昼夜分材质：ref-main 白天所有卡填充暗于天空（α~0.30 深蓝玻璃）；夜间维持白玻璃
                                                    property bool hot: moonHover.hovered
                                                    property real hoverFill: hot ? root.cardGlassAlphaHot : root.cardGlassAlpha
                                                    Behavior on hoverFill { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                                                    property real hoverStroke: hot ? 0.32 : 0.22
                                                    Behavior on hoverStroke { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                                                    color: Qt.rgba(root.cardGlassRgb.r, root.cardGlassRgb.g, root.cardGlassRgb.b, hoverFill)
                                                    border.width: 1
                                                    border.color: Qt.rgba(1, 1, 1, hoverStroke)
                                                    transform: Translate {
                                                        y: AppTheme.reduceMotion ? 0 : (moonCard.hot ? -3 : 0)
                                                        Behavior on y { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                                                    }

                                                    property real phaseVal: root.number(backend.current, "moonPhase", Number.NaN)
                                                    property bool hasPhase: Number.isFinite(phaseVal)
                                                    readonly property var phaseNames: [
                                                        qsTr("New Moon"), qsTr("Waxing Crescent"), qsTr("First Quarter"),
                                                        qsTr("Waxing Gibbous"), qsTr("Full Moon"), qsTr("Waning Gibbous"),
                                                        qsTr("Last Quarter"), qsTr("Waning Crescent")
                                                    ]
                                                    // 8 等分、以 0/0.25/0.5/0.75 为中心：round(p*8)%8
                                                    readonly property string phaseName: hasPhase
                                                        ? phaseNames[Math.round(((phaseVal % 1) + 1) % 1 * 8) % 8]
                                                        : "—"

                                                    onPhaseValChanged: {
                                                        moonCanvas.requestPaint()
                                                        moonGlyphCanvas.requestPaint()
                                                    }

                                                    HoverHandler { id: moonHover }
                                                    ToolTip.visible: moonHover.hovered
                                                    ToolTip.text: qsTr("Moon Phase")
                                                    Accessible.role: Accessible.StaticText
                                                    Accessible.name: qsTr("Moon Phase") + ": " + moonCard.phaseName

                                                    // ref-main 头部=相位名 caps + 小月相 glyph（y338-344 实测）
                                                    RowLayout {
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 14
                                                        anchors.top: parent.top
                                                        anchors.topMargin: 12
                                                        spacing: 8

                                                        Canvas {
                                                            id: moonGlyphCanvas
                                                            implicitWidth: 12
                                                            implicitHeight: 12
                                                            antialiasing: true
                                                            contextType: "2d"
                                                            onPaint: {
                                                                var ctx = getContext("2d")
                                                                ctx.reset()
                                                                var c = 6
                                                                var r = 5
                                                                // 暗面：整盘剪影（月亮相位剪影，同族白 0.14）
                                                                ctx.beginPath()
                                                                ctx.arc(c, c, r, 0, 2 * Math.PI)
                                                                ctx.fillStyle = "rgba(255,255,255,0.14)"
                                                                ctx.fill()
                                                                if (!moonCard.hasPhase)
                                                                    return
                                                                // 亮面：外弧（盈月亮在右，亏月亮在左）+ 终止线半椭圆折线，一次成形
                                                                var p = ((moonCard.phaseVal % 1) + 1) % 1
                                                                var cosT = Math.cos(2 * Math.PI * p)
                                                                var waxing = p < 0.5
                                                                ctx.beginPath()
                                                                if (waxing)
                                                                    ctx.arc(c, c, r, -Math.PI / 2, Math.PI / 2, false)   // 顶极→底极经右侧
                                                                else
                                                                    ctx.arc(c, c, r, -Math.PI / 2, Math.PI / 2, true)    // 顶极→底极经左侧
                                                                var steps = 32
                                                                for (var i = 0; i <= steps; i++) {
                                                                    var a = Math.PI / 2 - (Math.PI * i / steps)          // 底极→顶极
                                                                    // 带符号 cosT：蛾眉凸向亮侧、凸月凸向暗侧（|cosT| 会把凸月画成蛾眉、满月退化成零面积）
                                                                    var ex = waxing ? cosT * r * Math.cos(a) : -cosT * r * Math.cos(a)
                                                                    ctx.lineTo(c + ex, c + r * Math.sin(a))
                                                                }
                                                                ctx.closePath()
                                                                // 同色族冷蓝白，与 moonCanvas 大盘亮面一致
                                                                ctx.fillStyle = "#a1c0e4"
                                                                ctx.fill()
                                                            }
                                                        }

                                                        Label {
                                                            text: moonCard.phaseName.toLocaleUpperCase(Qt.locale())
                                                            color: root.skyTextMuted
                                                            font.pixelSize: 11
                                                            font.letterSpacing: 1.4
                                                            elide: Text.ElideRight
                                                            Accessible.ignored: true
                                                        }
                                                    }

                                                    // ref-main 月亮盘 d≈71@814 ×1.46 ≈ 104，盘顶距卡顶 28×1.46 ≈ 41，水平居中
                                                    Canvas {
                                                        id: moonCanvas
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        y: 41
                                                        width: 104
                                                        height: 104
                                                        antialiasing: true
                                                        contextType: "2d"
                                                        onPaint: {
                                                            var ctx = getContext("2d")
                                                            ctx.reset()
                                                            var c = 52
                                                            var r = 52
                                                            // 暗面：整盘剪影（月亮相位剪影，同族白 0.14）
                                                            ctx.beginPath()
                                                            ctx.arc(c, c, r, 0, 2 * Math.PI)
                                                            ctx.fillStyle = "rgba(255,255,255,0.14)"
                                                            ctx.fill()
                                                            if (!moonCard.hasPhase)
                                                                return
                                                            // 亮面：外弧（盈月亮在右，亏月亮在左）+ 终止线半椭圆折线，一次成形
                                                            var p = ((moonCard.phaseVal % 1) + 1) % 1
                                                            var cosT = Math.cos(2 * Math.PI * p)
                                                            var waxing = p < 0.5
                                                            ctx.beginPath()
                                                            if (waxing)
                                                                ctx.arc(c, c, r, -Math.PI / 2, Math.PI / 2, false)   // 顶极→底极经右侧
                                                            else
                                                                ctx.arc(c, c, r, -Math.PI / 2, Math.PI / 2, true)    // 顶极→底极经左侧
                                                            var steps = 32
                                                            for (var i = 0; i <= steps; i++) {
                                                                var a = Math.PI / 2 - (Math.PI * i / steps)          // 底极→顶极
                                                                // 带符号 cosT：蛾眉凸向亮侧、凸月凸向暗侧（|cosT| 会把凸月画成蛾眉、满月退化成零面积）
                                                                var ex = waxing ? cosT * r * Math.cos(a) : -cosT * r * Math.cos(a)
                                                                ctx.lineTo(c + ex, c + r * Math.sin(a))
                                                            }
                                                            ctx.closePath()
                                                            // 亮面冷蓝白：ref tile-cards 月亮相照片亮面实测均值 (161,192,228)；峰值 (228,236,247) 系纹理不可平面复刻
                                                            ctx.fillStyle = "#a1c0e4"
                                                            ctx.fill()
                                                        }
                                                    }
                                                }
                                            }

                                            // ref-main SUNSET 卡 x272-380 顶 y453：头部 glyph+SUNSET caps、大号时间左对齐（字形顶=卡顶+30、字高 ~14.4px@814 → 30px）；底缘被参考窗裁切，底部内容外推待确认
                                            // ref tile-cards 实测 SUNSET/UV 等宽对半（221/221@tile；ref-main 109/~117 近等宽）→ RowLayout 等分（214/15/214），镜像 wind/moon 先例
                                            RowLayout {
                                                Layout.columnSpan: 2
                                                Layout.topMargin: 8
                                                Layout.fillWidth: true
                                                spacing: 15

                                                Rectangle {
                                                    id: sunsetCard
                                                    Layout.fillWidth: true
                                                    Layout.preferredWidth: 214
                                                    implicitHeight: 162
                                                    radius: root.tileRadius
                                                    // 昼夜分材质：ref-main 白天所有卡填充暗于天空（α~0.30 深蓝玻璃）；夜间维持白玻璃
                                                    property bool hot: sunsetHover.hovered
                                                    property real hoverFill: hot ? root.cardGlassAlphaHot : root.cardGlassAlpha
                                                    Behavior on hoverFill { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                                                    property real hoverStroke: hot ? 0.32 : 0.22
                                                    Behavior on hoverStroke { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                                                    color: Qt.rgba(root.cardGlassRgb.r, root.cardGlassRgb.g, root.cardGlassRgb.b, hoverFill)
                                                    border.width: 1
                                                    border.color: Qt.rgba(1, 1, 1, hoverStroke)
                                                    transform: Translate {
                                                        y: AppTheme.reduceMotion ? 0 : (sunsetCard.hot ? -3 : 0)
                                                        Behavior on y { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                                                    }

                                                    // daily[0].sunset 形如 "2026-10-17T17:57"（Open-Meteo 本地 ISO，无时区后缀）——自旧 66px 日落瓦片原样迁入
                                                    readonly property string sunsetRaw:
                                                        backend.daily.length > 0 ? String(root.value(backend.daily[0], "sunset", "")) : ""
                                                    readonly property bool hasSunset: /T\d{1,2}:\d{2}/.test(sunsetRaw)
                                                    readonly property string sunsetText: {
                                                        if (!hasSunset) return "—"
                                                        const m = /T(\d{1,2}):(\d{2})/.exec(sunsetRaw)
                                                        let h = parseInt(m[1], 10)
                                                        const ap = h >= 12 ? qsTr("PM") : qsTr("AM")
                                                        h = h % 12
                                                        if (h === 0) h = 12
                                                        return h + ":" + m[2] + ap
                                                    }

                                                    HoverHandler { id: sunsetHover }
                                                    ToolTip.visible: sunsetHover.hovered
                                                    ToolTip.text: qsTr("Sunset")
                                                    Accessible.role: Accessible.StaticText
                                                    Accessible.name: qsTr("Sunset") + ": " + sunsetCard.sunsetText

                                                    RowLayout {
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 14
                                                        anchors.top: parent.top
                                                        anchors.topMargin: 12
                                                        spacing: 8

                                                        Canvas {
                                                            id: sunsetGlyphCanvas
                                                            implicitWidth: 12
                                                            implicitHeight: 12
                                                            antialiasing: true
                                                            contextType: "2d"
                                                            Accessible.ignored: true
                                                            onPaint: {
                                                                var ctx = getContext("2d")
                                                                ctx.reset()
                                                                // mini 日落 glyph（ref ~8px@814 → 12px）：地平线 + 上半圆太阳 + 下落箭头，同旧 46px sunCanvas 家族缩比
                                                                ctx.strokeStyle = "rgba(255,255,255,0.85)"
                                                                ctx.lineWidth = 1.2
                                                                ctx.beginPath()
                                                                ctx.moveTo(0.5, 9)
                                                                ctx.lineTo(11.5, 9)
                                                                ctx.stroke()
                                                                ctx.beginPath()
                                                                ctx.arc(6, 9, 3.5, Math.PI, 2 * Math.PI, false)
                                                                ctx.closePath()
                                                                // ref-main SUNSET 卡头 glyph 实测浅蓝白（峰值 (224,240,255)/(239,251,255)、暖色像素 0），非黄色
                                                                ctx.fillStyle = "#e7f5ff"
                                                                ctx.fill()
                                                                ctx.strokeStyle = "rgba(255,255,255,0.92)"
                                                                ctx.fillStyle = "rgba(255,255,255,0.92)"
                                                                ctx.lineWidth = 1.2
                                                                ctx.beginPath()
                                                                ctx.moveTo(6, 2)
                                                                ctx.lineTo(6, 4.5)
                                                                ctx.stroke()
                                                                ctx.beginPath()
                                                                ctx.moveTo(6, 6)
                                                                ctx.lineTo(4.4, 4.2)
                                                                ctx.lineTo(7.6, 4.2)
                                                                ctx.closePath()
                                                                ctx.fill()
                                                            }
                                                        }

                                                        Label {
                                                            text: qsTr("Sunset").toLocaleUpperCase(Qt.locale())
                                                            color: root.skyTextMuted
                                                            font.pixelSize: 11
                                                            font.letterSpacing: 1.4
                                                            Accessible.ignored: true
                                                        }
                                                    }

                                                    // ref-main 大号时间墨顶=卡顶+30×1.4598≈44、左 inset ~7-9@814 → 与头部 glyph 同列 14（30px 字体行高空隙 ~9，盒顶取 35）
                                                    Label {
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 14
                                                        anchors.top: parent.top
                                                        anchors.topMargin: 35
                                                        text: sunsetCard.sunsetText
                                                        color: root.skyText
                                                        font.pixelSize: 30
                                                        font.weight: Font.DemiBold
                                                        Accessible.ignored: true
                                                    }
                                                }

                                                // ref tile-cards UV 卡：头部太阳光线 glyph + "UV INDEX" caps + 左对齐大数字（ink 高与 SUNSET 大号时间同为 27@tile → 30px DemiBold）；卡底被参考窗裁切，底部内容不发明
                                                Rectangle {
                                                    id: uvCard
                                                    Layout.fillWidth: true
                                                    Layout.preferredWidth: 214
                                                    implicitHeight: 162
                                                    radius: root.tileRadius
                                                    // 昼夜分材质：ref-main 白天所有卡填充暗于天空（α~0.30 深蓝玻璃）；夜间维持白玻璃
                                                    property bool hot: uvHover.hovered
                                                    property real hoverFill: hot ? root.cardGlassAlphaHot : root.cardGlassAlpha
                                                    Behavior on hoverFill { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                                                    property real hoverStroke: hot ? 0.32 : 0.22
                                                    Behavior on hoverStroke { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                                                    color: Qt.rgba(root.cardGlassRgb.r, root.cardGlassRgb.g, root.cardGlassRgb.b, hoverFill)
                                                    border.width: 1
                                                    border.color: Qt.rgba(1, 1, 1, hoverStroke)
                                                    transform: Translate {
                                                        y: AppTheme.reduceMotion ? 0 : (uvCard.hot ? -3 : 0)
                                                        Behavior on y { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                                                    }

                                                    readonly property real uvVal: root.number(backend.current, "uvIndex", NaN)
                                                    readonly property string uvText: Number.isFinite(uvVal) ? String(Math.round(uvVal)) : "—"

                                                    HoverHandler { id: uvHover }
                                                    ToolTip.visible: uvHover.hovered
                                                    ToolTip.text: qsTr("UV Index")
                                                    Accessible.role: Accessible.StaticText
                                                    Accessible.name: qsTr("UV Index") + ": " + uvCard.uvText

                                                    RowLayout {
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 14
                                                        anchors.top: parent.top
                                                        anchors.topMargin: 12
                                                        spacing: 8

                                                        Canvas {
                                                            id: uvGlyphCanvas
                                                            implicitWidth: 12
                                                            implicitHeight: 12
                                                            antialiasing: true
                                                            contextType: "2d"
                                                            Accessible.ignored: true
                                                            onPaint: {
                                                                var ctx = getContext("2d")
                                                                ctx.reset()
                                                                // mini UV glyph（ref tile-cards ~14px@tile → 12px）：中心日盘 + 8 根射线
                                                                ctx.strokeStyle = "rgba(255,255,255,0.85)"
                                                                ctx.lineWidth = 1.2
                                                                for (var i = 0; i < 8; i++) {
                                                                    var a = i * Math.PI / 4
                                                                    ctx.beginPath()
                                                                    ctx.moveTo(6 + Math.cos(a) * 3.2, 6 + Math.sin(a) * 3.2)
                                                                    ctx.lineTo(6 + Math.cos(a) * 5.4, 6 + Math.sin(a) * 5.4)
                                                                    ctx.stroke()
                                                                }
                                                                ctx.beginPath()
                                                                ctx.arc(6, 6, 2, 0, 2 * Math.PI, false)
                                                                ctx.closePath()
                                                                // ref-main UV INDEX 卡头 glyph 实测浅蓝白（同 SUNSET 依据）
                                                                ctx.fillStyle = "#e7f5ff"
                                                                ctx.fill()
                                                            }
                                                        }

                                                        Label {
                                                            text: qsTr("UV Index").toLocaleUpperCase(Qt.locale())
                                                            color: root.skyTextMuted
                                                            font.pixelSize: 11
                                                            font.letterSpacing: 1.4
                                                            Accessible.ignored: true
                                                        }
                                                    }

                                                    Label {
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 14
                                                        anchors.top: parent.top
                                                        anchors.topMargin: 35
                                                        text: uvCard.uvText
                                                        color: root.skyText
                                                        font.pixelSize: 30
                                                        font.weight: Font.DemiBold
                                                        Accessible.ignored: true
                                                    }
                                                }
                                            }

                                            WeatherMetric {
                                                Layout.fillWidth: true
                                                symbol: "%"
                                                labelText: qsTr("Humidity")
                                                valueText: Math.round(root.number(
                                                    backend.current, "relativeHumidity", 0)) + "%"
                                            }

                                            WeatherMetric {
                                                Layout.fillWidth: true
                                                symbol: "◷"
                                                labelText: qsTr("Observed")
                                                valueText: root.localTime(root.value(
                                                    backend.current, "time", ""))
                                            }

                                            WeatherMetric {
                                                Layout.fillWidth: true
                                                symbol: "◉"
                                                labelText: qsTr("Visibility")
                                                valueText: {
                                                    const meters = root.number(backend.current, "visibility", NaN)
                                                    if (!Number.isFinite(meters))
                                                        return "—"
                                                    return backend.units === "imperial"
                                                        ? Math.round(meters / 1609.344) + " " + root.distanceUnit
                                                        : Math.round(meters / 1000) + " " + root.distanceUnit
                                                }
                                            }

                                            WeatherMetric {
                                                Layout.fillWidth: true
                                                symbol: "◐"
                                                labelText: qsTr("Pressure")
                                                valueText: {
                                                    const hpa = root.number(backend.current, "pressure", NaN)
                                                    return Number.isFinite(hpa) ? Math.round(hpa) + " hPa" : "—"
                                                }
                                            }

                                            WeatherMetric {
                                                Layout.fillWidth: true
                                                symbol: "≈"
                                                labelText: qsTr("Feels Like")
                                                valueText: {
                                                    const feels = root.number(backend.current, "apparentTemperature", NaN)
                                                    return Number.isFinite(feels) ? Math.round(feels) + "°" : "—"
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        // ref-main 右列：Conditions 卡 → 10 天卡（独立堆叠，不随左列高度走；列缝 19 见 GridLayout）
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredWidth: 0
                            Layout.alignment: Qt.AlignTop
                            spacing: 16
                            // Conditions 单卡：包住 头部行 + 右上分段胶囊 + 逐小时列（对齐 ref-main）
                            KosCard {
                                id: hourlyConditionsCard
                                Layout.fillWidth: true
                                // ref-main 两列等宽(239/241@814)：preferred 拉平让 GridLayout 等分剩余宽度
                                Layout.minimumWidth: 0
                                Layout.preferredWidth: 0
                                Layout.alignment: Qt.AlignTop

                                background: KosSurface {
                                    radius: 20
                                    fillColor: Qt.rgba(root.cardGlassRgb.r, root.cardGlassRgb.g, root.cardGlassRgb.b, root.currentIsDay ? root.cardGlassAlpha : 0.16)
                                    strokeWidth: 1
                                    strokeColor: Qt.rgba(1, 1, 1, 0.22)
                                    elevation: 0
                                }

                                contentItem: ColumnLayout {
                                    spacing: 10

                                    RowLayout {
                                        Layout.fillWidth: true

                                        ColumnLayout {
                                            spacing: 1
                                            Layout.fillWidth: true

                                            Label {
                                                Layout.fillWidth: true
                                                text: qsTr("Conditions")
                                                color: root.skyText
                                                font.pixelSize: 14
                                                font.weight: Font.DemiBold
                                                Accessible.name: qsTr("Hourly forecast")
                                            }

                                            // 副标题为外推：固定展示温度单位，不随 segment 切换
                                            Label {
                                                Layout.fillWidth: true
                                                text: qsTr("Temperature (%1)").arg(root.temperatureUnit)
                                                color: root.skyTextMuted
                                                font.pixelSize: 11
                                            }
                                        }

                                        // 三段胶囊切换钮，参照 ref-main Conditions 卡右上分段控件。
                                        // segment 0 = 温度/图标视图（默认，参考图选中态），
                                        // segment 1 = 逐小时降水概率视图；
                                        // segment 2 = 逐小时风速视图（后端 hourlyPoint.windSpeed 已有）。
                                        Item {
                                            id: hourlySegmented
                                            implicitWidth: 132
                                            implicitHeight: 36
                                            Layout.alignment: Qt.AlignTop | Qt.AlignRight
                                            property int segment: 0

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 18
                                                // 参考实测（ref-main 814×498 Pillow 采样）：胶囊内 (28,90,168) vs 卡面 (0,83,180)
                                                // ——相对卡面 R+28/G+7/B−12，解出脱饱和中性灰 ≈#767676 @ α0.22-0.26（压暗蓝通道）；白@0.14 方向相反（整体提亮），故按参考改灰。
                                                color: Qt.rgba(0.46, 0.46, 0.46, 0.24)
                                                border.width: 1
                                                border.color: Qt.rgba(1, 1, 1, 0.22)
                                            }

                                            // 选中圆盘（当前段背后）
                                            Rectangle {
                                                x: 3 + 44 * hourlySegmented.segment
                                                y: 3
                                                width: 30
                                                height: 30
                                                radius: 15
                                                color: Qt.rgba(1, 1, 1, 0.27)
                                            }

                                            AbstractButton {
                                                x: 0
                                                width: 44
                                                height: 36
                                                background: null
                                                // ref tile-conditions：实心云体 + 右上探出小日盘，云与日之间有缺口（SF cloud.sun.fill 构图）
                                                // Control 会覆写 contentItem 几何，Canvas 需包 Item 再居中；segment 属于外层 hourlySegmented
                                                contentItem: Item {
                                                    anchors.fill: parent
                                                    Canvas {
                                                        id: cloudSunCanvas
                                                        width: 20
                                                        height: 15
                                                        anchors.centerIn: parent
                                                        antialiasing: true
                                                        onPaint: {
                                                            var ctx = getContext("2d")
                                                            ctx.reset()
                                                            // 日盘（右上探出）
                                                            ctx.beginPath()
                                                            ctx.arc(13.5, 4.5, 3.2, 0, 2 * Math.PI)
                                                            ctx.fillStyle = hourlySegmented.segment === 0 ? "#ffffff" : Qt.rgba(1, 1, 1, 0.9)
                                                            ctx.fill()
                                                            // 云体：底边 y=14 平直，大鼓包 (6,10) r4.5、小鼓包 (11,10.5) r3.8，弧线顺滑闭合
                                                            ctx.beginPath()
                                                            ctx.moveTo(2.0, 14)
                                                            ctx.lineTo(12.49, 14)
                                                            ctx.arc(11, 10.5, 3.8, 1.168, -2.006, true)   // 右侧上行翻过小包顶
                                                            ctx.arc(6, 10, 4.5, -0.716, 2.15, true)       // 越谷扫过大包顶到左侧
                                                            ctx.quadraticCurveTo(2.0, 13.9, 2.0, 14)      // 左下角微圆收口
                                                            ctx.closePath()
                                                            // 缺口：沿云体路径 stroke 打孔（先于云体 fill，fill 会盖回内侧一半）
                                                            ctx.globalCompositeOperation = "destination-out"
                                                            ctx.strokeStyle = "#000000"
                                                            ctx.lineWidth = 2.4
                                                            ctx.lineCap = "round"
                                                            ctx.lineJoin = "round"
                                                            ctx.stroke()
                                                            ctx.globalCompositeOperation = "source-over"
                                                            ctx.fill()
                                                        }
                                                        Connections {
                                                            target: hourlySegmented
                                                            function onSegmentChanged() { cloudSunCanvas.requestPaint() }
                                                        }
                                                        Component.onCompleted: requestPaint()
                                                        Accessible.ignored: true
                                                    }
                                                }
                                                onClicked: hourlySegmented.segment = 0
                                                Accessible.name: qsTr("Hourly conditions")
                                            }
                                            AbstractButton {
                                                x: 44
                                                width: 44
                                                height: 36
                                                background: null
                                                // ref-main 实测降水段为实心水滴 6×9px@814（胶囊高 25px），我方胶囊 36px 按 1.44 折算 ≈ 9×13
                                                // Control 会覆写 contentItem 几何，Canvas 需包 Item 再居中（ref 胶囊中心 225 vs 水滴中心 225.5 居中）
                                                // LEDGER 仍差 15：ref 水滴墨/胶囊高比 0.386，canvas 12×16→15×20（×1.25），墨迹 8×11→~10×14
                                                contentItem: Item {
                                                    anchors.fill: parent
                                                    Canvas {
                                                        id: dropCanvas
                                                        width: 15
                                                        height: 20
                                                        anchors.centerIn: parent
                                                        antialiasing: true
                                                        onPaint: {
                                                            var ctx = getContext("2d")
                                                            ctx.reset()
                                                            ctx.beginPath()
                                                            ctx.moveTo(7.5, 1.9)
                                                            ctx.bezierCurveTo(10.25, 6.25, 12.5, 9.5, 12.5, 13.1)  // 右侧下行到圆右端
                                                            ctx.arc(7.5, 13.1, 5, 0, Math.PI, false)              // 经底部从右到左
                                                            ctx.bezierCurveTo(2.5, 9.5, 4.75, 6.25, 7.5, 1.9)     // 左侧收回尖点
                                                            ctx.closePath()
                                                            ctx.fillStyle = hourlySegmented.segment === 1 ? "#ffffff" : Qt.rgba(1, 1, 1, 0.9)
                                                            ctx.fill()
                                                        }
                                                        // segment 属于外层 hourlySegmented，Canvas 上无法直接写 onSegmentChanged
                                                        //（qmllint: no matching signal，运行时不触发），改用 Connections 监听后重绘
                                                        Connections {
                                                            target: hourlySegmented
                                                            function onSegmentChanged() { dropCanvas.requestPaint() }
                                                        }
                                                        Component.onCompleted: requestPaint()
                                                        Accessible.ignored: true
                                                    }
                                                }
                                                onClicked: hourlySegmented.segment = 1
                                                Accessible.name: qsTr("Hourly precipitation")
                                            }
                                            AbstractButton {
                                                x: 88
                                                width: 44
                                                height: 36
                                                background: null
                                                // ref SF wind：三道横向流线，右端卷成小螺旋，整体重心居中
                                                contentItem: Item {
                                                    anchors.fill: parent
                                                    Canvas {
                                                        id: windCanvas
                                                        width: 16
                                                        height: 13
                                                        anchors.centerIn: parent
                                                        antialiasing: true
                                                        onPaint: {
                                                            var ctx = getContext("2d")
                                                            ctx.reset()
                                                            ctx.strokeStyle = hourlySegmented.segment === 2 ? "#ffffff" : Qt.rgba(1, 1, 1, 0.9)
                                                            ctx.lineWidth = 1.8
                                                            ctx.lineCap = "round"
                                                            ctx.lineJoin = "round"
                                                            ctx.beginPath()
                                                            // 上线：右端 r2 向上卷
                                                            ctx.moveTo(2.0, 3.4)
                                                            ctx.quadraticCurveTo(6.0, 3.65, 10.0, 3.4)
                                                            ctx.arc(10.0, 1.4, 2.0, Math.PI / 2, 0, true)
                                                            // 中线：最长，右端 r2.4 卷
                                                            ctx.moveTo(1.5, 7.2)
                                                            ctx.quadraticCurveTo(6.5, 6.95, 12.3, 7.2)
                                                            ctx.arc(12.3, 4.8, 2.4, Math.PI / 2, -0.4, true)
                                                            // 下线：短，右端小卷
                                                            ctx.moveTo(3.0, 11.2)
                                                            ctx.quadraticCurveTo(5.5, 11.4, 8.0, 11.2)
                                                            ctx.arc(8.0, 9.6, 1.6, Math.PI / 2, 0.3, true)
                                                            ctx.stroke()
                                                        }
                                                        Connections {
                                                            target: hourlySegmented
                                                            function onSegmentChanged() { windCanvas.requestPaint() }
                                                        }
                                                        Component.onCompleted: requestPaint()
                                                        Accessible.ignored: true
                                                    }
                                                }
                                                onClicked: hourlySegmented.segment = 2
                                                Accessible.name: qsTr("Hourly wind")
                                            }
                                        }
                                    }

                                    Flickable {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 142
                                        contentWidth: hourlyRow.implicitWidth
                                        contentHeight: height
                                        boundsBehavior: Flickable.StopAtBounds
                                        clip: true

                                        ScrollBar.horizontal: ScrollBar {}

                                        // ref-main（参考图）Conditions 卡本无温度曲线；本条系 TASK.md
                                        // 用户裁定（2026-10-18）按 Apple Weather 惯例外推。
                                        // 布局适配：温度墨底 content 96（real 362）、☂ 行墨顶
                                        // content 114-115（real 380-381，Pillow 实测
                                        // tmp/shots/patrol-1792320265.png），真实空档为 96..115。
                                        // 曲线带 100..110 渲染于 real 365..377（content→real
                                        // 偏移实测 +266），与温度墨/☂ 墨各留 2-3px。旧值 97..113
                                        // 系行高钉死/列密度改动前的旧测量、带值未随动，导致曲线
                                        // 左端压到温度墨上（同一截图实证）。曲线带据此落位。
                                        // 层位：Canvas 位于 Flickable 内容区内部、Row 之前声明（先声明者
                                        // 先画、z 序在下），随 contentX 一起横滚覆盖逐小时列。
                                        Canvas {
                                            id: hourlyCurve

                                            readonly property int bandTop: 100
                                            readonly property int bandInner: 10
                                            readonly property int bandBottom: 110

                                            // draw-on 揭示动画：0..1，1 = 完整曲线。1000ms 系外推：
                                            // 内容揭示类动效，HIG 环境量级（阶段三 B.6，用户裁定 1）。
                                            property real drawProgress: 1.0
                                            Behavior on drawProgress {
                                                id: drawProgressBehavior
                                                NumberAnimation { duration: 1000; easing.type: Easing.OutCubic }
                                            }

                                            function replayDraw() {
                                                if (AppTheme.reduceMotion) {
                                                    // reduce-motion：永远完整曲线，动画不跑
                                                    drawProgressBehavior.enabled = false
                                                    drawProgress = 1
                                                    drawProgressBehavior.enabled = true
                                                    requestPaint()
                                                    return
                                                }
                                                // 先在 Behavior 关闭时归零（保证落 0），再开启 Behavior
                                                // 写 1 触发 0→1 动画；同块直写 0 再写 1 会被 Behavior
                                                // 重定向为 1→1 而吞掉动画。
                                                drawProgressBehavior.enabled = false
                                                drawProgress = 0
                                                requestPaint()
                                                drawProgressBehavior.enabled = true
                                                drawProgress = 1
                                            }

                                            x: 0
                                            y: 0
                                            width: hourlyRow.implicitWidth
                                            height: 142
                                            antialiasing: true
                                            visible: hourlySegmented.segment === 0
                                            Accessible.ignored: true

                                            onWidthChanged: requestPaint()
                                            onDrawProgressChanged: requestPaint()
                                            Component.onCompleted: replayDraw()

                                            Connections {
                                                target: root
                                                function onUpcomingHoursChanged() {
                                                    hourlyCurve.replayDraw()
                                                }
                                            }

                                            Connections {
                                                target: hourlySegmented
                                                function onSegmentChanged() {
                                                    if (hourlySegmented.segment === 0)
                                                        hourlyCurve.replayDraw()
                                                }
                                            }

                                            onPaint: {
                                                var ctx = hourlyCurve.getContext("2d")
                                                ctx.clearRect(0, 0, hourlyCurve.width, hourlyCurve.height)
                                                if (hourlyCurve.drawProgress <= 0)
                                                    return
                                                var pts = []
                                                for (var i = 0; i < root.upcomingHours.length; ++i) {
                                                    var t = root.number(root.upcomingHours[i], "temperature", NaN)
                                                    if (isFinite(t))
                                                        // 与委托 width 50 / Row spacing 10 联动：中心 x = 25，列距 60
                                                        pts.push({ x: 25 + i * 60, t: t })
                                                }
                                                if (pts.length < 2)
                                                    return
                                                var minT = pts[0].t
                                                var maxT = pts[0].t
                                                for (var j = 1; j < pts.length; ++j) {
                                                    minT = Math.min(minT, pts[j].t)
                                                    maxT = Math.max(maxT, pts[j].t)
                                                }
                                                function yFor(t) {
                                                    if (maxT === minT)
                                                        return hourlyCurve.bandTop + hourlyCurve.bandInner / 2
                                                    return hourlyCurve.bandTop
                                                        + (1 - (t - minT) / (maxT - minT)) * hourlyCurve.bandInner
                                                }
                                                var ys = []
                                                for (var k = 0; k < pts.length; ++k)
                                                    ys.push(yFor(pts[k].t))

                                                // 把二次贝塞尔路径展平为稠密折线，便于按累计弧长截断
                                                var samples = [{ x: pts[0].x, y: ys[0] }]
                                                for (var m = 1; m < pts.length - 1; ++m) {
                                                    var p0x = samples[samples.length - 1].x
                                                    var p0y = samples[samples.length - 1].y
                                                    var cx = pts[m].x
                                                    var cy = ys[m]
                                                    var p1x = (pts[m].x + pts[m + 1].x) / 2
                                                    var p1y = (ys[m] + ys[m + 1]) / 2
                                                    for (var s = 1; s <= 16; ++s) {
                                                        var u = s / 16
                                                        var a = (1 - u) * (1 - u)
                                                        var b = 2 * (1 - u) * u
                                                        var c = u * u
                                                        samples.push({
                                                            x: a * p0x + b * cx + c * p1x,
                                                            y: a * p0y + b * cy + c * p1y
                                                        })
                                                    }
                                                }
                                                samples.push({
                                                    x: pts[pts.length - 1].x,
                                                    y: ys[ys.length - 1]
                                                })

                                                var total = 0
                                                var segLen = []
                                                for (var d = 1; d < samples.length; ++d) {
                                                    var len = Math.hypot(samples[d].x - samples[d - 1].x,
                                                                         samples[d].y - samples[d - 1].y)
                                                    segLen.push(len)
                                                    total += len
                                                }
                                                var budget = total * Math.min(1, Math.max(0, hourlyCurve.drawProgress))
                                                var cutX = samples[samples.length - 1].x
                                                var cutY = samples[samples.length - 1].y
                                                var cutIdx = samples.length - 1
                                                if (budget < total) {
                                                    var acc = 0
                                                    for (var e = 0; e < segLen.length; ++e) {
                                                        if (acc + segLen[e] >= budget) {
                                                            var f = segLen[e] > 0 ? (budget - acc) / segLen[e] : 0
                                                            cutX = samples[e].x + (samples[e + 1].x - samples[e].x) * f
                                                            cutY = samples[e].y + (samples[e + 1].y - samples[e].y) * f
                                                            cutIdx = e
                                                            break
                                                        }
                                                        acc += segLen[e]
                                                    }
                                                }

                                                ctx.beginPath()
                                                ctx.moveTo(samples[0].x, samples[0].y)
                                                for (var g = 1; g <= cutIdx; ++g)
                                                    ctx.lineTo(samples[g].x, samples[g].y)
                                                ctx.lineTo(cutX, cutY)

                                                ctx.strokeStyle = "rgba(255,255,255,0.85)"
                                                ctx.lineWidth = 2
                                                ctx.lineJoin = "round"
                                                ctx.lineCap = "round"
                                                ctx.stroke()

                                                var grad = ctx.createLinearGradient(0, hourlyCurve.bandTop, 0, hourlyCurve.bandBottom)
                                                grad.addColorStop(0, "rgba(255,255,255,0.20)")
                                                grad.addColorStop(1, "rgba(255,255,255,0)")
                                                ctx.lineTo(cutX, hourlyCurve.bandBottom)
                                                ctx.lineTo(samples[0].x, hourlyCurve.bandBottom)
                                                ctx.closePath()
                                                ctx.fillStyle = grad
                                                ctx.fill()
                                            }
                                        }

                                        Row {
                                            id: hourlyRow
                                            height: parent.height - 12
                                            spacing: 10

                                            Repeater {
                                                model: root.upcomingHours

                                                delegate: Item {
                                                    id: hourlyCard

                                                    required property var modelData
                                                    required property int index
                                                    // ref-main Conditions 卡首列标签实测为 "Now"（当前小时），其余列为 localTime
                                                    readonly property bool isCurrentHour: {
                                                        const current = String(root.value(backend.current, "time", "")).substring(0, 13)
                                                        return current.length > 0
                                                            && String(root.value(hourlyCard.modelData, "time", "")).substring(0, 13) === current
                                                    }
                                                    // ref-main 实测小时列中心距 41px@814 × 1.4598 ≈ 60px（含 Row spacing 10）
                                                    width: 50
                                                    height: hourlyRow.height
                                                    opacity: 0
                                                    transform: Translate { id: entranceShift; y: 14 }

                                                    Component.onCompleted: {
                                                        if (AppTheme.reduceMotion) {
                                                            hourlyCard.opacity = 1
                                                            entranceShift.y = 0
                                                            iconBounceShift.y = 0
                                                            return
                                                        }
                                                        entranceAnim.restart()
                                                        iconBounceAnim.restart()
                                                    }

                                                    SequentialAnimation {
                                                        id: entranceAnim
                                                        PauseAnimation { duration: 40 * hourlyCard.index }
                                                        ParallelAnimation {
                                                            NumberAnimation { target: hourlyCard; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutCubic }
                                                            NumberAnimation { target: entranceShift; property: "y"; to: 0; duration: 260; easing.type: Easing.OutCubic }
                                                        }
                                                    }

                                                    SequentialAnimation {
                                                        id: iconBounceAnim
                                                        PauseAnimation { duration: 300 + 40 * hourlyCard.index }
                                                        NumberAnimation { target: iconBounceShift; property: "y"; to: -6; duration: 110; easing.type: Easing.OutCubic }
                                                        NumberAnimation { target: iconBounceShift; property: "y"; to: 0; duration: 160; easing.type: Easing.OutBack }
                                                    }

                                                    ColumnLayout {
                                                        anchors.fill: parent
                                                        spacing: 4

                                                        Label {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            // CJK 回退字形行盒高于数字（"现在"墨高 274-285 vs "17:00" 274-283），钉死行高防列内重排
                                                            Layout.preferredHeight: Math.ceil(font.pixelSize * 1.5)
                                                            verticalAlignment: Text.AlignVCenter
                                                            text: hourlyCard.isCurrentHour ? qsTr("Now")
                                                                : root.localTime(root.value(hourlyCard.modelData, "time", ""))
                                                            color: root.skyTextMuted
                                                        }

                                                        WeatherIcon {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            Layout.preferredWidth: 26
                                                            Layout.preferredHeight: 26
                                                            code: root.number(hourlyCard.modelData, "weatherCode", -1)
                                                            isDay: Boolean(root.value(hourlyCard.modelData, "isDay", true))
                                                            pulse: backend.loading && !AppTheme.reduceMotion
                                                            transform: Translate { id: iconBounceShift; y: 0 }
                                                            Accessible.ignored: true
                                                        }

                                                        Label {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            visible: hourlySegmented.segment === 0
                                                            // Ref hourly temps are unitless degrees ("68°"); the unit lives in the
                                                            // card subtitle "Temperature (°C)" only (see :2369).
                                                            text: Math.round(root.number(
                                                                hourlyCard.modelData, "temperature", 0)) + "°"
                                                            color: root.skyText
                                                            font.weight: Font.DemiBold
                                                        }

                                                        Label {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            visible: hourlySegmented.segment === 1
                                                            text: Math.round(root.number(
                                                                hourlyCard.modelData,
                                                                "precipitationProbability", 0)) + "%"
                                                            color: root.skyText
                                                            font.weight: Font.DemiBold
                                                            Accessible.name: qsTr("%1% chance of precipitation").arg(
                                                                Math.round(root.number(hourlyCard.modelData,
                                                                                       "precipitationProbability", 0)))
                                                        }

                                                        // 实测风段 "12 千米/时" ~70px 超出 50px 列宽（tmp/shots/windseg-probe-1792318936.png），
                                                        // 数字/单位分两行，单位行占用 segment 2 下 ☂ 占位行空出的位置、净行高不变；
                                                        // ref 无风段形态，两行结构系外推（Apple hourly wind 视图惯例数字大/单位小）
                                                        ColumnLayout {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            visible: hourlySegmented.segment === 2
                                                            spacing: 1
                                                            Accessible.name: qsTr("Wind speed %1 %2").arg(
                                                                Math.round(root.number(hourlyCard.modelData, "windSpeed", 0)))
                                                                                .arg(root.speedUnit)

                                                            Label {
                                                                Layout.alignment: Qt.AlignHCenter
                                                                text: Math.round(root.number(
                                                                    hourlyCard.modelData, "windSpeed", 0))
                                                                color: root.skyText
                                                                font.weight: Font.DemiBold
                                                            }

                                                            Label {
                                                                Layout.alignment: Qt.AlignHCenter
                                                                text: root.speedUnit
                                                                color: root.skyTextMuted
                                                                font.pixelSize: 10
                                                            }
                                                        }

                                                        Label {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            // ref-main Conditions 卡无 ☂ 行（可见小时全 0%）：0% 隐文字但保留占位，防 ColumnLayout 重排使温度行下坠（最小 repro 实证）
                                                            visible: hourlySegmented.segment === 0
                                                            text: Math.round(root.number(hourlyCard.modelData, "precipitationProbability", 0)) > 0
                                                                ? "☂︎  " + Math.round(root.number(hourlyCard.modelData, "precipitationProbability", 0)) + "%"
                                                                : ""
                                                            color: root.skyTextMuted
                                                            font.pixelSize: 10
                                                            Accessible.name: Math.round(root.number(hourlyCard.modelData, "precipitationProbability", 0)) > 0
                                                                ? qsTr("%1% chance of precipitation").arg(Math.round(root.number(hourlyCard.modelData, "precipitationProbability", 0)))
                                                                : ""
                                                        }
                                                    }
                                                }
                                            }
                                    }
                                        }
                                }
                            }

                            KosCard {
                                id: dailyCard
                                // ref-main 实测：10 天卡与 Conditions 同右列（x519-760），Conditions 底 y≈317 → 10 天卡顶 y≈329，gap ~12px@814 × 1.4598 ≈ 17.5 → rowSpacing 16 吻合（masonry 步骤 c）
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.preferredWidth: 0
                                Layout.alignment: Qt.AlignTop
                                Layout.preferredHeight: dailyColumn.implicitHeight + padding * 2

                                HoverHandler { id: dailyHover }
                                property bool cardHot: dailyHover.hovered
                                property real hoverFill: cardHot ? root.cardGlassAlphaHot : root.cardGlassAlpha
                                Behavior on hoverFill { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                                property real hoverStroke: cardHot ? 0.32 : 0.22
                                Behavior on hoverStroke { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                                transform: Translate {
                                    y: AppTheme.reduceMotion ? 0 : (dailyCard.cardHot ? -3 : 0)
                                    Behavior on y { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                                }

                                background: KosSurface {
                                    radius: 20
                                    fillColor: Qt.rgba(root.cardGlassRgb.r, root.cardGlassRgb.g, root.cardGlassRgb.b, dailyCard.hoverFill)
                                    strokeWidth: 1
                                    strokeColor: Qt.rgba(1, 1, 1, dailyCard.hoverStroke)
                                    elevation: 0
                                }

                                contentItem: ColumnLayout {
                                    id: dailyColumn
                                    spacing: 0

                                    // ref-ipad-small.png 实测：10 天卡头部 "10-DAY FORECAST" 在卡内顶部——
                                    // calendar glyph + caps 字距 muted 文本（文本带 y321-329、glyph x276-284、与文字同色）；
                                    // ref-main 该卡被窗底裁切无头部可见，以 ipad 参考为准。
                                    // 文案照参考 "10-Day Forecast"（数据上限 7 天，差异记 LEDGER）。
                                    // 头部→首行 ink gap：ipad 参考实测 29px（头部墨底 y328 → Today 墨顶 y357），我方实测 33px（patrol-1792318394：头部墨底 y471 → 今天墨顶 y504），bottomMargin 8→4 收敛 +4px。
                                    RowLayout {
                                        spacing: 6
                                        Layout.fillWidth: true
                                        Layout.bottomMargin: 4
                                        visible: backend.daily.length > 0

                                        Canvas {
                                            width: 12
                                            height: 12
                                            Accessible.ignored: true

                                            onPaint: {
                                                const ctx = getContext("2d")
                                                ctx.clearRect(0, 0, width, height)
                                                ctx.strokeStyle = root.skyTextMuted
                                                ctx.lineWidth = 1.2
                                                // 圆角方框（calendar 外形）：x1.5..10.5、y1.5..10.5，radius 3
                                                ctx.beginPath()
                                                ctx.moveTo(4.5, 1.5)
                                                ctx.lineTo(7.5, 1.5)
                                                ctx.arcTo(10.5, 1.5, 10.5, 4.5, 3)
                                                ctx.lineTo(10.5, 7.5)
                                                ctx.arcTo(10.5, 10.5, 7.5, 10.5, 3)
                                                ctx.lineTo(4.5, 10.5)
                                                ctx.arcTo(1.5, 10.5, 1.5, 7.5, 3)
                                                ctx.lineTo(1.5, 4.5)
                                                ctx.arcTo(1.5, 1.5, 4.5, 1.5, 3)
                                                ctx.closePath()
                                                ctx.stroke()
                                                // 框内两条横线（calendar 行）：y=4.8 与 y=7.6，x 3.6..8.4
                                                ctx.beginPath()
                                                ctx.moveTo(3.6, 4.8)
                                                ctx.lineTo(8.4, 4.8)
                                                ctx.moveTo(3.6, 7.6)
                                                ctx.lineTo(8.4, 7.6)
                                                ctx.stroke()
                                            }
                                        }

                                        Label {
                                            text: qsTr("10-Day Forecast").toLocaleUpperCase(Qt.locale())
                                            color: root.skyTextMuted
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            font.letterSpacing: 1.4
                                            Accessible.name: qsTr("10-day forecast")
                                        }
                                    }

                                    KosEmptyState {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 130
                                        visible: backend.daily.length === 0
                                        symbol: "☂"
                                        titleColor: root.skyText
                                        descriptionColor: root.skyTextMuted
                                        title: qsTr("Daily forecast unavailable")
                                        description: qsTr("Cached current conditions can still be used.")
                                    }

                                    Repeater {
                                        model: backend.daily

                                        delegate: Item {
                                            id: dailyRow

                                            required property int index
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 54

                                            readonly property real dayMinimum: root.number(
                                                dailyRow.modelData, "temperatureMinimum", 0)
                                            readonly property real dayMaximum: root.number(
                                                dailyRow.modelData, "temperatureMaximum", 0)
                                            readonly property real rangeSpan: root.dailyRange.maximum
                                                - root.dailyRange.minimum
                                            readonly property real uMin: root.clamp(
                                                (dailyRow.dayMinimum - root.dailyRange.minimum)
                                                    / dailyRow.rangeSpan, 0, 1)
                                            readonly property real uMax: root.clamp(
                                                (dailyRow.dayMaximum - root.dailyRange.minimum)
                                                    / dailyRow.rangeSpan, 0, 1)
                                            readonly property real uCurrent: dailyRow.index === 0
                                                ? root.clamp(
                                                    (root.number(backend.current, "temperature", Number.NaN)
                                                        - root.dailyRange.minimum) / dailyRow.rangeSpan,
                                                    0, 1)
                                                : 0
                                            readonly property int precipChance: Math.round(root.number(
                                                dailyRow.modelData, "precipitationProbability", 0))

                                            RowLayout {
                                                anchors.fill: parent
                                                spacing: 12

                                                Label {
                                                    Layout.preferredWidth: 88
                                                    text: root.dayLabel(root.value(
                                                        dailyRow.modelData, "date", ""), dailyRow.index)
                                                    color: root.skyText
                                                    font.weight: Font.DemiBold
                                                }

                                                Column {
                                                    spacing: 1

                                                    WeatherIcon {
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        width: 24
                                                        height: 24
                                                        code: root.number(dailyRow.modelData, "weatherCode", -1)
                                                        isDay: true
                                                        pulse: backend.loading && !AppTheme.reduceMotion
                                                        Accessible.ignored: true
                                                    }

                                                    // ref-main Fri 行 50% 峰值 (61,202,248)@814 降采样、纯百分数无伞 glyph
                                                    Label {
                                                        visible: dailyRow.precipChance > 0
                                                        text: dailyRow.precipChance + "%"
                                                        color: "#3dcaf8"
                                                        font.pixelSize: 10
                                                        Accessible.name: qsTr("%1% chance of precipitation").arg(
                                                            dailyRow.precipChance)
                                                    }
                                                }

                                                Label {
                                                    Layout.preferredWidth: 44
                                                    text: Math.round(dailyRow.dayMinimum) + "°"
                                                    color: root.skyTextMuted
                                                    horizontalAlignment: Text.AlignRight
                                                }

                                                Item {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 20

                                                    // ref-main 实测：10 天行无灰色轨道——渐变段单独落在 [uMin,uMax]，轨道位置为纯卡面色（Thu 行 x702-714 = (42,109,179)）
                                                    Rectangle {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        x: parent.width * dailyRow.uMin
                                                        width: Math.max(parent.width
                                                                        * (dailyRow.uMax - dailyRow.uMin), 14)
                                                        height: 5
                                                        radius: 2.5
                                                        gradient: Gradient {
                                                            orientation: Gradient.Horizontal
                                                            GradientStop {
                                                                position: 0
                                                                color: root.tempColor(dailyRow.dayMinimum)
                                                            }
                                                            GradientStop {
                                                                position: 1
                                                                color: root.tempColor(dailyRow.dayMaximum)
                                                            }
                                                        }
                                                    }

                                                    // Today 行当前温度标记（ref-main 实测：白点直径 ≈ 条高+1px，仅 Today 行有）
                                                    Rectangle {
                                                        visible: dailyRow.index === 0
                                                            && Number.isFinite(root.number(
                                                                backend.current, "temperature", Number.NaN))
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        x: parent.width * dailyRow.uCurrent - width / 2
                                                        width: 8
                                                        height: 8
                                                        radius: 4
                                                        color: "#ffffff"
                                                    }
                                                }

                                                Label {
                                                    Layout.preferredWidth: 44
                                                    text: Math.round(dailyRow.dayMaximum) + "°"
                                                    color: root.skyText
                                                    horizontalAlignment: Text.AlignLeft
                                                    font.weight: Font.DemiBold
                                                }
                                            }

                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.bottom: parent.bottom
                                                height: 1
                                                color: AppTheme.border
                                                visible: dailyRow.index < backend.daily.length - 1
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 6
                        text: qsTr("Weather data by Open-Meteo. Forecast times use the selected location's timezone.")
                        color: root.skyTextMuted
                        wrapMode: Text.WordWrap
                        font.pixelSize: 11
                    }
                }
            }
        }
    }

    KosWindowControls {
        targetWindow: root
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        z: 10
    }

    Item {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: root.sidebarExpanded ? 0 : 10
        width: root.sidebarExpanded ? sidebar.expandedWidth : AppTheme.controlHeight
        height: root.sidebarExpanded ? 46 : 44
        z: 10
        KosSidebarToggle {
            targetWindow: root
            anchors.right: parent.right
            anchors.rightMargin: root.sidebarExpanded ? 5 : 0
            anchors.top: parent.top
            anchors.topMargin: root.sidebarExpanded ? 10 : (44 - AppTheme.controlHeight) / 2
            implicitWidth: root.sidebarExpanded ? 26 : AppTheme.controlHeight
            implicitHeight: implicitWidth
            glyphColor: "#ffffff"
            glyphPaneColor: Qt.rgba(1, 1, 1, 0.95)
            background: Rectangle {
                radius: width / 2
                color: Qt.rgba(1, 1, 1, 0.14)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.22)
                Rectangle {
                    // specular top sheen, clipped to the circle
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.28) }
                        GradientStop { position: 0.22; color: Qt.rgba(1, 1, 1, 0) }
                    }
                }
            }
        }
    }
}
