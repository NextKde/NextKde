import QtQuick
import QtQuick.Controls
import QtQuick.Window
import "../foundation" as Foundation

// An anchored action menu, not a modal editor dialog.
Menu {
    id: root
    property Item anchorItem: null
    property Item sourceItem: null
    property real highlightStrength: 0.32
    property real borderWidth: 0
    property color borderColor: "transparent"
    property real materialOpacity: LiquidStyle.panelMaterialOpacity
    property real cornerRadius: 12
    property real arrowHeight: 8
    property real arrowWidth: 18
    property real anchorGap: 4
    property bool arrowOnBottom: false
    property real arrowX: width / 2
    parent: Overlay.overlay
    popupType: Popup.Item
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    implicitWidth: Math.max(2 * cornerRadius + arrowWidth,
        contentChildren.reduce((widest, item) => Math.max(widest, item.implicitWidth), 0)
        + leftPadding + rightPadding)
    margins: 8
    padding: 6
    topPadding: padding + (arrowOnBottom ? 0 : arrowHeight)
    bottomPadding: padding + (arrowOnBottom ? arrowHeight : 0)
    function updatePosition() {
        if (!anchorItem || !parent) return
        const point = anchorItem.mapToItem(parent, anchorItem.width/2, 0)
        const below = point.y + anchorItem.height + anchorGap
        arrowOnBottom = below + height > parent.height - margins && point.y > parent.height/2
        x = Math.max(margins, Math.min(parent.width-width-margins, point.x-width/2))
        y = arrowOnBottom ? point.y-anchorGap-height : below
        y = Math.max(margins, Math.min(parent.height-height-margins, y))
        arrowX = point.x-x
    }
    function openAtAnchor() {
        if (!anchorItem || !parent) return
        updatePosition()
        open()
        Qt.callLater(updatePosition)
    }
    onAboutToShow: updatePosition()
    onWidthChanged: if (visible) updatePosition()
    onHeightChanged: if (visible) updatePosition()
    Connections {
        target: root.anchorItem ? root.anchorItem.Window.window : null
        enabled: root.visible
        function onAfterAnimating() { root.updatePosition() }
    }
    background: LiquidPopoverSurface {
        backdrop: sceneBackdrop
        highlightStrength: root.highlightStrength
        borderWidth: root.borderWidth
        borderColor: root.borderColor
        materialOpacity: root.materialOpacity
        cornerRadius: root.cornerRadius
        arrowHeight: root.arrowHeight
        arrowWidth: root.arrowWidth
        arrowX: root.arrowX
        arrowOnBottom: root.arrowOnBottom
        LiquidBackdrop {
            id: sceneBackdrop
            sourceItem: root.sourceItem
            registerAsDefault: false
            active: root.visible && !Foundation.AppTheme.reduceTransparency
            blur: 0.85
        }
    }
}
