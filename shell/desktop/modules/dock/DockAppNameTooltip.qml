import QtQuick
import Quickshell
import qs.desktop.modules.common

// One shared label for the Dock; isolated DockIcon hosts can load it lazily.
PopupWindow {
    id: tooltip
    property Item targetIcon: null
    readonly property string dockEdge: targetIcon ? targetIcon.dockEdge : "bottom"
    readonly property bool shouldShow: targetIcon !== null
        && targetIcon._hovering && !targetIcon._hasWindows && !targetIcon.isRunning
        && targetIcon.displayName.trim().length > 0 && !targetIcon.editMode
        && !DockModelService.activeContextMenu
    property bool dwellComplete: false

    function restartDwell() {
        nameDwell.stop()
        dwellComplete = false
        if (shouldShow) nameDwell.start()
    }
    onTargetIconChanged: restartDwell()
    onShouldShowChanged: restartDwell()
    Component.onCompleted: restartDwell()
    Timer {
        id: nameDwell
        interval: DockAnimation.appNameTooltipDelay
        repeat: false
        onTriggered: tooltip.dwellComplete = tooltip.shouldShow
    }
    visible: shouldShow && dwellComplete
    mask: Region { item: null }
    implicitWidth: appNameText.implicitWidth + 16
    implicitHeight: appNameText.implicitHeight + 10
    color: "transparent"

    function refreshAnchor() {
        if (visible && targetIcon) anchor.updateAnchor()
    }
    onVisibleChanged: {
        if (visible) Qt.callLater(refreshAnchor)
    }
    // Apply the anchor after the shared frame's transforms have propagated.
    // callLater coalesces simultaneous changes rather than posting per-property work.
    Connections {
        target: tooltip.targetIcon ? tooltip.targetIcon.magnificationRoot : null
        enabled: tooltip.visible && tooltip.targetIcon !== null
            && tooltip.targetIcon._usesSharedMagnification
        ignoreUnknownSignals: true
        function on_HoverLayoutChanged() { Qt.callLater(tooltip.refreshAnchor) }
        function onWidthChanged() { Qt.callLater(tooltip.refreshAnchor) }
        function onHeightChanged() { Qt.callLater(tooltip.refreshAnchor) }
    }
    Connections {
        target: tooltip.targetIcon
        enabled: tooltip.visible && tooltip.targetIcon !== null
            && !tooltip.targetIcon._usesSharedMagnification
        function onScaleChanged() { Qt.callLater(tooltip.refreshAnchor) }
        function onXChanged() { Qt.callLater(tooltip.refreshAnchor) }
        function onYChanged() { Qt.callLater(tooltip.refreshAnchor) }
    }
    PopupAnchorBinding { popupAnchor: tooltip.anchor; sourceItem: tooltip.targetIcon }

    anchor {
        edges: tooltip.dockEdge === "bottom" ? Edges.Top
            : tooltip.dockEdge === "left" ? Edges.Right : Edges.Left
        gravity: tooltip.anchor.edges
        margins.top: tooltip.dockEdge === "bottom" ? -6 : 0
        margins.left: tooltip.dockEdge === "right" ? -6 : 0
        margins.right: tooltip.dockEdge === "left" ? -6 : 0
    }
    Rectangle {
        anchors.fill: parent
        radius: 6
        color: ThemeService.tooltipBackground
        border.width: 1
        border.color: ThemeService.borderColor
        Text {
            id: appNameText
            anchors.centerIn: parent
            text: tooltip.targetIcon ? tooltip.targetIcon.displayName : ""
            color: ThemeService.foregroundColor
            font {
                family: AppearanceTokens.typography.textChain
                pixelSize: 11
                weight: Font.DemiBold
            }
        }
    }
}
