pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

Item {
    id: root
    required property var musicController

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            KosTextField {
                id: queryField
                Layout.fillWidth: true
                placeholderText: qsTr("Search NetEase Music…")
                Accessible.name: qsTr("Online music search")
                onAccepted: root.musicController.searchOnline(text)
            }
            KosRoundButton {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                text: "⌕"
                highlighted: true
                enabled: queryField.text.trim().length > 0
                    && !root.musicController.onlineSearching
                Accessible.name: qsTr("Search")
                onClicked: root.musicController.searchOnline(queryField.text)
            }
            BusyIndicator {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                visible: root.musicController.onlineSearching
                running: visible
            }
        }

        Label {
            Layout.fillWidth: true
            visible: root.musicController.onlineError.length > 0
            text: root.musicController.onlineError
            color: AppTheme.warning
            wrapMode: Text.WordWrap
        }

        Label {
            Layout.fillWidth: true
            text: root.musicController.musicSourceState === "ready"
                ? qsTr("Custom source ready · URLs are resolved only when playback starts")
                : qsTr("Import and activate a custom source before playing online results")
            color: root.musicController.musicSourceState === "ready"
                ? AppTheme.positive : AppTheme.mutedText
            font.pixelSize: 11
        }

        TrackListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            musicController: root.musicController
            trackModel: root.musicController.onlineModel
            contextMode: "online"
            emptyTitle: qsTr("Search online music")
            emptyDescription: qsTr("Search metadata first; your active LuoXue source resolves the playable URL on demand.")
        }
    }
}
