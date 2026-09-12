import QtQuick
import Quickshell
import qs.desktop.modules.common

// Edge-aware tooltip shared by built-in status items. A PopupWindow is used
// instead of Qt Quick Controls ToolTip because tray items can live in separate
// layer-shell windows on any Dock edge.
PopupWindow {
    id: root

    property Item anchorItem: null
    property bool shown: false
    property bool dockHosted: false
    property string dockEdge: "bottom"
    property string primaryText: ""
    property string secondaryText: ""
    property int minimumWidth: 0

    visible: root.shown && ScreenLifecycle.outputAvailable && root.anchorItem !== null
    implicitWidth: Math.max(root.minimumWidth, tooltipColumn.implicitWidth + 18)
    implicitHeight: tooltipColumn.implicitHeight + 12
    color: "transparent"

    anchor {
        item: root.anchorItem
        edges: !root.dockHosted ? Edges.Bottom
            : root.dockEdge === "left" ? Edges.Right
            : root.dockEdge === "right" ? Edges.Left : Edges.Top
        gravity: !root.dockHosted ? Edges.Bottom
            : root.dockEdge === "left" ? Edges.Right
            : root.dockEdge === "right" ? Edges.Left : Edges.Top
        margins.top: root.dockHosted && root.dockEdge === "bottom" ? -6 : 0
        margins.bottom: root.dockHosted ? 0 : -6
        margins.left: root.dockHosted && root.dockEdge === "right" ? -6 : 0
        margins.right: root.dockHosted && root.dockEdge === "left" ? -6 : 0
    }

    Rectangle {
        anchors.fill: parent
        radius: 7
        color: "#000000"

        Column {
            id: tooltipColumn
            anchors.centerIn: parent
            spacing: 3

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.primaryText
                color: "#ffffff"
                font { family: "Noto Sans CJK SC"; pixelSize: 12; weight: Font.DemiBold }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.secondaryText.length > 0
                text: root.secondaryText
                color: "#ffffff"
                font { family: "Noto Sans CJK SC"; pixelSize: 10; weight: Font.Medium }
            }
        }
    }
}
