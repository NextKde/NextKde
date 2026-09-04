import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.desktop.modules.common
import qs.desktop.modules.dock

// Resolve the familiar dual-slider control-centre mark from the active system
// icon theme. This name is shared by Breeze, Oxygen, Fluent, Tela and Tahoe.
Item {
    id: root
    signal panelToggleRequested()
    property bool panelOpen: false
    property bool dockHosted: false
    property string dockEdge: "bottom"
    property bool verticalDock: false
    rotation: verticalDock ? -90 : 0
    implicitWidth: 24
    implicitHeight: 24
    width: implicitWidth
    height: implicitHeight

    DockStatusSvgIcon {
        anchors.centerIn: parent
        width: 20
        height: 20
        source: Qt.resolvedUrl("../../assets/control-center.svg")
        opacity: root.panelOpen ? 1.0 : 0.88
    }
    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.panelToggleRequested()
    }
    PopupWindow {
        id: controlCenterTooltip
        visible: hoverArea.containsMouse && !root.panelOpen
        implicitWidth: 92; implicitHeight: 26; color: "transparent"

        Connections {
            target: ScreenLifecycle
            function onOutputAvailableChanged() {
                if (!ScreenLifecycle.outputAvailable)
                    controlCenterTooltip.visible = false
            }
        }
        anchor {
            item: root
            edges: !root.dockHosted ? Edges.Bottom
                : root.dockEdge === "left" ? Edges.Right
                : root.dockEdge === "right" ? Edges.Left : Edges.Top
            gravity: !root.dockHosted ? Edges.Bottom
                : root.dockEdge === "left" ? Edges.Right
                : root.dockEdge === "right" ? Edges.Left : Edges.Top
            margins.top: root.dockHosted
                && root.dockEdge === "bottom" ? -5 : 0
            margins.bottom: root.dockHosted ? 0 : -5
            margins.left: root.dockHosted
                && root.dockEdge === "right" ? -5 : 0
            margins.right: root.dockHosted
                && root.dockEdge === "left" ? -5 : 0
        }
        Rectangle { anchors.fill: parent; radius: 7; color: ThemeService.tooltipBackground
            Text { anchors.centerIn: parent; text: "控制中心"; color: ThemeService.foregroundColor; font.pixelSize: 10 }
        }
    }
}
