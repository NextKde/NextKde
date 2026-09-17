/*
    SPDX-FileCopyrightText: 2026 KOS

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// The widget column: weather, the month, and a dial, stacked down the left
// edge the way the reference lock screen does it -- a rail of reports running
// parallel to the clock, not a second block of text fighting it for the
// centre.
//
// Everything here is white at some alpha and nothing else. Not because a
// monochrome lock screen is a style, but because these sit under a clock that
// is already the most colourful thing on the screen, and a second thing
// competing with it for colour is what makes a wallpaper look busy rather than
// composed. Colour is the clock's job; these report.
//
// The dial and the month need no data at all -- one reads the clock, the other
// reads the calendar -- which is the point: the greeter can reach neither the
// shell's services nor a file (see LockScreen.qml), so anything on this screen
// has to be computed from what QtQuick itself can see. The weather is the
// exception and it is optional: it renders only if a `LockFeed.qml` exists
// next to this file, which is something the desktop writes when it is
// installed. No file, no weather, no gap.
Item {
    id: widgets

    property date now: new Date()

    // Written by the desktop, not by this package. See LockScreen.qml. The
    // names match what the Dock's weather page reads, so the two views of the
    // same data cannot drift apart.
    property string feedSymbol: feed.item ? String(feed.item.weatherSymbol ?? "") : ""
    property string feedTemperature: feed.item ? String(feed.item.weatherTemperature ?? "") : ""
    property string feedCity: feed.item ? String(feed.item.weatherCity ?? "") : ""
    property string feedCondition: feed.item ? String(feed.item.weatherCondition ?? "") : ""
    property string feedApparent: feed.item ? String(feed.item.weatherApparent ?? "") : ""
    property string feedHumidity: feed.item ? String(feed.item.weatherHumidity ?? "") : ""

    readonly property bool hasWeather: feedSymbol !== "" || feedTemperature !== ""

    // One knob for the whole rail: everything below -- type, spacing, the dial,
    // the calendar cells -- is a fraction of this, so the column can be scaled
    // without retuning six independent numbers.
    readonly property int unit: 120
    readonly property int dialSize: Math.round(widgets.unit * 0.85)
    readonly property int temperatureSize: Math.round(widgets.unit * 0.24)
    readonly property int symbolSize: Math.round(widgets.unit * 0.26)
    readonly property int bodySize: Math.round(widgets.unit * 0.115)
    readonly property int smallSize: Math.round(widgets.unit * 0.098)
    readonly property int cellSize: Math.round(widgets.unit * 0.135)

    readonly property var weekdayHeader: ["一", "二", "三", "四", "五", "六", "日"]

    readonly property var monthGrid: {
        const first = new Date(widgets.now.getFullYear(), widgets.now.getMonth(), 1)
        const start = (first.getDay() + 6) % 7          // Monday first.
        const days = new Date(widgets.now.getFullYear(),
                              widgets.now.getMonth() + 1, 0).getDate()
        const cells = []
        for (let i = 0; i < start; ++i)
            cells.push(0)
        for (let day = 1; day <= days; ++day)
            cells.push(day)
        while (cells.length % 7 !== 0)
            cells.push(0)
        return cells
    }

    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight
    width: implicitWidth
    height: implicitHeight

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            widgets.now = new Date()
            dial.requestPaint()
        }
    }

    // Optional, and loaded rather than declared: a missing or broken feed is
    // the weather not being shown, not a lock screen that fails to draw.
    Loader {
        id: feed
        source: "LockFeed.qml"
    }

    Row {
        id: column

        spacing: Math.round(widgets.unit * 0.30)
        anchors.verticalCenter: parent.verticalCenter

        // The weather, when the desktop has left one for us. Same information
        // the Dock's weather page gives -- what a glance is actually for --
        // plus the next three days, because a temperature on its own is not
        // weather, it is a number.
        // Left: the temperature. Right: the numbers that qualify it. They sit
        // side by side rather than stacked, so the column stays a row of
        // reports at the same height as the dial instead of growing into a
        // paragraph.
        Row {
            spacing: Math.round(widgets.unit * 0.16)
            visible: widgets.hasWeather

            Column {
                spacing: Math.round(widgets.unit * 0.02)
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    spacing: Math.round(widgets.unit * 0.06)
                    anchors.horizontalCenter: parent.horizontalCenter

                    Text {
                        text: widgets.feedSymbol
                        color: Qt.rgba(1, 1, 1, 0.90)
                        font.pixelSize: widgets.symbolSize
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: widgets.feedTemperature
                        color: Qt.rgba(1, 1, 1, 0.92)
                        font.pixelSize: widgets.temperatureSize
                        font.weight: Font.Medium
                    }
                }

                Text {
                    text: widgets.feedCity
                        + (widgets.feedCondition !== "" ? " · " + widgets.feedCondition : "")
                    color: Qt.rgba(1, 1, 1, 0.72)
                    font.pixelSize: widgets.bodySize
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            Column {
                spacing: Math.round(widgets.unit * 0.03)
                anchors.verticalCenter: parent.verticalCenter
                visible: widgets.feedApparent !== "" || widgets.feedHumidity !== ""

                Text {
                    text: "体感 " + widgets.feedApparent
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.pixelSize: widgets.smallSize
                    visible: widgets.feedApparent !== ""
                }

                Text {
                    text: "湿度 " + widgets.feedHumidity
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.pixelSize: widgets.smallSize
                    visible: widgets.feedHumidity !== ""
                }
            }
        }

        // The month. A grid rather than a prose date, because the clock above
        // already says "星期四 9月17日" in type this column could never match:
        // what is left for a calendar to add is the shape of the month around
        // today.
        Column {
            spacing: 4

            Row {
                spacing: 6

                Repeater {
                    model: widgets.weekdayHeader

                    delegate: Text {
                        text: modelData
                        width: widgets.cellSize
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Math.max(9, widgets.smallSize - 2)
                        color: Qt.rgba(1, 1, 1, 0.38)
                    }
                }
            }

            Grid {
                columns: 7
                columnSpacing: 6
                rowSpacing: 3

                Repeater {
                    model: widgets.monthGrid

                    delegate: Text {
                        text: modelData === 0 ? "" : String(modelData)
                        width: widgets.cellSize
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Math.max(10, widgets.smallSize)
                        color: modelData === widgets.now.getDate()
                            ? Qt.rgba(1, 1, 1, 0.95)
                            : Qt.rgba(1, 1, 1, 0.42)
                        font.weight: modelData === widgets.now.getDate()
                            ? Font.Bold : Font.Normal
                    }
                }
            }
        }

        // The dial. Canvas rather than a shader for the same reason everything
        // else on this screen is: it has to paint under a software renderer.
        Canvas {
            id: dial

            width: widgets.dialSize
            height: widgets.dialSize
            antialiasing: true
            anchors.verticalCenter: parent.verticalCenter

            onPaint: {
                const ctx = getContext("2d")
                const r = dial.width / 2
                ctx.reset()
                ctx.clearRect(0, 0, dial.width, dial.height)

                // A filled face, not an outline: this is a plate of the same
                // smoked glass as the password field, standing off the
                // wallpaper by the light it holds, and an outline alone reads
                // as a hole rather than as a thing.
                ctx.beginPath()
                ctx.arc(r, r, r - 1, 0, Math.PI * 2)
                ctx.fillStyle = "rgba(255,255,255,0.10)"
                ctx.fill()

                // The edge of the plate, a little brighter than the fill --
                // the same lit contour the rest of the glass on this screen
                // has, for the same reason.
                ctx.strokeStyle = "rgba(255,255,255,0.24)"
                ctx.lineWidth = 1
                ctx.stroke()

                // The hours. Numbers rather than ticks: at this size a dial
                // with only twelve marks is a stopwatch, and the point of the
                // widget is that it can be read as a clock rather than as a
                // decoration.
                ctx.fillStyle = "rgba(255,255,255,0.66)"
                ctx.font = Math.max(8, Math.round(dial.width * 0.115)) + "px sans-serif"
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"
                for (let hour = 1; hour <= 12; ++hour) {
                    const angle = (hour / 12) * Math.PI * 2 - Math.PI / 2
                    ctx.fillText(String(hour),
                                 r + Math.cos(angle) * r * 0.72,
                                 r + Math.sin(angle) * r * 0.72)
                }

                // The hands. Hours are not snapped to the hour: a dial that
                // only ever points at twelve numbers is a picture of a clock.
                const hours = widgets.now.getHours() % 12 + widgets.now.getMinutes() / 60
                const minutes = widgets.now.getMinutes()
                ctx.lineCap = "round"
                ctx.strokeStyle = "rgba(255,255,255,0.88)"
                ctx.lineWidth = Math.max(1.6, dial.width * 0.045)
                ctx.beginPath()
                ctx.moveTo(r, r)
                ctx.lineTo(r + Math.cos((hours / 12) * Math.PI * 2 - Math.PI / 2) * r * 0.46,
                           r + Math.sin((hours / 12) * Math.PI * 2 - Math.PI / 2) * r * 0.46)
                ctx.stroke()

                ctx.strokeStyle = "rgba(255,255,255,0.62)"
                ctx.lineWidth = Math.max(1.2, dial.width * 0.03)
                ctx.beginPath()
                ctx.moveTo(r, r)
                ctx.lineTo(r + Math.cos((minutes / 60) * Math.PI * 2 - Math.PI / 2) * r * 0.68,
                           r + Math.sin((minutes / 60) * Math.PI * 2 - Math.PI / 2) * r * 0.68)
                ctx.stroke()
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }
    }

    Component.onCompleted: dial.requestPaint()
}
