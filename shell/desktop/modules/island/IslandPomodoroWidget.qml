import QtQuick
import "../../../shared/qml/i18n"

// IslandPomodoroWidget — ported from NookX's PomodoroMainView: a progress
// ring, the remaining time, the phase, and the transport controls. All
// state lives in IslandPomodoroService so the countdown keeps running
// while the island is collapsed.
Rectangle {
    id: root

    required property string widgetId

    readonly property var service: IslandPomodoroService
    readonly property real progress: service.phaseTotalMs > 0
        ? Math.min(1, Math.max(0, 1 - service.remainingMs / service.phaseTotalMs))
        : 0

    function formatMs(ms) {
        const total = Math.ceil(Math.max(0, ms) / 1000)
        const m = Math.floor(total / 60)
        const s = total % 60
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    }

    function phaseLabel() {
        if (service.phase === "short")
            return I18n.tr("Short break")
        if (service.phase === "long")
            return I18n.tr("Long break")
        return I18n.tr("Focus")
    }

    color: "transparent"

    Row {
        anchors.centerIn: parent
        spacing: 8

        Canvas {
            width: 40
            height: 40

            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, 40, 40)
                ctx.lineWidth = 3
                ctx.lineCap = "round"
                ctx.strokeStyle = "rgba(255,255,255,0.15)"
                ctx.beginPath()
                ctx.arc(20, 20, 15, 0, Math.PI * 2)
                ctx.stroke()
                ctx.strokeStyle = "rgba(74,222,128,0.9)"
                ctx.beginPath()
                ctx.arc(20, 20, 15, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * root.progress)
                ctx.stroke()
            }

            Connections {
                target: IslandPomodoroService
                function onRemainingMsChanged() { parent.requestPaint() }
                function onPhaseChanged() { parent.requestPaint() }
                function onPhaseTotalMsChanged() { parent.requestPaint() }
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                text: root.formatMs(root.service.remainingMs)
                color: "white"
                font.pixelSize: 14
                font.bold: true
            }

            Text {
                text: root.phaseLabel()
                color: Qt.rgba(1, 1, 1, 0.55)
                font.pixelSize: 9
            }

            Row {
                spacing: 4

                Rectangle {
                    width: 34
                    height: 18
                    radius: 9
                    color: Qt.rgba(1, 1, 1, 0.12)

                    Text {
                        anchors.centerIn: parent
                        text: root.service.running ? "II" : "\u25B6"
                        color: "white"
                        font.pixelSize: 8
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.service.toggle()
                    }
                }

                Rectangle {
                    width: 26
                    height: 18
                    radius: 9
                    color: Qt.rgba(1, 1, 1, 0.07)

                    Text {
                        anchors.centerIn: parent
                        text: "\u21BB"
                        color: Qt.rgba(1, 1, 1, 0.8)
                        font.pixelSize: 9
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.service.reset()
                    }
                }

                Rectangle {
                    width: 26
                    height: 18
                    radius: 9
                    color: Qt.rgba(1, 1, 1, 0.07)

                    Text {
                        anchors.centerIn: parent
                        text: "\u23ED"
                        color: Qt.rgba(1, 1, 1, 0.8)
                        font.pixelSize: 8
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.service.skip()
                    }
                }
            }
        }
    }
}
