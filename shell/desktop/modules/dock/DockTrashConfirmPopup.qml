import QtQuick
import Quickshell
import qs.desktop.modules.common

// iPadOS-style destructive confirmation, anchored to the trash icon instead
// of interrupting the desktop with a conventional modal dialog.
PopupWindow {
    id: popup

    property Item anchorItem: null

    implicitWidth: 296
    implicitHeight: 222
    color: "transparent"
    grabFocus: true

    anchor {
        item: popup.anchorItem
        edges: Edges.Top
        gravity: Edges.Top
        margins.top: -12
    }

    function setDockPopupVisible(shouldOpen) {
        visible = shouldOpen
    }

    LiquidGlassSurface {
        anchors.fill: parent
        radius: 22
        baseColor: ThemeService.backgroundColor
        ambientPrimary: Qt.rgba(0.95, 0.22, 0.28, 1)
        ambientSecondary: WallpaperPaletteService.secondary
        ambientStrength: 0.32
        materialDepth: 1.35

        Column {
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 8

            Rectangle {
                width: 40; height: 40; radius: 20
                anchors.horizontalCenter: parent.horizontalCenter
                color: Qt.rgba(1.0, 0.24, 0.30, 0.18)
                Text {
                    anchors.centerIn: parent
                    text: ""
                    color: "#ff5d68"
                    font { family: "Font Awesome 7 Free"; pixelSize: 18; weight: Font.Black }
                }
            }
            Text {
                width: parent.width
                text: "清空回收站？"
                horizontalAlignment: Text.AlignHCenter
                color: ThemeService.foregroundColor
                font { pixelSize: 16; weight: Font.Bold }
            }
            Text {
                width: parent.width - 12
                anchors.horizontalCenter: parent.horizontalCenter
                text: "所有项目将被永久删除，且无法恢复。"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: Qt.rgba(ThemeService.foregroundColor.r, ThemeService.foregroundColor.g,
                    ThemeService.foregroundColor.b, 0.68)
                font.pixelSize: 11
            }
        }

        Column {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
            spacing: 7
            Rectangle {
                width: parent.width; height: 36; radius: 12
                color: Qt.rgba(1.0, 0.25, 0.31, 0.92)
                Text { anchors.centerIn: parent; text: "清空回收站"; color: "white"; font { pixelSize: 12; weight: Font.Bold } }
                MouseArea {
                    anchors.fill: parent
                    enabled: !DockTrashService.emptying
                    onClicked: {
                        // Call the action at the confirmation control itself.
                        // This keeps the destructive operation independent of
                        // popup visibility and menu-dismissal signal timing.
                        DockTrashService.empty()
                        DockModelService.setDockPopupVisible(popup, false)
                    }
                }
            }
            Rectangle {
                width: parent.width; height: 32; radius: 11
                color: Qt.rgba(1, 1, 1, 0.10)
                Text { anchors.centerIn: parent; text: "取消"; color: ThemeService.foregroundColor; font { pixelSize: 12; weight: Font.DemiBold } }
                MouseArea { anchors.fill: parent; onClicked: DockModelService.setDockPopupVisible(popup, false) }
            }
        }
    }

    onVisibleChanged: {
        if (!visible)
            DockModelService.releaseDockPopup(popup)
    }
}
