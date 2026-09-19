import QtQuick
import qs.desktop.modules.common

// System-level destructive confirmation. It shares the same centered,
// high-readability KWin glass contract as Wi-Fi credentials.
KosFloatPanel {
    id: popup

    modal: true
    centerOnScreen: true
    backdropMode: "none"
    dismissOnBackdrop: true
    contentPadding: 0
    materialTone: "auto"

    function setDockPopupVisible(shouldOpen) {
        if (shouldOpen)
            popup.open()
        else
            popup.close()
    }

    Item {
        id: dialogContent
        width: Math.min(340, popup.width - 44)
        // Height follows the content. A fixed height is what used to leave a
        // dead gap between the body text and the buttons -- an alert is exactly
        // as tall as the stack it shows, and nothing more.
        height: column.height
        readonly property int sidePadding: 24

        // macOS alert rhythm: icon, title and body sit close together, and the
        // buttons follow after a single wider step.
        Column {
            id: column
            width: parent.width

            Item { width: parent.width; height: 20 }

            Item {
                width: parent.width
                height: 58

                Rectangle {
                    width: 58
                    height: 58
                    radius: width / 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Qt.rgba(popup.contentForegroundColor.r,
                        popup.contentForegroundColor.g,
                        popup.contentForegroundColor.b, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(popup.contentForegroundColor.r,
                        popup.contentForegroundColor.g,
                        popup.contentForegroundColor.b, 0.34)

                    BundledIcon {
                        anchors.centerIn: parent
                        name: "user-trash"
                        color: popup.contentForegroundColor
                        size: 28
                    }
                }
            }

            Item { width: parent.width; height: 12 }

            Text {
                width: parent.width
                leftPadding: dialogContent.sidePadding
                rightPadding: dialogContent.sidePadding
                text: "确定要清空回收站吗？"
                horizontalAlignment: Text.AlignHCenter
                color: popup.contentForegroundColor
                font { pixelSize: 17; weight: Font.Bold }
            }

            Item { width: parent.width; height: 4 }

            Text {
                width: parent.width
                leftPadding: dialogContent.sidePadding
                rightPadding: dialogContent.sidePadding
                text: "所有项目都将被永久删除。\n此操作无法撤销。"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: popup.contentSecondaryColor
                font.pixelSize: 13
                lineHeight: 1.16
            }

            Item { width: parent.width; height: 22 }

            // The buttons keep a row of their own so they can span the card: a
            // positioner would force every child onto the same x.
            Item {
                width: parent.width
                height: buttonRow.height

                Row {
                    id: buttonRow
                    anchors {
                        left: parent.left
                        right: parent.right
                        leftMargin: 16
                        rightMargin: 16
                    }
                    spacing: 8

                    Rectangle {
                        width: (parent.width - parent.spacing) / 2
                        height: 34
                        radius: height / 2
                        color: popup.contentControlFill

                        Text {
                            anchors.centerIn: parent
                            text: "取消"
                            color: popup.contentForegroundColor
                            font { pixelSize: 13; weight: Font.DemiBold }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: DockModelService.setDockPopupVisible(popup, false)
                        }
                    }

                    Rectangle {
                        width: (parent.width - parent.spacing) / 2
                        height: 34
                        radius: height / 2
                        // Same face as the neutral button; only the label carries
                        // the destructive colour, so the pair reads as one row of
                        // buttons instead of a grey block beside a red one.
                        color: popup.contentControlFill

                        Text {
                            anchors.centerIn: parent
                            text: DockTrashService.emptying ? "正在清空…" : "清空回收站"
                            color: DockTrashService.emptying
                                ? Qt.rgba(1.0, 0.23, 0.19, 0.55)
                                : "#ff3b30"
                            font { pixelSize: 13; weight: Font.DemiBold }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !DockTrashService.emptying
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                DockTrashService.empty()
                                DockModelService.setDockPopupVisible(popup, false)
                            }
                        }
                    }
                }
            }

            Item { width: parent.width; height: 16 }
        }

        Rectangle {
            width: 24
            height: 24
            radius: width / 2
            anchors { top: parent.top; right: parent.right; topMargin: 14; rightMargin: 14 }
            color: Qt.rgba(popup.contentForegroundColor.r,
                popup.contentForegroundColor.g,
                popup.contentForegroundColor.b, 0.16)
            border.width: 1
            border.color: Qt.rgba(popup.contentForegroundColor.r,
                popup.contentForegroundColor.g,
                popup.contentForegroundColor.b, 0.18)

            Text {
                anchors.centerIn: parent
                text: "?"
                color: popup.contentForegroundColor
                font { pixelSize: 14; weight: Font.Bold }
            }
        }
    }

    onVisibleChanged: {
        if (!visible)
            DockModelService.releaseDockPopup(popup)
    }
}
