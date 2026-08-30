pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

KosApplicationWindow {
    id: root

    visible: true
    title: qsTr("Music")

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 240
            color: AppTheme.withAlpha(AppTheme.sidebar, 0.92)
            border.width: 1
            border.color: AppTheme.border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 8

                Label {
                    text: qsTr("KOS Music")
                    color: AppTheme.text
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    Layout.bottomMargin: 16
                }

                ButtonGroup { id: navigationGroup }

                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Recently added")
                    symbol: "◷"
                    checked: true
                    ButtonGroup.group: navigationGroup
                }

                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Songs")
                    symbol: "♫"
                    ButtonGroup.group: navigationGroup
                }

                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Albums")
                    symbol: "▦"
                    ButtonGroup.group: navigationGroup
                }

                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Artists")
                    symbol: "♙"
                    ButtonGroup.group: navigationGroup
                }

                Label {
                    Layout.topMargin: 20
                    text: qsTr("PLAYLISTS")
                    color: AppTheme.mutedText
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Queue")
                    symbol: "≡"
                    ButtonGroup.group: navigationGroup
                }

                Item { Layout.fillHeight: true }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Engine: not initialized\nMPRIS: not registered")
                    color: AppTheme.mutedText
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: AppTheme.pageMargin
            spacing: 16

            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 2

                    Label {
                        text: qsTr("Recently added")
                        color: AppTheme.text
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                    }

                    Label {
                        text: qsTr("Your local music library")
                        color: AppTheme.mutedText
                    }
                }

                Item { Layout.fillWidth: true }

                LiquidTextField {
                    Layout.preferredWidth: 260
                    placeholderText: qsTr("Search library…")
                    Accessible.name: qsTr("Search music library")
                    enabled: false
                }

                Button {
                    text: qsTr("Add folder")
                    highlighted: true
                    enabled: false
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Library scanning is added with the music engine")
                }
            }

            KosCard {
                Layout.fillWidth: true
                Layout.fillHeight: true

                contentItem: KosEmptyState {
                    symbol: "♫"
                    title: qsTr("Your library is empty")
                    description: qsTr("Add local music folders after the GStreamer engine, TagLib scanner, and SQLite library are connected.")
                    actionText: qsTr("Music engine pending")
                    actionEnabled: false
                }
            }

            KosCard {
                Layout.fillWidth: true
                Layout.preferredHeight: 92
                padding: 14

                contentItem: RowLayout {
                    spacing: 14

                    Rectangle {
                        Layout.preferredWidth: 62
                        Layout.preferredHeight: 62
                        radius: AppTheme.smallRadius
                        color: AppTheme.withAlpha(AppTheme.accent, 0.12)

                        Label {
                            anchors.centerIn: parent
                            text: "♫"
                            color: AppTheme.mutedText
                            font.pixelSize: 24
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Nothing playing")
                            color: AppTheme.text
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Start a track to publish metadata over MPRIS")
                            color: AppTheme.mutedText
                            elide: Text.ElideRight
                        }

                        Slider {
                            Layout.fillWidth: true
                            from: 0
                            to: 1
                            value: 0
                            enabled: false
                            Accessible.name: qsTr("Playback position")
                        }
                    }

                    Button {
                        text: "│‹"
                        enabled: false
                        Accessible.name: qsTr("Previous track")
                    }

                    Button {
                        text: "▶"
                        enabled: false
                        Accessible.name: qsTr("Play")
                    }

                    Button {
                        text: "›│"
                        enabled: false
                        Accessible.name: qsTr("Next track")
                    }
                }
            }
        }
    }
}
