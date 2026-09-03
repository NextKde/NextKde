pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

Item {
    id: root

    required property var groupModel
    property string groupKind: "album"
    property string emptyTitle: qsTr("No albums yet")

    signal openRequested(string name, string subtitle, string filterValue)
    signal playRequested(string filterValue)

    KosEmptyState {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 440)
        symbol: root.groupKind === "artist" ? "♙" : "▦"
        title: root.emptyTitle
        description: qsTr("Add a folder and scan your local music collection.")
        visible: root.groupModel.length === 0
    }

    GridView {
        id: grid
        anchors.fill: parent
        visible: count > 0
        clip: true
        cellWidth: Math.max(154, width / Math.max(1, Math.floor(width / 182)))
        cellHeight: root.groupKind === "artist" ? 214 : 234
        model: root.groupModel
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        delegate: Item {
            id: groupDelegate

            required property var modelData

            readonly property string groupName: String(modelData.name ?? "")
            readonly property string subtitle: String(modelData.subtitle ?? "")
            readonly property string filterValue: String(modelData.filterValue ?? groupName)
            readonly property string artworkUrl: String(modelData.artworkUrl ?? "")
            readonly property int trackCount: Number(modelData.count ?? 0)

            width: grid.cellWidth
            height: grid.cellHeight
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: groupName
            Accessible.focusable: true
            Accessible.focused: activeFocus
            Accessible.onPressAction: root.openRequested(
                groupDelegate.groupName, groupDelegate.subtitle,
                groupDelegate.filterValue)

            Keys.onSpacePressed: root.openRequested(
                groupDelegate.groupName, groupDelegate.subtitle,
                groupDelegate.filterValue)
            Keys.onEnterPressed: root.openRequested(
                groupDelegate.groupName, groupDelegate.subtitle,
                groupDelegate.filterValue)
            Keys.onReturnPressed: root.openRequested(
                groupDelegate.groupName, groupDelegate.subtitle,
                groupDelegate.filterValue)

            Rectangle {
                anchors.fill: parent
                anchors.margins: 6
                radius: AppTheme.mediumRadius
                color: groupHover.hovered ? AppTheme.cardHover : AppTheme.cardSurface
                border.width: groupDelegate.activeFocus ? 2 : 1
                border.color: groupDelegate.activeFocus
                    ? AppTheme.accent : AppTheme.border

                HoverHandler { id: groupHover }
                TapHandler {
                    onTapped: root.openRequested(groupDelegate.groupName,
                                                 groupDelegate.subtitle,
                                                 groupDelegate.filterValue)
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 5

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: width

                        Artwork {
                            anchors.fill: parent
                            source: groupDelegate.artworkUrl
                            title: groupDelegate.groupName
                            radius: root.groupKind === "artist"
                                ? Math.round(width / 2) : AppTheme.smallRadius
                        }

                        KosRoundButton {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 8
                            width: 42
                            height: 42
                            text: "▶"
                            highlighted: true
                            visible: groupHover.hovered || groupDelegate.activeFocus
                            Accessible.name: qsTr("Play %1").arg(groupDelegate.groupName)
                            onClicked: root.playRequested(groupDelegate.filterValue)
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: groupDelegate.groupName
                        color: AppTheme.text
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        text: groupDelegate.subtitle.length > 0
                            ? groupDelegate.subtitle
                            : qsTr("%n track(s)", "", groupDelegate.trackCount)
                        color: AppTheme.mutedText
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
