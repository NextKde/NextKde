pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Kos.Ui

Item {
    id: root
    required property var musicController

    MusicDialog {
        id: attemptDialog
        title: qsTr("最近的音源尝试")
        anchors.centerIn: parent
        width: Math.min(root.width - 24, 680)
        height: Math.min(root.height - 24, 420)
        modal: true
        standardButtons: Dialog.Close
        contentItem: ScrollView {
            TextArea {
                text: root.musicController.playbackAttempts.join("\n\n")
                color: AppTheme.text
                background: Rectangle { radius: AppTheme.smallRadius; color: AppTheme.fieldSurface }
                readOnly: true
                wrapMode: TextEdit.Wrap
                selectByMouse: true
            }
        }
    }

    FileDialog {
        id: sourceDialog
        title: qsTr("Import LuoXue custom source")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("JavaScript sources (*.js)"), qsTr("All files (*)")]
        onAccepted: root.musicController.importMusicSource(selectedFile.toString())
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 12

        Label {
            Layout.fillWidth: true
            text: qsTr("Custom sources run in a separate helper process for crash and timeout isolation. This is not a security sandbox: only install scripts you trust. Source availability and music rights are not guaranteed.")
            color: AppTheme.mutedText
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            KosTextField {
                id: sourceUrl
                Layout.fillWidth: true
                placeholderText: qsTr("HTTPS URL to a LuoXue source script")
                Accessible.name: qsTr("Custom source URL")
                onAccepted: if (text.trim().length > 0)
                    root.musicController.importMusicSource(text.trim())
            }
            KosButton {
                text: qsTr("Import URL")
                enabled: sourceUrl.text.trim().length > 0
                onClicked: root.musicController.importMusicSource(sourceUrl.text.trim())
            }
            KosButton {
                text: qsTr("Import file…")
                onClicked: sourceDialog.open()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                text: qsTr("Installed sources")
                color: AppTheme.text
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }
            Label {
                text: root.musicController.musicSourceState
                color: root.musicController.musicSourceState === "ready"
                    ? AppTheme.positive : AppTheme.mutedText
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.musicController.musicSourceState === "ready"
                && root.musicController.onlineQualities.length > 0
            Label {
                text: qsTr("Playback quality")
                color: AppTheme.text
            }
            MusicComboBox {
                id: qualityChoice
                Layout.preferredWidth: 180
                model: root.musicController.onlineQualities
                currentIndex: Math.max(0, root.musicController.onlineQualities.indexOf(
                                           root.musicController.onlineQuality))
                Accessible.name: qsTr("Online playback quality")
                onActivated: root.musicController.onlineQuality = currentText
            }
        }

        Label {
            Layout.fillWidth: true
            visible: root.musicController.musicSourceError.length > 0
            text: root.musicController.musicSourceError
            color: AppTheme.warning
            wrapMode: Text.WordWrap
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("播放异常时会依次尝试已导入的兼容音源；每次最多等待 12 秒，整曲重试最多 45 秒，失败后 3 秒继续队列。")
            color: AppTheme.mutedText
            wrapMode: Text.WordWrap
        }
        KosButton {
            text: qsTr("查看最近的音源尝试")
            enabled: root.musicController.playbackAttempts.length > 0
            onClicked: attemptDialog.open()
        }

        KosEmptyState {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.musicController.musicSources.length === 0
            symbol: "⌁"
            title: qsTr("No custom source")
            description: qsTr("Import an LX Music-compatible user API script to resolve online tracks.")
            actionText: qsTr("Import source")
            onActionTriggered: sourceDialog.open()
        }

        ListView {
            id: sourceList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.musicController.musicSources.length > 0
            model: root.musicController.musicSources
            spacing: 8
            clip: true
            ScrollBar.vertical: ScrollBar {}

            delegate: Rectangle {
                id: sourceDelegate
                required property var modelData
                width: sourceList.width
                height: 74
                radius: AppTheme.smallRadius
                color: String(modelData.id) === root.musicController.activeMusicSourceId
                    ? AppTheme.withAlpha(AppTheme.accent, AppTheme.dark ? 0.16 : 0.09)
                    : AppTheme.cardSurface
                border.width: 1
                border.color: String(modelData.id) === root.musicController.activeMusicSourceId
                    ? AppTheme.accent : AppTheme.border

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    ColumnLayout {
                        Layout.fillWidth: true
                        Label {
                            Layout.fillWidth: true
                            text: String(sourceDelegate.modelData.name ?? qsTr("Unnamed source"))
                            color: AppTheme.text
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Label {
                            Layout.fillWidth: true
                            text: [String(sourceDelegate.modelData.version ?? ""),
                                   String(sourceDelegate.modelData.author ?? "")]
                                  .filter(value => value.length > 0).join(" · ")
                            color: AppTheme.mutedText
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                    KosButton {
                        text: String(sourceDelegate.modelData.id)
                            === root.musicController.activeMusicSourceId
                            ? qsTr("Active") : qsTr("Activate")
                        enabled: String(sourceDelegate.modelData.id)
                            !== root.musicController.activeMusicSourceId
                        onClicked: root.musicController.activateMusicSource(
                                       String(sourceDelegate.modelData.id))
                    }
                    KosToolButton {
                        destructive: true
                        text: "×"
                        Accessible.name: qsTr("Remove source")
                        onClicked: root.musicController.removeMusicSource(
                                       String(sourceDelegate.modelData.id))
                    }
                }
            }
        }
    }
}
