import QtQuick

Item {
    id: root

    required property var widgetSize
    required property var appearance
    required property var weatherData
    property var host: null
    property bool showAmbientArtwork: true
    property color primaryInk: "#ffffff"
    property color subtleInk: Qt.rgba(1, 1, 1, 0.74)
    property color accentInk: "#ffe36a"

    readonly property int spanCols: (widgetSize && widgetSize.length >= 2) ? Number(widgetSize[0]) : 2
    readonly property bool compact: spanCols <= 1

    readonly property bool isZh: String(appearance?.locale ?? "").toLowerCase().startsWith("zh")
    readonly property bool outlineText: Boolean(appearance?.transparent)
    readonly property int textStyle: outlineText ? Text.Outline : Text.Normal
    readonly property color textStyleColor: appearance?.isDark
        ? Qt.rgba(0, 0, 0, 0.58) : Qt.rgba(1, 1, 1, 0.68)

    readonly property string status: String(weatherData?.status ?? "unavailable")
    readonly property bool ready: status === "ready" || Boolean(weatherData?.available)
    readonly property bool loading: status === "loading" || Boolean(weatherData?.loading)

    readonly property int weatherCode: Number(weatherData?.weatherCode ?? 0)
    readonly property bool isDay: weatherData?.isDay !== false
    readonly property string conditionCategory: {
        const value = weatherCode
        if (value === 0) return "clear"
        if (value >= 1 && value <= 2) return "partlyCloudy"
        if (value === 3) return "overcast"
        if (value === 45 || value === 48) return "fog"
        if ((value >= 51 && value <= 67) || (value >= 80 && value <= 82)) return "rain"
        if ((value >= 71 && value <= 77) || value === 85 || value === 86) return "snow"
        if (value >= 95) return "storm"
        return "overcast"
    }
    readonly property bool isRainOrStorm: conditionCategory === "rain" || conditionCategory === "storm"
    readonly property bool isCloudy: conditionCategory === "partlyCloudy" || conditionCategory === "overcast"

    readonly property int forecastDayCount: compact ? 3 : 7
    readonly property var forecastList: {
        const raw = weatherData?.forecastDays
        if (!raw || typeof raw === "string" || typeof raw.length !== "number") return []
        const list = []
        for (let i = 0; i < Math.min(root.forecastDayCount, raw.length); ++i)
            list.push(raw[i])
        return list
    }
    readonly property string highLowText: {
        const raw = weatherData?.forecastDays
        if (!raw || typeof raw.length !== "number" || raw.length === 0) return ""
        const today = raw[0]
        if (today?.high === undefined || today?.high === null || today?.low === undefined || today?.low === null)
            return ""
        return (root.isZh ? "最高 " : "High ") + today.high + "°  " + (root.isZh ? "最低 " : "Low ") + today.low + "°"
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (!root.host || root.host.isPreview || typeof root.host.invokeAction !== "function")
                return
            const locId = String(root.weatherData?.locationId ?? "")
            root.host.invokeAction("app.open-weather", locId ? ({ location: locId }) : ({}))
        }
    }

    // ── Ambient atmospheric weather artwork (static, matching main) ──────
    Item {
        id: weatherArtworkLayer
        visible: root.ready && root.showAmbientArtwork
        anchors.fill: parent
        clip: true
        opacity: 0.34

        // Clear day sun with 8 rays
        Item {
            id: sunLayer
            visible: root.conditionCategory === "clear" && root.isDay
            width: root.compact ? 54 : 70
            height: width
            anchors { right: parent.right; top: parent.top; rightMargin: root.compact ? 10 : 20; topMargin: 5 }

            Repeater {
                model: 8
                delegate: Rectangle {
                    required property int index
                    width: 2
                    height: root.compact ? 9 : 12
                    radius: 1
                    color: "#ffe36a"
                    x: sunLayer.width / 2 - width / 2
                    y: 2
                    transform: Rotation {
                        origin.x: 1
                        origin.y: sunLayer.width / 2 - 2
                        angle: index * 45
                    }
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: root.compact ? 22 : 28
                height: width
                radius: width / 2
                color: "#ffe36a"
            }
        }

        // Clear night crescent & stars
        Item {
            visible: root.conditionCategory === "clear" && !root.isDay
            anchors.fill: parent

            Item {
                width: 40; height: 40
                anchors { right: parent.right; top: parent.top; rightMargin: 20; topMargin: 10 }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "#c8d9ff"
                }
                Rectangle {
                    width: 30; height: 30; radius: 15
                    x: 14; y: -2
                    color: "#1b2b5e"
                    opacity: 0.85
                }
            }
            Repeater {
                model: [
                    { rx: 0.56, ry: 0.16, s: 3 },
                    { rx: 0.68, ry: 0.34, s: 2 },
                    { rx: 0.44, ry: 0.28, s: 2.5 },
                    { rx: 0.78, ry: 0.42, s: 2 }
                ]
                delegate: Rectangle {
                    required property var modelData
                    width: modelData.s; height: modelData.s; radius: width / 2
                    x: parent.width * modelData.rx
                    y: parent.height * modelData.ry
                    color: "#dbeafe"
                }
            }
        }

        // Partly cloudy / overcast soft layered clouds
        Item {
            visible: root.isCloudy
            anchors.fill: parent

            Item {
                width: 96; height: 46
                anchors { right: parent.right; top: parent.top; rightMargin: 14; topMargin: 8 }
                Rectangle { width: 72; height: 22; radius: 11; x: 12; y: 20; color: Qt.rgba(1, 1, 1, 0.28) }
                Rectangle { width: 34; height: 34; radius: 17; x: 18; y: 6; color: Qt.rgba(1, 1, 1, 0.30) }
                Rectangle { width: 40; height: 40; radius: 20; x: 38; y: 2; color: Qt.rgba(1, 1, 1, 0.32) }
            }
            Item {
                visible: !root.compact
                width: 72; height: 34
                anchors { left: parent.left; top: parent.top; leftMargin: 28; topMargin: 18 }
                opacity: 0.55
                Rectangle { width: 54; height: 16; radius: 8; x: 8; y: 14; color: Qt.rgba(1, 1, 1, 0.24) }
                Rectangle { width: 26; height: 26; radius: 13; x: 16; y: 4; color: Qt.rgba(1, 1, 1, 0.26) }
            }
        }

        // Rain / storm slanted raindrops
        Item {
            visible: root.isRainOrStorm
            anchors.fill: parent

            Repeater {
                model: 9
                delegate: Rectangle {
                    required property int index
                    width: 1
                    height: 12
                    radius: 1
                    color: "#d9f1ff"
                    x: weatherArtworkLayer.width * (index + 0.4) / 9
                    y: 12 + (index % 3) * 18
                    rotation: -13
                }
            }
        }

        // Fog mist bands
        Item {
            visible: root.conditionCategory === "fog"
            anchors.fill: parent

            Repeater {
                model: 3
                delegate: Rectangle {
                    required property int index
                    width: weatherArtworkLayer.width * (0.54 + index * 0.09)
                    height: 10
                    radius: height / 2
                    x: -width * 0.15 + index * 24
                    y: 16 + index * 26
                    color: Qt.rgba(1, 1, 1, 0.20 - index * 0.035)
                }
            }
        }

        // Snow dots
        Item {
            visible: root.conditionCategory === "snow"
            anchors.fill: parent

            Repeater {
                model: 14
                delegate: Rectangle {
                    required property int index
                    width: index % 3 === 0 ? 4 : 2
                    height: width
                    radius: width / 2
                    x: weatherArtworkLayer.width * ((index * 37) % 100) / 100
                    y: 8 + (index * 19) % Math.max(1, weatherArtworkLayer.height - 12)
                    color: Qt.rgba(1, 1, 1, 0.62)
                }
            }
        }
    }

    // ── Loading / unavailable fallback ───────────────────────────────────
    Column {
        visible: !root.ready
        anchors.centerIn: parent
        width: Math.max(1, parent.width - 24)
        spacing: 4

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.loading
                ? (root.isZh ? "正在更新天气…" : "Updating weather…")
                : (root.isZh ? "天气不可用" : "Weather unavailable")
            color: root.primaryInk
            font { pixelSize: 13; weight: Font.DemiBold }
            style: root.textStyle
            styleColor: root.textStyleColor
        }
        Text {
            visible: String(root.weatherData?.errorMessage || root.weatherData?.sourceMessage || "").length > 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: String(root.weatherData?.errorMessage || root.weatherData?.sourceMessage || "")
            color: root.subtleInk
            font.pixelSize: 10
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            style: root.textStyle
            styleColor: root.textStyleColor
        }
    }

    // ── Ready state — unified main layout (1x1 / 2x1 / 3x1) ──────────────
    Item {
        visible: root.ready
        anchors.fill: parent

        Text {
            anchors {
                left: parent.left; top: parent.top
                leftMargin: root.compact ? 12 : 16
                topMargin: root.compact ? 10 : 12
                right: weatherConditionSymbol.left; rightMargin: 8
            }
            text: String(root.weatherData?.locationName || (root.isZh ? "本地" : "Local"))
            color: root.primaryInk
            font { pixelSize: root.compact ? 13 : 15; weight: Font.DemiBold }
            elide: Text.ElideRight
            style: root.textStyle
            styleColor: root.textStyleColor
        }

        Text {
            anchors {
                left: parent.left; top: parent.top
                leftMargin: root.compact ? 11 : 15
                topMargin: root.compact ? 25 : 29
            }
            text: String(root.weatherData?.temperatureText || "--°")
            color: root.primaryInk
            font {
                pixelSize: Math.min(root.compact ? 34 : 42, parent.height * 0.32,
                    Math.max(18, (parent.height - weeklyForecast.height - 38) / 1.4))
                weight: Font.Normal
            }
            style: root.textStyle
            styleColor: root.textStyleColor
        }

        Text {
            id: weatherConditionSymbol
            anchors {
                right: parent.right; top: parent.top
                rightMargin: root.compact ? 12 : 18
                topMargin: root.compact ? 10 : 14
            }
            text: String(root.weatherData?.conditionSymbol || "☀")
            color: root.accentInk
            font.pixelSize: root.compact ? 22
                : Math.min(34, parent.height * 0.26,
                    Math.max(18, (parent.height - weeklyForecast.height - 64) * 0.75))
            style: root.textStyle
            styleColor: root.textStyleColor
        }

        Text {
            anchors {
                right: parent.right
                rightMargin: root.compact ? 12 : 16
                top: weatherConditionSymbol.bottom
                topMargin: 2
            }
            text: String(root.weatherData?.conditionText || "")
            color: root.primaryInk
            font { pixelSize: root.compact ? 11 : 15; weight: Font.DemiBold }
            elide: Text.ElideRight
            style: root.textStyle
            styleColor: root.textStyleColor
        }

        Text {
            visible: !root.compact && root.highLowText.length > 0
            anchors {
                right: parent.right; bottom: weeklyForecast.top
                rightMargin: 16; bottomMargin: 3
            }
            text: root.highLowText
            color: root.subtleInk
            font.pixelSize: 11
            style: root.textStyle
            styleColor: root.textStyleColor
        }

        Item {
            id: weeklyForecast
            anchors {
                left: parent.left; right: parent.right; bottom: parent.bottom
                leftMargin: root.compact ? 8 : 10
                rightMargin: root.compact ? 8 : 10
                bottomMargin: 8
            }
            height: Math.min(root.compact ? 50 : 62, parent.height * 0.44)

            Repeater {
                model: root.forecastList
                delegate: Item {
                    required property var modelData
                    required property int index
                    readonly property int count: Math.max(1, root.forecastList.length)
                    x: index * weeklyForecast.width / count
                    width: weeklyForecast.width / count
                    height: weeklyForecast.height

                    Text {
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
                        width: parent.width - 2
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: String(modelData?.label ?? "")
                        color: root.subtleInk
                        font { pixelSize: root.compact ? 9 : 10; weight: Font.DemiBold }
                        style: root.textStyle
                        styleColor: root.textStyleColor
                    }
                    Text {
                        anchors.centerIn: parent
                        text: String(modelData?.symbol ?? "")
                        color: root.accentInk
                        font.pixelSize: root.compact ? 16 : 22
                        style: root.textStyle
                        styleColor: root.textStyleColor
                    }
                    Text {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                        width: parent.width - 2
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: (modelData?.high ?? "-") + "°/" + (modelData?.low ?? "-") + "°"
                        color: root.primaryInk
                        font { pixelSize: root.compact ? 9 : 10; weight: Font.DemiBold }
                        style: root.textStyle
                        styleColor: root.textStyleColor
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.forecastList.length === 0
                width: Math.max(0, parent.width - 12)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                text: (!root.weatherData?.sourceMessage ? "" : String(root.weatherData.sourceMessage))
                    || String(root.weatherData?.errorMessage || "")
                    || (root.loading
                        ? (root.isZh ? "正在加载 7 日预报…" : "Loading 7-day forecast…")
                        : (root.isZh ? "暂无 7 日预报" : "No 7-day forecast"))
                color: root.subtleInk
                font.pixelSize: 11
                style: root.textStyle
                styleColor: root.textStyleColor
            }
        }
    }
}
