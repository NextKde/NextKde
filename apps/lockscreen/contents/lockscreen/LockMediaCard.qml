// SPDX-FileCopyrightText: 2026 KOS
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Window
import QtQuick.Controls

Item {
    id: card
    property real unit: 1
    property string fontFamily: "Inter"
    property Item glassTexture: null
    property Item glassFrame: null
    property string title: ""
    property string artist: ""
    property url artwork: ""
    property bool playing: false
    property bool canPrevious: false
    property bool canPlayPause: false
    property bool canNext: false
    property real position: 0
    property real duration: 0
    property string currentLine: ""
    property string nextLine: ""
    property bool lyricsExpanded: false
    signal controlRequested(string method)
    implicitHeight: (150 + (lyricsExpanded && currentLine ? 62 : 0)) * unit
    function timeText(seconds) {
        const value = Math.max(0, Math.floor(seconds))
        return Math.floor(value / 60) + ":" + String(value % 60).padStart(2, "0")
    }
    LockGlass {
        anchors.fill: parent
        texture: card.glassTexture; frame: card.glassFrame
        radius: 28 * card.unit; tint: 0.23; thickness: 26
    }
    Rectangle {
        id: cover
        x: 16 * card.unit; y: 16 * card.unit
        width: 58 * card.unit; height: width
        radius: 11 * card.unit
        color: "#22ffffff"
        Text { anchors.centerIn: parent; text: "♪"; color: "#bbffffff"; font.pixelSize: 26 * card.unit }
        Image {
            anchors.fill: parent
            source: card.artwork
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
            asynchronous: true
        }
    }
    Text {
        font.family: card.fontFamily
        objectName: "lockTrackTitle"
        x: 86 * card.unit; y: 26 * card.unit
        width: parent.width - x - 16 * card.unit
        text: card.title; textFormat: Text.PlainText
        color: "#edffffff"; font.pixelSize: Math.max(12, 15 * card.unit); font.weight: Font.Medium
        elide: Text.ElideRight
    }
    Text {
        font.family: card.fontFamily
        x: 86 * card.unit; y: 47 * card.unit
        width: parent.width - x - 16 * card.unit
        text: card.artist; textFormat: Text.PlainText
        color: "#b3ffffff"; font.pixelSize: Math.max(11, 13 * card.unit)
        elide: Text.ElideRight
    }
    Text {
        font.family: card.fontFamily
        x: 16 * card.unit; y: 86 * card.unit
        text: card.timeText(card.position)
        color: "#aaffffff"; font.pixelSize: Math.max(9, 11 * card.unit)
    }
    Rectangle {
        x: 54 * card.unit; y: 92 * card.unit
        width: Math.max(1, parent.width - 112 * card.unit); height: 4 * card.unit
        radius: height / 2; color: "#33ffffff"
        Rectangle {
            width: Math.min(1, card.duration > 0 ? card.position / card.duration : 0) * parent.width
            height: parent.height; radius: height / 2; color: "#b3ffffff"
        }
    }
    Text {
        font.family: card.fontFamily
        anchors.right: parent.right; anchors.rightMargin: 16 * card.unit
        y: 86 * card.unit
        text: card.duration > 0 ? "−" + card.timeText(card.duration - card.position) : "−:−−"
        color: "#aaffffff"; font.pixelSize: Math.max(9, 11 * card.unit)
    }
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 108 * card.unit
        spacing: 18 * card.unit
        Repeater {
            model: ["Previous", "PlayPause", "Next"]
            delegate: ToolButton {
                required property string modelData
                id: control
                width: 40 * card.unit; height: 32 * card.unit
                enabled: modelData === "Previous" ? card.canPrevious : modelData === "Next" ? card.canNext : card.canPlayPause
                opacity: enabled ? 0.92 : 0.3
                Accessible.name: modelData === "Previous" ? qsTr("上一首") : modelData === "Next" ? qsTr("下一首") : card.playing ? qsTr("暂停") : qsTr("播放")
                background: Rectangle { radius: 8 * card.unit; color: control.hovered || control.activeFocus ? "#22ffffff" : "transparent" }
                contentItem: Item {
                    Canvas {
                        anchors.centerIn: parent
                        width: 18 * card.unit; height: width
                        property bool playing: card.playing
                        onPlayingChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset(); ctx.scale(width / 18, height / 18); ctx.fillStyle = "#e6ffffff"
                            if (control.modelData === "PlayPause" && playing) {
                                ctx.fillRect(4, 3, 3, 12); ctx.fillRect(11, 3, 3, 12)
                            } else {
                                if (control.modelData === "Previous") { ctx.translate(18, 0); ctx.scale(-1, 1) }
                                ctx.beginPath(); ctx.moveTo(4, 3); ctx.lineTo(14, 9); ctx.lineTo(4, 15); ctx.closePath(); ctx.fill()
                                if (control.modelData !== "PlayPause") ctx.fillRect(14, 3, 2, 12)
                            }
                        }
                    }
                }
                onClicked: card.controlRequested(modelData)
            }
        }
    }
    ToolButton {
        anchors.right: parent.right; anchors.rightMargin: 12 * card.unit
        y: 109 * card.unit; width: 32 * card.unit; height: width
        visible: card.currentLine.length > 0
        Accessible.name: card.lyricsExpanded ? qsTr("收起歌词") : qsTr("显示歌词")
        contentItem: Text { text: "≡"; color: "#ccffffff"; font.pixelSize: 20 * card.unit; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        background: Rectangle { radius: 8; color: parent.hovered || parent.activeFocus || card.lyricsExpanded ? "#22ffffff" : "transparent" }
        onClicked: card.lyricsExpanded = !card.lyricsExpanded
    }
    Column {
        visible: card.lyricsExpanded && card.currentLine.length > 0
        y: 153 * card.unit; width: parent.width - 32 * card.unit
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6 * card.unit
        Text {
        font.family: card.fontFamily
            objectName: "lockCurrentLyric"
            width: parent.width; text: card.currentLine; textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
            color: "#eeffffff"; font.pixelSize: 15 * card.unit
        }
        Text {
        font.family: card.fontFamily
            width: parent.width; text: card.nextLine; textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
            color: "#99ffffff"; font.pixelSize: 12 * card.unit
        }
    }
}
