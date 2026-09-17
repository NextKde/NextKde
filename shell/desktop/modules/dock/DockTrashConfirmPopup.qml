import QtQuick
import qs.desktop.modules.common

// System-level destructive confirmation. It shares the same centered,
// high-readability KWin glass contract as Wi-Fi credentials.
KosFloatPanel {
    id: popup

    modal: true
    centerOnScreen: true
    backdropMode: "dimBlur"
    backdropTint: "black"
    backdropOpacity: 0.28
    dismissOnBackdrop: true
    contentPadding: 0
    radius: 24
    materialTone: "dark"

    function setDockPopupVisible(shouldOpen) {
        if (shouldOpen)
            popup.open()
        else
            popup.close()
    }

    Item {
        width: Math.min(340, popup.width - 44)
        height: 196

        Row {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 24
            }
            spacing: 16

            Rectangle {
                width: 52
                height: 52
                radius: width / 2
                color: Qt.rgba(1.0, 0.20, 0.25, 0.12)

                BundledIcon {
                    anchors.centerIn: parent
                    name: "user-trash"
                    color: "#e02f3d"
                    size: 24
                }
            }

            Column {
                width: parent.width - 68
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7

                Text {
                    width: parent.width
                    text: "确定要清空回收站吗？"
                    color: popup.contentForegroundColor
                    font { pixelSize: 17; weight: Font.DemiBold }
                }

                Text {
                    width: parent.width
                    text: "回收站中的所有项目都将被永久删除。此操作无法撤销。"
                    wrapMode: Text.WordWrap
                    color: popup.contentSecondaryColor
                    font.pixelSize: 13
                    lineHeight: 1.18
                }
            }
        }

        Row {
            anchors {
                right: parent.right
                bottom: parent.bottom
                rightMargin: 20
                bottomMargin: 20
            }
            spacing: 10

            Rectangle {
                width: 82
                height: 32
                radius: height / 2
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
                width: 116
                height: 32
                radius: height / 2
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
