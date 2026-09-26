import QtQuick
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
import "../../../Kos/Ui"
import "../../../shared/qml/controls" as LiquidControls

// Compact desktop adaptation of the supplied Control Center reference.
// Its geometry intentionally stays small enough for a top-bar popup while
// preserving the reference's two-column, pill-and-media-card hierarchy.
//
// PER-CARD INDEPENDENT GLASS: instead of one PopupWindow with a single blur
// slab, each card is its own PopupWindow (ControlCenterCard) with its own
// compositor blur region. KWin's blur is per-window, so each card blurs
// exactly what is behind it (wallpaper AND open windows) and the gaps
// between cards show the real desktop - the iOS "hollow" control center.
// ControlCenterCoordinator owns the group so all cards open/close together.
PopupWindow {
    id: panel

    // ── Single-block windowing ──
    // One window, one glass block, cards laid out by simple anchors inside it.
    // This replaces the per-card PopupWindow + ControlCenterCoordinator model.
    implicitWidth: panel.controlCenterWidth
    implicitHeight: panel.controlCenterHeight
    color: "transparent"
    grabFocus: true
    anchor {
        item: panel.anchorItem
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
    property bool draggingBrightness: false
    property bool sessionModalVisible: false
    property string pendingConfirmAction: ""
    property alias logoutConfirmationVisible: panel.sessionModalVisible
    property string activeSubmenu: ""
    property bool submenuOpen: false
    readonly property bool hasActiveSubmenu: activeSubmenu !== "" || sessionModalVisible
    // A standalone top Bar grows downward, so controls come first. A panel
    // hosted by a bottom/side Dock grows away from the Dock, so keep the
    // controls nearest the Dock and place notification history above them.
    readonly property bool notificationFirst: dockHosted && dockEdge !== "top"
    readonly property int mainControlsOffsetY: notificationFirst ? 238 : 0
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
        coordinator.modalActive = true
    }

    function closeSubmenu() {
        _triggerTransitionGuard()
        submenuOpen = false
        sessionModalVisible = false
        pendingConfirmAction = ""
        // The current control center is one window with no outgoing submenu
        // animation. Keeping the old page identity here makes the next toggle
        // mistake an invisible panel for an open Wi-Fi submenu.
        activeSubmenu = ""
        coordinator.modalActive = false
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

    // Bar reads this for sharedPanelOpen / toggle state.
    readonly property bool isOpen: coordinator.open

    // The target screen (the bar's output). Cards live on the same screen.
    readonly property var targetScreen: ScreenLifecycle.activeScreen
    readonly property int controlCenterHeight: 597
    readonly property int controlCenterWidth: 336
    readonly property real effectiveBlur: dockHosted
        ? AppearanceConfigService.effectiveDockBlur
        : AppearanceConfigService.effectiveBarBlur
    readonly property real effectiveLiquid: dockHosted
        ? AppearanceConfigService.effectiveDockLiquid
        : AppearanceConfigService.effectiveBarLiquid

    component TransportButton: MediaControlButton {
        glassInk: ThemeService.foregroundColor
        width: primary ? 40 : 32
        height: width
    }

    // Stubbed coordinator: the single block replaces the N-card orchestration.
    // Keeps the same surface (open/close/modal/cardAnchor) so existing call
    // sites and card content compile; openAll/closeAll now just show/hide this
    // one window.
    QtObject {
        id: coordinator
        property bool open: panel.visible
        property bool modalActive: false
        property var cardAnchor: panel.anchorItem
        function openAll() { panel.visible = true }
        function closeAll(closingModal) { panel.visible = false }
    }

    // No panel-wide glass slab: the window blur region is the UNION of every
    // card's blurRegion, so KWin blurs behind the cards (real frosted glass)
    // but not over the gaps between them -- hollow and frosted, in one window
    // with no coordinator.
    //
    // Every card that publishes a SurfaceShape has to be in this list, and only
    // while it is visible. The effect aligns the whole declared shape set with
    // this region's top-left, so a shape that is declared but missing from the
    // region -- or the reverse -- slides the glass of *every* card by the
    // difference. The overlay cards used to be left out on the grounds that they
    // cover the primary area, but the notification-first layout puts the primary
    // cards at y=258 while the session sheet stays at y=20: with an empty
    // notification history (slotCard8 hidden) that is a 238px shift of the whole
    // panel's glass. Gating on visibility keeps the two sets equal in every
    // state -- a hidden card publishes no shape and contributes no area, and an
    // empty card would otherwise blur a lingering frosted slab.
    Region { id: emptyRegion }
    Region {
        id: cardsBlurRegion
        regions: [
            wifiCard.visible ? wifiCard.blurRegion : emptyRegion,
            bluetoothCard.visible ? bluetoothCard.blurRegion : emptyRegion,
            mediaCard.visible ? mediaCard.blurRegion : emptyRegion,
            slotCard1.visible ? slotCard1.blurRegion : emptyRegion,
            slotCard2.visible ? slotCard2.blurRegion : emptyRegion,
            slotCard3.visible ? slotCard3.blurRegion : emptyRegion,
            slotCard4.visible ? slotCard4.blurRegion : emptyRegion,
            slotCard5.visible ? slotCard5.blurRegion : emptyRegion,
            slotCard6.visible ? slotCard6.blurRegion : emptyRegion,
            slotCard7.visible ? slotCard7.blurRegion : emptyRegion,
            slotCard8.visible ? slotCard8.blurRegion : emptyRegion,
            sessionCard.visible ? sessionCard.blurRegion : emptyRegion,
            submenuCard.visible ? submenuCard.blurRegion : emptyRegion
        ]
    }
    // A tonal/non-glass theme draws its own surface and publishes no shapes, so
    // the window must not ask KWin for a backdrop either.
    BackgroundEffect.blurRegion: (AppearanceTokens.surface.usesKwinBlur && panel.visible)
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
        for (let i = 0; i < panel.data.length; i++) {
            const c = panel.data[i]
            if (c && c.isControlCenterCard) {
                // A submenu or session sheet REPLACES the primary cards, it does
                // not float over them: every coordinator-managed card hides
                // while one is open, so the two interfaces never stack on top
                // of each other. sessionCard/submenuCard (managedByCoordinator
                // false) own their own cardShown instead.
                if (c.managedByCoordinator) {
                    c.cardShown = Qt.binding(function() {
                        return !panel.submenuOpen && !panel.sessionModalVisible
                    })
                }
                panel.placeCard(c)
            }
        }
    }
    function placeCard(c) {
        c.x = Qt.binding(function() {
            return panel.controlCenterWidth - c.offsetRight - c.width
        })
        c.y = Qt.binding(function() {
            return c.offsetTop
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
            // mapped for it to have anywhere to sit -- but nothing else about the
            // Control Center changes, and the primary cards stay mapped behind it.
            if (!coordinator.open)
                coordinator.openAll()
            coordinator.modalActive = true
        }
        if (!panel.sessionModalVisible) {
            panel.pendingConfirmAction = ""
            if (panel.activeSubmenu === "")
                coordinator.modalActive = false
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
        else
            sessionConfirm.open()
    }

    function toggle(item) {
        anchorItem = item
        _triggerTransitionGuard()
        if (coordinator.open || panel.sessionModalVisible || panel.activeSubmenu !== "") {
            close()
        } else {
            panel.sessionModalVisible = false
            panel.submenuOpen = false
            panel.activeSubmenu = ""
            panel.pendingConfirmAction = ""
            ControlCenterService.refresh()
            coordinator.openAll()
        }
    }
    function close() {
        _triggerTransitionGuard()
        const closingSubmenu = submenuOpen || activeSubmenu !== ""
        const closingModal = sessionModalVisible || closingSubmenu
        coordinator.closeAll(closingModal)
        sessionModalVisible = false
        submenuOpen = false
        activeSubmenu = ""
        coordinator.modalActive = false
        pendingConfirmAction = ""
    }

    // The session list dispatches through here rather than each row carrying its
    // own handler: the three destructive entries ask first (inside the same
    // card), everything else acts immediately and closes the Control Center.
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

    // (Single-block: no extra full-screen dismissal window needed; Escape and
    // WindowService's active-window change below close the control center.)

    Connections {
        target: WindowService
        function onActiveWindowIdChanged() {
            // A confirmation dialog being up is not "the user moved to another
            // window": the dialog's own surface takes focus when it maps, and
            // closing the Control Center here would clear pendingConfirmAction and
            // make the dialog flash away.
            if (panel.pendingConfirmAction !== "")
                return
            if (!panel._internalTransition && (coordinator.open || panel.sessionModalVisible || panel.activeSubmenu !== "")) {
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
                    && (coordinator.open || panel.sessionModalVisible || panel.activeSubmenu !== ""))
                panel.close()
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: coordinator.open || panel.sessionModalVisible || panel.activeSubmenu !== ""
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
    ControlCenterCard {
        id: wifiCard
        coordinator: coordinator
        offsetTop: 20 + panel.mainControlsOffsetY
        offsetRight: 179
        cardRadius: 29.5
        cardWidth: 137
        cardHeight: 59
        cardBorderColor: ThemeService.isDark ? Qt.rgba(0.74, 0.95, 1, 0.34) : Qt.rgba(0, 0, 0, 0.10)
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid

        Rectangle {
            id: wifiToggleDisc
            width: 39; height: 39; radius: width / 2
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            color: NetworkService.wifiEnabled
                ? ThemeService.tileActiveFill
                : (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.05)))
            opacity: NetworkService.wifiToggleInProgress ? 0.55 : 1.0
            scale: wifiTogglePointer.pressed ? 0.92
                : (wifiTogglePointer.containsMouse ? 1.04 : 1.0)
            Behavior on color { ColorAnimation { duration: 140 } }
            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
            WifiSignalIcon {
                anchors.centerIn: parent
                width: 20; height: 20
                opacity: NetworkService.wifiToggleInProgress ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 140 } }
                wifiEnabled: NetworkService.wifiEnabled
                connected: NetworkService.deviceState === "connected"
                    && NetworkService.connectionType === "wifi"
                signalStrength: NetworkService.signalStrength
                glyphColor: NetworkService.wifiEnabled
                    ? ThemeService.tileActiveGlyph : ThemeService.tileGlyph
            }
            // Toggling NetworkManager's radio is not instant either; mirror
            // the Bluetooth disc's busy arc so both read as "working", not
            // "stuck", while the toggle is in flight.
            Item {
                id: wifiBusySpinner
                anchors.centerIn: parent
                width: 21; height: 21
                opacity: NetworkService.wifiToggleInProgress ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 140 } }

                Canvas {
                    id: wifiBusyArc
                    anchors.fill: parent
                    property color glyphColor: ThemeService.tileGlyph
                    onGlyphColorChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = glyphColor
                        ctx.lineWidth = 2.0
                        ctx.lineCap = "round"
                        const cx = width / 2, cy = height / 2, r = width / 2 - 1.5
                        ctx.beginPath()
                        ctx.arc(cx, cy, r, 0, Math.PI * 1.5)
                        ctx.stroke()
                    }
                    Connections {
                        target: ThemeService
                        function onIsDarkChanged() { wifiBusyArc.requestPaint() }
                    }
                    Component.onCompleted: requestPaint()
                }

                RotationAnimation on rotation {
                    running: NetworkService.wifiToggleInProgress
                    loops: Animation.Infinite
                    from: 0; to: 360
                    duration: 900
                }
            }
            MouseArea {
                id: wifiTogglePointer
                anchors.fill: parent
                enabled: NetworkService.available
                    && !NetworkService.wifiToggleInProgress
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: NetworkService.setWifiEnabled(
                    !NetworkService.wifiEnabled)
            }
        }
        Column {
            anchors { left: parent.left; right: parent.right; leftMargin: 58; rightMargin: 18; verticalCenter: parent.verticalCenter }
            spacing: 1
            GlassText {
                width: parent.width
                text: "Wi‑Fi"
                color: wifiCard.materialForegroundColor
                font { pixelSize: 12; weight: Font.Bold; family: "Noto Sans CJK SC" }
            }
            GlassText {
                width: parent.width
                text: NetworkService.wifiEnabled ? (NetworkService.ssid || "未连接") : "已关闭"
                elide: Text.ElideRight
                color: wifiCard.materialSecondaryForegroundColor
                opacity: 1.0
                font { pixelSize: 10; family: "Noto Sans CJK SC" }
            }
        }
        GlassText {
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            text: "›"
            color: wifiCard.materialSecondaryForegroundColor
            opacity: 0.60
            font { pixelSize: 14; weight: Font.Bold }
        }
        MouseArea {
            anchors {
                top: parent.top
                right: parent.right
                bottom: parent.bottom
                left: parent.left
                leftMargin: 49
            }
            enabled: NetworkService.available
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: panel.networkRequested()
        }
    }

    // ── Card 2: Bluetooth ────────────────────────────────────────────
    // Disc toggles power; tapping the pill opens the device list.
    ControlCenterCard {
        id: bluetoothCard
        coordinator: coordinator
        offsetTop: 87 + panel.mainControlsOffsetY
        offsetRight: 179
        cardRadius: 29.5
        cardWidth: 137
        cardHeight: 59
        cardBorderColor: ThemeService.isDark ? Qt.rgba(0.74, 0.95, 1, 0.34) : Qt.rgba(0, 0, 0, 0.10)
        cardOpacity: ControlCenterService.bluetoothAvailable ? 1 : 0.48
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid

        Rectangle {
            id: bluetoothToggleDisc
            width: 39; height: 39; radius: width / 2
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            color: ControlCenterService.bluetoothPowered
                ? ThemeService.tileActiveFill
                : (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.05)))
            opacity: ControlCenterService.bluetoothChangeInProgress ? 0.55 : 1.0
            scale: bluetoothTogglePointer.pressed ? 0.92
                : (bluetoothTogglePointer.containsMouse ? 1.04 : 1.0)
            Behavior on color { ColorAnimation { duration: 140 } }
            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
            Canvas {
                id: controlBtGlyph
                anchors.centerIn: parent
                width: 21; height: 21
                property bool active: ControlCenterService.bluetoothPowered
                property color glyphColor: ThemeService.tileGlyph
                opacity: ControlCenterService.bluetoothChangeInProgress ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 140 } }
                onActiveChanged: requestPaint()
                onGlyphColorChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.strokeStyle = glyphColor
                    ctx.lineWidth = 2.0
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    ctx.scale(0.78, 0.78)
                    ctx.beginPath()
                    ctx.moveTo(13.5, 2.5)
                    ctx.lineTo(20, 9)
                    ctx.lineTo(13.5, 15)
                    ctx.lineTo(20, 21)
                    ctx.lineTo(13.5, 26.5)
                    ctx.lineTo(13.5, 2.5)
                    ctx.moveTo(7, 8.5)
                    ctx.lineTo(13.5, 15)
                    ctx.lineTo(7, 21.5)
                    ctx.stroke()
                }
                Connections {
                    target: ThemeService
                    function onIsDarkChanged() { controlBtGlyph.requestPaint() }
                }
            }
            // Powering BlueZ's adapter genuinely takes a second or more; a
            // flat opacity dim alone reads as "stuck", not "working". Spin an
            // indeterminate arc in its place, macOS Control Center style.
            Item {
                id: bluetoothBusySpinner
                anchors.centerIn: parent
                width: 21; height: 21
                opacity: ControlCenterService.bluetoothChangeInProgress ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 140 } }

                Canvas {
                    id: bluetoothBusyArc
                    anchors.fill: parent
                    property color glyphColor: ThemeService.tileGlyph
                    onGlyphColorChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = glyphColor
                        ctx.lineWidth = 2.0
                        ctx.lineCap = "round"
                        const cx = width / 2, cy = height / 2, r = width / 2 - 1.5
                        ctx.beginPath()
                        ctx.arc(cx, cy, r, 0, Math.PI * 1.5)
                        ctx.stroke()
                    }
                    Connections {
                        target: ThemeService
                        function onIsDarkChanged() { bluetoothBusyArc.requestPaint() }
                    }
                    Component.onCompleted: requestPaint()
                }

                RotationAnimation on rotation {
                    running: ControlCenterService.bluetoothChangeInProgress
                    loops: Animation.Infinite
                    from: 0; to: 360
                    duration: 900
                }
            }
            MouseArea {
                id: bluetoothTogglePointer
                anchors.fill: parent
                enabled: ControlCenterService.bluetoothAvailable && !ControlCenterService.bluetoothChangeInProgress
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: ControlCenterService.setBluetoothEnabled(!ControlCenterService.bluetoothPowered)
            }
        }
        Column {
            anchors { left: parent.left; right: parent.right; leftMargin: 58; rightMargin: 18; verticalCenter: parent.verticalCenter }
            spacing: 1
            GlassText {
                width: parent.width
                text: "Bluetooth"
                color: bluetoothCard.materialForegroundColor
                font { pixelSize: 12; weight: Font.Bold; family: "Noto Sans CJK SC" }
            }
            GlassText {
                width: parent.width
                text: ControlCenterService.bluetoothPowered ? "已开启" : "已关闭"
                color: bluetoothCard.materialSecondaryForegroundColor
                opacity: 1.0
                font { pixelSize: 10; family: "Noto Sans CJK SC" }
            }
        }
        GlassText {
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            text: "›"
            color: bluetoothCard.materialSecondaryForegroundColor
            opacity: 0.60
            font { pixelSize: 14; weight: Font.Bold }
        }
        MouseArea {
            anchors {
                top: parent.top
                right: parent.right
                bottom: parent.bottom
                left: parent.left
                leftMargin: 49
            }
            enabled: ControlCenterService.bluetoothAvailable
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: panel.bluetoothRequested()
        }
    }

    // ── Card 3: Media player ─────────────────────────────────────────
    ControlCenterCard {
        id: mediaCard
        coordinator: coordinator
        offsetTop: 20 + panel.mainControlsOffsetY
        offsetRight: 20
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 25)
        cardWidth: 151
        cardHeight: 127
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid

        Rectangle {
            id: artwork
            width: 43; height: 43; radius: 13
            anchors { left: parent.left; top: parent.top; leftMargin: 13; topMargin: 13 }
            color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.08))
            GlassText {
                anchors.centerIn: parent
                text: "♫"
                color: ThemeService.foregroundColor
                opacity: 0.86
                font.pixelSize: 21
            }
            Image {
                anchors.fill: parent
                source: panel.player?.trackArtUrl ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
                smooth: true
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: artworkMask
                }
            }
            Rectangle {
                id: artworkMask
                anchors.fill: parent
                radius: artwork.radius
                visible: false
                layer.enabled: true
            }
        }
        Column {
            anchors { left: artwork.right; right: parent.right; top: artwork.top; leftMargin: 8; rightMargin: 10 }
            spacing: 2
            GlassText {
                width: parent.width
                text: panel.player?.trackTitle || "未在播放"
                elide: Text.ElideRight
                color: ThemeService.foregroundColor
                font { pixelSize: 12; weight: Font.Bold; family: "Noto Sans CJK SC" }
            }
            GlassText {
                width: parent.width
                text: DockMprisService.loading ? DockMprisService.playbackStatus : panel.player?.trackArtist || "媒体控制"
                elide: Text.ElideRight
                color: ThemeService.foregroundColor
                opacity: 0.70
                font { pixelSize: 10; family: "Noto Sans CJK SC" }
            }
        }
        Row {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 15 }
            height: 40
            spacing: 12
            
            TransportButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "media-previous"
                text: qsTr("上一首")
                enabled: panel.player?.canGoPrevious ?? false
                onClicked: DockMprisService.previous()
            }
            TransportButton {
                anchors.verticalCenter: parent.verticalCenter
                primary: true
                iconName: panel.player?.isPlaying ? "media-pause" : "media-play"
                text: panel.player?.isPlaying ? qsTr("暂停") : qsTr("播放")
                busy: DockMprisService.loading
                enabled: panel.player?.canTogglePlaying ?? false
                onClicked: DockMprisService.togglePlayPause()
            }
            TransportButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "media-next"
                text: qsTr("下一首")
                enabled: panel.player?.canGoNext ?? false
                onClicked: DockMprisService.next()
            }
        }
    }

    // ── Card 4: Screenshot ───────────────────────────────────────────
    ControlCenterCard {
        id: slotCard1
        coordinator: coordinator
        offsetTop: 155 + panel.mainControlsOffsetY
        offsetRight: 264
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
        cardWidth: 52
        cardHeight: 52

        cardScale: screenshotPointer.pressed ? 0.91 : (screenshotPointer.containsMouse ? 1.06 : 1.0)
        Behavior on cardScale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.fill: parent
            radius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
            color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.45)
            opacity: screenshotPointer.containsMouse && !screenshotPointer.pressed ? 1 : 0
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
        coordinator: coordinator
        offsetTop: 155 + panel.mainControlsOffsetY
        offsetRight: 203
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
        cardWidth: 52
        cardHeight: 52

        cardScale: themePointer.pressed ? 0.91 : (themePointer.containsMouse ? 1.06 : 1.0)
        Behavior on cardScale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.fill: parent
            radius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
            color: ThemeService.isDark
                ? "#ffffff"
                : Qt.rgba(1, 1, 1, 0.45)
            opacity: ThemeService.isDark || (themePointer.containsMouse && !themePointer.pressed) ? 1 : 0
            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
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
        coordinator: coordinator
        offsetTop: 155 + panel.mainControlsOffsetY
        offsetRight: 142
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
        cardWidth: 52
        cardHeight: 52

        cardScale: powerPointer.pressed ? 0.91 : (powerPointer.containsMouse ? 1.06 : 1.0)
        Behavior on cardScale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.fill: parent
            radius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
            color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.45)
            opacity: powerPointer.containsMouse && !powerPointer.pressed ? 1 : 0
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
        coordinator: coordinator
        offsetTop: 155 + panel.mainControlsOffsetY
        offsetRight: 81
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
        cardWidth: 52
        cardHeight: 52

        cardScale: dndPointer.pressed ? 0.91 : (dndPointer.containsMouse ? 1.06 : 1.0)
        Behavior on cardScale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.fill: parent
            radius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
            color: ControlCenterService.doNotDisturbEnabled
                ? (ThemeService.isDark ? Qt.rgba(0.04, 0.52, 1.0, 0.28) : Qt.rgba(0.04, 0.52, 1.0, 0.18))
                : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.45))
            opacity: ControlCenterService.doNotDisturbEnabled || (dndPointer.containsMouse && !dndPointer.pressed) ? 1 : 0
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
        coordinator: coordinator
        offsetTop: 155 + panel.mainControlsOffsetY
        offsetRight: 20
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
        cardWidth: 52
        cardHeight: 52

        cardScale: nightLightPointer.pressed ? 0.91 : (nightLightPointer.containsMouse ? 1.06 : 1.0)
        Behavior on cardScale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.fill: parent
            radius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 26)
            color: ControlCenterService.nightLightActive
                ? "#ffcc00"
                : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.45))
            opacity: ControlCenterService.nightLightActive || (nightLightPointer.containsMouse && !nightLightPointer.pressed) ? 1 : 0
            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
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

    // ── Card 9: Display brightness ───────────────────────────────────
    ControlCenterCard {
        id: slotCard6
        coordinator: coordinator
        offsetTop: 217 + panel.mainControlsOffsetY
        offsetRight: 20
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 19)
        cardWidth: 296
        cardHeight: 57
        cardBorderColor: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10))
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid

        Row {
            anchors { left: parent.left; top: parent.top; leftMargin: 14; topMargin: 8 }
            spacing: 4
            GlassText {
                text: "显示亮度"
                color: ThemeService.foregroundColor
                font { pixelSize: 11; weight: Font.DemiBold; family: "Noto Sans CJK SC" }
            }
        }
        GlassText {
            anchors { right: parent.right; top: parent.top; rightMargin: 30; topMargin: 8 }
            text: ControlCenterService.brightnessAvailable ? Math.round(panel.brightnessPreview) + "%" : "无亮度设备"
            color: ThemeService.foregroundColor
            opacity: 0.50
            font { pixelSize: 9; family: "Noto Sans CJK SC" }
        }
        GlassText {
            anchors { right: parent.right; top: parent.top; rightMargin: 13; topMargin: 5 }
            text: "›"
            color: ThemeService.foregroundColor
            font { pixelSize: 15; weight: Font.Bold }
        }
        MouseArea {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 27
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.openSubmenu("brightness")
        }
        ControlCenterSlider {
            id: brightnessSlider
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 31; rightMargin: 31; bottomMargin: 8 }
            value: panel.brightnessPreview / 100
            enabled: ControlCenterService.brightnessAvailable
            onPreviewChanged: function(v) {
                panel.draggingBrightness = true
                panel.brightnessPreview = Math.round(v * 100)
            }
            onCommitRequested: function(v) {
                panel.draggingBrightness = false
                ControlCenterService.setBrightness(Math.round(v * 100))
            }
        }
        GlassText {
            anchors { left: parent.left; leftMargin: 12; bottom: parent.bottom; bottomMargin: 12 }
            text: "☀"
            color: ThemeService.foregroundColor
            opacity: 0.65
            font.pixelSize: 13
        }
    }

    // ── Card 8: Sound / volume ───────────────────────────────────────
    ControlCenterCard {
        id: slotCard7
        coordinator: coordinator
        offsetTop: 282 + panel.mainControlsOffsetY
        offsetRight: 20
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 19)
        cardWidth: 296
        cardHeight: 57
        cardBorderColor: ThemeService.isDark ? Qt.rgba(0.72, 0.93, 1, 0.27) : Qt.rgba(0, 0, 0, 0.10)
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid

        Row {
            anchors { left: parent.left; top: parent.top; leftMargin: 14; topMargin: 8 }
            spacing: 4
            GlassText {
                text: "声音"
                color: ThemeService.foregroundColor
                font { pixelSize: 11; weight: Font.DemiBold; family: "Noto Sans CJK SC" }
            }
            GlassText {
                text: "›"
                color: ThemeService.foregroundColor
                opacity: 0.50
                font { pixelSize: 13; weight: Font.Bold }
            }
        }
        MouseArea {
            anchors { left: parent.left; top: parent.top; right: parent.right }
            height: 26
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: panel.openSubmenu("sound")
        }
        GlassText {
            anchors { right: parent.right; top: parent.top; rightMargin: 14; topMargin: 8 }
            text: Math.round(panel.volumePreview) + "%"
            color: ThemeService.foregroundColor
            opacity: 0.72
            font { pixelSize: 10; family: "Noto Sans CJK SC" }
        }
        Canvas {
            id: volumeGlyph
            anchors { left: parent.left; leftMargin: 12; bottom: parent.bottom; bottomMargin: 12 }
            width: 15
            height: 15
            property color glyphColor: ThemeService.tileGlyph
            onGlyphColorChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = glyphColor
                ctx.fillStyle = glyphColor
                ctx.lineWidth = 1.7
                ctx.lineJoin = "round"
                ctx.fillRect(1, 6, 3.5, 4)
                ctx.beginPath(); ctx.moveTo(4.3, 6); ctx.lineTo(8, 3); ctx.lineTo(8, 13); ctx.lineTo(4.3, 10); ctx.closePath(); ctx.fill()
                if (!ControlCenterService.audioMuted) {
                    ctx.lineCap = "round"
                    ctx.beginPath(); ctx.arc(7.2, 8, 4, -0.8, 0.8); ctx.stroke()
                } else {
                    ctx.beginPath(); ctx.moveTo(10.5, 4.5); ctx.lineTo(14, 11.5); ctx.stroke()
                }
            }
            Connections {
                target: ControlCenterService
                function onAudioMutedChanged() { volumeGlyph.requestPaint() }
            }
        }
        ControlCenterSlider {
            id: volumeSlider
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 34; rightMargin: 17; bottomMargin: 8 }
            value: panel.volumePreview / 100
            onPreviewChanged: function(v) {
                panel.draggingVolume = true
                panel.volumePreview = Math.round(v * 100)
            }
            onCommitRequested: function(v) {
                panel.draggingVolume = false
                ControlCenterService.setVolume(Math.round(v * 100))
            }
        }
    }

    // ── Card 9: Notification history ─────────────────────────────────
    // Session history grouped by app: dismissed/expired banners and DND
    // notifications (which are never shown) land here. Each group header
    // carries the app icon/name, and every row has its own close button.
    ControlCenterCard {
        id: slotCard8
        coordinator: coordinator
        // An empty history is not worth a permanently visible, permanently
        // empty card taking up the bottom of the panel; only occupy that
        // window/blur-region/hit-test space once there is something to show.
        // cardShown (bound by the panel: hidden while a submenu/session sheet
        // is open) is factored in here because this card overrides `visible`.
        visible: cardShown && coordinator.cardAnchor !== null
            && ControlCenterService.historyGroups.length > 0
        offsetTop: panel.notificationFirst ? 20 : 347
        offsetRight: 20
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 19)
        cardWidth: 296
        cardHeight: 230
        cardBorderColor: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10))
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid

        Item {
            anchors { fill: parent; margins: 10 }

            GlassText {
                id: historyTitle
                text: "通知历史"
                color: ThemeService.foregroundColor
                font { pixelSize: 12; weight: Font.Bold; family: "Noto Sans CJK SC" }
                anchors { left: parent.left; top: parent.top }
            }
            GlassText {
                text: "清空"
                color: clearMouse.containsMouse ? "#0a84ff"
                    : AppearanceTokens.surface.pick(
                        AppearanceTokens.colors.surfaceContainerHigh,
                        AppearanceTokens.content.glassInk(0.50))
                font { pixelSize: 11; family: "Noto Sans CJK SC" }
                anchors { right: parent.right; top: parent.top }
                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        ControlCenterService.notificationHistory.clear()
                        AppNotificationService.clearAll()
                    }
                }
            }
            ListView {
                id: historyList
                anchors {
                    left: parent.left
                    right: parent.right
                    top: historyTitle.bottom
                    topMargin: 6
                    bottom: parent.bottom
                }
                model: ControlCenterService.historyGroups
                clip: true
                interactive: true
                spacing: 6

                // One group per app: a compact header + its notification rows.
                delegate: Column {
                    required property var modelData
                    width: historyList.width

                    Row {
                        width: parent.width
                        height: 18
                        spacing: 5
                        IconImage {
                            width: 12; height: 12
                            source: modelData.appIcon || ""
                            // Theme icon: synchronous, see AppIcon.qml.
                            asynchronous: false
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        GlassText {
                            text: modelData.appName
                            color: AppearanceTokens.content.glassInk(0.62)
                            font { pixelSize: 10; weight: Font.DemiBold; family: "Noto Sans CJK SC" }
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Column {
                        width: parent.width
                        spacing: 3
                        Repeater {
                            model: modelData.items
                            delegate: Item {
                                required property var modelData
                                width: historyList.width
                                height: rowSummary.implicitHeight + (rowBody.visible ? rowBody.implicitHeight + 1 : 0)

                                GlassText {
                                    id: rowSummary
                                    width: parent.width - removeButton.width - 6
                                    text: modelData.summary.length > 0 ? modelData.summary : "通知"
                                    color: ThemeService.foregroundColor
                                    font { pixelSize: 11; weight: Font.Bold; family: "Noto Sans CJK SC" }
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                                GlassText {
                                    id: rowBody
                                    anchors.top: rowSummary.bottom
                                    anchors.topMargin: 1
                                    width: parent.width - removeButton.width - 6
                                    visible: text.length > 0
                                    text: modelData.body
                                    color: AppearanceTokens.content.glassInk(0.50)
                                    font { pixelSize: 10; family: "Noto Sans CJK SC" }
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                                GlassText {
                                    id: removeButton
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "×"
                                    color: removeMouse.containsMouse ? "#ff453a"
                                        : AppearanceTokens.surface.pick(
                                            AppearanceTokens.colors.surfaceContainerHigh,
                                            AppearanceTokens.content.glassInk(0.42))
                                    font { pixelSize: 13; weight: Font.Bold }
                                    MouseArea {
                                        id: removeMouse
                                        anchors.fill: parent
                                        anchors.margins: -5
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: ControlCenterService.removeHistoryById(modelData.notifId)
                                    }
                                }
                            }
                        }
                    }
                }
                GlassText {
                    anchors.centerIn: parent
                    visible: historyList.count === 0
                    text: "暂无历史通知"
                    color: AppearanceTokens.content.glassInk(0.30)
                    font { pixelSize: 11; family: "Noto Sans CJK SC" }
                }
            }
        }
    }

    // ── Card 10 (Sub-panel): Power & Session Management ──────────────
    // The power/session page: Lock, Suspend, Switch User, Logout, Reboot and
    // Power Off in one list. It uses the same slot and the same card material as
    // the Wi-Fi/Bluetooth pages -- the coordinator-managed cards hide while it is
    // open, so the two interfaces never stack on top of each other.
    ControlCenterCard {
        id: sessionCard
        coordinator: coordinator
        managedByCoordinator: false
        // Same slot as the Wi-Fi/Bluetooth submenu, so the session list is one
        // more page of the Control Center instead of a panel of its own.
        offsetTop: panel.notificationFirst
            ? panel.controlCenterHeight - 20 - sessionCard.cardHeight
            : 20
        offsetRight: 20
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 22)
        cardWidth: 296
        cardHeight: 340
        cardBorderColor: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.10))
        // Hidden while a confirmation is up: the dialog owns the screen then, and
        // leaving the list card mapped would strand an empty glass slab behind it.
        cardShown: panel.sessionModalVisible && panel.pendingConfirmAction === ""
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid

        // ── VIEW 1: 6-action Grid ──
        Item {
            anchors.fill: parent
            visible: panel.pendingConfirmAction === ""

            // Header: same shape as the Wi-Fi/Bluetooth pages -- back button on the
            // left, identity on the right -- instead of a title with a close box.
            Item {
                id: sessionHeader
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    topMargin: 12
                    leftMargin: 12
                    rightMargin: 12
                }
                height: 28

                Rectangle {
                    id: sessionBackBtn
                    width: 26
                    height: 26
                    radius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 13)
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    color: sessionBackMouse.pressed
                        ? (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.26) : Qt.rgba(0, 0, 0, 0.14)))
                        : (sessionBackMouse.containsMouse
                            ? (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.09)))
                            : (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.05))))
                    border.width: 1
                    border.color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.08))
                    Behavior on color { ColorAnimation { duration: 110 } }

                    GlassText {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: -1
                        text: "‹"
                        color: AppearanceTokens.content.glassInk()
                        font { pixelSize: 18; weight: Font.Bold }
                    }

                    MouseArea {
                        id: sessionBackMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.closeSubmenu()
                    }
                }

                Row {
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 8

                    GlassText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ControlCenterService.currentUserName
                        color: ThemeService.foregroundColor
                        font { pixelSize: 12; weight: Font.Bold; family: "Noto Sans CJK SC" }
                    }

                    Rectangle {
                        width: 28
                        height: 28
                        radius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 14)
                        color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.06))
                        border.width: 1
                        border.color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0, 0, 0, 0.10))

                        BundledIcon {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            name: BundledIcons.roleName("switchUser")
                            color: ThemeService.foregroundColor
                        }
                    }
                }
            }

            // Divider line
            Rectangle {
                id: sessionDivider
                anchors {
                    top: sessionHeader.bottom
                    topMargin: 8
                    left: parent.left
                    right: parent.right
                    leftMargin: 12
                    rightMargin: 12
                }
                height: 1
                color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08))
            }

            // A plain list, the same shape as the Wi-Fi/Bluetooth pages: one row
            // per action, the whole row highlights on hover, and the destructive
            // three sit at the bottom in dark red.
            Column {
                id: actionsList
                anchors {
                    top: sessionDivider.bottom
                    topMargin: 4
                    left: parent.left
                    right: parent.right
                    leftMargin: 6
                    rightMargin: 6
                }

                Repeater {
                    model: [
                        { icon: "lock", label: "锁定屏幕", danger: false, action: "lock" },
                        { icon: "suspend", label: "睡眠", danger: false, action: "suspend" },
                        { icon: "switchUser", label: "切换用户", danger: false, action: "switch" },
                        { icon: "logout", label: "注销", danger: true, action: "logout" },
                        { icon: "reboot", label: "重新启动", danger: true, action: "reboot" },
                        { icon: "powerOff", label: "关机", danger: true, action: "poweroff" }
                    ]

                    delegate: Item {
                        required property var modelData
                        width: actionsList.width
                        height: 44

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 9
                            color: sessionRow.containsMouse
                                ? (modelData.danger
                                    ? Qt.rgba(1.0, 0.23, 0.19, 0.14)
                                    : (ThemeService.isDark
                                        ? Qt.rgba(1, 1, 1, 0.10)
                                        : Qt.rgba(0, 0, 0, 0.06)))
                                : "transparent"
                            Behavior on color { ColorAnimation { duration: 110 } }
                        }

                        Row {
                            anchors {
                                left: parent.left
                                leftMargin: 12
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 10

                            BundledIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20
                                height: 20
                                name: BundledIcons.roleName(modelData.icon)
                                color: modelData.danger
                                    ? "#ff3b30" : ThemeService.foregroundColor
                            }

                            GlassText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                color: modelData.danger
                                    ? "#ff3b30" : ThemeService.foregroundColor
                                font { pixelSize: 13; weight: Font.Medium; family: "Noto Sans CJK SC" }
                            }
                        }

                        MouseArea {
                            id: sessionRow
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.runSessionAction(modelData.action)
                        }
                    }
                }
            }

            // Error / Status bar
            GlassText {
                anchors {
                    bottom: parent.bottom
                    bottomMargin: 6
                    horizontalCenter: parent.horizontalCenter
                }
                visible: ControlCenterService.lastSessionError.length > 0
                text: "⚠ " + ControlCenterService.lastSessionError
                color: "#ff453a"
                font { pixelSize: 10; weight: Font.Medium; family: "Noto Sans CJK SC" }
            }
        }

    }

    // Session confirmations (log out / restart / shut down) are important
    // interactions, so they use the shared modal dialog primitive instead of a
    // page of the Control Center: centred, with the strong readable scrim and the
    // card shadow the other important dialogs already have.
    KosFloatPanel {
        id: sessionConfirm
        centerOnScreen: true
        modal: true
        backdropMode: "none"
        dismissOnBackdrop: false
        contentPadding: 0
        radius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 24)
        onBackdropClicked: panel.pendingConfirmAction = ""

        Item {
            width: 300
            height: 204

            Rectangle {
                width: 56
                height: 56
                radius: width / 2
                anchors {
                    top: parent.top
                    topMargin: 20
                    horizontalCenter: parent.horizontalCenter
                }
                color: Qt.rgba(sessionConfirm.contentForegroundColor.r,
                    sessionConfirm.contentForegroundColor.g,
                    sessionConfirm.contentForegroundColor.b, 0.08)
                border.width: 1
                border.color: Qt.rgba(sessionConfirm.contentForegroundColor.r,
                    sessionConfirm.contentForegroundColor.g,
                    sessionConfirm.contentForegroundColor.b, 0.34)

                BundledIcon {
                    anchors.centerIn: parent
                    width: 26
                    height: 26
                    name: BundledIcons.roleName(panel.pendingConfirmAction === "poweroff"
                        ? "powerOff"
                        : (panel.pendingConfirmAction === "reboot" ? "reboot" : "logout"))
                    color: sessionConfirm.contentForegroundColor
                }
            }

            Text {
                anchors {
                    top: parent.top
                    topMargin: 88
                    left: parent.left
                    right: parent.right
                }
                horizontalAlignment: Text.AlignHCenter
                text: panel.pendingConfirmAction === "poweroff" ? "确定要关机吗？"
                    : (panel.pendingConfirmAction === "reboot" ? "确定要重启吗？" : "确定要注销吗？")
                color: sessionConfirm.contentForegroundColor
                font { pixelSize: 16; weight: Font.Bold; family: "Noto Sans CJK SC" }
            }

            Text {
                anchors {
                    top: parent.top
                    topMargin: 114
                    left: parent.left
                    right: parent.right
                }
                horizontalAlignment: Text.AlignHCenter
                text: "未保存的工作可能会丢失"
                color: sessionConfirm.contentSecondaryColor
                font { pixelSize: 12; family: "Noto Sans CJK SC" }
            }

            Row {
                anchors {
                    right: parent.right
                    bottom: parent.bottom
                    rightMargin: 18
                    bottomMargin: 18
                }
                spacing: 12

                Rectangle {
                    width: 88
                    height: 32
                    radius: height / 2
                    color: sessionConfirm.contentControlFill

                    Text {
                        anchors.centerIn: parent
                        text: "取消"
                        color: sessionConfirm.contentForegroundColor
                        font { pixelSize: 13; weight: Font.Medium; family: "Noto Sans CJK SC" }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.pendingConfirmAction = ""
                    }
                }

                Rectangle {
                    width: 104
                    height: 32
                    radius: height / 2
                    // Same face as the neutral button, red label only.
                    color: sessionConfirm.contentControlFill

                    Text {
                        anchors.centerIn: parent
                        text: panel.pendingConfirmAction === "poweroff" ? "关机"
                            : (panel.pendingConfirmAction === "reboot" ? "重启" : "注销")
                        color: "#ff3b30"
                        font { pixelSize: 13; weight: Font.Medium; family: "Noto Sans CJK SC" }
                    }

                    MouseArea {
                        id: executeConfirmMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
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
                }
            }
        }
    }

    // ── Card 11 (Submenu Panel): Wi-Fi, Bluetooth, Brightness, Sound ─
    ControlCenterCard {
        id: submenuCard
        coordinator: coordinator
        managedByCoordinator: false
        // Top Bar submenus grow down from the systray. Bottom/side Dock
        // submenus instead keep their lower edge beside the systray/control
        // area, regardless of the selected submenu's individual height.
        offsetTop: panel.notificationFirst
            ? panel.controlCenterHeight - 20 - submenuCard.cardHeight
            : 20
        offsetRight: 20
        cardRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 22)
        cardWidth: 296
        cardHeight: panel.activeSubmenu === "wifi" ? 360
            : (panel.activeSubmenu === "bluetooth" ? 340
            : (panel.activeSubmenu === "brightness" ? 280
            : (panel.activeSubmenu === "sound" ? 420 : 280)))
        cardShown: panel.submenuOpen

        // Navigation Header
        Item {
            id: submenuHeader
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                topMargin: 12
                leftMargin: 12
                rightMargin: 12
            }
            height: 28

            // Back button
            Rectangle {
                id: submenuBackBtn
                width: 26
                height: 26
                radius: AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 13)
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                color: submenuBackMouse.pressed
                    ? (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.26) : Qt.rgba(0, 0, 0, 0.14)))
                    : (submenuBackMouse.containsMouse
                        ? (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.09)))
                        : (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.05))))
                border.width: 1
                border.color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.08))
                Behavior on color { ColorAnimation { duration: 110 } }

                GlassText {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -1
                    text: "‹"
                    color: AppearanceTokens.content.glassInk()
                    font { pixelSize: 18; weight: Font.Bold }
                }

                MouseArea {
                    id: submenuBackMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.closeSubmenu()
                }
            }

            // Title
            GlassText {
                anchors {
                    left: submenuBackBtn.right
                    leftMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                text: panel.activeSubmenu === "wifi" ? "Wi‑Fi"
                    : (panel.activeSubmenu === "bluetooth" ? "蓝牙"
                    : (panel.activeSubmenu === "brightness" ? "显示亮度"
                    : (panel.activeSubmenu === "sound" ? "声音" : "")))
                color: AppearanceTokens.content.glassInk()
                font { pixelSize: 13; weight: Font.Bold; family: "Noto Sans CJK SC" }
            }

            // Right toggle switch for Wi-Fi and Bluetooth
            Rectangle {
                id: submenuToggleSwitch
                visible: panel.activeSubmenu === "wifi" || panel.activeSubmenu === "bluetooth"
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                width: 38
                height: 22
                radius: 11
                readonly property bool isChecked: panel.activeSubmenu === "wifi"
                    ? NetworkService.wifiEnabled : ControlCenterService.bluetoothPowered
                readonly property bool inProgress: panel.activeSubmenu === "wifi"
                    ? NetworkService.wifiToggleInProgress : ControlCenterService.bluetoothChangeInProgress

                color: isChecked
                    ? "#0a84ff"
                    : (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.14)))
                opacity: inProgress ? 0.6 : 1.0
                Behavior on color { ColorAnimation { duration: 160 } }

                Rectangle {
                    width: 18
                    height: 18
                    radius: 9
                    anchors.verticalCenter: parent.verticalCenter
                    x: submenuToggleSwitch.isChecked ? parent.width - width - 2 : 2
                    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    color: "#ffffff"
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: !submenuToggleSwitch.inProgress
                    onClicked: {
                        if (panel.activeSubmenu === "wifi") {
                            NetworkService.setWifiEnabled(!NetworkService.wifiEnabled)
                        } else if (panel.activeSubmenu === "bluetooth") {
                            ControlCenterService.setBluetoothEnabled(!ControlCenterService.bluetoothPowered)
                        }
                    }
                }
            }
        }

        // Header divider
        Rectangle {
            id: submenuDivider
            anchors {
                top: submenuHeader.bottom
                topMargin: 9
                left: parent.left
                right: parent.right
                leftMargin: 12
                rightMargin: 12
            }
            height: 1
            color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08))
        }

        // ── View A: Wi-Fi ──
        Item {
            id: wifiSubmenuView
            visible: panel.activeSubmenu === "wifi"
            anchors {
                top: submenuDivider.bottom
                topMargin: 6
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }

            // Wi-Fi Off state
            Item {
                anchors.fill: parent
                visible: !NetworkService.wifiEnabled

                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    GlassText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Wi‑Fi 已关闭"
                        color: AppearanceTokens.content.glassInk()
                        font { pixelSize: 14; weight: Font.Bold; family: "Noto Sans CJK SC" }
                    }
                    GlassText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "在上方开启开关以查看附近网络"
                        color: AppearanceTokens.content.glassInk()
                        font { pixelSize: 12; weight: Font.DemiBold; family: "Noto Sans CJK SC" }
                    }
                }
            }

            // Wi-Fi On state
            Item {
                anchors.fill: parent
                visible: NetworkService.wifiEnabled

                Item {
                    id: wifiSectionHeader
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        leftMargin: 14
                        rightMargin: 14
                    }
                    height: 22

                    GlassText {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        text: "附近网络"
                        color: AppearanceTokens.content.glassInk()
                        font { pixelSize: 11; weight: Font.Bold; family: "Noto Sans CJK SC" }
                    }

                    GlassText {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        visible: NetworkService.wifiScanInProgress
                        text: "正在扫描…"
                        color: AppearanceTokens.content.glassInk()
                        font { pixelSize: 10; weight: Font.DemiBold; family: "Noto Sans CJK SC" }
                    }
                }

                ListView {
                    id: submenuWifiList
                    anchors {
                        top: wifiSectionHeader.bottom
                        topMargin: 2
                        left: parent.left
                        right: parent.right
                        // wifiFooter is a sibling of this state container, so
                        // it cannot be used as an anchor target. Reserve its
                        // height locally; cross-parent anchoring collapses the
                        // ListView and makes all scanned networks invisible.
                        bottom: parent.bottom
                        leftMargin: 8
                        rightMargin: 8
                        bottomMargin: 42
                    }
                    clip: true
                    spacing: 2
                    model: NetworkService.nearbyWifi

                    delegate: Rectangle {
                        required property var modelData
                        width: submenuWifiList.width
                        height: 42
                        radius: 10
                        color: wifiRowMouse.containsMouse
                            ? (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)))
                            : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        GlassText {
                            visible: !!modelData.active
                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                            text: "✓"
                            color: AppearanceTokens.content.glassInk()
                            font { pixelSize: 13; weight: Font.Bold }
                        }

                        WifiSignalIcon {
                            anchors {
                                left: parent.left
                                leftMargin: 26
                                verticalCenter: parent.verticalCenter
                            }
                            width: 16
                            height: 16
                            wifiEnabled: true
                            connected: !!modelData.active
                            signalStrength: modelData.signalStrength !== undefined ? modelData.signalStrength : 70
                            glyphColor: modelData.active ? ThemeService.tileAccent : ThemeService.tileGlyph
                        }

                        GlassText {
                            anchors {
                                left: parent.left
                                right: wifiRowRightArea.left
                                leftMargin: 48
                                rightMargin: 6
                                verticalCenter: parent.verticalCenter
                            }
                            text: modelData.ssid || "隐藏网络"
                            elide: Text.ElideRight
                            color: AppearanceTokens.content.glassInk()
                            font {
                                pixelSize: 12
                                weight: modelData.active ? Font.Bold : Font.DemiBold
                                family: "Noto Sans CJK SC"
                            }
                        }

                        Row {
                            id: wifiRowRightArea
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            spacing: 6

                            Canvas {
                                visible: modelData.security && modelData.security !== "none"
                                anchors.verticalCenter: parent.verticalCenter
                                width: 12
                                height: 14
                                readonly property color ink: AppearanceTokens.content.glassInk()
                                onInkChanged: requestPaint()
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.reset()
                                    ctx.strokeStyle = ink
                                    ctx.fillStyle = ink
                                    ctx.lineWidth = 1.5
                                    ctx.lineCap = "round"
                                    ctx.beginPath()
                                    ctx.arc(width / 2, 5, 3, Math.PI, 0)
                                    ctx.stroke()
                                    ctx.beginPath()
                                    ctx.moveTo(3.5, 5)
                                    ctx.lineTo(width - 3.5, 5)
                                    ctx.quadraticCurveTo(width - 2, 5, width - 2, 6.5)
                                    ctx.lineTo(width - 2, 10.5)
                                    ctx.quadraticCurveTo(width - 2, 12, width - 3.5, 12)
                                    ctx.lineTo(3.5, 12)
                                    ctx.quadraticCurveTo(2, 12, 2, 10.5)
                                    ctx.lineTo(2, 6.5)
                                    ctx.quadraticCurveTo(2, 5, 3.5, 5)
                                    ctx.closePath()
                                    ctx.fill()
                                }
                                Component.onCompleted: requestPaint()
                            }

                            Rectangle {
                                visible: !!modelData.active
                                width: 38
                                height: 20
                                radius: 10
                                color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08))
                                border.width: 1
                                border.color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.10))
                                GlassText {
                                    anchors.centerIn: parent
                                    text: "断开"
                                    color: AppearanceTokens.content.glassInk()
                                    font { pixelSize: 10; weight: Font.DemiBold; family: "Noto Sans CJK SC" }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: NetworkService.disconnectActiveWifi()
                                }
                            }
                        }

                        MouseArea {
                            id: wifiRowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.active) return
                                if (modelData.savedProfileUuid) {
                                    NetworkService.connectWifi(modelData.ssid, "", modelData.savedProfileUuid)
                                } else if (!modelData.security || modelData.security === "none") {
                                    NetworkService.connectWifi(modelData.ssid, "", "")
                                } else {
                                    // Copy the delegate value before closing;
                                    // the ListView may destroy this delegate as
                                    // soon as the control center is unloaded.
                                    const network = Object.assign({}, modelData, {
                                        secured: Boolean(modelData.secured
                                            || (modelData.security
                                                && modelData.security !== "none"))
                                    })
                                    panel.close()
                                    panel.wifiNetworkSelected(network)
                                }
                            }
                        }
                    }

                    GlassText {
                        anchors.centerIn: parent
                        visible: submenuWifiList.count === 0 && !NetworkService.wifiScanInProgress
                        text: "未搜索到 Wi‑Fi 网络"
                        color: AppearanceTokens.content.glassInk()
                        font { pixelSize: 12; weight: Font.DemiBold; family: "Noto Sans CJK SC" }
                    }
                }
            }

            Item {
                id: wifiFooter
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 38

                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 12; rightMargin: 12 }
                    height: 1
                    color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
                }

                GlassText {
                    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                    text: "网络设置…"
                    color: AppearanceTokens.content.glassInk()
                    font { pixelSize: 12; weight: Font.Bold; family: "Noto Sans CJK SC" }
                }

                GlassText {
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    text: "›"
                    color: AppearanceTokens.content.glassInk()
                    font { pixelSize: 13; weight: Font.Bold }
                }

                MouseArea {
                    id: wifiSettingsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.openSettingsModule("kcm_networkmanagement")
                }
            }
        }

        // ── View B: Bluetooth ──
        Item {
            id: bluetoothSubmenuView
            visible: panel.activeSubmenu === "bluetooth"
            anchors {
                top: submenuDivider.bottom
                topMargin: 6
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }

            Item {
                anchors.fill: parent
                visible: !ControlCenterService.bluetoothPowered

                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    GlassText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "蓝牙已关闭"
                        color: AppearanceTokens.content.glassInk()
                        font { pixelSize: 13; weight: Font.Bold; family: "Noto Sans CJK SC" }
                    }
                    GlassText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "在上方开启开关以连接设备"
                        color: AppearanceTokens.content.glassInk()
                        font { pixelSize: 11; family: "Noto Sans CJK SC" }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: ControlCenterService.bluetoothPowered

                Item {
                    id: btSectionHeader
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        leftMargin: 14
                        rightMargin: 14
                    }
                    height: 22

                    GlassText {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        text: "设备"
                        color: AppearanceTokens.content.glassInk()
                        font { pixelSize: 10; weight: Font.DemiBold; family: "Noto Sans CJK SC" }
                    }

                    GlassText {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        visible: ControlCenterService.bluetoothDevicesRefreshInProgress
                        text: "正在刷新…"
                        color: AppearanceTokens.content.glassInk()
                        font { pixelSize: 9; family: "Noto Sans CJK SC" }
                    }
                }

                ListView {
                    id: submenuBtList
                    anchors {
                        top: btSectionHeader.bottom
                        topMargin: 2
                        left: parent.left
                        right: parent.right
                        // btFooter is a sibling of this state container; use
                        // local geometry rather than an invalid cross-parent
                        // anchor so paired devices receive a real list height.
                        bottom: parent.bottom
                        leftMargin: 8
                        rightMargin: 8
                        bottomMargin: 42
                    }
                    clip: true
                    spacing: 2
                    model: ControlCenterService.bluetoothDevices

                    delegate: Rectangle {
                        required property var modelData
                        width: submenuBtList.width
                        height: 42
                        radius: 10
                        color: btRowMouse.containsMouse
                            ? (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)))
                            : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        GlassText {
                            visible: !!modelData.connected
                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                            text: "✓"
                            color: AppearanceTokens.content.glassInk()
                            font { pixelSize: 13; weight: Font.Bold }
                        }

                        Canvas {
                            anchors {
                                left: parent.left
                                leftMargin: 26
                                verticalCenter: parent.verticalCenter
                            }
                            width: 16
                            height: 16
                            readonly property color ink: AppearanceTokens.content.glassInk()
                            onInkChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.reset()
                                ctx.strokeStyle = modelData.connected ? "#0a84ff" : ink
                                ctx.lineWidth = 1.6
                                ctx.lineCap = "round"
                                ctx.lineJoin = "round"
                                ctx.scale(0.55, 0.55)
                                ctx.beginPath()
                                ctx.moveTo(13.5, 2.5)
                                ctx.lineTo(20, 9)
                                ctx.lineTo(13.5, 15)
                                ctx.lineTo(20, 21)
                                ctx.lineTo(13.5, 26.5)
                                ctx.lineTo(13.5, 2.5)
                                ctx.moveTo(7, 8.5)
                                ctx.lineTo(13.5, 15)
                                ctx.lineTo(7, 21.5)
                                ctx.stroke()
                            }
                        }

                        Column {
                            anchors {
                                left: parent.left
                                right: btBatteryArea.left
                                leftMargin: 50
                                rightMargin: 6
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 1

                            GlassText {
                                width: parent.width
                                text: modelData.name || "未知设备"
                                elide: Text.ElideRight
                                color: AppearanceTokens.content.glassInk()
                                font { pixelSize: 11; weight: modelData.connected ? Font.DemiBold : Font.Normal; family: "Noto Sans CJK SC" }
                            }

                            GlassText {
                                text: modelData.connected ? "已连接" : "未连接"
                                color: AppearanceTokens.content.glassInk()
                                font { pixelSize: 9; family: "Noto Sans CJK SC" }
                            }
                        }

                        Item {
                            id: btBatteryArea
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            width: btBatteryText.implicitWidth
                            height: 16
                            visible: modelData.battery !== undefined && modelData.battery !== null

                            GlassText {
                                id: btBatteryText
                                anchors.centerIn: parent
                                text: (modelData.battery || 0) + "%"
                                color: AppearanceTokens.content.glassInk()
                                font { pixelSize: 10; family: "Noto Sans CJK SC" }
                            }
                        }

                        MouseArea {
                            id: btRowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !ControlCenterService.bluetoothDeviceChangeInProgress
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: ControlCenterService.setBluetoothDeviceConnected(modelData, !modelData.connected)
                        }
                    }

                    GlassText {
                        anchors.centerIn: parent
                        visible: submenuBtList.count === 0 && !ControlCenterService.bluetoothDevicesRefreshInProgress
                        text: "未发现已配对设备"
                        color: AppearanceTokens.content.glassInk()
                        font { pixelSize: 11; family: "Noto Sans CJK SC" }
                    }
                }
            }

            Item {
                id: btFooter
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 38

                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 12; rightMargin: 12 }
                    height: 1
                    color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
                }

                GlassText {
                    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                    text: "蓝牙设置…"
                    color: AppearanceTokens.content.glassInk()
                    font { pixelSize: 11; weight: Font.DemiBold; family: "Noto Sans CJK SC" }
                }

                GlassText {
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    text: "›"
                    color: AppearanceTokens.content.glassInk()
                    font { pixelSize: 13; weight: Font.Bold }
                }

                MouseArea {
                    id: btSettingsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.openSettingsModule("kcm_bluetooth")
                }
            }
        }

        // ── View C: Per-display brightness ──
        Item {
            id: brightnessSubmenuView
            visible: panel.activeSubmenu === "brightness"
            anchors {
                top: submenuDivider.bottom
                topMargin: 8
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }

            ListView {
                id: brightnessDisplayList
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    leftMargin: 14
                    rightMargin: 14
                    bottomMargin: 38
                }
                spacing: 4
                clip: true
                model: ControlCenterService.brightnessDisplays

                delegate: Item {
                        id: displayBrightnessRow
                        required property var modelData
                        width: brightnessDisplayList.width
                        height: 82
                        property real preview: Number(modelData.percent || 0)

                        GlassText {
                            anchors { left: parent.left; right: displayBrightnessPercent.left; top: parent.top; rightMargin: 8 }
                            text: modelData.label || modelData.id || "显示器"
                            elide: Text.ElideRight
                            color: AppearanceTokens.content.glassInk()
                            font { pixelSize: 11; weight: Font.DemiBold; family: "Noto Sans CJK SC" }
                        }
                        GlassText {
                            id: displayBrightnessPercent
                            anchors { right: parent.right; top: parent.top }
                            text: Math.round(displayBrightnessRow.preview) + "%"
                            color: AppearanceTokens.content.glassInk()
                            font { pixelSize: 10; family: "Noto Sans CJK SC" }
                        }
                        GlassText {
                            anchors { left: parent.left; top: parent.top; topMargin: 20 }
                            text: modelData.isInternal ? "内置屏幕" : "外接显示器"
                            color: AppearanceTokens.content.glassInk()
                            font { pixelSize: 9; family: "Noto Sans CJK SC" }
                        }
                        ControlCenterSlider {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 3 }
                            value: displayBrightnessRow.preview / 100
                            enabled: !ControlCenterService.brightnessChangeInProgress
                            onPreviewChanged: function(v) {
                                displayBrightnessRow.preview = Math.round(v * 100)
                            }
                            onCommitRequested: function(v) {
                                ControlCenterService.setDisplayBrightness(
                                    displayBrightnessRow.modelData.id, Math.round(v * 100))
                            }
                        }
                }
            }

            GlassText {
                anchors.centerIn: parent
                visible: ControlCenterService.brightnessDisplays.length === 0
                text: "未发现可调节亮度的显示器"
                color: AppearanceTokens.content.glassInk()
                font { pixelSize: 11; family: "Noto Sans CJK SC" }
            }

            Item {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 38
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 12; rightMargin: 12 }
                    height: 1
                    color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
                }
                GlassText {
                    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                    text: "显示设置…"
                    color: AppearanceTokens.content.glassInk()
                    font { pixelSize: 11; weight: Font.DemiBold; family: "Noto Sans CJK SC" }
                }
                GlassText {
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    text: "›"
                    color: AppearanceTokens.content.glassInk()
                    font { pixelSize: 13; weight: Font.Bold }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.openSettingsModule("kcm_kscreen")
                }
            }
        }

        // ── View D: Sound ──
        Item {
            id: soundSubmenuView
            visible: panel.activeSubmenu === "sound"
            anchors {
                top: submenuDivider.bottom
                topMargin: 6
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }

            Item {
                id: soundVolumeSection
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    leftMargin: 14
                    rightMargin: 14
                }
                height: 62

                GlassText {
                    anchors { left: parent.left; top: parent.top; topMargin: 2 }
                    text: "主音量"
                    color: ThemeService.foregroundColor
                    font { pixelSize: 11; weight: Font.DemiBold; family: "Noto Sans CJK SC" }
                }

                GlassText {
                    anchors { right: parent.right; top: parent.top; topMargin: 2 }
                    text: Math.round(panel.volumePreview) + "%"
                    color: ThemeService.foregroundColor
                    opacity: 0.65
                    font { pixelSize: 10; family: "Noto Sans CJK SC" }
                }

                Canvas {
                    id: submenuVolumeGlyph
                    anchors { left: parent.left; leftMargin: 2; verticalCenter: submenuVolumeSlider.verticalCenter }
                    width: 19
                    height: 16
                    renderTarget: Canvas.Image

                    readonly property int volumeLevel: Math.round(panel.volumePreview)
                    readonly property bool isMuted: ControlCenterService.audioMuted
                    // One resolved ink for the whole glyph: the muted body is
                    // the same colour at a lower alpha, so it never has to be
                    // recomputed from a light/dark pair here.
                    readonly property color ink: AppearanceTokens.content.glassInk()

                    onVolumeLevelChanged: requestPaint()
                    onIsMutedChanged: requestPaint()
                    onInkChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const fg = ink
                        const bodyColor = isMuted
                            ? Qt.rgba(fg.r, fg.g, fg.b, 0.50) : fg

                        ctx.fillStyle = bodyColor
                        ctx.strokeStyle = fg
                        ctx.lineWidth = 1.5
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"

                        ctx.fillRect(1.0, 5.5, 3.2, 5.0)

                        ctx.beginPath()
                        ctx.moveTo(4.2, 5.5)
                        ctx.lineTo(7.5, 2.5)
                        ctx.lineTo(7.5, 13.5)
                        ctx.lineTo(4.2, 10.5)
                        ctx.closePath()
                        ctx.fill()

                        if (isMuted) {
                            ctx.globalCompositeOperation = "destination-out"
                            ctx.lineWidth = 2.6
                            ctx.beginPath()
                            ctx.moveTo(0.8, 2.0)
                            ctx.lineTo(8.8, 14.0)
                            ctx.stroke()

                            ctx.globalCompositeOperation = "source-over"
                            ctx.lineWidth = 1.5
                            ctx.strokeStyle = fg
                            ctx.beginPath()
                            ctx.moveTo(0.8, 2.0)
                            ctx.lineTo(8.8, 14.0)
                            ctx.stroke()
                        } else {
                            const arcs = volumeLevel > 66 ? 3 : (volumeLevel > 33 ? 2 : (volumeLevel > 0 ? 1 : 0))
                            const cx = 6.0, cy = 8.0
                            if (arcs >= 1) {
                                ctx.beginPath()
                                ctx.arc(cx, cy, 4.2, -0.65, 0.65)
                                ctx.stroke()
                            }
                            if (arcs >= 2) {
                                ctx.beginPath()
                                ctx.arc(cx, cy, 7.0, -0.70, 0.70)
                                ctx.stroke()
                            }
                            if (arcs >= 3) {
                                ctx.beginPath()
                                ctx.arc(cx, cy, 9.8, -0.72, 0.72)
                                ctx.stroke()
                            }
                        }
                    }

                    Connections {
                        target: ControlCenterService
                        function onAudioMutedChanged() { submenuVolumeGlyph.requestPaint() }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ControlCenterService.setMuted(!ControlCenterService.audioMuted)
                    }
                }

                ControlCenterSlider {
                    id: submenuVolumeSlider
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 26; rightMargin: 2; bottomMargin: 4 }
                    height: 28
                    value: panel.volumePreview / 100
                    onPreviewChanged: function(v) {
                        panel.draggingVolume = true
                        panel.volumePreview = Math.round(v * 100)
                    }
                    onCommitRequested: function(v) {
                        panel.draggingVolume = false
                        if (ControlCenterService.audioMuted)
                            ControlCenterService.setMuted(false)
                        ControlCenterService.setVolume(Math.round(v * 100))
                    }
                }
            }

            Item {
                id: soundOutputSection
                anchors {
                    top: soundVolumeSection.bottom
                    topMargin: 8
                    left: parent.left
                    right: parent.right
                    leftMargin: 14
                    rightMargin: 14
                }
                height: 52

                GlassText {
                    anchors { left: parent.left; top: parent.top }
                    text: "输出设备"
                    color: ThemeService.foregroundColor
                    opacity: 0.60
                    font { pixelSize: 10; weight: Font.DemiBold; family: "Noto Sans CJK SC" }
                }

                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        topMargin: 18
                        bottom: parent.bottom
                    }
                    radius: 10
                    color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.05))
                    border.width: 1
                    border.color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.08))

                    Row {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 8

                        GlassText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "✓"
                            color: "#0a84ff"
                            font { pixelSize: 12; weight: Font.Bold }
                        }

                        GlassText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "🔊"
                            font.pixelSize: 12
                        }

                        GlassText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "默认音频输出设备"
                            color: ThemeService.foregroundColor
                            font { pixelSize: 11; weight: Font.DemiBold; family: "Noto Sans CJK SC" }
                        }
                    }
                }
            }

            Item {
                id: soundApplicationsSection
                anchors {
                    top: soundOutputSection.bottom
                    topMargin: 10
                    left: parent.left
                    right: parent.right
                    bottom: soundFooter.top
                    leftMargin: 14
                    rightMargin: 14
                    bottomMargin: 4
                }

                GlassText {
                    id: soundApplicationsTitle
                    anchors { left: parent.left; top: parent.top }
                    text: "应用音量"
                    color: ThemeService.foregroundColor
                    opacity: 0.60
                    font { pixelSize: 10; weight: Font.DemiBold; family: "Noto Sans CJK SC" }
                }

                GlassText {
                    visible: ControlCenterService.audioApplications.length === 0
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 8
                    text: ControlCenterService.audioApplicationsRefreshInProgress ? "正在读取…" : "没有活动的音频应用"
                    color: ThemeService.foregroundColor
                    opacity: 0.45
                    font { pixelSize: 10; family: "Noto Sans CJK SC" }
                }

                Column {
                    anchors {
                        top: soundApplicationsTitle.bottom
                        topMargin: 5
                        left: parent.left
                        right: parent.right
                    }
                    spacing: 3

                    Repeater {
                        model: ControlCenterService.audioApplications.slice(0, 3)

                        delegate: Item {
                            id: appVolumeRow
                            required property var modelData
                            width: parent.width
                            height: 58
                            property int volumePreview: Number(modelData.percent || 0)
                            property bool muted: !!modelData.muted

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: appVolumeHover.hovered
                                    ? (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.055)))
                                    : "transparent"
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }

                            Rectangle {
                                id: appMuteButton
                                anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                                width: 28
                                height: 28
                                radius: 8
                                color: appVolumeRow.muted
                                    ? Qt.rgba(1.0, 0.27, 0.23, ThemeService.isDark ? 0.30 : 0.18)
                                    : (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.07)))

                                GlassText {
                                    anchors.centerIn: parent
                                    text: appVolumeRow.muted ? "×" : "♪"
                                    color: appVolumeRow.muted ? "#ff453a" : ThemeService.foregroundColor
                                    font { pixelSize: appVolumeRow.muted ? 15 : 13; weight: Font.Bold }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        appVolumeRow.muted = !appVolumeRow.muted
                                        ControlCenterService.setApplicationMuted(appVolumeRow.modelData.id,
                                            appVolumeRow.muted)
                                    }
                                }
                            }

                            GlassText {
                                id: appVolumeName
                                anchors {
                                    left: appMuteButton.right
                                    leftMargin: 8
                                    right: appVolumePercent.left
                                    rightMargin: 6
                                    top: parent.top
                                    topMargin: 5
                                }
                                text: appVolumeRow.modelData.name || "音频应用"
                                elide: Text.ElideRight
                                color: ThemeService.foregroundColor
                                font { pixelSize: 10; weight: Font.DemiBold; family: "Noto Sans CJK SC" }
                            }

                            GlassText {
                                id: appVolumePercent
                                anchors { right: parent.right; rightMargin: 5; verticalCenter: appVolumeName.verticalCenter }
                                text: Math.round(appVolumeRow.volumePreview) + "%"
                                color: ThemeService.foregroundColor
                                opacity: 0.55
                                font { pixelSize: 9; family: "Noto Sans CJK SC" }
                            }

                            ControlCenterSlider {
                                anchors {
                                    left: appMuteButton.right
                                    leftMargin: 8
                                    right: parent.right
                                    rightMargin: 4
                                    bottom: parent.bottom
                                    bottomMargin: 3
                                }
                                height: 27
                                value: Math.min(1, appVolumeRow.volumePreview / 150)
                                accentColor: AppearanceTokens.content.glassInk(
                                    appVolumeRow.muted ? 0.25 : 0.42)
                                onPreviewChanged: function(v) {
                                    appVolumeRow.volumePreview = Math.round(v * 150)
                                }
                                onCommitRequested: function(v) {
                                    if (appVolumeRow.muted) {
                                        appVolumeRow.muted = false
                                        ControlCenterService.setApplicationMuted(appVolumeRow.modelData.id, false)
                                    }
                                    ControlCenterService.setApplicationVolume(appVolumeRow.modelData.id,
                                        Math.round(v * 150))
                                }
                            }

                            HoverHandler { id: appVolumeHover }
                        }
                    }
                }
            }

            Item {
                id: soundFooter
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 38

                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 12; rightMargin: 12 }
                    height: 1
                    color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
                }

                GlassText {
                    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                    text: "声音设置…"
                    color: soundSettingsMouse.containsMouse ? "#0a84ff" : ThemeService.foregroundColor
                    font { pixelSize: 11; weight: Font.DemiBold; family: "Noto Sans CJK SC" }
                }

                GlassText {
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    text: "›"
                    color: ThemeService.foregroundColor
                    opacity: 0.45
                    font { pixelSize: 13; weight: Font.Bold }
                }

                MouseArea {
                    id: soundSettingsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.openSettingsModule("kcm_pulseaudio")
                }
            }
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
