import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.desktop.modules.common
import qs.desktop.modules.dock

// The dual-slider control-centre mark is project-owned artwork (BundledIcons),
// so it renders identically on every machine regardless of the icon theme.
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

    BundledIcon {
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        name: "control-center"
        color: IconAppearanceService.mode === "tint"
            ? IconAppearanceService.styledSymbolicColor()
            : ThemeService.foregroundColor
        opacity: IconAppearanceService.mode !== "color"
            ? IconAppearanceService.opacity * (root.panelOpen ? 1.0 : 0.88)
            : (root.panelOpen ? 1.0 : 0.88)
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
