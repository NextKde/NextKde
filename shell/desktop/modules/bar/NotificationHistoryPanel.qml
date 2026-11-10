import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.notifications
import "../../../shared/qml/i18n"
import "../../../Kos/Ui"

// Independent session notification history.
PersistentPanelWindow {
    id: panel

    property Item anchorItem: null
    property bool dockHosted: false
    property string dockEdge: "bottom"
    readonly property real availableHeight: Math.max(1, (targetScreen?.height ?? 900) - 110)
    implicitWidth: Math.min(336, Math.max(1, (targetScreen?.width ?? 1920) - 24))
    implicitHeight: Math.min(576, availableHeight)
    color: "transparent"
    contentItem.scale: 1
    motionOrigin: !dockHosted ? Item.Top
        : dockEdge === "left" ? Item.Left
        : dockEdge === "right" ? Item.Right : Item.Bottom

    // AnimatedPopupWindow's public surface, kept so BarStatusArea and the dock
    // popup plumbing do not need to change.
    property bool requestedOpen: false
    property bool animationEnabled: true
    property int openDuration: AppearanceTokens.motion.popupOpenDuration
    property int closeDuration: AppearanceTokens.motion.popupCloseDuration
    readonly property real revealProgress: animationEnabled ? ncMotion.progress : 1
    readonly property bool interactive: effectiveOpen && (!animationEnabled || ncMotion.interactive)
    readonly property bool effectiveOpen: requestedOpen && ScreenLifecycle.outputAvailable
    motion: ncMotion
    function show() { requestedOpen = true }
    function hide() { requestedOpen = false }
    function setDockPopupVisible(shouldOpen) { requestedOpen = shouldOpen }
    function dismissDockPopupImmediately() { requestedOpen = false; ncMotion.reset() }
    // Deferred open: let a few frames render before the reveal starts.
    property int _openPreroll: 0
    FrameAnimation {
        running: panel._openPreroll > 0
        onTriggered: {
            panel._openPreroll--
            if (panel._openPreroll === 0 && ncMotion.requestedOpen)
                ncMotion.open()
        }
    }
    onEffectiveOpenChanged: {
        if (effectiveOpen) {
            ncMotion.requestedOpen = true
            ncMotion.mapped = true
            panel._openPreroll = 3
        } else if (!ScreenLifecycle.outputAvailable) {
            ncMotion.reset()
        } else {
            ncMotion.close()
        }
    }
    signal closed()
    // Clicking outside used to be dismissed by the compositor's popup grab.
    // A persistent surface has to do it itself; the press still reaches the
    // window underneath, which is the same result a popup gave.
    property double _suppressToggleUntil: 0
    Connections {
        target: WindowService
        function onGlobalPointerPressed(x, y, button, timestamp) {
            if (!(panel.interactive))
                return
            if (x < panel.globalX || x > panel.globalX + panel.width
                    || y < panel.globalY || y > panel.globalY + panel.height) {
                panel._suppressToggleUntil = Date.now() + 350
                panel.close()
            }
        }
    }
    PopupMotion {
        id: ncMotion
        openDuration: panel.animationEnabled ? panel.openDuration : 0
        closeDuration: panel.animationEnabled ? panel.closeDuration : 0
    }
    Connections {
        target: ncMotion
        function onClosed() {
            DockModelService.releaseDockPopup(panel)
            panel.closed()
        }
    }

    readonly property var targetScreen: ScreenLifecycle.activeScreen

    // The surface owns both its outline and compositor blur region.
    onVisibleChanged: {
        if (!visible)
            DockModelService.releaseDockPopup(panel)
    }
    Component.onDestruction: DockModelService.releaseDockPopup(panel)
    // v8 cards publish their own glass declarations and leave this legacy
    // aggregate empty. An empty blur region can mean the entire popup to the
    // compositor, exposing a rectangular backdrop while the cards fade out.
    BackgroundEffect.blurRegion: (panel.visible && panel.revealProgress > 0
        && AppearanceTokens.surface.usesKwinBlur && historyPane.legacyBlurRegions.length > 0)
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
