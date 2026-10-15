import QtQuick
import "controlcenter" as ControlParts
import QtQuick.Controls
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.notifications
import qs.desktop.modules.platform
import qs.desktop.modules.stage
import "../../../shared/qml/i18n"
import "../../../Kos/Ui"
import "../../../shared/qml/controls" as LiquidControls

// Compact desktop adaptation of the supplied Control Center reference.
// Its geometry intentionally stays small enough for a top-bar popup while
// preserving the reference's two-column, pill-and-media-card hierarchy.
//
PopupWindow {
    id: panel

    implicitWidth: Math.min(panel.controlCenterWidth, Math.max(1, (panel.targetScreen?.width ?? 1920) - 24))
    implicitHeight: panel.controlCenterHeight
    color: "transparent"
    grabFocus: popupMotion.interactive
    visible: popupMotion.mapped
    // The whole surface animates as one block: opacity + a small scale around
    // the anchor edge. Animating the shared contentItem instead of each card's
    // x/y/scale keeps every card's compositor blur shape locked to the same
    // transform, so the frosted silhouettes move together instead of drifting
    // as a dozen independent regions.
    contentItem.opacity: popupMotion.progress
    contentItem.scale: 1
    contentItem.transformOrigin: !panel.dockHosted ? Item.Top
        : panel.dockEdge === "left" ? Item.Left
        : panel.dockEdge === "right" ? Item.Right : Item.Bottom
    contentItem.enabled: popupMotion.interactive
    mask: popupMotion.interactive ? panelInputRegion : emptyRegion
    PopupAnchorBinding { popupAnchor: panel.anchor; sourceItem: panel.anchorItem }

    anchor {
        edges: !panel.dockHosted ? Edges.Bottom
            : panel.dockEdge === "left" ? Edges.Right
            : panel.dockEdge === "right" ? Edges.Left : Edges.Top
        gravity: !panel.dockHosted ? Edges.Bottom
            : panel.dockEdge === "left" ? Edges.Right
            : panel.dockEdge === "right" ? Edges.Left : Edges.Top
        adjustment: PopupAdjustment.Slide
        margins.top: 0
        margins.bottom: panel.dockHosted ? 0 : -4
        margins.left: 0
        margins.right: 0
    }

    property Item anchorItem: null
    property bool dockHosted: false
    property string dockEdge: "bottom"
    property real volumePreview: ControlCenterService.volumePercent
    property bool draggingVolume: false
    property real brightnessPreview: ControlCenterService.brightnessPercent
    readonly property var player: DockMprisService.activePlayer
    property bool draggingBrightness: false
    property bool sessionModalVisible: false
    // Reveal progress of the auto-hiding Bar this panel hangs off (1 when the
    // Bar is permanently visible or the panel is Dock hosted).
    property real barRevealProgress: 1
    // Set while an open request is waiting for the Bar to settle before the
    // popup window is created. See anchorSettled.
    property bool pendingOpen: false
    // A PopupWindow measures its anchor rectangle once, when its window is
    // created. The Bar translates its whole content while auto-hiding
    // (barWrapper.y), so creating the window while the Bar is still hidden
    // anchors the panel to the hidden Bar and leaves it overlapping the Bar
    // once the Bar slides back in -- which is exactly what the Super+B
    // shortcut hit, because a shortcut can arrive with the Bar put away.
    // `requestedOpen` is already true while we wait, so the Bar's own popup
    // inhibitor slides the Bar out first and the window is only created once
    // it has stopped moving.
    readonly property bool anchorSettled: panel.dockHosted || panel.barRevealProgress > 0.999
    property string pendingConfirmAction: ""
    property string confirmActionLabel: ""
    property alias logoutConfirmationVisible: panel.sessionModalVisible
    property string activeSubmenu: ""
    property bool submenuOpen: false
    readonly property string requestedPage: sessionModalVisible
        ? (pendingConfirmAction !== "" ? "confirm" : "session") : activeSubmenu
    readonly property string displayedSubmenu: pageMotion.displayedPage
    readonly property real revealProgress: popupMotion.progress
    readonly property real pageProgress: pageMotion.progress
    // Page currently fading out during a crossfade, "" once the transition
    // settles. Cards bound to it stay mapped (and fade) instead of being cut
    // the frame the new page commits.
    readonly property string outgoingPage: pageMotion.outgoingPage
    readonly property bool hasActiveSubmenu: activeSubmenu !== "" || sessionModalVisible
    readonly property bool dockFacingLayout: dockHosted && dockEdge !== "top"
    readonly property bool notificationsAboveControls: dockHosted
    // The controls already have a 20px top inset. When the notification deck
    // precedes them, consume that inset instead of adding a second section gap.
    readonly property int historyLayoutAdjustment: notificationsAboveControls ? -20 : 12
    readonly property real mainControlsOffsetY: notificationsAboveControls && historyShown
        ? notificationHistory.height + historyLayoutAdjustment : 0
    signal networkRequested()
    signal bluetoothRequested()
    signal wifiNetworkSelected(var network)

    function openSubmenu(name) {
        if (name === "session") {
            openSessionPanel()
            return
        }
        _triggerTransitionGuard()
        activeSubmenu = name
        submenuOpen = true
        sessionModalVisible = false
        if (name === "wifi") {
            NetworkService.refreshWifiNetworks()
        } else if (name === "bluetooth") {
            ControlCenterService.refresh()
            ControlCenterService.refreshBluetoothDevices()
        } else if (name === "brightness") {
            ControlCenterService.refresh()
        }
        if (!coordinator.open)
            coordinator.openAll()
    }

    function closeSubmenu() {
        _triggerTransitionGuard()
        submenuOpen = false
        sessionModalVisible = false
        pendingConfirmAction = ""
        activeSubmenu = ""
    }
    function openSettingsModule(module) {
        panel.close()
        // The platform daemon owns launching KCMs (allow-listed module names,
        // fixed argv); a closing popup or a stale response cannot swallow the
        // click because the daemon, not this window, spawns kcmshell6.
        PlatformClient.request("settings.open", { module: module },
            function(response) {
                if (!response?.ok)
                    console.warn("[ControlCenter] settings module failed: " + module
                        + " " + (response?.error?.message || "platform unavailable"))
            })
    }

    onNetworkRequested: openSubmenu("wifi")
    onBluetoothRequested: openSubmenu("bluetooth")

    // Bar reads this for sharedPanelOpen / toggle state. A deferred open
    // (pendingOpen) already counts as open: it is what keeps the Bar revealed
    // while the panel waits for the Bar to settle.
    readonly property bool isOpen: coordinator.open || panel.pendingOpen

    // The target screen (the bar's output). Cards live on the same screen.
    readonly property var targetScreen: ScreenLifecycle.activeScreen
    // Keep the main controls compact. The sound page needs its original
    // 420px card plus both 20px margins; keep that room through its outgoing
    // transition so neither the card nor its compositor blur is clipped.
    readonly property int controlAreaHeight: requestedPage === "sound"
        || displayedSubmenu === "sound" || outgoingPage === "sound" ? 460 : 411
    // A fixed compositor envelope prevents window/texture reallocations while
    // the deck unfolds. Empty envelope space is click-through. Compact outputs
    // scroll the original-size controls instead of shrinking text and buttons.
    readonly property real availableHeight: Math.max(1, (targetScreen?.height ?? 900) - 110)
    readonly property real fitScale: 1
    readonly property bool historyShown: cardMapped("")
        && (NotificationHistoryService.count > 0
            || !notificationHistory.historyEmptyReady
            || notificationHistory.historyExitCount > 0)
    readonly property real historyMaximumHeight: Math.min(560,
        Math.max(208, availableHeight - controlAreaHeight - historyLayoutAdjustment))
    readonly property real historyHeight: historyShown ? notificationHistory.desiredHeight : 0
    readonly property real naturalContentHeight: controlAreaHeight
        + (historyShown ? notificationHistory.height + historyLayoutAdjustment : 0)
    readonly property int controlCenterHeight: Math.min(availableHeight, 460 + 560 + 12)
    readonly property int controlCenterWidth: Math.max(296, Math.min(336, (targetScreen?.width ?? 1920) - 24))
    readonly property real controlsWidth: controlCenterWidth - 40
    readonly property real connectivityWidth: Math.round((controlsWidth - 8) * 137 / 288)
    readonly property real mediaWidth: controlsWidth - connectivityWidth - 8
    readonly property real quickControlWidth: (controlsWidth - 36) / 5
    readonly property real halfControlWidth: (controlsWidth - 8) / 2
    readonly property real canvasOffsetY: panelCanvas.y
    Item {
        id: popupCapture
        width: panel.width
        height: panel.height
    }
    Item {
        id: inputArea
        width: panel.width
        y: Math.max(0, panelCanvas.y - controlViewport.contentY)
        height: Math.max(0, Math.min(controlViewport.height,
            panelCanvas.y - controlViewport.contentY + panel.naturalContentHeight) - y)
    }
    RoundedBlurRegion { id: panelInputRegion; item: inputArea; radius: 0 }
    Flickable {
        id: controlViewport
        objectName: "control-center-viewport"
        width: panel.width
        height: panel.height
        contentWidth: panel.controlCenterWidth
        contentHeight: Math.max(height, panel.naturalContentHeight)
        interactive: contentHeight > height + 1 || contentWidth > width + 1
        flickableDirection: Flickable.AutoFlickIfNeeded
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ScrollBar.vertical: ScrollBar { policy: controlViewport.contentHeight > controlViewport.height + 1 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff; width: 3 }
        KosKineticScroll { flickable: controlViewport; horizontal: true }
    }
    Item {
        id: panelCanvas
        parent: controlViewport.contentItem
        width: panel.controlCenterWidth
        height: panel.naturalContentHeight
        y: panel.dockFacingLayout ? Math.max(0, controlViewport.height - height) : 0
        scale: AppearanceTokens.motion.popupStartScale + (1 - AppearanceTokens.motion.popupStartScale) * popupMotion.progress
        transformOrigin: !panel.dockHosted ? Item.Top
            : panel.dockEdge === "left" ? Item.Left : panel.dockEdge === "right" ? Item.Right : Item.Bottom
    }
    NotificationHistoryPane {
        id: notificationHistory
        showEmptyState: false
        parent: panelCanvas
        x: 20
        y: panel.notificationsAboveControls ? 0 : panel.controlAreaHeight
        width: panel.controlsWidth
        maximumHeight: panel.historyMaximumHeight
        height: panel.historyHeight
        captureAnchor: popupCapture
        outerViewport: controlViewport
        visible: panel.historyShown
        opacity: panel.pageFactor("")
        glassOpacity: panel.pageFactor("") * panel.revealProgress
        backdropScale: panelCanvas.scale
        active: panel.isOpen && visible && !panel.hasActiveSubmenu
        enabled: popupMotion.interactive && pageMotion.interactive
    }
    readonly property real effectiveBlur: dockHosted
        ? AppearanceConfigService.effectiveDockBlur
        : AppearanceConfigService.effectiveBarBlur
    readonly property real effectiveLiquid: dockHosted
        ? AppearanceConfigService.effectiveDockLiquid
        : AppearanceConfigService.effectiveBarLiquid

    QtObject {
        id: coordinator
        readonly property bool open: popupMotion.requestedOpen
        property var cardAnchor: panel.anchorItem
        function openAll() {
            const opening = !popupMotion.requestedOpen
            if (!popupMotion.mapped)
                pageMotion.reset(panel.requestedPage)
            popupMotion.open()
            panel.positionViewportForOpen()
            // Paint cached values first, including after a deferred Bar reveal.
            if (opening) Qt.callLater(function() {
                if (popupMotion.requestedOpen)
                    ControlCenterService.refresh()
            })
        }
        function closeAll(closingModal) { popupMotion.close() }
    }

    PopupMotion {
        id: popupMotion
    }

    PageMotion {
        id: pageMotion
        page: panel.requestedPage
        enabled: popupMotion.requestedOpen
        // One continuous crossfade per navigation: the incoming page maps
        // immediately and fades in while the outgoing page's cards fade out,
        // so there is never an empty-glass frame between the two.
        crossfade: true
    }

    // The page the submenu card is currently rendering: the displayed page
    // when it is a submenu, otherwise the outgoing page while it still holds
    // one (its content and height must survive the fade-out unchanged).
    readonly property string submenuShownPage:
        ["wifi", "bluetooth", "brightness", "sound"].indexOf(panel.displayedSubmenu) >= 0
            ? panel.displayedSubmenu
            : (["wifi", "bluetooth", "brightness", "sound"].indexOf(panel.outgoingPage) >= 0
                ? panel.outgoingPage : "")

    // Per-page crossfade factor: 1 while a page is fully in, progress while it
    // fades in, (1 - progress) while it fades out, 0 when it owns neither side
    // of the transition. Multiplied into a card's opacity so glass AND content
    // fade together -- a card that only faded its content would leave a lit
    // glass shell hanging over the incoming page.
    function pageFactor(page) {
        if (pageMotion.displayedPage === page)
            return pageMotion.progress
        if (pageMotion.outgoingPage === page)
            return 1 - pageMotion.progress
        return 0
    }

    // Whether a card belonging to `page` stays mapped. Incoming pages map
    // immediately; an outgoing page unmaps only once its fade has fully
    // landed, because its KWin blur region has no opacity of its own -- the
    // scrim fade (glassOpacity) is what retires the glass, and keeping the
    // card mapped to the last frame lets that fade finish instead of leaving
    // a frozen blurred silhouette that pops away a few frames early.
    function cardMapped(page) {
        if (pageMotion.displayedPage === page)
            return true
        return pageMotion.outgoingPage === page && pageMotion.progress < 0.995
    }

    // The capsule a sub-page grows out of / collapses back into, in panel
    // coordinates. Returning to the primary page is a shrink into that source
    // rect rather than a flat fade: the submenu card morphs onto the Wi-Fi
    // pill (or the brightness/sound slider) it was opened from.
    readonly property var submenuSourceRects: ({
        "wifi":       Qt.rect(20, 20 + mainControlsOffsetY, connectivityWidth, 59),
        "bluetooth":  Qt.rect(20, 87 + mainControlsOffsetY, connectivityWidth, 59),
        "brightness": Qt.rect(20, 269 + mainControlsOffsetY, controlsWidth, 57),
        "sound":      Qt.rect(20, 334 + mainControlsOffsetY, controlsWidth, 57),
        // Power/session sheet returns to the power-key capsule (slotCard3:
        // offsetRight 142, offsetTop 155, 52x52) so it morphs back into the
        // button it was opened from exactly like the Wi-Fi/BT pills.
        "session":    Qt.rect(20 + 2 * (quickControlWidth + 9), 155 + mainControlsOffsetY, quickControlWidth, quickControlWidth)
    })

    // 0 when a page is at full size, 1 when it has fully collapsed onto its
    // source capsule. Drives a card's morphRect interpolation; the ease matches
    // the crossfade so geometry and opacity stay in lockstep. Works for every
    // page that has a submenuSourceRects entry (wifi/bluetooth/brightness/sound
    // on the shared submenu card, "session" on the power sheet).
    function pageMorph(page) {
        if (page === "")
            return 0
        if (pageMotion.displayedPage === page)
            return 1 - pageMotion.progress
        if (pageMotion.outgoingPage === page)
            return pageMotion.progress
        return 0
    }
    readonly property real submenuMorph: pageMorph(submenuShownPage)
    // The power/session sheet morphs back into the power-key capsule, using the
    // same rule as the submenu card's collapse-into-source.
    readonly property real sessionMorph: pageMorph("session")

    // Capture is one stationary window-sized rectangle. The compositor draws
    // only the declared card outlines, so the gaps remain transparent. Include
    // every visible declaration in the region union; capture and shape bounds
    // must describe the same envelope throughout scrolling and navigation.
    Region { id: emptyRegion }
    Region {
        id: cardsBlurRegion
        regions: [
            wifiCard.visible && wifiCard.backdropVisible ? wifiCard.blurRegion : emptyRegion,
            bluetoothCard.visible && bluetoothCard.backdropVisible ? bluetoothCard.blurRegion : emptyRegion,
            mediaCard.visible && mediaCard.backdropVisible ? mediaCard.blurRegion : emptyRegion,
            slotCard1.visible && slotCard1.backdropVisible ? slotCard1.blurRegion : emptyRegion,
            slotCard2.visible && slotCard2.backdropVisible ? slotCard2.blurRegion : emptyRegion,
            slotCard3.visible && slotCard3.backdropVisible ? slotCard3.blurRegion : emptyRegion,
            slotCard4.visible && slotCard4.backdropVisible ? slotCard4.blurRegion : emptyRegion,
            slotCard5.visible && slotCard5.backdropVisible ? slotCard5.blurRegion : emptyRegion,
            slotCard6.visible && slotCard6.backdropVisible ? slotCard6.blurRegion : emptyRegion,
            slotCard7.visible && slotCard7.backdropVisible ? slotCard7.blurRegion : emptyRegion,
            // stageModeCard 同样发布 SurfaceShape（可见即发布）——漏列
            // 一张 = 声明的 shape 集比 region 多一个条目，全卡玻璃按它
            // 偏移（见本清单头注释；审计 🔴，glass 主题下实测错位源）
            stageModeCard.visible && stageModeCard.backdropVisible ? stageModeCard.blurRegion : emptyRegion,
            keepAwakeCard.visible && keepAwakeCard.backdropVisible ? keepAwakeCard.blurRegion : emptyRegion,
            sessionCard.visible && sessionCard.backdropVisible ? sessionCard.blurRegion : emptyRegion,
            submenuCard.visible && submenuCard.backdropVisible ? submenuCard.blurRegion : emptyRegion,
            notificationHistory.visible ? notificationHistory.blurRegion : emptyRegion
        ]
    }
    // A tonal/non-glass theme draws its own surface and publishes no shapes, so
    // the window must not ask KWin for a backdrop either.
    BackgroundEffect.blurRegion: (AppearanceTokens.surface.usesKwinBlur && panel.visible
        && popupMotion.progress > 0)
        ? cardsBlurRegion : null

    // Position the cards at their grid offsets (top-right origin). One pass on
    // completion; the window owns layout. The submenu and session cards resize
    // as the active page changes (wifi/brightness/sound are all different
    // heights), and their offsetTop is a live binding on that cardHeight. Hand
    // assigning x/y once here would freeze the submenu at the height it had
    // when the panel finished loading, stranding it below its intended slot so
    // the primary cards stay visible above it (the two-panel "overlay"). Bind
    // the position so the submenu reflows into place whenever its geometry
    // changes.
    Component.onCompleted: {
        const children = []
        for (let i = 0; i < panel.data.length; i++) children.push(panel.data[i])
        for (let i = 0; i < children.length; i++) {
            const c = children[i]
            if (c && c.isControlCenterCard) {
                // A submenu or session sheet REPLACES the primary cards, it does
                // not float over them: every coordinator-managed card hides
                // while one is open, so the two interfaces never stack on top
                // of each other. sessionCard/submenuCard (managedByCoordinator
                // false) own their own cardShown instead.
                if (c.managedByCoordinator) {
                    c.cardShown = Qt.binding(function() {
                        return panel.cardMapped("")
                    })
                }
                c.captureAnchor = popupCapture
                c.clipViewport = controlViewport
                c.parent = panelCanvas
                panel.placeCard(c)
            }
        }
    }
    function placeCard(c) {
        c.backdropScale = Qt.binding(function() { return panelCanvas.scale * c.scale })
        c.x = Qt.binding(function() {
            return panel.controlCenterWidth - c.offsetRight - c.width
        })
        c.y = Qt.binding(function() {
            return c.offsetTop
        })
        // Page-level visibility lives on the card itself (glass + content
        // fade together); the window-level reveal rides on contentItem.
        c.opacity = Qt.binding(function() {
            return panel.pageFactor(c.pageTag)
        })
        // The compositor glass has no opacity of its own; drive its scrim
        // from the same page factor so the frosted silhouette fades with the
        // card instead of persisting as a blurred ghost after unmap.
        c.glassOpacity = Qt.binding(function() {
            return panel.pageFactor(c.pageTag) * panel.revealProgress
        })
        // Cards that morph through morphRect (the shared submenu card and the
        // session sheet) collapse by geometry, not a uniform Item scale:
        // applying the 0.96 breathing scale on top of a collapse that already
        // carries the card to a capsule would double-shrink it off the source.
        // Only the primary page's cards take the scale nudge.
        const morphsToSource = c === submenuCard || c === sessionCard
        // Mirror of the entrance: the incoming page grows 0.96→1 while the
        // outgoing page shrinks 1→0.96 over the same progress. Morphing cards
        // skip this -- their collapse is expressed by morphRect geometry,
        // and stacking an Item scale on top would double-shrink it.
        c.scale = morphsToSource ? 1 : Qt.binding(function() {
            if (pageMotion.displayedPage === c.pageTag)
                return 0.96 + 0.04 * pageMotion.progress
            if (pageMotion.outgoingPage === c.pageTag)
                return 1 - 0.04 * pageMotion.progress
            return 1
        })
        // The card itself owns the page fade. A second content fade would
        // dim text twice as fast as its compositor material.
        c.contentOpacity = 1
        c.contentOffsetY = Qt.binding(function() {
            // Only the incoming page slides into place. An outgoing page
            // fades exactly where it sits: drifting its content would peel it
            // away from the compositor blur shape the card still publishes,
            // which reads as the frosting being left behind, shifted to one
            // side of the departing panel.
            // A morphing card's displacement is already carried by its
            // morphRect collapse; adding the slide would drift it off the
            // capsule it is shrinking into.
            if (morphsToSource)
                return 0
            if (pageMotion.displayedPage !== c.pageTag)
                return 0
            return (panel.dockFacingLayout ? 1 : -1) * (1 - pageMotion.progress) * 8
        })
        c.enabled = Qt.binding(function() {
            return popupMotion.interactive && pageMotion.interactive
                && panel.displayedSubmenu === c.pageTag
        })
    }

    property bool _internalTransition: false

    Timer {
        id: transitionGuardTimer
        interval: 350
        repeat: false
        onTriggered: panel._internalTransition = false
    }

    function _triggerTransitionGuard() {
        panel._internalTransition = true
        transitionGuardTimer.restart()
    }

    onSessionModalVisibleChanged: {
        _triggerTransitionGuard()
        if (panel.sessionModalVisible) {
            // The menu is a card of this same surface, so the panel has to be
            // mapped before switching to the session page.
            if (!coordinator.open)
                coordinator.openAll()
        }
        if (!panel.sessionModalVisible) {
            panel.pendingConfirmAction = ""
        }
    }

    // The confirmation dialog is the shared modal primitive, driven exactly the
    // way the other dialogs drive it: open()/close(), never a `visible` binding.
    // Its own show path is what starts PopupMotion, and the card's opacity is that
    // animation's progress -- bound directly, it would sit at zero forever.
    onPendingConfirmActionChanged: {
        // The dialog is its own focusable surface, so mapping it changes KWin's
        // active window; the guard keeps that from being read as "the user clicked
        // away" and closing the Control Center (which would clear this property
        // again, making the dialog flash).
        _triggerTransitionGuard()
        if (panel.pendingConfirmAction === "")
            sessionConfirm.close()
        else {
            panel.confirmActionLabel = panel.pendingConfirmAction
            sessionConfirm.open()
        }
    }

    function toggle(item) {
        anchorItem = item
        _triggerTransitionGuard()
        if (panel.isOpen || panel.sessionModalVisible || panel.activeSubmenu !== "") {
            close()
        } else {
            controlViewport.contentX = 0
            controlViewport.contentY = 0
            notificationHistory.reset()
            panel.sessionModalVisible = false
            panel.submenuOpen = false
            panel.activeSubmenu = ""
            panel.pendingConfirmAction = ""
            if (panel.anchorSettled)
                coordinator.openAll()
            else
                panel.pendingOpen = true
        }
    }

    function positionViewportForOpen() {
        controlViewport.contentX = 0
        // On a short output keep the dock-facing controls reachable immediately.
        // Notifications above them remain available by scrolling upward.
        controlViewport.contentY = panel.notificationsAboveControls
            ? Math.max(0, controlViewport.contentHeight - controlViewport.height) : 0
    }

    // The Bar finished sliding; open the deferred panel now that its anchor
    // will be measured against the Bar's resting position.
    onAnchorSettledChanged: {
        if (!panel.anchorSettled || !panel.pendingOpen)
            return
        panel.pendingOpen = false
        coordinator.openAll()
    }

    // Safety net: a request must never be swallowed if the Bar stops reporting
    // a settled reveal. Showing the panel slightly high beats not showing it.
    Timer {
        id: pendingOpenFallback
        interval: 700
        repeat: false
        running: panel.pendingOpen
        onTriggered: {
            if (!panel.pendingOpen)
                return
            console.info("[ControlCenter] Bar reveal never settled; opening anyway")
            panel.pendingOpen = false
            coordinator.openAll()
        }
    }

    function close() {
        _triggerTransitionGuard()
        panel.pendingOpen = false
        const closingSubmenu = submenuOpen || activeSubmenu !== ""
        const closingModal = sessionModalVisible || closingSubmenu
        coordinator.closeAll(closingModal)
        sessionModalVisible = false
        submenuOpen = false
        activeSubmenu = ""
        pendingConfirmAction = ""
    }

    // The session list dispatches through here. The three destructive entries
    // open the shared confirmation dialog; other entries act immediately.
    function runSessionAction(action) {
        if (action === "logout" || action === "reboot" || action === "poweroff") {
            panel.pendingConfirmAction = action
            return
        }
        panel.close()
        if (action === "lock")
            ControlCenterService.lockSession()
        else if (action === "suspend")
            ControlCenterService.suspendSystem()
        else if (action === "switch")
            ControlCenterService.switchUser()
    }

    function openSessionPanel() {
        pendingConfirmAction = ""
        submenuOpen = false
        activeSubmenu = ""
        sessionModalVisible = true
    }

    // ── Outside-press dismissal ──────────────────────────────────────
    // A PopupWindow anchored to the layer-shell Bar cannot take a Wayland
    // popup grab here: Qt refuses to create the grabbing popup, so the surface
    // never maps and the compositor never dismisses the panel on an outside
    // press. Escape and the WindowService active-window watch below only cover
    // the keyboard and presses on another *toplevel* -- not presses on the
    // desktop or on the Bar itself, which is exactly where users click to put
    // the Control Center away. Catch those with a transparent full-screen
    // Top-layer surface: a popup attached to a layer surface renders above its
    // layer, so the panel keeps every press that lands on a card and this
    // catcher only sees the ones that miss.
    PanelWindow {
        id: dismissalCatcher
        screen: panel.targetScreen
        visible: ScreenLifecycle.outputAvailable && panel.targetScreen !== null
            && (panel.isOpen || panel.sessionModalVisible || panel.activeSubmenu !== "")
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-controlcenter-backdrop"
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

    // If the display server ever closes the popup behind our back, fold the
    // motion state too: otherwise `coordinator.open` keeps reporting true and
    // the next toggle would "close" a panel that is already gone.
    onClosed: popupMotion.reset()

    Connections {
        target: WindowService
        function onActiveWindowIdChanged() {
            // A confirmation dialog being up is not "the user moved to another
            // window": the dialog's own surface takes focus when it maps, and
            // closing the Control Center here would clear pendingConfirmAction and
            // make the dialog flash away.
            if (panel.pendingConfirmAction !== "")
                return
            if (!panel._internalTransition && (panel.isOpen || panel.sessionModalVisible || panel.activeSubmenu !== "")) {
                panel.close()
            }
        }
    }

    // A context menu mapped over the control center would overlap it the same
    // way the removed dismissal backdrop used to be the only thing keeping an
    // outside right-click from showing one. The menu surfaces are layer-shell
    // popups, so activating one does not change the active window and the
    // handler above never fires. Watch the shared context-menu coordinator
    // instead: whenever ANY menu opens (desktop, dock, launcher, bar), fold the
    // control center away and let the menu stand alone.
    Connections {
        target: ContextMenuCoordinator
        function onActiveMenuChanged() {
            if (ContextMenuCoordinator.activeMenu
                    && !panel._internalTransition
                    && (panel.isOpen || panel.sessionModalVisible || panel.activeSubmenu !== ""))
                panel.close()
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: panel.isOpen || panel.sessionModalVisible || panel.activeSubmenu !== ""
        onActivated: {
            if (panel.pendingConfirmAction !== "") {
                panel.pendingConfirmAction = ""
            } else if (panel.hasActiveSubmenu) {
                panel.closeSubmenu()
            } else {
                panel.close()
            }
        }
    }

    // ── Card 1: Wi-Fi ────────────────────────────────────────────────
    // Disc toggles power; tapping the rest of the pill opens the network list.
    ControlParts.WifiCard {
        id: wifiCard
        coordinator: coordinator
        offsetTop: 20 + panel.mainControlsOffsetY
        offsetRight: 20 + panel.mediaWidth + 8
        cardRadius: 29.5
        cardWidth: panel.connectivityWidth
        cardHeight: 59
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid
        network: NetworkService
        onPageRequested: panel.networkRequested()
    }

    // ── Card 2: Bluetooth ────────────────────────────────────────────
    // Disc toggles power; tapping the pill opens the device list.
    ControlParts.BluetoothCard {
        id: bluetoothCard
        coordinator: coordinator
        offsetTop: 87 + panel.mainControlsOffsetY
        offsetRight: 20 + panel.mediaWidth + 8
        cardRadius: 29.5
        cardWidth: panel.connectivityWidth
        cardHeight: 59
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid
        service: ControlCenterService
        onPageRequested: panel.bluetoothRequested()
    }

    // ── Card 3: Media player ─────────────────────────────────────────
    ControlParts.MediaCard {
        id: mediaCard
        coordinator: coordinator
        offsetTop: 20 + panel.mainControlsOffsetY
        offsetRight: 20
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 25)
        cardWidth: panel.mediaWidth
        cardHeight: 127
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid
        media: DockMprisService
        player: panel.player
    }

    // ── Card 4: Screenshot ───────────────────────────────────────────
    ControlCenterCard {
        id: slotCard1
        ControlCenterSelection {
            pointer: screenshotPointer
            cornerRadius: slotCard1.cardRadius
        }
        coordinator: coordinator
        offsetTop: 155 + panel.mainControlsOffsetY
        offsetRight: 20 + 4 * (panel.quickControlWidth + 9)
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
        cardWidth: panel.quickControlWidth
        cardHeight: panel.quickControlWidth

        cardScale: screenshotPointer.pressed ? 0.91 : (screenshotPointer.containsMouse ? 1.06 : 1.0)
        Behavior on cardScale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.fill: parent
            radius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
            color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.45)
            opacity: AppearanceTokens.surface.selectionHighlightStyle !== "glass"
                && screenshotPointer.containsMouse && !screenshotPointer.pressed ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }
        Image {
            anchors.centerIn: parent
            width: 24
            height: 24
            source: BundledIcons.source("screenshot")
            sourceSize.width: 46
            sourceSize.height: 46
            fillMode: Image.PreserveAspectFit
            smooth: true
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: ThemeService.foregroundColor
            }
        }
        MouseArea { id: screenshotPointer; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ControlCenterService.captureInteractiveScreenshot() }
    }

    // ── Card 5: Dark Mode / Theme Toggle ─────────────────────────────
    ControlCenterCard {
        id: slotCard2
        ControlCenterSelection {
            pointer: themePointer
            cornerRadius: slotCard2.cardRadius
            selected: ThemeService.isDark
        }
        coordinator: coordinator
        offsetTop: 155 + panel.mainControlsOffsetY
        offsetRight: 20 + 3 * (panel.quickControlWidth + 9)
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
        cardWidth: panel.quickControlWidth
        cardHeight: panel.quickControlWidth

        cardScale: themePointer.pressed ? 0.91 : (themePointer.containsMouse ? 1.06 : 1.0)
        Behavior on cardScale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.fill: parent
            radius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
            color: "#ffffff"
            opacity: ThemeService.isDark ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }
        Image {
            anchors.centerIn: parent
            width: 24
            height: 24
            source: BundledIcons.source("theme-appearance")
            sourceSize.width: 48
            sourceSize.height: 48
            fillMode: Image.PreserveAspectFit
            smooth: true
            rotation: ThemeService.isDark ? 0 : 180
            Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: ThemeService.isDark ? "#000000" : "#ffffff"
            }
        }
        MouseArea {
            id: themePointer
            anchors.fill: parent
            hoverEnabled: true
            enabled: !ControlCenterService.themeChangeInProgress
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: ControlCenterService.toggleDarkMode()
        }
    }

    // ── Card 6: Power & Session ──────────────────────────────────────
    ControlCenterCard {
        id: slotCard3
        ControlCenterSelection {
            pointer: powerPointer
            cornerRadius: slotCard3.cardRadius
        }
        coordinator: coordinator
        offsetTop: 155 + panel.mainControlsOffsetY
        offsetRight: 20 + 2 * (panel.quickControlWidth + 9)
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
        cardWidth: panel.quickControlWidth
        cardHeight: panel.quickControlWidth

        cardScale: powerPointer.pressed ? 0.91 : (powerPointer.containsMouse ? 1.06 : 1.0)
        Behavior on cardScale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.fill: parent
            radius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
            color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.45)
            opacity: AppearanceTokens.surface.selectionHighlightStyle !== "glass"
                && powerPointer.containsMouse && !powerPointer.pressed ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }
        Image {
            anchors.centerIn: parent
            width: 24
            height: 24
            source: BundledIcons.source("power")
            sourceSize.width: 48
            sourceSize.height: 48
            fillMode: Image.PreserveAspectFit
            smooth: true
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: ThemeService.foregroundColor
            }
        }
        MouseArea {
            id: powerPointer
            anchors.fill: parent
            hoverEnabled: true
            enabled: !ControlCenterService.sessionActionInProgress
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: panel.openSessionPanel()
        }
    }

    // ── Card 7: Do Not Disturb ───────────────────────────────────────
    ControlCenterCard {
        id: slotCard4
        ControlCenterSelection {
            pointer: dndPointer
            cornerRadius: slotCard4.cardRadius
            selected: ControlCenterService.doNotDisturbEnabled
        }
        coordinator: coordinator
        offsetTop: 155 + panel.mainControlsOffsetY
        offsetRight: 20 + 1 * (panel.quickControlWidth + 9)
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
        cardWidth: panel.quickControlWidth
        cardHeight: panel.quickControlWidth

        cardScale: dndPointer.pressed ? 0.91 : (dndPointer.containsMouse ? 1.06 : 1.0)
        Behavior on cardScale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.fill: parent
            radius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
            color: ThemeService.isDark ? Qt.rgba(0.04, 0.52, 1.0, 0.28) : Qt.rgba(0.04, 0.52, 1.0, 0.18)
            opacity: ControlCenterService.doNotDisturbEnabled ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }
        Image {
            anchors.centerIn: parent
            width: 22
            height: 22
            source: BundledIcons.source("do-not-disturb")
            sourceSize.width: 44
            sourceSize.height: 44
            fillMode: Image.PreserveAspectFit
            smooth: true
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: ControlCenterService.doNotDisturbEnabled
                    ? "#0a84ff" : ThemeService.foregroundColor
            }
        }
        MouseArea {
            id: dndPointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ControlCenterService.toggleDoNotDisturb()
        }
    }

    // ── Card 8: Night Light ──────────────────────────────────────────
    ControlCenterCard {
        id: slotCard5
        ControlCenterSelection {
            pointer: nightLightPointer
            cornerRadius: slotCard5.cardRadius
            selected: ControlCenterService.nightLightActive
        }
        coordinator: coordinator
        offsetTop: 155 + panel.mainControlsOffsetY
        offsetRight: 20
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
        cardWidth: panel.quickControlWidth
        cardHeight: panel.quickControlWidth

        cardScale: nightLightPointer.pressed ? 0.91 : (nightLightPointer.containsMouse ? 1.06 : 1.0)
        Behavior on cardScale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.fill: parent
            radius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
            color: "#ffcc00"
            opacity: ControlCenterService.nightLightActive ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }
        Image {
            anchors.centerIn: parent
            width: 22
            height: 22
            source: BundledIcons.source("night-light")
            sourceSize.width: 44
            sourceSize.height: 44
            fillMode: Image.PreserveAspectFit
            smooth: true
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: ThemeService.foregroundColor
            }
        }
        MouseArea {
            id: nightLightPointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ControlCenterService.toggleNightLight()
        }
    }

    // Utility toggles share the row between the quick actions and brightness.
    ControlParts.StageModeCard {
        id: stageModeCard
        coordinator: coordinator
        offsetTop: 217 + panel.mainControlsOffsetY
        offsetRight: 20 + panel.halfControlWidth + 8
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 19)
        cardWidth: panel.halfControlWidth
        cardHeight: 44
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid
        stageMode: StageModeService
    }

    // Caffeine is held by the resident service, never the popup lifetime.
    ControlParts.KeepAwakeCard {
        id: keepAwakeCard
        coordinator: coordinator
        offsetTop: 217 + panel.mainControlsOffsetY
        offsetRight: 20
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 19)
        cardWidth: panel.halfControlWidth
        cardHeight: 44
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid
        service: ControlCenterService
    }

    // ── Card 9: Display brightness ───────────────────────────────────
    ControlParts.BrightnessCard {
        id: slotCard6
        coordinator: coordinator
        offsetTop: 269 + panel.mainControlsOffsetY
        offsetRight: 20
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 19)
        cardWidth: panel.controlsWidth
        cardHeight: 57
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid
        service: ControlCenterService
        brightnessPreview: panel.brightnessPreview
        onBrightnessPreviewRequested: value => panel.brightnessPreview = value
        onDraggingBrightnessRequested: value => panel.draggingBrightness = value
        onPageRequested: page => panel.openSubmenu(page)
    }

    // ── Card 8: Sound / volume ───────────────────────────────────────
    ControlParts.SoundCard {
        id: slotCard7
        coordinator: coordinator
        offsetTop: 334 + panel.mainControlsOffsetY
        offsetRight: 20
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 19)
        cardWidth: panel.controlsWidth
        cardHeight: 57
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid
        service: ControlCenterService
        volumePreview: panel.volumePreview
        onVolumePreviewRequested: value => panel.volumePreview = value
        onDraggingVolumeRequested: value => panel.draggingVolume = value
        onPageRequested: page => panel.openSubmenu(page)
    }

    // The session sheet is another page of the same popup.
    ControlParts.SessionCard {
        id: sessionCard
        coordinator: coordinator
        managedByCoordinator: false
        // Same slot as the Wi-Fi/Bluetooth submenu, so the session list is one
        // more page of the Control Center instead of a panel of its own.
        offsetTop: panel.dockFacingLayout
            ? panel.controlCenterHeight - panel.canvasOffsetY - 20 - sessionCard.cardHeight
            : 20
        offsetRight: 20
        // Roundness interpolates toward the power-key capsule while the sheet
        // shrinks, so the collapsing panel lands flush with the button it was
        // opened from -- the same morph the Wi-Fi/Bluetooth submenu card uses.
        readonly property real _baseRadius:
            AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 22)
        // slotCard3 (the power key) is a 52px capsule whose cardRadius is
        // pick(extraLarge, 26); match that exact token so the collapsed sheet
        // lands flush with the button's real corner in both glass and material.
        readonly property real _sourceRadius:
            AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
        cardRadius: _baseRadius + (_sourceRadius - _baseRadius) * panel.sessionMorph
        cardWidth: panel.controlsWidth
        cardHeight: 340
        pageTag: "session"
        // Stays mapped while the sheet is the outgoing side of a crossfade, so
        // it fades out instead of snapping away the frame the next page commits.
        cardShown: panel.cardMapped("session")
        // Collapse-into-source morph, identical in shape to the submenu card:
        // the visible window slides from the full sheet down onto the power-key
        // capsule (and back out on open). The source rect is in panel
        // coordinates, so subtract the card's own position for card-local space.
        morphRect: {
            const src = panel.submenuSourceRects["session"]
            if (!src)
                return Qt.rect(0, 0, -1, -1)
            const t = panel.sessionMorph
            const cx = sessionCard.x
            const cy = sessionCard.y
            const x = (src.x - cx) * t
            const y = (src.y - cy) * t
            const w = sessionCard.width + (src.width - sessionCard.width) * t
            const h = sessionCard.height + (src.height - sessionCard.height) * t
            return Qt.rect(x, y, w, h)
        }
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid

        service: ControlCenterService
        onBackRequested: panel.closeSubmenu()
        onActionRequested: action => panel.runSessionAction(action)
    }

    // Session confirmations (log out / restart / shut down) are important
    // interactions, so they use the shared modal dialog primitive instead of a
    // page of the Control Center: centred, with the strong readable scrim and the
    // card shadow the other important dialogs already have.
    ControlParts.SessionConfirmationDialog {
        id: sessionConfirm
        actionLabel: panel.confirmActionLabel
        onCancelRequested: panel.pendingConfirmAction = ""
        onConfirmRequested: {
            const action = panel.pendingConfirmAction
            panel.pendingConfirmAction = ""
            panel.close()
            if (action === "poweroff")
                ControlCenterService.powerOffSystem()
            else if (action === "reboot")
                ControlCenterService.rebootSystem()
            else if (action === "logout")
                ControlCenterService.logoutCurrentSession()
        }
    }

    // ── Card 11 (Submenu Panel): Wi-Fi, Bluetooth, Brightness, Sound ─
    ControlParts.SubmenuCard {
        id: submenuCard
        page: panel.submenuShownPage
        coordinator: coordinator
        managedByCoordinator: false
        // Top Bar submenus grow down from the systray. Bottom/side Dock
        // submenus instead keep their lower edge beside the systray/control
        // area, regardless of the selected submenu's individual height.
        offsetTop: panel.dockFacingLayout
            ? panel.controlCenterHeight - panel.canvasOffsetY - 20 - submenuCard.cardHeight
            : 20
        offsetRight: 20
        // Roundness interpolates toward the source capsule while the card
        // shrinks, so the collapsing panel ends flush with the control it
        // returns to instead of staying a rounded slab.
        readonly property real _baseRadius:
            AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 22)
        cardRadius: _baseRadius + (_sourceRadius - _baseRadius) * panel.submenuMorph
        // The capsule it returns to: Wi-Fi/Bluetooth pills are near-circular
        // (29.5) and the brightness/sound sliders use the extraLarge token.
        readonly property real _sourceRadius:
            panel.submenuShownPage === "wifi" || panel.submenuShownPage === "bluetooth"
                ? 29.5 : AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 19)
        cardWidth: panel.controlsWidth
        // Driven by the page the card is actually rendering (incoming or
        // outgoing), so a fade-out keeps its height and a fade-in grows to
        // the new page's height with a smooth Behavior instead of a jump.
        cardHeight: panel.submenuShownPage === "wifi" ? 360
            : (panel.submenuShownPage === "bluetooth" ? 340
            : (panel.submenuShownPage === "brightness" ? 280
            : (panel.submenuShownPage === "sound" ? 420 : 280)))
        pageTag: panel.submenuShownPage
        cardShown: panel.submenuShownPage !== ""
            && panel.cardMapped(panel.submenuShownPage)
        // Collapse-into-source morph: the card's visible window slides from its
        // full rectangle down onto the capsule that spawned this page, and the
        // reverse on open. The source rect is in panel coordinates, so subtract
        // the card's own position to express it in card-local space.
        morphRect: {
            const src = panel.submenuSourceRects[panel.submenuShownPage]
            if (!src)
                return Qt.rect(0, 0, -1, -1)
            const t = panel.submenuMorph
            const cx = submenuCard.x
            const cy = submenuCard.y
            const x = (src.x - cx) * t
            const y = (src.y - cy) * t
            const w = submenuCard.width + (src.width - submenuCard.width) * t
            const h = submenuCard.height + (src.height - submenuCard.height) * t
            return Qt.rect(x, y, w, h)
        }

        network: NetworkService
        service: ControlCenterService
        onBackRequested: panel.closeSubmenu()
        volumePreview: panel.volumePreview
        onVolumePreviewRequested: value => panel.volumePreview = value
        onDraggingVolumeRequested: value => panel.draggingVolume = value
        onSettingsRequested: module => panel.openSettingsModule(module)
        onWifiNetworkSelected: network => {
            panel.close()
            panel.wifiNetworkSelected(network)
        }
    }

    // ── Volume / brightness sync from the service ────────────────────
    Connections {
        target: ControlCenterService
        function onVolumePercentChanged() {
            if (!panel.draggingVolume)
                panel.volumePreview = ControlCenterService.volumePercent
        }
        function onBrightnessPercentChanged() {
            if (!panel.draggingBrightness)
                panel.brightnessPreview = ControlCenterService.brightnessPercent
        }
    }
}
