pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

KosCard {
    id: root

    required property var musicController
    property bool compact: false
    property real pendingSeekMs: 0
    signal nowPlayingRequested()

    function formatTime(milliseconds) {
        const seconds = Math.max(0, Math.floor(Number(milliseconds) / 1000))
        const minutes = Math.floor(seconds / 60)
        const rest = seconds % 60
        return minutes + ":" + String(rest).padStart(2, "0")
    }

    Layout.fillWidth: true
    Layout.preferredHeight: root.musicController.playbackStatusText.length > 0 ? 142 : 116
    padding: 12

    contentItem: ColumnLayout {
        spacing: 5

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Artwork {
                Layout.preferredWidth: 58
                Layout.preferredHeight: 58
                source: root.musicController.currentArtworkUrl
                title: root.musicController.currentTitle

                TapHandler {
                    enabled: root.musicController.currentTrackId >= 0
                    onTapped: root.nowPlayingRequested()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Label {
                    Layout.fillWidth: true
                    text: root.musicController.currentTrackId >= 0
                        ? root.musicController.currentTitle : qsTr("Nothing playing")
                    color: AppTheme.text
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    text: root.musicController.currentTrackId >= 0
                        ? (root.musicController.currentArtist.length > 0
                           ? root.musicController.currentArtist : qsTr("Unknown artist"))
                        : qsTr("Choose a local or online track")
                    color: AppTheme.mutedText
                    elide: Text.ElideRight
                    font.pixelSize: 12
                }
            }

            RowLayout {
                visible: !root.compact
                spacing: 2

                Repeater {
                    model: [
                        { mode: "sequential", symbol: "→", label: qsTr("Sequential playback") },
                        { mode: "playlist", symbol: "↻", label: qsTr("Repeat queue") },
                        { mode: "track", symbol: "↻¹", label: qsTr("Repeat current track") },
                        { mode: "shuffle", symbol: "⇄", label: qsTr("Shuffle") }
                    ]
                    delegate: KosToolButton {
                        required property var modelData
                        text: modelData.symbol
                        checkable: true
                        checked: root.musicController.playbackMode === modelData.mode
                        enabled: modelData.mode !== "shuffle"
                            || root.musicController.queueModel.count > 1
                        Accessible.name: modelData.label
                        ToolTip.visible: hovered
                        ToolTip.text: modelData.label
                        onClicked: root.musicController.playbackMode = modelData.mode
                    }
                }
            }

            KosToolButton {
                visible: root.compact
                text: root.musicController.playbackMode === "track" ? "↻¹"
                    : root.musicController.playbackMode === "playlist" ? "↻"
                    : root.musicController.playbackMode === "shuffle" ? "⇄" : "→"
                Accessible.name: qsTr("Playback mode")
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Playback mode")
                onClicked: playbackModeMenu.popup()

                Menu {
                    id: playbackModeMenu
                    y: -implicitHeight
                    MenuItem {
                        text: qsTr("Sequential playback")
                        checkable: true
                        checked: root.musicController.playbackMode === "sequential"
                        onTriggered: root.musicController.playbackMode = "sequential"
                    }
                    MenuItem {
                        text: qsTr("Repeat queue")
                        checkable: true
                        checked: root.musicController.playbackMode === "playlist"
                        onTriggered: root.musicController.playbackMode = "playlist"
                    }
                    MenuItem {
                        text: qsTr("Repeat current track")
                        checkable: true
                        checked: root.musicController.playbackMode === "track"
                        onTriggered: root.musicController.playbackMode = "track"
                    }
                    MenuItem {
                        text: qsTr("Shuffle")
                        checkable: true
                        checked: root.musicController.playbackMode === "shuffle"
                        enabled: root.musicController.queueModel.count > 1
                        onTriggered: root.musicController.playbackMode = "shuffle"
                    }
                }
            }

            KosToolButton {
                text: qsTr("歌词")
                checkable: true
                checked: root.musicController.lyricsEnabled
                Accessible.name: qsTr("显示歌词")
                ToolTip.visible: hovered
                ToolTip.text: checked ? qsTr("关闭歌词") : qsTr("开启歌词")
                onClicked: root.musicController.lyricsEnabled = !root.musicController.lyricsEnabled
            }
            KosToolButton {
                text: "│◀"
                enabled: root.musicController.canGoPrevious
                Accessible.name: qsTr("Previous track")
                onClicked: root.musicController.previous()
            }
            KosRoundButton {
                Layout.preferredWidth: 46
                Layout.preferredHeight: 46
                text: root.musicController.playbackState === "Loading" ? "…"
                    : (root.musicController.playbackState === "Playing" ? "Ⅱ" : "▶")
                highlighted: true
                enabled: root.musicController.currentTrackId >= 0
                Accessible.name: root.musicController.playbackState === "Playing"
                    ? qsTr("Pause") : qsTr("Play")
                onClicked: root.musicController.togglePlayPause()
            }
            KosToolButton {
                text: "▶│"
                enabled: root.musicController.canGoNext
                Accessible.name: qsTr("Next track")
                onClicked: root.musicController.next()
            }
            Slider {
                visible: !root.compact
                Layout.preferredWidth: 90
                from: 0
                to: 1
                value: root.musicController.volume
                Accessible.name: qsTr("Volume")
                onMoved: root.musicController.volume = value
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.musicController.playbackStatusText.length > 0
            spacing: 8
            BusyIndicator {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                running: root.musicController.playbackState === "Loading"
                visible: running
            }
            Label {
                text: root.musicController.playbackStatusText
                color: AppTheme.mutedText
                font.pixelSize: 12
            }
            ProgressBar {
                Layout.fillWidth: true
                from: 0; to: 1
                value: Math.max(0, root.musicController.cacheProgress)
                indeterminate: root.musicController.cacheProgress < 0
                visible: root.musicController.playbackState === "Loading"
                    || (root.musicController.cacheProgress >= 0 && root.musicController.cacheProgress < 1)
            }
            Item { Layout.fillWidth: true; visible: root.musicController.playbackState === "Error" }
            KosToolButton {
                text: qsTr("重试")
                visible: root.musicController.playbackState === "Error"
                onClicked: root.musicController.play()
            }
            KosToolButton {
                text: qsTr("取消")
                visible: root.musicController.playbackState === "Loading"
                    || root.musicController.playbackState === "Error"
                onClicked: root.musicController.stop()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                Layout.preferredWidth: 40
                text: root.formatTime(root.musicController.positionMs)
                color: AppTheme.mutedText
                horizontalAlignment: Text.AlignRight
                font.pixelSize: 10
            }
            Slider {
                id: positionSlider
                Layout.fillWidth: true
                from: 0
                to: Math.max(1, root.musicController.durationMs)
                value: pressed ? root.pendingSeekMs : root.musicController.positionMs
                enabled: root.musicController.seekable
                Accessible.name: qsTr("Playback position")
                onPressedChanged: {
                    if (pressed)
                        root.pendingSeekMs = root.musicController.positionMs
                    else
                        root.musicController.seek(Math.round(root.pendingSeekMs))
                }
                onMoved: root.pendingSeekMs = value
            }
            Label {
                Layout.preferredWidth: 40
                text: root.formatTime(root.musicController.durationMs)
                color: AppTheme.mutedText
                font.pixelSize: 10
            }
        }
    }
}
