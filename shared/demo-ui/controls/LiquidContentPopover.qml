import QtQuick
import QtQuick.Controls
import QtQuick.Window
import "../foundation" as Foundation

// Anchored non-modal content/editor panel, retaining Dialog's action signals.
Dialog {
    id: root
    property Item anchorItem: null
    property rect anchorRect: Qt.rect(0, 0, -1, -1)
    property Item sourceItem: null
    property real highlightStrength: 0.32
    property real borderWidth: 0
    property color borderColor: "transparent"
    property real materialOpacity: LiquidStyle.panelMaterialOpacity
    // Glass blending, tint coverage and source blur are independent controls.
    property alias tintStrength: surface.tintStrength
    property alias blurStrength: surface.blurStrength
    property real backdropBlur: 0.85
    property real cornerRadius: 22
    property string preferredSide: "right"
    property string resolvedSide: "right"
    property real arrowPosition: 30
    readonly property real arrowHeight: 8
    readonly property real arrowWidth: 18
    parent: Overlay.overlay
    popupType: Popup.Item
    modal: false
    dim: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 14
    leftPadding: padding + (resolvedSide === "right" ? arrowHeight : 0)
    rightPadding: padding + (resolvedSide === "left" ? arrowHeight : 0)
    topPadding: padding + (resolvedSide === "bottom" ? arrowHeight : 0)
    bottomPadding: padding + (resolvedSide === "top" ? arrowHeight : 0)
    function updatePosition() {
        if (!anchorItem || !parent) return
        const rect = anchorRect.width >= 0 ? anchorRect : Qt.rect(0, 0, anchorItem.width, anchorItem.height)
        const a = anchorItem.mapToItem(parent, rect.x, rect.y)
        const cx = a.x + rect.width/2, cy = a.y + rect.height/2
        const gap = 4, margin = 8
        if (preferredSide === "bottom")
            resolvedSide = a.y + rect.height + gap + height <= parent.height-margin ? "bottom" : "top"
        else if (a.x + rect.width + gap + width <= parent.width-margin)
            resolvedSide = "right"
        else if (a.x-gap-width >= margin)
            resolvedSide = "left"
        else
            resolvedSide = cy < parent.height/2 ? "bottom" : "top"
        const side = resolvedSide
        x = side === "right" ? a.x+rect.width+gap : side === "left" ? a.x-gap-width : cx-width/2
        y = side === "bottom" ? a.y+rect.height+gap : side === "top" ? a.y-gap-height : cy-height/2
        x = Math.max(margin, Math.min(parent.width-width-margin, x))
        y = Math.max(margin, Math.min(parent.height-height-margin, y))
        arrowPosition = side === "right" ? height-(cy-y) : side === "left" ? cy-y : cx-x
    }
    onAnchorItemChanged: if (visible) { if (!anchorItem) close(); else updatePosition() }
    onAboutToShow: updatePosition()
    onOpened: Qt.callLater(updatePosition)
    onWidthChanged: if (visible) updatePosition()
    onHeightChanged: if (visible) updatePosition()
    Connections {
        target: root.anchorItem ? root.anchorItem.Window.window : null
        enabled: root.visible
        function onAfterAnimating() { root.updatePosition() }
    }
    background: Item {
        LiquidBackdrop {
            id: sceneBackdrop
            sourceItem: root.sourceItem
            registerAsDefault: false
            active: root.visible && !Foundation.AppTheme.reduceTransparency
            blur: root.backdropBlur
        }
        LiquidPopoverSurface {
            id: surface
            anchors.centerIn: parent
            readonly property bool sideways: root.resolvedSide === "left" || root.resolvedSide === "right"
            width: sideways ? parent.height : parent.width
            height: sideways ? parent.width : parent.height
            rotation: root.resolvedSide === "right" ? -90 : root.resolvedSide === "left" ? 90 : 0
            backdrop: sceneBackdrop
            cornerRadius: root.cornerRadius
            highlightStrength: root.highlightStrength
            borderWidth: root.borderWidth
            borderColor: root.borderColor
            materialOpacity: root.materialOpacity
            arrowHeight: root.arrowHeight
            arrowWidth: root.arrowWidth
            arrowOnBottom: root.resolvedSide === "top"
            arrowX: root.arrowPosition
        }
    }
}
