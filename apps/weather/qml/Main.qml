pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

KosApplicationWindow {
    id: root

    modernDesign: true
    visible: true
    title: qsTr("Weather")

    readonly property string temperatureUnit: backend.units === "imperial" ? "°F" : "°C"
    readonly property string speedUnit: backend.units === "imperial" ? qsTr("mph") : qsTr("km/h")
    readonly property var upcomingHours: upcomingForecast()
    property string pendingLocationId: ""
    readonly property var skyStops: skyStopsFor(
        number(backend.current, "weatherCode", -1),
        Boolean(value(backend.current, "isDay", true)))
    readonly property color skyText: "#ffffff"
    readonly property color skyTextMuted: Qt.rgba(1, 1, 1, 0.66)
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

                ListView {
                    id: savedLocations
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitWidth: 0
                    Layout.fillHeight: true
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

                RowLayout {
                    Layout.fillWidth: true
                    Accessible.name: qsTr("Units")

                    ButtonGroup { id: unitsGroup }

                    KosToolButton {
                        text: "⚙"
                        font.pixelSize: 16
                        Accessible.name: qsTr("Weather settings")
                        ToolTip.visible: hovered
                        ToolTip.text: Accessible.name
                        onClicked: settingsDialog.open()
                    }

                    KosToolButton {
                        text: "↻"
                        font.pixelSize: 18
                        enabled: backend.connected && !backend.loading
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
                        text: "°C"
                        checkable: true
                        ButtonGroup.group: unitsGroup
                        checked: backend.units === "metric"
                        Accessible.role: Accessible.RadioButton
                        Accessible.checked: checked
                        Accessible.name: qsTr("Use metric units")
                        onClicked: backend.setUnits("metric")
                    }

                    KosButton {
                        text: "°F"
                        checkable: true
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
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 2

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
                        Layout.fillWidth: true

                        background: KosSurface {
                            radius: 14
                            fillColor: Qt.rgba(1, 1, 1, 0.16)
                            strokeWidth: 1
                            strokeColor: Qt.rgba(1, 1, 1, 0.22)
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

                                    WeatherMetric {
                                        Layout.fillWidth: true
                                        symbol: "↗"
                                        labelText: qsTr("Direction")
                                        valueText: Math.round(root.number(
                                            backend.current, "windDirection", 0)) + "°"
                                    }

                                    WeatherMetric {
                                        Layout.fillWidth: true
                                        symbol: "◷"
                                        labelText: qsTr("Observed")
                                        valueText: root.localTime(root.value(
                                            backend.current, "time", ""))
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
                                    width: 108
                                    height: hourlyRow.height
                                    padding: 12

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
                        Layout.fillWidth: true
                        Layout.preferredHeight: dailyColumn.implicitHeight + padding * 2

                        background: KosSurface {
                            radius: 14
                            fillColor: Qt.rgba(1, 1, 1, 0.16)
                            strokeWidth: 1
                            strokeColor: Qt.rgba(1, 1, 1, 0.22)
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
        anchors.margins: 10
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
                border.color: Qt.rgba(1, 1, 1, 0.20)
            }
        }
    }
}
