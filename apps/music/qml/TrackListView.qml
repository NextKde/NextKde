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


    function playRow(row, trackId) {
        if (contextMode === "queue")
            musicController.playQueueRow(row)
        else if (contextMode === "playlist")
            musicController.playPlaylistRow(row)
        else if (contextMode === "online")
            musicController.playOnlineRow(row)
        else
            musicController.playTrack(trackId)
    }

    // One shared menu for the whole list. Giving every delegate its own Menu
    // with many MenuItems costs extra objects per row and is rebuilt on every
    // model reset; a single instance just re-targets the row/track it was
    // opened for.
    property int menuRow: -1
    property var menuTrackId: -1
    property string menuTrackTitle: ""
    property bool menuTrackQueued: false
    property var deletionInfo: ({})

    function openTrackMenu(row, trackId, title, sourceItem) {
        menuRow = row
        menuTrackId = trackId
        menuTrackTitle = title
        menuTrackQueued = musicController.isTrackQueued(trackId)
        trackMenu.popup(sourceItem)
    }

    Connections {
        target: root.trackModel
        function onModelReset() { trackMenu.close() }
    }

    MusicMenu {
        id: trackMenu
        objectName: "trackContextMenu"
        MusicMenuItem {
            text: qsTr("立即播放")
            onTriggered: root.playRow(root.menuRow, root.menuTrackId)
        }
        MusicMenuItem {
            text: root.contextMode === "queue" ? qsTr("移到下一首") : qsTr("下一首播放")
            visible: root.contextMode === "queue"
                ? root.menuRow !== root.musicController.queueIndex && root.menuRow !== root.musicController.queueIndex + 1
                : root.contextMode === "online" || Number(root.menuTrackId) !== Number(root.musicController.currentTrackId)
            onTriggered: {
                if (root.contextMode === "online") root.musicController.playOnlineNext(root.menuRow)
                else if (root.contextMode === "queue") root.musicController.moveQueueRowNext(root.menuRow)
                else root.musicController.playTrackNext(root.menuTrackId)
            }
        }
        MusicMenuItem {
            text: qsTr("加入播放队列")
            visible: root.contextMode !== "queue" && !root.menuTrackQueued
            onTriggered: root.contextMode === "online"
                ? root.musicController.enqueueOnlineRow(root.menuRow)
                : root.musicController.enqueueTrack(root.menuTrackId)
        }
        MenuSeparator { visible: root.contextMode !== "online"; height: visible ? implicitHeight : 0 }
        MusicMenuItem {
            visible: root.contextMode === "queue"
            text: qsTr("从队列移除")
            onTriggered: root.musicController.removeQueueRow(root.menuRow)
        }
        MusicMenuItem {
            visible: root.contextMode === "playlist"
            text: qsTr("从歌单移除")
            onTriggered: root.musicController.removeTrackFromPlaylist(root.playlistId, root.menuTrackId)
        }
        MusicMenuItem {
            visible: root.contextMode === "library"
            text: qsTr("删除音乐…")
            destructive: true
            onTriggered: {
                root.deletionInfo = root.musicController.trackDeletionInfo(root.menuTrackId)
                if (root.deletionInfo.path) deleteDialog.open()
            }
        }
    }

    MusicDialog {
        id: deleteDialog
        objectName: "deleteMusicDialog"
        anchors.centerIn: parent
        width: Math.min(root.width - 24, 420)
        title: qsTr("删除音乐？")
        onAccepted: root.musicController.deleteTrack(root.deletionInfo.id, root.deletionInfo.path)
        contentItem: ColumnLayout {
            spacing: 12
            Label {
                Layout.fillWidth: true
                text: String(root.deletionInfo.title ?? "")
                color: AppTheme.text
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            Label {
                Layout.fillWidth: true
                text: root.deletionInfo.localFile
                    ? qsTr("本地音频将移到回收站，可在回收站恢复。歌曲也会从音乐库、播放队列和所有歌单中移除。")
                    : qsTr("歌曲及其音频缓存将从本机移除，同时清理播放队列和歌单中的记录。")
                color: AppTheme.mutedText
                wrapMode: Text.WordWrap
            }
        }
        footer: DialogButtonBox {
            padding: 14
            spacing: 8
            background: Item {}
            KosButton { text: qsTr("取消"); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
            KosButton {
                text: root.deletionInfo.localFile ? qsTr("移到回收站") : qsTr("删除")
                destructive: true
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
            }
            onAccepted: deleteDialog.accept()
            onRejected: deleteDialog.reject()
        }
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
                Number(trackId) >= 0
                && Number(trackId) === Number(root.musicController.currentTrackId)

            width: trackList.width
            height: 66
            activeFocusOnTab: true
            radius: AppTheme.smallRadius
            color: isCurrent
                ? AppTheme.withAlpha(AppTheme.accent, AppTheme.dark ? 0.18 : 0.12)
                : (hover.hovered ? AppTheme.cardHover : "transparent")
            border.width: activeFocus ? 1 : 0
            border.color: AppTheme.withAlpha(AppTheme.accent, 0.62)
            Accessible.name: qsTr("%1 by %2").arg(title).arg(
                artist.length > 0 ? artist : qsTr("unknown artist"))
            Accessible.role: Accessible.ListItem
            Accessible.focusable: true
            Accessible.focused: activeFocus
            Accessible.onPressAction: root.playRow(trackDelegate.index,
                                                    trackDelegate.trackId)

            Keys.onSpacePressed: root.playRow(trackDelegate.index,
                                              trackDelegate.trackId)
            Keys.onEnterPressed: root.playRow(trackDelegate.index,
                                              trackDelegate.trackId)
            Keys.onReturnPressed: root.playRow(trackDelegate.index,
                                               trackDelegate.trackId)

            TapHandler {
                acceptedButtons: Qt.LeftButton
                onDoubleTapped: root.playRow(trackDelegate.index, trackDelegate.trackId)
            }

            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: root.openTrackMenu(trackDelegate.index,
                                             trackDelegate.trackId,
                                             trackDelegate.title,
                                             trackDelegate)
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

                KosToolButton {
                    Layout.preferredWidth: 34
                    text: "⋮"
                    flat: true
                    Accessible.name: qsTr("Track actions")
                    onClicked: root.openTrackMenu(trackDelegate.index,
                                                  trackDelegate.trackId,
                                                  trackDelegate.title,
                                                  this)
                }
            }
        }
    }
}
