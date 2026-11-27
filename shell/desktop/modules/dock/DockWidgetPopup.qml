import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common
import qs.desktop.modules.deskcenter
import "../../../Kos/Ui"

// Unified hover detail popup shell for third-party and package-backed Dock widgets.
// The host owns the glass/Material surface, fixed 300px width, clamped 72..480px
// height, internal scroll when overflowing, blur region, dwell motion and edge
// anchoring across bottom, left and right Docks. Package `Popup.qml` only defines
// foreground layout and `implicitHeight` (or `popupHeight`).
AnimatedPopupWindow {
    id: popup

    property Item anchorItem: null
    property string dockEdge: "bottom" // "bottom" | "left" | "right"
    property var packageEntry: null

    readonly property bool pointerInside: popupHover.hovered
    readonly property int fixedPopupWidth: 300
    readonly property int minPopupHeight: 72
    readonly property int maxPopupHeight: 480
    readonly property real rawDesiredHeight: popupHost.preferredContentHeight > 0
        ? popupHost.preferredContentHeight : 160
    readonly property int clampedHeight: Math.round(
        Math.max(minPopupHeight, Math.min(maxPopupHeight, rawDesiredHeight)))
    readonly property var popupAppearance: {
        const base = WidgetHostService.widgetAppearance
        return Object.assign({}, base, {
            foreground: ThemeService.foregroundColor,
            palette: AppearanceTokens.isMaterial ? (base.palette ?? ({})) : ({})
        })
    }

    motionOrigin: dockEdge === "bottom"
        ? Item.Bottom : (dockEdge === "left" ? Item.Left : Item.Right)
    openDuration: DockAnimation.infoPopupEntranceDuration
    implicitWidth: fixedPopupWidth
    implicitHeight: clampedHeight
    color: "transparent"
    grabFocus: false
    BackgroundEffect.blurRegion: popup.visible && popup.revealProgress > 0
        && AppearanceTokens.surface.usesKwinBlur ? popupSurface.blurRegion : null

    PopupAnchorBinding { popupAnchor: popup.anchor; sourceItem: popup.anchorItem }

    anchor {
        edges: popup.dockEdge === "bottom" ? Edges.Top
            : (popup.dockEdge === "left" ? Edges.Right : Edges.Left)
        gravity: popup.dockEdge === "bottom" ? Edges.Top
            : (popup.dockEdge === "left" ? Edges.Right : Edges.Left)
        margins.top: popup.dockEdge === "bottom" ? -12 : 0
        margins.right: popup.dockEdge === "left" ? -12 : 0
        margins.left: popup.dockEdge === "right" ? -12 : 0
    }

    function requestClose() { hide() }

    Item {
        id: panel
        anchors.fill: parent
        transformOrigin: popup.motionOrigin

        LiquidGlassPanel {
            id: popupSurface
            anchors.fill: parent
            radius: 18
            cornerExponent: AppearanceTokens.shape.cornerExponent
            baseColor: ThemeService.backgroundColor
            surfaceOpacity: 1.0
            scrimEnabled: AppearanceTokens.surface.usesBackdrop
            scrimLevel: "subtle"
        }

        Flickable {
            id: popupFlick
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: Math.max(height, Math.round(popup.rawDesiredHeight))
            interactive: contentHeight > height + 1

            WidgetPackageHost {
                id: popupHost
                x: 0
                y: 0
                width: popupFlick.width
                height: popupFlick.contentHeight
                useImplicitHeight: true
                packageId: String(popup.packageEntry?.id ?? "")
                instanceId: "dock:" + String(popup.packageEntry?.id ?? "")
                widgetEntry: (popup.visible || popup.requestedOpen) && popup.packageEntry?.hasPopup
                    ? String(popup.packageEntry?.popupEntry ?? "") : ""
                packageRevision: String(popup.packageEntry?.revision ?? "")
                containerType: "dock"
                containerOrientation: popup.dockEdge === "bottom" ? "horizontal" : "vertical"
                hostActive: popup.visible
                widgetSize: [Math.max(2, Math.min(4, Number(popup.packageEntry?.dockUnits) || 4)), 1]
                appearance: popup.popupAppearance
            }
        }

        HoverHandler {
            id: popupHover
        }
    }
}
