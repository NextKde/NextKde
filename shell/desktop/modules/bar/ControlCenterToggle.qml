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
    property real iconSize: 18
    rotation: verticalDock ? -90 : 0
    implicitWidth: 24
    implicitHeight: 24
    width: implicitWidth
    height: implicitHeight

    DockStatusSvgIcon {
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
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
    StatusTooltip {
        anchorItem: root
        shown: hoverArea.containsMouse && !root.panelOpen
        dockHosted: root.dockHosted
        dockEdge: root.dockEdge
        primaryText: "控制中心"
        minimumWidth: 92
    }
}
