import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.notifications
import "../../../Kos/Ui"

// Independent session notification history.
AnimatedPopupWindow {
    id: panel

    property Item anchorItem: null
    property bool dockHosted: false
    property string dockEdge: "bottom"
    readonly property real availableHeight: Math.max(1, (targetScreen?.height ?? 900) - 110)
    implicitWidth: Math.min(336, Math.max(1, (targetScreen?.width ?? 1920) - 24))
    implicitHeight: Math.min(576, availableHeight)
    mask: interactive ? historyInput : emptyHistoryInput
    color: "transparent"
    grabFocus: interactive
    contentItem.scale: 1
    motionOrigin: !dockHosted ? Item.Top
        : dockEdge === "left" ? Item.Left
        : dockEdge === "right" ? Item.Right : Item.Bottom
    PopupAnchorBinding { popupAnchor: panel.anchor; sourceItem: panel.anchorItem }

    anchor {
        edges: !panel.dockHosted ? Edges.Bottom
            : panel.dockEdge === "left" ? Edges.Right
            : panel.dockEdge === "right" ? Edges.Left : Edges.Top
        gravity: !panel.dockHosted ? Edges.Bottom
            : panel.dockEdge === "left" ? Edges.Right
            : panel.dockEdge === "right" ? Edges.Left : Edges.Top
        adjustment: PopupAdjustment.Slide
        margins.top: panel.dockHosted
            && panel.dockEdge === "bottom" ? -8 : 0
        margins.bottom: panel.dockHosted ? 0 : -8
        margins.left: panel.dockHosted
            && panel.dockEdge === "right" ? -8 : 0
        margins.right: panel.dockHosted
            && panel.dockEdge === "left" ? -8 : 0
    }

    readonly property var targetScreen: ScreenLifecycle.activeScreen

    // The surface owns both its outline and compositor blur region.
    onVisibleChanged: {
        if (!visible)
            DockModelService.releaseDockPopup(panel)
    }
    Component.onDestruction: DockModelService.releaseDockPopup(panel)
    BackgroundEffect.blurRegion: (panel.visible && panel.revealProgress > 0
        && AppearanceTokens.surface.usesKwinBlur)
        ? historyPane.blurRegion : null

    function toggle(item) {
        anchorItem = item
        if (requestedOpen) close()
        else show()
    }
    function close() { hide() }

    // If the display server ever closes the popup behind our back, fold the
    // open state too.
    onClosed: {
        if (panel.requestedOpen)
            panel.close()
    }

    Connections {
        target: ScreenLifecycle
        function onOutputAvailableChanged() {
            if (!ScreenLifecycle.outputAvailable)
                panel.close()
        }
    }

    // ── Outside-press and focus-loss dismissal ───────────────────────
    // An AnimatedPopupWindow anchored to the layer-shell Bar cannot take a Wayland
    // popup grab, so an explicit full-screen transparent catcher covers presses
    // on the desktop or the Bar itself when the network list is open.
    PanelWindow {
        id: dismissalCatcher
        screen: panel.targetScreen
        visible: ScreenLifecycle.outputAvailable && panel.targetScreen !== null
            && panel.requestedOpen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-notification-history-backdrop"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.ArrowCursor
            onPressed: panel.close()
        }
    }

    Connections {
        target: WindowService
        function onActiveWindowIdChanged() {
            if (panel.requestedOpen)
                panel.close()
        }
    }

    Connections {
        target: ContextMenuCoordinator
        function onActiveMenuChanged() {
            if (ContextMenuCoordinator.activeMenu
                    && panel.requestedOpen)
                panel.close()
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: panel.requestedOpen
        onActivated: panel.close()
    }

    Region { id: emptyHistoryInput }
    Item { id: popupCapture; width: panel.width; height: panel.height }
    Item {
        id: inputArea
        width: panel.width
        y: Math.max(0, deckCanvas.y - deckViewport.contentY)
        height: Math.max(0, Math.min(deckViewport.height,
            deckCanvas.y - deckViewport.contentY + deckCanvas.height) - y)
    }
    RoundedBlurRegion { id: historyInput; item: inputArea; radius: 0 }
    Flickable {
        id: deckViewport
        width: panel.width; height: panel.height
        contentWidth: panel.width; contentHeight: Math.max(height, deckCanvas.height)
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.AutoFlickIfNeeded
        interactive: contentHeight > height + 1 || contentWidth > width + 1
        clip: true
        KosKineticScroll { flickable: deckViewport; horizontal: true }
    }
    Item {
        id: deckCanvas
        parent: deckViewport.contentItem
        width: panel.width; height: historyPane.height + 16
        y: panel.dockHosted && panel.dockEdge === "bottom" ? Math.max(0, deckViewport.height - height) : 0
        scale: AppearanceTokens.motion.popupStartScale + (1 - AppearanceTokens.motion.popupStartScale) * panel.revealProgress
        transformOrigin: panel.motionOrigin
        NotificationHistoryPane {
            id: historyPane
            x: 20; y: 8; width: Math.max(1, parent.width - 40)
            maximumHeight: Math.min(560, Math.max(208, panel.availableHeight - 16))
            height: desiredHeight
            captureAnchor: popupCapture
            outerViewport: deckViewport
            active: panel.requestedOpen
            glassOpacity: panel.revealProgress
            backdropScale: deckCanvas.scale
        }
    }
    onRequestedOpenChanged: {
        if (requestedOpen) {
            deckViewport.contentX = 0
            deckViewport.contentY = 0
            historyPane.reset()
            if (dockHosted) DockModelService.openDockPopup(panel)
        }
    }
}
