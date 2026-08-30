pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

KosApplicationWindow {
    id: root

    visible: true
    title: qsTr("Weather")

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 258
            color: AppTheme.withAlpha(AppTheme.sidebar, 0.92)
            border.width: 1
            border.color: AppTheme.border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 10

                Label {
                    text: qsTr("KOS Weather")
                    color: AppTheme.text
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    Layout.bottomMargin: 8
                }

                LiquidTextField {
                    id: locationField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Search locations…")
                    Accessible.name: qsTr("Location search")
                    enabled: false
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Location search is enabled with the weather service")
                }

                Label {
                    Layout.topMargin: 10
                    text: qsTr("SAVED LOCATIONS")
                    color: AppTheme.mutedText
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                KosEmptyState {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    symbol: "⌖"
                    title: qsTr("No saved locations")
                    description: qsTr("Locations will be shared with the desktop weather widget.")
                }

                Label {
                    Layout.fillWidth: true
                    text: qsTr("Provider: Open-Meteo · cache unavailable")
                    color: AppTheme.mutedText
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                }
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: content.implicitHeight + AppTheme.pageMargin * 2
            clip: true

            ScrollBar.vertical: ScrollBar {}

            ColumnLayout {
                id: content
                x: AppTheme.pageMargin
                y: AppTheme.pageMargin
                width: parent.width - AppTheme.pageMargin * 2
                spacing: 16

                RowLayout {
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: 2

                        Label {
                            text: qsTr("Weather")
                            color: AppTheme.text
                            font.pixelSize: 28
                            font.weight: Font.DemiBold
                        }

                        Label {
                            text: qsTr("Waiting for the shared weather service")
                            color: AppTheme.mutedText
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Button {
                        text: qsTr("Refresh")
                        enabled: false
                    }
                }

                KosCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 260

                    contentItem: KosEmptyState {
                        symbol: "☁"
                        title: qsTr("Choose a location")
                        description: qsTr("Current conditions, hourly details, and the seven-day forecast will appear here once the data service is connected.")
                        actionText: qsTr("Weather service pending")
                        actionEnabled: false
                    }
                }

                Label {
                    text: qsTr("Hourly forecast")
                    color: AppTheme.text
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: 6

                        delegate: KosCard {
                            required property int index
                            Layout.fillWidth: true
                            Layout.preferredHeight: 112
                            opacity: 0.55

                            contentItem: ColumnLayout {
                                Label {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "--:--"
                                    color: AppTheme.mutedText
                                }
                                Label {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "·"
                                    color: AppTheme.text
                                    font.pixelSize: 24
                                }
                                Label {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "--°"
                                    color: AppTheme.text
                                }
                            }
                        }
                    }
                }

                Label {
                    text: qsTr("Seven-day forecast")
                    color: AppTheme.text
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }

                KosCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 130
                    opacity: 0.55

                    contentItem: Label {
                        text: qsTr("Forecast data is not loaded yet.")
                        color: AppTheme.mutedText
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
}
