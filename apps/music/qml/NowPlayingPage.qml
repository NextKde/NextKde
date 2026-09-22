pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

Item {
    id: root
    required property var musicController

    Image {
        anchors.fill: parent
        source: root.musicController.currentArtworkUrl
        fillMode: Image.PreserveAspectCrop
        opacity: AppTheme.dark ? 0.18 : 0.10
        asynchronous: true
        cache: true
        visible: source.toString().length > 0
    }

    Rectangle {
        anchors.fill: parent
        color: AppTheme.withAlpha(AppTheme.window, AppTheme.dark ? 0.76 : 0.86)
    }

    RowLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 780)
        spacing: 28

        Artwork {
            Layout.preferredWidth: Math.min(300, parent.width * 0.42)
            Layout.preferredHeight: width
            source: root.musicController.currentArtworkUrl
            title: root.musicController.currentTitle
            radius: AppTheme.largeRadius
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            Label {
                Layout.fillWidth: true
                text: root.musicController.currentTitle || qsTr("Nothing playing")
                color: AppTheme.text
                font.pixelSize: 30
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            Label {
                Layout.fillWidth: true
                text: root.musicController.currentArtist || qsTr("Choose a track to begin")
                color: AppTheme.mutedText
                font.pixelSize: 17
                wrapMode: Text.WordWrap
            }
            Label {
                Layout.fillWidth: true
                text: root.musicController.currentAlbum
                visible: text.length > 0
                color: AppTheme.mutedText
                wrapMode: Text.WordWrap
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 260

                BusyIndicator {
                    anchors.centerIn: parent
                    running: root.musicController.lyricsLoading
                    visible: running
                }

                Label {
                    anchors.centerIn: parent
                    width: parent.width
                    visible: !root.musicController.lyricsLoading
                        && root.musicController.lyrics.length === 0
                    text: root.musicController.lyricsError.length > 0
                        ? root.musicController.lyricsError
                        : qsTr("No synchronized lyrics")
                    color: AppTheme.mutedText
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.italic: true
                }

                ListView {
                    id: lyricList
                    anchors.fill: parent
                    visible: root.musicController.lyrics.length > 0
                    model: root.musicController.lyrics
                    clip: true
                    spacing: 14
                    boundsBehavior: Flickable.StopAtBounds
                    preferredHighlightBegin: height * 0.42
                    preferredHighlightEnd: height * 0.58
                    highlightRangeMode: ListView.ApplyRange

                    delegate: Label {
                        id: lyricDelegate
                        required property int index
                        required property var modelData
                        width: lyricList.width
                        text: String(modelData.text ?? "")
                        color: index === root.musicController.currentLyricIndex
                            ? AppTheme.text : AppTheme.mutedText
                        font.pixelSize: index === root.musicController.currentLyricIndex ? 22 : 17
                        font.weight: index === root.musicController.currentLyricIndex
                            ? Font.DemiBold : Font.Normal
                        wrapMode: Text.WordWrap
                        opacity: index === root.musicController.currentLyricIndex ? 1 : 0.62

                        Behavior on opacity {
                            NumberAnimation { duration: AppTheme.motionNormal }
                        }
                    }
                }

                Connections {
                    target: root.musicController
                    function onCurrentLyricChanged() {
                        const index = root.musicController.currentLyricIndex
                        if (index >= 0 && index < lyricList.count)
                            lyricList.positionViewAtIndex(index, ListView.Center)
                    }
                }
            }
        }
    }
}
