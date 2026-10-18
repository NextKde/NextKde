import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../shared/qml/i18n"
import "../../../Kos/Ui"
import "StatusCollection.mjs" as StatusCollection

AnimatedPopupWindow {
    id: popup
    required property var coordinator
    required property Item anchorItem
    property bool dockHosted: false
    property string dockEdge: "bottom"
    readonly property var targetScreen: popup.anchorItem ? (popup.anchorItem.QsWindow.window?.screen ?? ScreenLifecycle.activeScreen) : ScreenLifecycle.activeScreen
    readonly property var layoutMetrics: StatusCollection.popupGeometry(coordinator.previewCollectionKeys.length,
        (targetScreen?.height ?? 900) - 120)
    readonly property alias grid: collectionGrid
    requestedOpen: coordinator.collectionExpanded
    implicitWidth: 300
    implicitHeight: layoutMetrics.height
    color: "transparent"
    // Native DnD owns its pointer grab; opening the destination must not
    // acquire keyboard focus or scale the drop coordinates beneath it.
    grabFocus: interactive && coordinator.draggedKey === ""
    contentItem.scale: 1
    motionOrigin: !dockHosted ? Item.Top
        : dockEdge === "left" ? Item.Left
        : dockEdge === "right" ? Item.Right : Item.Bottom
    PopupAnchorBinding { popupAnchor: popup.anchor; sourceItem: popup.anchorItem }
    anchor {
        edges: !popup.dockHosted ? Edges.Bottom
            : popup.dockEdge === "left" ? Edges.Right
            : popup.dockEdge === "right" ? Edges.Left : Edges.Top
        gravity: !popup.dockHosted ? Edges.Bottom
            : popup.dockEdge === "left" ? Edges.Right
            : popup.dockEdge === "right" ? Edges.Left : Edges.Top
        adjustment: PopupAdjustment.Slide
        margins.top: popup.dockHosted && popup.dockEdge === "bottom" ? -8 : 0
        margins.bottom: popup.dockHosted ? 0 : -8
        margins.left: popup.dockHosted && popup.dockEdge === "right" ? -8 : 0
        margins.right: popup.dockHosted && popup.dockEdge === "left" ? -8 : 0
    }
    onClosed: coordinator.closeCollection()
    BackgroundEffect.blurRegion: popup.visible && popup.revealProgress > 0
        && AppearanceTokens.surface.usesKwinBlur ? surface.blurRegion : null

    LiquidGlassPanel {
        id: surface
        anchors.fill: parent
        radius: 16
        cornerExponent: 2.35
        baseColor: ThemeService.backgroundColor
        surfaceOpacity: 0.98
        scrimEnabled: AppearanceTokens.surface.usesBackdrop
        scrimLevel: AppearanceTokens.bar.popupScrimLevel
    }
    Flickable {
        id: viewport
        x: popup.layoutMetrics.padding
        y: popup.layoutMetrics.padding
        width: popup.width - 2 * x
        height: popup.layoutMetrics.viewportHeight
        contentWidth: width
        contentHeight: popup.layoutMetrics.contentHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height && popup.coordinator.draggedKey === ""
        onVisibleChanged: if (visible) contentY = 0
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Item {
            id: collectionGrid
            x: (viewport.width - popup.layoutMetrics.columns * popup.layoutMetrics.cellSize
                - (popup.layoutMetrics.columns - 1) * popup.layoutMetrics.spacing) / 2
            width: viewport.width - 2 * x
            height: popup.layoutMetrics.contentHeight
        }
        Text {
            anchors.fill: parent
            visible: popup.coordinator.previewCollectionKeys.length === 0
            text: I18n.tr("Drag icons here to collect")
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: ThemeService.foregroundColor
            opacity: 0.6
            font.pixelSize: 12
        }
        // DnD move events continue while this timer scrolls a tall collection.
        Timer {
            interval: 30
            repeat: true
            running: popup.coordinator.dragTarget === "collection"
                && popup.coordinator.dragScrollDirection !== 0
            onTriggered: viewport.contentY = Math.max(0, Math.min(viewport.contentHeight - viewport.height,
                viewport.contentY + popup.coordinator.dragScrollDirection * 8))
        }
        onContentYChanged: popup.coordinator.refreshCollectionDrop()
    }
    Text {
        x: 12
        y: viewport.y + viewport.height + 8
        width: popup.width - 24
        text: I18n.tr("Alt-drag to reorder, collect or keep visible")
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        color: ThemeService.foregroundColor
        opacity: 0.6
        font.pixelSize: 10
    }
    StatusCollectionDropArea {
        id: popupDropArea
        anchors.fill: parent
        coordinator: popup.coordinator
        section: "collection"
        z: 100
    }
}
