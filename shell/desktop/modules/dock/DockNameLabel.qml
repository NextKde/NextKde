import QtQuick
import qs.desktop.modules.common

// A single node in the Dock's render tree. One dwell timer gates the first
// appearance; subsequent icon changes keep the visible label continuous.
Rectangle {
    id: label
    objectName: "dockSharedNameLabel"
    property Item targetIcon: null
    property Item pointerRoot: null
    property point pointerPosition: Qt.point(-10000, -10000)
    readonly property bool eligible: targetIcon !== null && targetIcon.dockNameEligible === true
    property bool dwellComplete: false
    visible: eligible && dwellComplete
    enabled: false
    z: 1000
    width: Math.min(DockAnimation.nameLabelMaximumWidth, labelText.implicitWidth + 16)
    height: DockAnimation.nameLabelMaximumHeight
    radius: 6
    color: ThemeService.tooltipBackground
    border.width: 1
    border.color: ThemeService.borderColor
    function updateGeometry() {
        const icon = targetIcon
        if (!icon || !parent || !pointerRoot) return
        const center = icon.mapToItem(parent, icon.width / 2, icon.height / 2)
        const pointer = pointerRoot.mapToItem(parent, pointerPosition.x, pointerPosition.y)
        const extent = icon.iconSize * icon.scale / 2 + DockAnimation.nameLabelGap
        const edge = icon.dockEdge
        const px = edge === "bottom" ? pointer.x - width / 2
            : edge === "left" ? center.x + extent : center.x - extent - width
        const py = edge === "bottom" ? center.y - extent - height : pointer.y - height / 2
        x = Math.max(0, Math.min(Math.max(0, parent.width - width), px))
        y = Math.max(0, Math.min(Math.max(0, parent.height - height), py))
    }
    function synchronizeDwell() {
        if (!eligible) {
            nameDwell.stop()
            dwellComplete = false
        } else if (!dwellComplete) {
            nameDwell.restart()
        }
    }
    onTargetIconChanged: {
        updateGeometry()
        synchronizeDwell()
    }
    onEligibleChanged: synchronizeDwell()
    Component.onCompleted: synchronizeDwell()
    Timer {
        id: nameDwell
        interval: DockAnimation.appNameTooltipDelay
        repeat: false
        onTriggered: {
            if (label.eligible) {
                label.dwellComplete = true
                label.updateGeometry()
            }
        }
    }
    onPointerPositionChanged: updateGeometry()
    onWidthChanged: updateGeometry()
    ShellText {
        id: labelText
        anchors.centerIn: parent
        width: Math.min(implicitWidth, label.width - 16)
        text: label.targetIcon ? label.targetIcon.displayName : ""
        color: ThemeService.foregroundColor
        elide: Text.ElideRight
        font.family: "Noto Sans CJK SC, sans-serif"
        font.pixelSize: 11
        font.weight: Font.DemiBold
    }
}
