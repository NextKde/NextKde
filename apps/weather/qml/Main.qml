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
        if (weatherCode === 0) return isDay ? "☀" : "☾"
        if (weatherCode === 1 || weatherCode === 2) return isDay ? "⛅" : "☁"
        if (weatherCode === 3) return "☁"
        if (weatherCode === 45 || weatherCode === 48) return "≋"
        if ((weatherCode >= 51 && weatherCode <= 67)
                || (weatherCode >= 80 && weatherCode <= 82)) return "☔"
        if ((weatherCode >= 71 && weatherCode <= 77)
                || (weatherCode >= 85 && weatherCode <= 86)) return "❄"
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

    WeatherClient { id: backend }

    Timer {
        id: searchDebounce
        interval: 450
        onTriggered: backend.searchLocations(locationField.text)
    }

    Shortcut {
        sequence: StandardKey.Refresh
        onActivated: backend.refresh()
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 258
            color: AppTheme.withAlpha(AppTheme.sidebar, 0.92)
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

                Label {
                    Layout.topMargin: 8
                    text: qsTr("SAVED LOCATIONS")
                    color: AppTheme.mutedText
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
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

                    Label {
                        text: qsTr("Units")
                        color: AppTheme.mutedText
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: "°C"
                        checkable: true
                        checked: backend.units === "metric"
                        Accessible.name: qsTr("Use metric units")
                        onClicked: backend.setUnits("metric")
                    }

                    Button {
                        text: "°F"
                        checkable: true
                        checked: backend.units === "imperial"
                        Accessible.name: qsTr("Use imperial units")
                        onClicked: backend.setUnits("imperial")
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: backend.connected
                        ? qsTr("Service connected · Open-Meteo")
                        : qsTr("Offline cache · service disconnected")
                    color: backend.connected ? AppTheme.positive : AppTheme.warning
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
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
                        spacing: 2

                        Label {
                            text: root.locationName(backend.location)
                            color: AppTheme.text
                            font.pixelSize: 28
                            font.weight: Font.DemiBold
                        }

                        Label {
                            text: root.locationDetail(backend.location)
                            color: AppTheme.mutedText
                            visible: text.length > 0
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Label {
                        text: backend.stale ? qsTr("Cached") : root.updatedText()
                        color: backend.stale ? AppTheme.warning : AppTheme.mutedText
                    }

                    BusyIndicator {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        running: backend.loading
                        visible: running
                    }

                    Button {
                        text: qsTr("Refresh")
                        enabled: backend.connected && !backend.loading
                        Accessible.name: qsTr("Refresh weather forecast")
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
                    Layout.preferredHeight: 250

                    contentItem: Item {
                        KosEmptyState {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, implicitWidth)
                            height: implicitHeight
                            visible: !backend.ready
                            symbol: backend.loading ? "↻" : "☁"
                            title: backend.loading
                                ? qsTr("Loading the forecast") : qsTr("No forecast available")
                            description: backend.connected
                                ? qsTr("Refresh or choose another saved location.")
                                : qsTr("Start shell-data-service to fetch weather data.")
                            actionText: backend.connected ? qsTr("Refresh") : ""
                            actionEnabled: !backend.loading
                            onActionTriggered: backend.refresh()
                        }

                        RowLayout {
                            anchors.fill: parent
                            visible: backend.ready
                            spacing: 24

                            ColumnLayout {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 180
                                spacing: 2

                                Label {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.conditionSymbol(
                                        root.number(backend.current, "weatherCode", -1),
                                        Boolean(root.value(backend.current, "isDay", true)))
                                    color: AppTheme.accent
                                    font.pixelSize: 72
                                    Accessible.name: root.conditionText(
                                        root.number(backend.current, "weatherCode", -1))
                                }

                                Label {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.conditionText(
                                        root.number(backend.current, "weatherCode", -1))
                                    color: AppTheme.text
                                    font.pixelSize: 18
                                    font.weight: Font.DemiBold
                                }
                            }

                            ColumnLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 4

                                Label {
                                    text: Math.round(root.number(
                                        backend.current, "temperature", 0)) + root.temperatureUnit
                                    color: AppTheme.text
                                    font.pixelSize: 54
                                    font.weight: Font.Light
                                }

                                Label {
                                    text: qsTr("Feels like %1%2").arg(Math.round(root.number(
                                        backend.current, "apparentTemperature", 0))).arg(root.temperatureUnit)
                                    color: AppTheme.mutedText
                                }
                            }

                            Rectangle {
                                Layout.fillHeight: true
                                Layout.preferredWidth: 1
                                Layout.topMargin: 22
                                Layout.bottomMargin: 22
                                color: AppTheme.border
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                columns: 2
                                columnSpacing: 22
                                rowSpacing: 16

                                Label { text: qsTr("Humidity"); color: AppTheme.mutedText }
                                Label {
                                    text: Math.round(root.number(
                                        backend.current, "relativeHumidity", 0)) + "%"
                                    color: AppTheme.text
                                    font.weight: Font.DemiBold
                                }

                                Label { text: qsTr("Wind"); color: AppTheme.mutedText }
                                Label {
                                    text: Math.round(root.number(
                                        backend.current, "windSpeed", 0)) + " " + root.speedUnit
                                    color: AppTheme.text
                                    font.weight: Font.DemiBold
                                }

                                Label { text: qsTr("Direction"); color: AppTheme.mutedText }
                                Label {
                                    text: Math.round(root.number(
                                        backend.current, "windDirection", 0)) + "°"
                                    color: AppTheme.text
                                    font.weight: Font.DemiBold
                                }

                                Label { text: qsTr("Observed"); color: AppTheme.mutedText }
                                Label {
                                    text: root.localTime(root.value(backend.current, "time", ""))
                                    color: AppTheme.text
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }
                }

                Label {
                    text: qsTr("Hourly forecast")
                    color: AppTheme.text
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
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
                                        color: AppTheme.text
                                        font.pixelSize: 25
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
                                        text: qsTr("%1% rain").arg(Math.round(root.number(
                                            hourlyCard.modelData, "precipitationProbability", 0)))
                                        color: AppTheme.mutedText
                                        font.pixelSize: 10
                                    }
                                }
                            }
                        }
                    }
                }

                Label {
                    text: qsTr("Seven-day forecast")
                    color: AppTheme.text
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
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
                                        color: AppTheme.text
                                        font.pixelSize: 22
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: root.conditionText(root.number(
                                            dailyRow.modelData, "weatherCode", -1))
                                        color: AppTheme.mutedText
                                        elide: Text.ElideRight
                                    }

                                    Label {
                                        text: qsTr("%1% precipitation").arg(Math.round(root.number(
                                            dailyRow.modelData, "precipitationProbability", 0)))
                                        color: AppTheme.mutedText
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
