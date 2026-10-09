pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: dialog

    property bool open: false
    property bool cancelable: true
    property string title: qsTr("提示")
    property string message: ""
    property var options: []
    property Component contentComponent: null
    readonly property var contentItem: customContent.item
    property int selectedOption: 0
    property string primaryLabel: qsTr("确认")
    property string secondaryLabel: qsTr("取消")
    property color accentColor: AppTheme.accent
    signal accepted(int option)
    signal rejected

    visible: opacity > 0.001
    opacity: open ? 1 : 0
    enabled: open
    focus: open

    function rejectDialog() {
        if (!cancelable) return
        rejected()
    }

    Behavior on opacity {
        NumberAnimation { duration: AppTheme.duration(160); easing.type: Easing.OutCubic }
    }

    Keys.onEscapePressed: function(event) {
        if (dialog.cancelable) {
            dialog.rejectDialog()
            event.accepted = true
        }
    }

    Rectangle {
        anchors.fill: parent
        color: AppTheme.scrim
        TapHandler { onTapped: dialog.rejectDialog() }
    }

    GlassSurface {
        id: card
        width: 460
        height: Math.max(218, dialogColumn.implicitHeight + 48)
        anchors.centerIn: parent
        cornerRadius: 22
        tint: AppTheme.cardStrong
        edgeColor: AppTheme.border
        shadowOpacity: 0.28
        scale: dialog.open ? 1 : 0.96

        Behavior on scale {
            NumberAnimation { duration: AppTheme.duration(210); easing.type: Easing.OutCubic }
        }

        TapHandler { onTapped: {} }

        Column {
            id: dialogColumn
            x: 24
            y: 24
            width: parent.width - 48
            spacing: 12

            Text {
                width: parent.width
                text: dialog.title
                color: AppTheme.textPrimary
                font.family: AppTheme.fontFamily
                font.pixelSize: 21
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: parent.width
                text: dialog.message
                color: AppTheme.textSecondary
                font.family: AppTheme.fontFamily
                font.pixelSize: 12
                lineHeight: 1.25
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }

            Column {
                id: optionColumn
                width: parent.width
                spacing: 7
                visible: dialog.options && dialog.options.length > 0

                Repeater {
                    model: dialog.options
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: optionColumn.width
                        height: 40
                        radius: 11
                        color: dialog.selectedOption === index ? Qt.rgba(.20, .61, .83, .18) : optionHover.hovered ? AppTheme.controlHover : AppTheme.control
                        border.width: 1
                        border.color: dialog.selectedOption === index ? dialog.accentColor : "#d9e0e4"
                        Behavior on color { ColorAnimation { duration: AppTheme.duration(100) } }
                        Row {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10
                            Rectangle {
                                width: 17
                                height: 17
                                radius: 8.5
                                color: AppTheme.field
                                border.width: 1.5
                                border.color: dialog.selectedOption === index ? dialog.accentColor : "#aab3b9"
                                Rectangle {
                                    visible: dialog.selectedOption === index
                                    anchors.centerIn: parent
                                    width: 9
                                    height: 9
                                    radius: 4.5
                                    color: dialog.accentColor
                                }
                            }
                            Text {
                                text: String(modelData)
                                color: AppTheme.textPrimary
                                font.family: AppTheme.fontFamily
                                font.pixelSize: 12
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        HoverHandler { id: optionHover }
                        TapHandler { onTapped: dialog.selectedOption = index }
                    }
                }
            }

            Loader {
                id: customContent
                width: parent.width
                visible: dialog.contentComponent !== null
                active: visible
                sourceComponent: dialog.contentComponent
                height: item ? Math.max(item.height, item.implicitHeight) : 0
            }

            Item { width: 1; height: 2 }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                UiButton {
                    visible: dialog.cancelable && dialog.secondaryLabel.length > 0
                    label: dialog.secondaryLabel
                    onClicked: dialog.rejectDialog()
                }
                UiButton {
                    label: dialog.primaryLabel
                    emphasized: true
                    onClicked: {
                        dialog.accepted(dialog.selectedOption)
                    }
                }
            }
        }
    }
}
