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
    radius: 24
    materialTone: "auto"

    function setDockPopupVisible(shouldOpen) {
        if (shouldOpen)
            popup.open()
        else
            popup.close()
    }

    Item {
        width: Math.min(340, popup.width - 44)
        height: 242

        Rectangle {
            width: 58
            height: 58
            radius: width / 2
            anchors { top: parent.top; topMargin: 24; horizontalCenter: parent.horizontalCenter }
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

        Column {
            anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 94; leftMargin: 24; rightMargin: 24 }
            spacing: 7

            Text {
                width: parent.width
                text: "确定要清空回收站吗？"
                horizontalAlignment: Text.AlignHCenter
                color: popup.contentForegroundColor
                font { pixelSize: 17; weight: Font.Bold }
            }

            Text {
                width: parent.width
                text: "所有项目都将被永久删除。\n此操作无法撤销。"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: popup.contentSecondaryColor
                font.pixelSize: 13
                lineHeight: 1.16
            }
        }

        Row {
            anchors {
                right: parent.right
                bottom: parent.bottom
                left: parent.left
                leftMargin: 16
                rightMargin: 16
                bottomMargin: 16
            }
            spacing: 8

            Rectangle {
                width: (parent.width - parent.spacing) / 2
                height: 34
                radius: 9
                color: popup.contentControlFill
                border.width: 1
                border.color: popup.contentControlBorder

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
                radius: 9
                color: DockTrashService.emptying ? "#c76a70" : "#d92f3d"

                Text {
                    anchors.centerIn: parent
                    text: DockTrashService.emptying ? "正在清空…" : "清空回收站"
                    color: "white"
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

    onVisibleChanged: {
        if (!visible)
            DockModelService.releaseDockPopup(popup)
    }
}
