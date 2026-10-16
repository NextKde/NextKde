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
        radius: AppTheme.smallRadius
        color: Qt.rgba(1, 1, 1, 0.12)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.20)
        Accessible.role: Accessible.StaticText
        Accessible.name: metric.labelText + ": " + metric.valueText

        HoverHandler { id: metricHover }
        ToolTip.visible: metricHover.hovered
        ToolTip.text: metric.labelText

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 9

            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 10
                color: Qt.rgba(1, 1, 1, 0.16)

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
                    text: metric.labelText
                    color: root.skyTextMuted
                    font.pixelSize: 10
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

                x: -cloudW - 20
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

                    PauseAnimation { duration: modelData.phaseMs }
                    NumberAnimation {
                        from: -cloud.cloudW - 20
                        to: cloudFieldLayer.width + 20
                        duration: modelData.driftMs
                        easing.type: Easing.Linear
                    }
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

                KosTextField {
                    id: locationField
                    Layout.topMargin: 36
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredHeight: 30
                    cornerRadius: 15
                    // 阶段三功能层 Liquid Glass：specular 高光与细描边。
                    // 按参考图量得高光强度温和，用 liquidStrength 0.2 缩放。
                    materialForm: false
                    liquidFinish: true
                    liquidStrength: 0.2
                    glassColor: Qt.rgba(1, 1, 1, 0.22)
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
                            readonly property var summary: root.value(modelData, "summary", null)
                            readonly property var cardStops: root.skyStopsFor(
                                savedLocation.summary ? savedLocation.summary.weatherCode : 2,
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
                                border.width: 1
                                border.color: savedLocation.highlighted
                                    ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(1, 1, 1, 0.18)
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
                                    text: savedLocation.summary
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
                            font.pixelSize: 34
                            font.weight: Font.DemiBold
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: Math.round(root.number(backend.current, "temperature", 0)) + "°"
                            color: root.skyText
                            font.pixelSize: 160
                            font.weight: Font.Light
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.conditionText(root.number(backend.current, "weatherCode", -1))
                            color: root.skyText
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

                    KosCard {
                        id: airQualityCard
                        Layout.fillWidth: true
                        visible: !Number.isNaN(root.number(backend.airQuality, "usAqi", Number.NaN))

                        background: KosSurface {
                            radius: 14
                            fillColor: Qt.rgba(1, 1, 1, 0.16)
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
                                        ctx.fillStyle = Qt.rgba(1, 1, 1, 0.6)
                                        for (let row = 0; row < 3; ++row) {
                                            for (let col = 0; col < 3; ++col) {
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
                                text: Math.round(root.number(backend.airQuality, "usAqi", 0))
                                color: root.skyText
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                            }

                            Label {
                                text: root.value(backend.airQuality, "category", "")
                                visible: text.length > 0
                                color: root.skyText
                                font.pixelSize: 13
                            }

                            Item {
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
                                        stops: [
                                            GradientStop { position: 0.00; color: "#00de72" },
                                            GradientStop { position: 0.20; color: "#ffdf1d" },
                                            GradientStop { position: 0.35; color: "#ffa205" },
                                            GradientStop { position: 0.50; color: "#fd4530" },
                                            GradientStop { position: 0.65; color: "#e70d79" },
                                            GradientStop { position: 0.80; color: "#a207d6" },
                                            GradientStop { position: 1.00; color: "#80172b" }
                                        ]
                                    }
                                }

                                Rectangle {
                                    x: Math.max(0, Math.min(1, root.number(backend.airQuality, "usAqi", 0) / 300)) * (parent.width - 9)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 9
                                    height: 9
                                    radius: 4.5
                                    color: "#ffffff"
                                }
                            }

                            Label {
                                text: qsTr("Air quality index is %1, which is similar to yesterday at about this time.")
                                    .arg(Math.round(root.number(backend.airQuality, "usAqi", 0)))
                                color: root.skyTextMuted
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                    }

                    KosCard {
                        id: conditionsCard
                        Layout.fillWidth: true

                        HoverHandler { id: conditionsHover }
                        property bool cardHot: conditionsHover.hovered
                        property real hoverFill: cardHot ? 0.21 : 0.16
                        Behavior on hoverFill { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                        property real hoverStroke: cardHot ? 0.32 : 0.22
                        Behavior on hoverStroke { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                        transform: Translate {
                            y: AppTheme.reduceMotion ? 0 : (conditionsCard.cardHot ? -3 : 0)
                            Behavior on y { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                        }

                        background: KosSurface {
                            radius: 14
                            fillColor: Qt.rgba(1, 1, 1, conditionsCard.hoverFill)
                            strokeWidth: 1
                            strokeColor: Qt.rgba(1, 1, 1, conditionsCard.hoverStroke)
                            elevation: 0
                        }

                        contentItem: ColumnLayout {
                            spacing: 12

                            KosEmptyState {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: !backend.ready
                                symbol: backend.loading ? "↻" : "☁"
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
                                    columns: root.compact ? 2 : 4
                                    columnSpacing: 8
                                    rowSpacing: 8

                                    WeatherMetric {
                                        Layout.fillWidth: true
                                        symbol: "%"
                                        labelText: qsTr("Humidity")
                                        valueText: Math.round(root.number(
                                            backend.current, "relativeHumidity", 0)) + "%"
                                    }

                                    WeatherMetric {
                                        Layout.fillWidth: true
                                        symbol: "≋"
                                        labelText: qsTr("Wind")
                                        valueText: Math.round(root.number(
                                            backend.current, "windSpeed", 0)) + " " + root.speedUnit
                                    }

                                    Rectangle {
                                        id: directionTile
                                        Layout.fillWidth: true
                                        implicitHeight: 66
                                        radius: AppTheme.smallRadius
                                        color: Qt.rgba(1, 1, 1, 0.12)
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.20)

                                        property real windDir: root.number(backend.current, "windDirection", 0)
                                        // arrow points where the wind blows TO (Open-Meteo direction is where it comes FROM)
                                        property real flowAngle: (directionTile.windDir + 180) % 360
                                        property real gustVal: root.number(backend.current, "windGust", Number.NaN)
                                        property bool hasGust: Number.isFinite(gustVal)

                                        onWindDirChanged: compass.requestPaint()
                                        onFlowAngleChanged: compass.requestPaint()

                                        HoverHandler { id: directionHover }
                                        ToolTip.visible: directionHover.hovered
                                        ToolTip.text: qsTr("Direction")
                                        Accessible.role: Accessible.StaticText
                                        Accessible.name: qsTr("Direction") + ": " + Math.round(directionTile.windDir) + "° " + directionTile.cardinal
                                            + (directionTile.hasGust
                                                ? " " + qsTr("Gusts") + ": " + Math.round(directionTile.gustVal) + " " + root.speedUnit
                                                : "")

                                        property string cardinal: {
                                            var names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
                                            return names[Math.round(directionTile.windDir / 45) % 8]
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 8

                                            Item {
                                                Layout.preferredWidth: 46
                                                Layout.preferredHeight: 46

                                                Canvas {
                                                    id: compass
                                                    anchors.fill: parent
                                                    antialiasing: true
                                                    contextType: "2d"
                                                    onPaint: {
                                                        var ctx = getContext("2d")
                                                        ctx.reset()
                                                        var c = 23
                                                        ctx.strokeStyle = "rgba(255,255,255,0.30)"
                                                        ctx.lineWidth = 1
                                                        for (var i = 0; i < 36; i++) {
                                                            var a = i * Math.PI / 18
                                                            ctx.beginPath()
                                                            ctx.moveTo(c + Math.sin(a) * 15, c - Math.cos(a) * 15)
                                                            ctx.lineTo(c + Math.sin(a) * 19.5, c - Math.cos(a) * 19.5)
                                                            ctx.stroke()
                                                        }
                                                        ctx.fillStyle = "rgba(255,255,255,0.92)"
                                                        ctx.font = "600 7px sans-serif"
                                                        ctx.textAlign = "center"
                                                        ctx.textBaseline = "middle"
                                                        ctx.fillText("N", c, c - 21.5)
                                                        ctx.fillText("E", c + 21.5, c)
                                                        ctx.fillText("S", c, c + 21.5)
                                                        ctx.fillText("W", c - 21.5, c)
                                                        ctx.save()
                                                        ctx.translate(c, c)
                                                        ctx.rotate(directionTile.flowAngle * Math.PI / 180)
                                                        ctx.strokeStyle = "#ffffff"
                                                        ctx.fillStyle = "#ffffff"
                                                        ctx.lineWidth = 1.6
                                                        ctx.beginPath()
                                                        ctx.moveTo(0, -11)
                                                        ctx.lineTo(0, -19)
                                                        ctx.stroke()
                                                        ctx.beginPath()
                                                        ctx.moveTo(0, -23)      // tip
                                                        ctx.lineTo(-2.6, -18.4)
                                                        ctx.lineTo(2.6, -18.4)
                                                        ctx.closePath()
                                                        ctx.fill()
                                                        ctx.restore()
                                                    }
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1

                                                Label {
                                                    Layout.fillWidth: true
                                                    text: qsTr("Direction")
                                                    color: root.skyTextMuted
                                                    font.pixelSize: 10
                                                    elide: Text.ElideRight
                                                    Accessible.ignored: true
                                                }

                                                Label {
                                                    Layout.fillWidth: true
                                                    text: Math.round(directionTile.windDir) + "° " + directionTile.cardinal
                                                    color: root.skyText
                                                    font.pixelSize: 15
                                                    font.weight: Font.DemiBold
                                                    elide: Text.ElideRight
                                                    Accessible.ignored: true
                                                }

                                                Label {
                                                    Layout.fillWidth: true
                                                    visible: directionTile.hasGust
                                                    text: qsTr("Gusts: ") + Math.round(directionTile.gustVal) + " " + root.speedUnit
                                                          + " " + directionTile.cardinal
                                                    color: root.skyText
                                                    font.pixelSize: 10
                                                    font.weight: Font.DemiBold
                                                    elide: Text.ElideRight
                                                    Accessible.ignored: true
                                                }
                                            }
                                        }
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
                                        symbol: "☀"
                                        labelText: qsTr("UV Index")
                                        valueText: {
                                            const uv = root.number(backend.current, "uvIndex", NaN)
                                            return Number.isFinite(uv) ? String(Math.round(uv)) : "—"
                                        }
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

                                    Rectangle {
                                        id: moonPhaseTile
                                        Layout.fillWidth: true
                                        implicitHeight: 66
                                        radius: AppTheme.smallRadius
                                        color: Qt.rgba(1, 1, 1, 0.12)
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.20)

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

                                        onPhaseValChanged: moonCanvas.requestPaint()

                                        HoverHandler { id: moonHover }
                                        ToolTip.visible: moonHover.hovered
                                        ToolTip.text: qsTr("Moon Phase")
                                        Accessible.role: Accessible.StaticText
                                        Accessible.name: qsTr("Moon Phase") + ": " + moonPhaseTile.phaseName

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 8

                                            Item {
                                                Layout.preferredWidth: 46
                                                Layout.preferredHeight: 46

                                                Canvas {
                                                    id: moonCanvas
                                                    anchors.fill: parent
                                                    antialiasing: true
                                                    contextType: "2d"
                                                    onPaint: {
                                                        var ctx = getContext("2d")
                                                        ctx.reset()
                                                        var c = 23
                                                        var r = 17
                                                        // 暗面：整盘剪影（月亮相位剪影，同族白 0.14）
                                                        ctx.beginPath()
                                                        ctx.arc(c, c, r, 0, 2 * Math.PI)
                                                        ctx.fillStyle = "rgba(255,255,255,0.14)"
                                                        ctx.fill()
                                                        if (!moonPhaseTile.hasPhase)
                                                            return
                                                        // 亮面：外弧（盈月亮在右，亏月亮在左）+ 终止线半椭圆折线，一次成形
                                                        var p = ((moonPhaseTile.phaseVal % 1) + 1) % 1
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
                                                        ctx.fillStyle = "#f7f3dc"
                                                        ctx.fill()
                                                    }
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1

                                                Label {
                                                    Layout.fillWidth: true
                                                    text: qsTr("Moon Phase")
                                                    color: root.skyTextMuted
                                                    font.pixelSize: 10
                                                    elide: Text.ElideRight
                                                    Accessible.ignored: true
                                                }

                                                Label {
                                                    Layout.fillWidth: true
                                                    text: moonPhaseTile.phaseName
                                                    color: root.skyText
                                                    font.pixelSize: 15
                                                    font.weight: Font.DemiBold
                                                    elide: Text.ElideRight
                                                    Accessible.ignored: true
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Label {
                        text: qsTr("Hourly")
                        color: root.skyTextMuted
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        Accessible.name: qsTr("Hourly forecast")
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 142
                        contentWidth: hourlyRow.implicitWidth
                        contentHeight: height
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true

                        ScrollBar.horizontal: ScrollBar {}

                        Row {
                            id: hourlyRow
                            height: parent.height - 12
                            spacing: 10

                            Repeater {
                                model: root.upcomingHours

                                delegate: KosCard {
                                    id: hourlyCard

                                    required property var modelData
                                    required property int index
                                    width: 108
                                    height: hourlyRow.height
                                    padding: 12
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

                                    background: KosSurface {
                                        radius: 14
                                        fillColor: Qt.rgba(1, 1, 1, 0.20)
                                        strokeWidth: 1
                                        strokeColor: Qt.rgba(1, 1, 1, 0.22)
                                        elevation: 0
                                    }

                                    contentItem: ColumnLayout {
                                        spacing: 4

                                        Label {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: root.localTime(root.value(
                                                hourlyCard.modelData, "time", ""))
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
                                            text: Math.round(root.number(
                                                hourlyCard.modelData, "temperature", 0)) + root.temperatureUnit
                                            color: root.skyText
                                            font.weight: Font.DemiBold
                                        }

                                        Label {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "☂︎  " + Math.round(root.number(
                                                hourlyCard.modelData,
                                                "precipitationProbability", 0)) + "%"
                                            color: root.skyTextMuted
                                            font.pixelSize: 10
                                            Accessible.name: qsTr("%1% chance of precipitation").arg(
                                                Math.round(root.number(hourlyCard.modelData,
                                                                       "precipitationProbability", 0)))
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Label {
                        text: qsTr("7 days")
                        color: root.skyTextMuted
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        Accessible.name: qsTr("Seven-day forecast")
                    }

                    KosCard {
                        id: dailyCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: dailyColumn.implicitHeight + padding * 2

                        HoverHandler { id: dailyHover }
                        property bool cardHot: dailyHover.hovered
                        property real hoverFill: cardHot ? 0.21 : 0.16
                        Behavior on hoverFill { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                        property real hoverStroke: cardHot ? 0.32 : 0.22
                        Behavior on hoverStroke { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                        transform: Translate {
                            y: AppTheme.reduceMotion ? 0 : (dailyCard.cardHot ? -3 : 0)
                            Behavior on y { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                        }

                        background: KosSurface {
                            radius: 14
                            fillColor: Qt.rgba(1, 1, 1, dailyCard.hoverFill)
                            strokeWidth: 1
                            strokeColor: Qt.rgba(1, 1, 1, dailyCard.hoverStroke)
                            elevation: 0
                        }

                        contentItem: ColumnLayout {
                            id: dailyColumn
                            spacing: 0

                            KosEmptyState {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 130
                                visible: backend.daily.length === 0
                                symbol: "☂"
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

                                            Label {
                                                visible: dailyRow.precipChance > 0
                                                text: "☂︎ " + dailyRow.precipChance + "%"
                                                color: root.skyTextMuted
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

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width
                                                height: 5
                                                radius: 2.5
                                                color: Qt.rgba(1, 1, 1, 0.28)
                                            }

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
