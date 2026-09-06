pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

KosApplicationWindow {
    id: root

    visible: true
    title: qsTr("Weather")

    readonly property string temperatureUnit: backend.units === "imperial" ? "°F" : "°C"
    readonly property string speedUnit: backend.units === "imperial" ? qsTr("mph") : qsTr("km/h")
    readonly property var upcomingHours: upcomingForecast()
    property string pendingLocationId: ""

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

    function conditionSymbol(code, isDay) {
        const weatherCode = Number(code)
        if (weatherCode === 0) return isDay ? "☀︎" : "☾"
        if (weatherCode === 1 || weatherCode === 2) return isDay ? "☀︎·☁︎" : "☁︎"
        if (weatherCode === 3) return "☁︎"
        if (weatherCode === 45 || weatherCode === 48) return "≋"
        if ((weatherCode >= 51 && weatherCode <= 67)
                || (weatherCode >= 80 && weatherCode <= 82)) return "☂︎"
        if ((weatherCode >= 71 && weatherCode <= 77)
                || (weatherCode >= 85 && weatherCode <= 86)) return "❄︎"
        if (weatherCode >= 95) return "ϟ"
        return "?"
    }

    function localTime(isoTime) {
        const match = String(isoTime ?? "").match(/T(\d{2}:\d{2})/)
        return match ? match[1] : "--:--"
    }

    function dayLabel(isoDate, index) {
        if (index === 0)
            return qsTr("Today")
        if (index === 1)
            return qsTr("Tomorrow")
        const parsed = new Date(String(isoDate) + "T12:00:00")
        return Number.isNaN(parsed.getTime())
            ? String(isoDate) : Qt.formatDate(parsed, "dddd")
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

    function updatedText() {
        if (backend.fetchedAt <= 0)
            return qsTr("Never updated")
        return qsTr("Updated %1").arg(Qt.formatDateTime(
            new Date(backend.fetchedAt), Locale.ShortFormat))
    }

    component WeatherMetric: Rectangle {
        id: metric

        required property string symbol
        required property string labelText
        required property string valueText

        implicitHeight: 66
        radius: AppTheme.smallRadius
        color: AppTheme.withAlpha(AppTheme.accent, AppTheme.dark ? 0.10 : 0.045)
        border.width: 1
        border.color: AppTheme.withAlpha(AppTheme.accent, AppTheme.dark ? 0.18 : 0.10)
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
                color: AppTheme.withAlpha(AppTheme.accent,
                                          AppTheme.dark ? 0.17 : 0.09)

                Label {
                    anchors.centerIn: parent
                    text: metric.symbol
                    color: AppTheme.accent
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
                    color: AppTheme.mutedText
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    Accessible.ignored: true
                }

                Label {
                    Layout.fillWidth: true
                    text: metric.valueText
                    color: AppTheme.text
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

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: root.compact ? AppTheme.compactSidebarWidth : AppTheme.sidebarWidth
            color: AppTheme.sidebarSurface
            border.width: 1
            border.color: AppTheme.border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 10

                Label {
                    text: qsTr("KOS Weather")
                    color: AppTheme.text
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    Layout.bottomMargin: 8
                }

                LiquidTextField {
                    id: locationField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Search locations…")
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
                    Layout.preferredHeight: visible ? Math.min(contentHeight, 220) : 0
                    visible: backend.searchResults.length > 0
                    clip: true
                    spacing: 3
                    model: backend.searchResults

                    delegate: ItemDelegate {
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
                }

                RowLayout {
                    Layout.topMargin: 8
                    Accessible.name: qsTr("Saved locations")

                    Label {
                        text: "●"
                        color: AppTheme.accent
                        font.pixelSize: 8
                        Accessible.ignored: true
                    }
                    Label {
                        text: qsTr("Locations")
                        color: AppTheme.mutedText
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        Accessible.ignored: true
                    }
                }

                ListView {
                    id: savedLocations
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: backend.locations

                    delegate: ItemDelegate {
                        id: savedLocation

                        required property var modelData
                        width: savedLocations.width
                        implicitHeight: 46
                        highlighted: String(root.value(modelData, "id", ""))
                            === String(root.value(backend.location, "id", ""))
                        Accessible.name: root.locationName(modelData)
                        onClicked: backend.selectLocation(modelData)

                        contentItem: RowLayout {
                            spacing: 8

                            Label {
                                text: savedLocation.highlighted ? "●" : "○"
                                color: savedLocation.highlighted
                                    ? AppTheme.accent : AppTheme.mutedText
                                font.pixelSize: 11
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Label {
                                    Layout.fillWidth: true
                                    text: root.locationName(savedLocation.modelData)
                                    color: AppTheme.text
                                    elide: Text.ElideRight
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: root.locationDetail(savedLocation.modelData)
                                    color: AppTheme.mutedText
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    visible: text.length > 0
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    ButtonGroup { id: unitsGroup }

                    Label {
                        text: "°"
                        color: AppTheme.mutedText
                        font.pixelSize: 17
                        Accessible.name: qsTr("Units")
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
                    text: backend.connected
                        ? "●  Open-Meteo"
                        : "○  " + qsTr("Offline cache")
                    color: backend.connected ? AppTheme.positive : AppTheme.warning
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    Accessible.name: backend.connected
                        ? qsTr("Weather service connected")
                        : qsTr("Weather service disconnected; showing offline cache")
                }
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: content.implicitHeight + AppTheme.pageMargin * 2
            clip: true

            ScrollBar.vertical: ScrollBar {}

            ColumnLayout {
                id: content
                x: AppTheme.pageMargin
                y: AppTheme.pageMargin
                width: parent.width - AppTheme.pageMargin * 2
                spacing: 16

                RowLayout {
                    Layout.fillWidth: true

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 120
                        spacing: 2

                        Label {
                            Layout.fillWidth: true
                            text: root.locationName(backend.location)
                            color: AppTheme.text
                            font.pixelSize: 28
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: root.locationDetail(backend.location)
                            color: AppTheme.mutedText
                            visible: text.length > 0
                            elide: Text.ElideRight
                        }
                    }

                    Label {
                        Layout.maximumWidth: 180
                        text: backend.stale ? qsTr("Cached") : root.updatedText()
                        color: backend.stale ? AppTheme.warning : AppTheme.mutedText
                        elide: Text.ElideRight
                    }

                    BusyIndicator {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        running: backend.loading
                        visible: running
                    }

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
                    Layout.preferredHeight: root.compact ? 292 : 250

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

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 22

                                ColumnLayout {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.preferredWidth: root.compact ? 145 : 180
                                    spacing: 0

                                    Label {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.conditionSymbol(
                                            root.number(backend.current, "weatherCode", -1),
                                            Boolean(root.value(backend.current, "isDay", true)))
                                        color: AppTheme.accent
                                        font.pixelSize: root.compact ? 54 : 64
                                        Accessible.name: root.conditionText(
                                            root.number(backend.current, "weatherCode", -1))
                                    }

                                    Label {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.conditionText(
                                            root.number(backend.current, "weatherCode", -1))
                                        color: AppTheme.text
                                        font.pixelSize: 17
                                        font.weight: Font.DemiBold
                                    }
                                }

                                ColumnLayout {
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 2

                                    Label {
                                        text: Math.round(root.number(
                                            backend.current, "temperature", 0)) + root.temperatureUnit
                                        color: AppTheme.accent
                                        font.pixelSize: root.compact ? 46 : 54
                                        font.weight: Font.Light
                                    }

                                    Label {
                                        text: "≈ " + Math.round(root.number(
                                            backend.current, "apparentTemperature", 0))
                                            + root.temperatureUnit
                                        color: AppTheme.mutedText
                                        Accessible.name: qsTr("Feels like %1%2").arg(
                                            Math.round(root.number(backend.current,
                                                                   "apparentTemperature", 0)))
                                            .arg(root.temperatureUnit)
                                    }
                                }

                                Item { Layout.fillWidth: true }
                            }

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
                    text: "◷  " + qsTr("Hourly")
                    color: AppTheme.text
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

                                contentItem: ColumnLayout {
                                    spacing: 4

                                    Label {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.localTime(root.value(
                                            hourlyCard.modelData, "time", ""))
                                        color: AppTheme.mutedText
                                    }

                                    Label {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.conditionSymbol(
                                            root.number(hourlyCard.modelData, "weatherCode", -1),
                                            Boolean(root.value(hourlyCard.modelData, "isDay", true)))
                                        color: AppTheme.accent
                                        font.pixelSize: 25
                                        Accessible.ignored: true
                                    }

                                    Label {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: Math.round(root.number(
                                            hourlyCard.modelData, "temperature", 0)) + root.temperatureUnit
                                        color: AppTheme.text
                                        font.weight: Font.DemiBold
                                    }

                                    Label {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "☂︎  " + Math.round(root.number(
                                            hourlyCard.modelData,
                                            "precipitationProbability", 0)) + "%"
                                        color: AppTheme.mutedText
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
                    text: "▦  " + qsTr("7 days")
                    color: AppTheme.text
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    Accessible.name: qsTr("Seven-day forecast")
                }

                KosCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: dailyColumn.implicitHeight + padding * 2

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

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 12

                                    Label {
                                        Layout.preferredWidth: 120
                                        text: root.dayLabel(root.value(
                                            dailyRow.modelData, "date", ""), dailyRow.index)
                                        color: AppTheme.text
                                        font.weight: Font.DemiBold
                                    }

                                    Label {
                                        text: root.conditionSymbol(root.number(
                                            dailyRow.modelData, "weatherCode", -1), true)
                                        color: AppTheme.accent
                                        font.pixelSize: 22
                                        Accessible.ignored: true
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: root.conditionText(root.number(
                                            dailyRow.modelData, "weatherCode", -1))
                                        color: AppTheme.mutedText
                                        elide: Text.ElideRight
                                    }

                                    Label {
                                        text: "☂︎  " + Math.round(root.number(
                                            dailyRow.modelData,
                                            "precipitationProbability", 0)) + "%"
                                        color: AppTheme.mutedText
                                        Accessible.name: qsTr("%1% chance of precipitation").arg(
                                            Math.round(root.number(dailyRow.modelData,
                                                                   "precipitationProbability", 0)))
                                    }

                                    Label {
                                        Layout.preferredWidth: 92
                                        text: Math.round(root.number(
                                            dailyRow.modelData, "temperatureMaximum", 0))
                                            + "°  /  " + Math.round(root.number(
                                                dailyRow.modelData, "temperatureMinimum", 0)) + "°"
                                        color: AppTheme.text
                                        horizontalAlignment: Text.AlignRight
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
                    color: AppTheme.mutedText
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                }
            }
        }
    }
}
