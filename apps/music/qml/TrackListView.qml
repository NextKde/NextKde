pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

Item {
    id: root

    required property var musicController
    required property var trackModel
    property string contextMode: "library"
    property var playlistId: -1
    property string emptyTitle: qsTr("No music here yet")
    property string emptyDescription: qsTr("Add a music folder or choose another view.")

    signal addToPlaylistRequested(var trackId)
    signal transcodeRequested(var trackId, string title)

    function playRow(row, trackId) {
        if (contextMode === "queue")
            musicController.playQueueRow(row)
        else if (contextMode === "playlist")
            musicController.playPlaylistRow(row)
        else
            musicController.playTrack(trackId)
    }

    KosEmptyState {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 440)
        symbol: "♫"
        title: root.emptyTitle
        description: root.emptyDescription
        visible: root.trackModel.count === 0
    }

    ListView {
        id: trackList
        anchors.fill: parent
        visible: count > 0
        clip: true
        spacing: 2
        model: root.trackModel
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        header: Rectangle {
            width: trackList.width
            height: 34
            color: "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 62
                anchors.rightMargin: 54
                spacing: 12

                Label {
                    Layout.fillWidth: true
                    text: qsTr("TITLE")
                    color: AppTheme.mutedText
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
                Label {
                    Layout.preferredWidth: Math.max(100, trackList.width * 0.21)
                    visible: trackList.width >= 610
                    text: qsTr("ALBUM")
                    color: AppTheme.mutedText
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
                Label {
                    Layout.preferredWidth: 58
                    text: qsTr("TIME")
                    color: AppTheme.mutedText
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
        }

        delegate: Rectangle {
            id: trackDelegate

            required property int index
            required property var trackId
            required property string title
            required property string artist
            required property string album
            required property string durationText
            required property string artworkUrl
            required property string format

            readonly property bool isCurrent:
                Number(trackId) === Number(root.musicController.currentTrackId)

            width: trackList.width
            height: 66
            radius: AppTheme.smallRadius
            color: isCurrent
                ? AppTheme.withAlpha(AppTheme.accent, AppTheme.dark ? 0.18 : 0.12)
                : (hover.hovered ? AppTheme.cardHover : "transparent")
            border.width: activeFocus ? 1 : 0
            border.color: AppTheme.withAlpha(AppTheme.accent, 0.62)
            Accessible.name: qsTr("%1 by %2").arg(title).arg(
                artist.length > 0 ? artist : qsTr("unknown artist"))
            Accessible.role: Accessible.ListItem

            TapHandler {
                acceptedButtons: Qt.LeftButton
                onDoubleTapped: root.playRow(trackDelegate.index, trackDelegate.trackId)
            }

            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: trackMenu.popup()
            }

            HoverHandler { id: hover }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 6
                spacing: 12

                Item {
                    Layout.preferredWidth: 46
                    Layout.preferredHeight: 46

                    Artwork {
                        anchors.fill: parent
                        source: trackDelegate.artworkUrl
                        title: trackDelegate.title
                        radius: 8
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: AppTheme.withAlpha("#000000", 0.42)
                        visible: hover.hovered || trackDelegate.isCurrent

                        Label {
                            anchors.centerIn: parent
                            text: trackDelegate.isCurrent
                                && root.musicController.playbackState === "Playing" ? "Ⅱ" : "▶"
                            color: "white"
                            font.pixelSize: 17
                        }

                        TapHandler {
                            onTapped: root.playRow(trackDelegate.index, trackDelegate.trackId)
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Label {
                        Layout.fillWidth: true
                        text: trackDelegate.title
                        color: trackDelegate.isCurrent ? AppTheme.accent : AppTheme.text
                        font.weight: trackDelegate.isCurrent ? Font.DemiBold : Font.Medium
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        text: trackDelegate.artist.length > 0
                            ? trackDelegate.artist : qsTr("Unknown artist")
                        color: AppTheme.mutedText
                        elide: Text.ElideRight
                        font.pixelSize: 12
                    }
                }

                Label {
                    Layout.preferredWidth: Math.max(100, trackList.width * 0.21)
                    visible: trackList.width >= 610
                    text: trackDelegate.album.length > 0
                        ? trackDelegate.album : qsTr("Unknown album")
                    color: AppTheme.mutedText
                    elide: Text.ElideRight
                    font.pixelSize: 12
                }

                Label {
                    Layout.preferredWidth: 58
                    text: trackDelegate.durationText
                    color: AppTheme.mutedText
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: 12
                }

                ToolButton {
                    Layout.preferredWidth: 34
                    text: "⋮"
                    flat: true
                    Accessible.name: qsTr("Track actions")
                    onClicked: trackMenu.popup()
                }
            }

            Menu {
                id: trackMenu

                MenuItem {
                    text: qsTr("Play now")
                    onTriggered: root.playRow(trackDelegate.index, trackDelegate.trackId)
                }
                MenuItem {
                    text: qsTr("Play next")
                    onTriggered: root.musicController.playTrackNext(trackDelegate.trackId)
                }
                MenuItem {
                    text: qsTr("Add to queue")
                    onTriggered: root.musicController.enqueueTrack(trackDelegate.trackId)
                }
                MenuSeparator {}
                MenuItem {
                    text: qsTr("Add to playlist…")
                    onTriggered: root.addToPlaylistRequested(trackDelegate.trackId)
                }
                MenuItem {
                    text: qsTr("Convert audio…")
                    onTriggered: root.transcodeRequested(trackDelegate.trackId,
                                                         trackDelegate.title)
                }
                MenuSeparator {
                    visible: root.contextMode === "queue"
                        || root.contextMode === "playlist"
                }
                MenuItem {
                    visible: root.contextMode === "queue"
                    text: qsTr("Remove from queue")
                    onTriggered: root.musicController.removeQueueRow(trackDelegate.index)
                }
                MenuItem {
                    visible: root.contextMode === "playlist"
                    text: qsTr("Remove from playlist")
                    onTriggered: root.musicController.removeTrackFromPlaylist(
                                     root.playlistId, trackDelegate.trackId)
                }
            }
        }
    }
}
