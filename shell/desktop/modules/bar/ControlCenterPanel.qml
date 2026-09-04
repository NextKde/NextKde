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
Item {
    id: panel

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
    signal networkRequested()
    signal bluetoothRequested()

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

    // Compact counterpart to the Dock player's transport controls. It keeps
    // the same circular glass treatment but is sized for this small panel.
    // Uses the shared LiquidGlassButton for a pure-QML liquid glass effect.
    component MediaControlButton: LiquidControls.LiquidGlassButton {
        property bool controlEnabled: true
        enabled: controlEnabled
        iconColor: ThemeService.foregroundColor
        width: primary ? 40 : 32
        height: width
    }

    ControlCenterCoordinator {
        id: coordinator
        cardAnchor: positioningAnchor
        gridWidth: panel.controlCenterWidth
        cardOffsetX: !panel.dockHosted ? 0
            : panel.dockEdge === "left" ? -20
            : panel.dockEdge === "right" ? 20 : 0
        cardOffsetY: panel.dockHosted && panel.dockEdge === "bottom" ? 20 : 0
    }

    // Geometry oracle: it is anchored to the clicked control, which makes
    // Quickshell select the correct output and clamp the group on every Dock
    // edge. The visible cards use positioningAnchor as their common origin.
    PopupWindow {
        id: positioningPopup
        visible: panel.anchorItem !== null
        implicitWidth: panel.controlCenterWidth
        implicitHeight: panel.controlCenterHeight
        color: "transparent"
        grabFocus: false
        mask: Region { width: 0; height: 0 }

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
            margins.bottom: panel.dockHosted ? 0 : -8
            margins.left: 0
            margins.right: 0
        }

        Item {
            id: positioningAnchor
            anchors.fill: parent
        }
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
        if (panel.sessionModalVisible)
            coordinator.modalActive = true
        if (!panel.sessionModalVisible) {
            panel.pendingConfirmAction = ""
        }
    }

    function toggle(item) {
        anchorItem = item
        _triggerTransitionGuard()
        if (coordinator.open || panel.sessionModalVisible) {
            close()
        } else {
            panel.sessionModalVisible = false
            panel.pendingConfirmAction = ""
            ControlCenterService.refresh()
            coordinator.openAll()
        }
    }
    function close() {
        _triggerTransitionGuard()
        sessionModalVisible = false
        pendingConfirmAction = ""
        coordinator.closeAll()
    }

    // Fullscreen transparent click-catcher window mapped ONLY while the control center is open.
    // Clicking anywhere outside the control center cards instantly dismisses it.
    PanelWindow {
        id: dismissalBackdrop
        screen: panel.targetScreen
        visible: ScreenLifecycle.outputAvailable && panel.targetScreen !== null
            && (coordinator.open || panel.sessionModalVisible)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-controlcenter-backdrop"

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
            if (!panel._internalTransition && (coordinator.open || panel.sessionModalVisible)) {
                panel.close()
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: coordinator.open || panel.sessionModalVisible
        onActivated: {
            if (panel.sessionModalVisible) {
                panel.sessionModalVisible = false
            } else {
                panel.close()
            }
        }
    }

    // ── Card 1: Wi-Fi ────────────────────────────────────────────────
    // Opens the Wi-Fi picker. Power toggle lives inside that picker.
    ControlCenterCard {
        id: wifiCard
        coordinator: coordinator
        offsetTop: 20
        offsetRight: 179
        cardRadius: 29.5
        cardWidth: 137
        cardHeight: 59
        cardBorderColor: ThemeService.isDark ? Qt.rgba(0.74, 0.95, 1, 0.34) : Qt.rgba(0, 0, 0, 0.10)
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid

        Rectangle {
            width: 39; height: 39; radius: width / 2
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            color: NetworkService.wifiEnabled
                ? (ThemeService.isDark ? "#f7fbff" : Qt.rgba(0, 0, 0, 0.08))
                : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.05))
            Canvas {
                id: controlWifiGlyph
                anchors.centerIn: parent
                width: 20; height: 20
                property bool active: NetworkService.wifiEnabled
                property color glyphColor: active ? "#0a84ff" : (ThemeService.isDark ? "white" : "#000000")
                onActiveChanged: requestPaint()
                onGlyphColorChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.strokeStyle = glyphColor
                    ctx.fillStyle = glyphColor
                    ctx.lineWidth = 1.55
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    ctx.scale(1.08, 1.08)
                    ctx.translate(0, -1.8)
                    const rings = NetworkService.signalStrength < 25 ? 1
                        : (NetworkService.signalStrength < 50 ? 2 : 3)
                    for (let ring = 0; ring < rings; ring++) {
                        const radius = 3.1 + ring * 2.45
                        ctx.beginPath()
                        ctx.arc(8, 14.2, radius, Math.PI * 1.22, Math.PI * 1.78)
                        ctx.stroke()
                    }
                    ctx.beginPath()
                    ctx.arc(8, 13.8, 1.15, 0, Math.PI * 2)
                    ctx.fill()
                }
                Connections {
                    target: NetworkService
                    function onSignalStrengthChanged() { controlWifiGlyph.requestPaint() }
                }
            }
        }
        Column {
            anchors { left: parent.left; right: parent.right; leftMargin: 58; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 1
            Text {
                width: parent.width
                text: "Wi‑Fi"
                color: wifiCard.materialForegroundColor
                style: ThemeService.isDark ? Text.Outline : Text.Normal
                styleColor: Qt.rgba(0, 0, 0, 0.50)
                font { pixelSize: 12; weight: Font.Bold; family: "Noto Sans CJK SC" }
            }
            Text {
                width: parent.width
                text: NetworkService.wifiEnabled ? (NetworkService.ssid || "未连接") : "已关闭"
                elide: Text.ElideRight
                color: wifiCard.materialSecondaryForegroundColor
                style: ThemeService.isDark ? Text.Outline : Text.Normal
                styleColor: Qt.rgba(0, 0, 0, 0.50)
                opacity: 0.72
                font { pixelSize: 10; family: "Noto Sans CJK SC" }
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: panel.networkRequested() }
    }

    // ── Card 2: Bluetooth ────────────────────────────────────────────
    // Disc toggles power; tapping the pill opens the device list.
    ControlCenterCard {
        id: bluetoothCard
        coordinator: coordinator
        offsetTop: 87
        offsetRight: 179
        cardRadius: 29.5
        cardWidth: 137
        cardHeight: 59
        cardBorderColor: ThemeService.isDark ? Qt.rgba(0.74, 0.95, 1, 0.34) : Qt.rgba(0, 0, 0, 0.10)
        cardOpacity: ControlCenterService.bluetoothAvailable ? 1 : 0.48
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid

        Rectangle {
            width: 39; height: 39; radius: width / 2
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            color: ControlCenterService.bluetoothPowered
                ? (ThemeService.isDark ? "#f7fbff" : Qt.rgba(0, 0, 0, 0.08))
                : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.05))
            Canvas {
                id: controlBtGlyph
                anchors.centerIn: parent
                width: 21; height: 21
                property bool active: ControlCenterService.bluetoothPowered
                property color glyphColor: active ? "#0a84ff" : (ThemeService.isDark ? "white" : "#000000")
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
            MouseArea {
                anchors.fill: parent
                enabled: ControlCenterService.bluetoothAvailable && !ControlCenterService.bluetoothChangeInProgress
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: ControlCenterService.setBluetoothEnabled(!ControlCenterService.bluetoothPowered)
            }
        }
        Column {
            anchors { left: parent.left; right: parent.right; leftMargin: 58; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 1
            Text {
                width: parent.width
                text: "Bluetooth"
                color: bluetoothCard.materialForegroundColor
                style: ThemeService.isDark ? Text.Outline : Text.Normal
                styleColor: Qt.rgba(0, 0, 0, 0.50)
                font { pixelSize: 12; weight: Font.Bold; family: "Noto Sans CJK SC" }
            }
            Text {
                width: parent.width
                text: ControlCenterService.bluetoothPowered ? "已开启" : "已关闭"
                color: bluetoothCard.materialSecondaryForegroundColor
                style: ThemeService.isDark ? Text.Outline : Text.Normal
                styleColor: Qt.rgba(0, 0, 0, 0.50)
                opacity: 0.72
                font { pixelSize: 10; family: "Noto Sans CJK SC" }
            }
        }
        MouseArea {
            anchors.fill: parent
            enabled: ControlCenterService.bluetoothAvailable && !ControlCenterService.bluetoothChangeInProgress
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: panel.bluetoothRequested()
        }
    }

    // ── Card 3: Media player ─────────────────────────────────────────
    ControlCenterCard {
        id: mediaCard
        coordinator: coordinator
        offsetTop: 20
        offsetRight: 20
        cardRadius: 25
        cardWidth: 151
        cardHeight: 127
        cardBorderColor: ThemeService.isDark ? Qt.rgba(0.72, 0.95, 1, 0.32) : Qt.rgba(0, 0, 0, 0.10)
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid

        // A faint wallpaper-tone layer is both the card's quiet liquid base
        // and the blur source for the transport buttons. Blurring it makes
        // each button a frosted lens that absorbs the ambient wallpaper tint
        // (iOS-style), instead of a swatch of the album artwork.
        Rectangle {
            id: mediaBackdrop
            anchors.fill: parent
            // `parent` here is the card's contentHost (a plain Item), which
            // has no cardRadius; read the card's blurRadius instead so the
            // backdrop corners follow the card's SDF-rounded shape.
            radius: mediaCard.blurRadius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(WallpaperPaletteService.primary.r, WallpaperPaletteService.primary.g, WallpaperPaletteService.primary.b, 0.16) }
                GradientStop { position: 1.0; color: Qt.rgba(WallpaperPaletteService.secondary.r, WallpaperPaletteService.secondary.g, WallpaperPaletteService.secondary.b, 0.07) }
            }
        }

        Rectangle {
            id: artwork
            width: 43; height: 43; radius: 13
            anchors { left: parent.left; top: parent.top; leftMargin: 13; topMargin: 13 }
            color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.08)
            Text {
                anchors.centerIn: parent
                text: "♫"
                color: ThemeService.foregroundColor
                style: ThemeService.isDark ? Text.Outline : Text.Normal
                styleColor: Qt.rgba(0, 0, 0, 0.50)
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
            Text {
                width: parent.width
                text: panel.player?.trackTitle || "未在播放"
                elide: Text.ElideRight
                color: ThemeService.foregroundColor
                style: ThemeService.isDark ? Text.Outline : Text.Normal
                styleColor: Qt.rgba(0, 0, 0, 0.50)
                font { pixelSize: 12; weight: Font.Bold; family: "Noto Sans CJK SC" }
            }
            Text {
                width: parent.width
                text: panel.player?.trackArtist || "媒体控制"
                elide: Text.ElideRight
                color: ThemeService.foregroundColor
                style: ThemeService.isDark ? Text.Outline : Text.Normal
                styleColor: Qt.rgba(0, 0, 0, 0.50)
                opacity: 0.70
                font { pixelSize: 10; family: "Noto Sans CJK SC" }
            }
        }
        Row {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 15 }
            height: 40
            spacing: 12
            
            MediaControlButton {
                anchors.verticalCenter: parent.verticalCenter
                symbol: "⏮"
                controlEnabled: panel.player?.canGoPrevious ?? false
                onTriggered: DockMprisService.previous()
            }
            MediaControlButton {
                anchors.verticalCenter: parent.verticalCenter
                primary: true
                symbol: panel.player?.isPlaying ? "⏸" : "▶"
                controlEnabled: panel.player !== null
                onTriggered: DockMprisService.togglePlayPause()
            }
            MediaControlButton {
                anchors.verticalCenter: parent.verticalCenter
                symbol: "⏭"
                controlEnabled: panel.player?.canGoNext ?? false
                onTriggered: DockMprisService.next()
            }
        }
    }

    // ── Card 4: Screenshot ───────────────────────────────────────────
    ControlCenterCard {
        coordinator: coordinator
        offsetTop: 155
        offsetRight: 262
        cardRadius: 27
        cardWidth: 54
        cardHeight: 54
        cardBorderColor: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(0, 0, 0, 0.10)
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid

        cardScale: screenshotPointer.pressed ? 0.91 : (screenshotPointer.containsMouse ? 1.06 : 1.0)
        Behavior on cardScale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Image {
            anchors.centerIn: parent
            width: 25
            height: 25
            source: "../../assets/screenshot.svg"
            sourceSize.width: 46
            sourceSize.height: 46
            fillMode: Image.PreserveAspectFit
            smooth: true
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: ThemeService.isDark ? ThemeService.foregroundColor : "#000000"
            }
        }
        MouseArea { id: screenshotPointer; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ControlCenterService.captureInteractiveScreenshot() }
    }

    // ── Card 5: Dark Mode / Theme Toggle ─────────────────────────────
    ControlCenterCard {
        coordinator: coordinator
        offsetTop: 155
        offsetRight: 198
        cardRadius: 27
        cardWidth: 54
        cardHeight: 54
        cardBorderColor: ThemeService.isDark ? "#0a84ff" : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(0, 0, 0, 0.10))
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid

        cardScale: themePointer.pressed ? 0.91 : (themePointer.containsMouse ? 1.06 : 1.0)
        Behavior on cardScale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Text {
            anchors.centerIn: parent
            text: ThemeService.isDark ? "☾" : "☼"
            color: ThemeService.isDark ? "#0a84ff" : ThemeService.foregroundColor
            style: ThemeService.isDark ? Text.Outline : Text.Normal
            styleColor: Qt.rgba(0, 0, 0, 0.50)
            font.pixelSize: 22
            font.weight: Font.Bold
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
        coordinator: coordinator
        offsetTop: 155
        offsetRight: 134
        cardRadius: 27
        cardWidth: 54
        cardHeight: 54
        cardBorderColor: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(0, 0, 0, 0.10)
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid

        cardScale: powerPointer.pressed ? 0.91 : (powerPointer.containsMouse ? 1.06 : 1.0)
        Behavior on cardScale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Image {
            anchors.centerIn: parent
            width: 24
            height: 24
            source: "../../assets/logout.svg"
            sourceSize.width: 48
            sourceSize.height: 48
            fillMode: Image.PreserveAspectFit
            smooth: true
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: ThemeService.isDark ? ThemeService.foregroundColor : "#000000"
            }
        }
        MouseArea {
            id: powerPointer
            anchors.fill: parent
            hoverEnabled: true
            enabled: !ControlCenterService.sessionActionInProgress
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                panel.pendingConfirmAction = ""
                panel.sessionModalVisible = true
            }
        }
    }

    // ── Card 7: Do Not Disturb ───────────────────────────────────────
    ControlCenterCard {
        coordinator: coordinator
        offsetTop: 155
        offsetRight: 20
        cardRadius: 27
        cardWidth: 104
        cardHeight: 54
        cardBorderColor: ControlCenterService.doNotDisturbEnabled
            ? "#0a84ff" : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(0, 0, 0, 0.10))
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid

        cardScale: dndPointer.pressed ? 0.97 : (dndPointer.containsMouse ? 1.025 : 1.0)
        Behavior on cardScale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Image {
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            width: 21
            height: 21
            source: "../../assets/do-not-disturb.svg"
            sourceSize.width: 46
            sourceSize.height: 46
            fillMode: Image.PreserveAspectFit
            smooth: true
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: ControlCenterService.doNotDisturbEnabled
                    ? "#0a84ff" : (ThemeService.isDark ? ThemeService.foregroundColor : "#000000")
            }
        }
        Text {
            anchors { left: parent.left; leftMargin: 42; verticalCenter: parent.verticalCenter }
            text: "勿扰"
            color: ThemeService.foregroundColor
            style: ThemeService.isDark ? Text.Outline : Text.Normal
            styleColor: Qt.rgba(0, 0, 0, 0.50)
            font { pixelSize: 12; weight: Font.Bold; family: "Noto Sans CJK SC" }
        }
        MouseArea { id: dndPointer; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ControlCenterService.toggleDoNotDisturb() }
    }

    // ── Card 7: Display brightness ───────────────────────────────────
    ControlCenterCard {
        coordinator: coordinator
        offsetTop: 217
        offsetRight: 20
        cardRadius: 19
        cardWidth: 296
        cardHeight: 57
        cardBorderColor: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10)
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid

        Text {
            anchors { left: parent.left; top: parent.top; leftMargin: 14; topMargin: 8 }
            text: "显示亮度"
            color: ThemeService.foregroundColor
            style: ThemeService.isDark ? Text.Outline : Text.Normal
            styleColor: Qt.rgba(0, 0, 0, 0.50)
            opacity: 0.70
            font { pixelSize: 11; weight: Font.DemiBold; family: "Noto Sans CJK SC" }
        }
        Text {
            anchors { right: parent.right; top: parent.top; rightMargin: 14; topMargin: 8 }
            text: ControlCenterService.brightnessAvailable ? Math.round(panel.brightnessPreview) + "%" : "无亮度设备"
            color: ThemeService.foregroundColor
            style: ThemeService.isDark ? Text.Outline : Text.Normal
            styleColor: Qt.rgba(0, 0, 0, 0.50)
            opacity: 0.50
            font { pixelSize: 9; family: "Noto Sans CJK SC" }
        }
        LiquidControls.LiquidSlider {
            id: brightnessSlider
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 31; rightMargin: 31; bottomMargin: 8 }
            height: 30
            value: panel.brightnessPreview / 100
            enabled: ControlCenterService.brightnessAvailable
            trackHeight: 4
            trackColor: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.17) : Qt.rgba(0, 0, 0, 0.12)
            accentColor: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.42) : Qt.rgba(0, 0, 0, 0.35)
            thumbColor: ThemeService.isDark ? "#ffffff" : "#e7f1ff"
            onPreviewChanged: function(v) {
                panel.draggingBrightness = true
                panel.brightnessPreview = Math.round(v * 100)
            }
            onCommitRequested: function(v) {
                panel.draggingBrightness = false
                ControlCenterService.setBrightness(Math.round(v * 100))
            }
        }
        Text {
            anchors { left: parent.left; leftMargin: 12; bottom: parent.bottom; bottomMargin: 12 }
            text: "☀"
            color: ThemeService.foregroundColor
            style: ThemeService.isDark ? Text.Outline : Text.Normal
            styleColor: Qt.rgba(0, 0, 0, 0.50)
            opacity: 0.65
            font.pixelSize: 13
        }
    }

    // ── Card 8: Sound / volume ───────────────────────────────────────
    ControlCenterCard {
        coordinator: coordinator
        offsetTop: 282
        offsetRight: 20
        cardRadius: 19
        cardWidth: 296
        cardHeight: 57
        cardBorderColor: ThemeService.isDark ? Qt.rgba(0.72, 0.93, 1, 0.27) : Qt.rgba(0, 0, 0, 0.10)
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid

        Text {
            anchors { left: parent.left; top: parent.top; leftMargin: 14; topMargin: 8 }
            text: "声音"
            color: ThemeService.foregroundColor
            style: ThemeService.isDark ? Text.Outline : Text.Normal
            styleColor: Qt.rgba(0, 0, 0, 0.50)
            font { pixelSize: 11; weight: Font.DemiBold; family: "Noto Sans CJK SC" }
        }
        Text {
            anchors { right: parent.right; top: parent.top; rightMargin: 14; topMargin: 8 }
            text: Math.round(panel.volumePreview) + "%"
            color: ThemeService.foregroundColor
            style: ThemeService.isDark ? Text.Outline : Text.Normal
            styleColor: Qt.rgba(0, 0, 0, 0.50)
            opacity: 0.72
            font { pixelSize: 10; family: "Noto Sans CJK SC" }
        }
        Canvas {
            id: volumeGlyph
            anchors { left: parent.left; leftMargin: 12; bottom: parent.bottom; bottomMargin: 12 }
            width: 15
            height: 15
            property color glyphColor: ThemeService.isDark ? "white" : "#000000"
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
        LiquidControls.LiquidSlider {
            id: volumeSlider
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 34; rightMargin: 17; bottomMargin: 8 }
            height: 30
            value: panel.volumePreview / 100
            trackHeight: 5
            trackColor: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.17) : Qt.rgba(0, 0, 0, 0.15)
            accentColor: ThemeService.isDark ? "#ffffff" : Qt.rgba(0, 0, 0, 0.40)
            thumbColor: ThemeService.isDark ? "#ffffff" : "#e7f1ff"
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
        coordinator: coordinator
        offsetTop: 347
        offsetRight: 20
        cardRadius: 19
        cardWidth: 296
        cardHeight: 230
        cardBorderColor: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10)
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid

        Item {
            anchors { fill: parent; margins: 10 }

            Text {
                id: historyTitle
                text: "通知历史"
                color: ThemeService.foregroundColor
                font { pixelSize: 12; weight: Font.Bold; family: "Noto Sans CJK SC" }
                anchors { left: parent.left; top: parent.top }
            }
            Text {
                text: "清空"
                color: clearMouse.containsMouse ? "#0a84ff" : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.50) : Qt.rgba(0, 0, 0, 0.45))
                font { pixelSize: 11; family: "Noto Sans CJK SC" }
                anchors { right: parent.right; top: parent.top }
                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ControlCenterService.notificationHistory.clear()
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
                            asynchronous: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: modelData.appName
                            color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.62) : Qt.rgba(0, 0, 0, 0.62)
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

                                Text {
                                    id: rowSummary
                                    width: parent.width - removeButton.width - 6
                                    text: modelData.summary.length > 0 ? modelData.summary : "通知"
                                    color: ThemeService.foregroundColor
                                    font { pixelSize: 11; weight: Font.Bold; family: "Noto Sans CJK SC" }
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                                Text {
                                    id: rowBody
                                    anchors.top: rowSummary.bottom
                                    anchors.topMargin: 1
                                    width: parent.width - removeButton.width - 6
                                    visible: text.length > 0
                                    text: modelData.body
                                    color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.50) : Qt.rgba(0, 0, 0, 0.50)
                                    font { pixelSize: 10; family: "Noto Sans CJK SC" }
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                                Text {
                                    id: removeButton
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "×"
                                    color: removeMouse.containsMouse ? "#ff453a" : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.42) : Qt.rgba(0, 0, 0, 0.35))
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
                Text {
                    anchors.centerIn: parent
                    visible: historyList.count === 0
                    text: "暂无历史通知"
                    color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(0, 0, 0, 0.35)
                    font { pixelSize: 11; family: "Noto Sans CJK SC" }
                }
            }
        }
    }

    // ── Card 10 (Sub-panel): Power & Session Management ──────────────
    // Overlays the 9 dimmed, non-interactive main cards with a dedicated power
    // & session sheet covering Lock, Suspend, Switch User, Logout, Reboot and
    // Power Off.
    ControlCenterCard {
        id: sessionCard
        coordinator: coordinator
        managedByCoordinator: false
        offsetTop: 20
        offsetRight: 20
        cardRadius: 22
        cardWidth: 296
        cardHeight: panel.pendingConfirmAction === "" ? 278 : 180
        cardBorderColor: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.10)
        cardShown: panel.sessionModalVisible
        blurStrength: panel.effectiveBlur
        liquidStrength: panel.effectiveLiquid
        onMotionClosed: {
            if (!panel.sessionModalVisible)
                coordinator.modalActive = false
        }

        // ── VIEW 1: 6-action Grid ──
        Item {
            anchors.fill: parent
            visible: panel.pendingConfirmAction === ""

            // Header
            Item {
                id: sessionHeader
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    topMargin: 12
                    leftMargin: 14
                    rightMargin: 14
                }
                height: 32

                Row {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 8

                    Rectangle {
                        width: 28
                        height: 28
                        radius: 14
                        color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.06)
                        border.width: 1
                        border.color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0, 0, 0, 0.10)
                        SystemIcon {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            role: "switchUser"
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        Text {
                            text: ControlCenterService.currentUserName
                            color: ThemeService.foregroundColor
                            style: ThemeService.isDark ? Text.Outline : Text.Normal
                            styleColor: Qt.rgba(0, 0, 0, 0.50)
                            font { pixelSize: 12; weight: Font.Bold; family: "Noto Sans CJK SC" }
                        }
                        Text {
                            text: "电源与会话管理"
                            color: ThemeService.foregroundColor
                            opacity: 0.60
                            style: ThemeService.isDark ? Text.Outline : Text.Normal
                            styleColor: Qt.rgba(0, 0, 0, 0.40)
                            font { pixelSize: 9; family: "Noto Sans CJK SC" }
                        }
                    }
                }

                // Close Button "×"
                Rectangle {
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    width: 24
                    height: 24
                    radius: 12
                    color: closeMouse.containsMouse
                        ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0, 0, 0, 0.12))
                        : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06))
                    border.width: 1
                    border.color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.08)

                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: ThemeService.foregroundColor
                        font { pixelSize: 15; weight: Font.Bold }
                    }
                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.sessionModalVisible = false
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
                color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
            }

            // 2-column Grid of Action Buttons
            Grid {
                id: actionsGrid
                anchors {
                    top: sessionDivider.bottom
                    topMargin: 10
                    horizontalCenter: parent.horizontalCenter
                }
                columns: 2
                spacing: 8

                // 1. 锁屏 (Lock Screen)
                Rectangle {
                    width: 132; height: 56; radius: 14
                    color: lockArea.containsMouse
                        ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.08))
                        : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.04))
                    border.width: 1
                    border.color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.08)

                    Row {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        SystemIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20
                            role: "lock"
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text { text: "锁屏"; color: ThemeService.foregroundColor; font { pixelSize: 12; weight: Font.Bold; family: "Noto Sans CJK SC" } }
                            Text { text: "锁定屏幕"; color: ThemeService.foregroundColor; opacity: 0.55; font { pixelSize: 9; family: "Noto Sans CJK SC" } }
                        }
                    }
                    MouseArea {
                        id: lockArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            panel.sessionModalVisible = false
                            panel.close()
                            ControlCenterService.lockSession()
                        }
                    }
                }

                // 2. 睡眠 (Sleep / Suspend)
                Rectangle {
                    width: 132; height: 56; radius: 14
                    color: sleepArea.containsMouse
                        ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.08))
                        : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.04))
                    border.width: 1
                    border.color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.08)

                    Row {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        SystemIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20
                            role: "suspend"
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text { text: "睡眠"; color: ThemeService.foregroundColor; font { pixelSize: 12; weight: Font.Bold; family: "Noto Sans CJK SC" } }
                            Text { text: "挂起系统"; color: ThemeService.foregroundColor; opacity: 0.55; font { pixelSize: 9; family: "Noto Sans CJK SC" } }
                        }
                    }
                    MouseArea {
                        id: sleepArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            panel.sessionModalVisible = false
                            panel.close()
                            ControlCenterService.suspendSystem()
                        }
                    }
                }

                // 3. 切换用户 (Switch User)
                Rectangle {
                    width: 132; height: 56; radius: 14
                    color: switchUserArea.containsMouse
                        ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.08))
                        : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.04))
                    border.width: 1
                    border.color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.08)

                    Row {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        SystemIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20
                            role: "switchUser"
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text { text: "切换用户"; color: ThemeService.foregroundColor; font { pixelSize: 12; weight: Font.Bold; family: "Noto Sans CJK SC" } }
                            Text { text: "保留会话"; color: ThemeService.foregroundColor; opacity: 0.55; font { pixelSize: 9; family: "Noto Sans CJK SC" } }
                        }
                    }
                    MouseArea {
                        id: switchUserArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            panel.sessionModalVisible = false
                            panel.close()
                            ControlCenterService.switchUser()
                        }
                    }
                }

                // 4. 注销 (Log Out)
                Rectangle {
                    width: 132; height: 56; radius: 14
                    color: logoutArea.containsMouse
                        ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.08))
                        : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.04))
                    border.width: 1
                    border.color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.08)

                    Row {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        SystemIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20
                            role: "logout"
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text { text: "注销"; color: ThemeService.foregroundColor; font { pixelSize: 12; weight: Font.Bold; family: "Noto Sans CJK SC" } }
                            Text { text: "结束当前会话"; color: ThemeService.foregroundColor; opacity: 0.55; font { pixelSize: 9; family: "Noto Sans CJK SC" } }
                        }
                    }
                    MouseArea {
                        id: logoutArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: panel.pendingConfirmAction = "logout"
                    }
                }

                // 5. 重启 (Restart)
                Rectangle {
                    width: 132; height: 56; radius: 14
                    color: rebootArea.containsMouse
                        ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.08))
                        : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.04))
                    border.width: 1
                    border.color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.08)

                    Row {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        SystemIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20
                            role: "reboot"
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text { text: "重启"; color: ThemeService.foregroundColor; font { pixelSize: 12; weight: Font.Bold; family: "Noto Sans CJK SC" } }
                            Text { text: "重新启动电脑"; color: ThemeService.foregroundColor; opacity: 0.55; font { pixelSize: 9; family: "Noto Sans CJK SC" } }
                        }
                    }
                    MouseArea {
                        id: rebootArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: panel.pendingConfirmAction = "reboot"
                    }
                }

                // 6. 关机 (Power Off)
                Rectangle {
                    width: 132; height: 56; radius: 14
                    color: powerOffArea.containsMouse
                        ? Qt.rgba(255, 69, 58, 0.22)
                        : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.04))
                    border.width: 1
                    border.color: powerOffArea.containsMouse
                        ? Qt.rgba(255, 69, 58, 0.50)
                        : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.08))

                    Row {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        SystemIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20
                            role: "powerOff"
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text { text: "关机"; color: ThemeService.foregroundColor; font { pixelSize: 12; weight: Font.Bold; family: "Noto Sans CJK SC" } }
                            Text { text: "关闭电脑电源"; color: ThemeService.foregroundColor; opacity: 0.55; font { pixelSize: 9; family: "Noto Sans CJK SC" } }
                        }
                    }
                    MouseArea {
                        id: powerOffArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: panel.pendingConfirmAction = "poweroff"
                    }
                }
            }

            // Error / Status bar
            Text {
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

        // ── VIEW 2: Confirmation Dialog ──
        Item {
            anchors.fill: parent
            visible: panel.pendingConfirmAction !== ""

            SystemIcon {
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 16 }
                width: 28
                height: 28
                role: panel.pendingConfirmAction === "poweroff" ? "powerOff"
                    : (panel.pendingConfirmAction === "reboot" ? "reboot" : "logout")
            }

            Text {
                anchors { top: parent.top; topMargin: 50; horizontalCenter: parent.horizontalCenter }
                text: panel.pendingConfirmAction === "poweroff" ? "确定要关机吗？"
                    : (panel.pendingConfirmAction === "reboot" ? "确定要重启吗？" : "确定要注销吗？")
                color: ThemeService.foregroundColor
                style: ThemeService.isDark ? Text.Outline : Text.Normal
                styleColor: Qt.rgba(0, 0, 0, 0.50)
                font { pixelSize: 14; weight: Font.Bold; family: "Noto Sans CJK SC" }
            }

            Text {
                anchors { top: parent.top; topMargin: 72; horizontalCenter: parent.horizontalCenter }
                text: "未保存的工作可能会丢失"
                color: ThemeService.foregroundColor
                opacity: 0.66
                style: ThemeService.isDark ? Text.Outline : Text.Normal
                styleColor: Qt.rgba(0, 0, 0, 0.50)
                font { pixelSize: 10; family: "Noto Sans CJK SC" }
            }

            Row {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
                spacing: 12

                Rectangle {
                    width: 100
                    height: 34
                    radius: 17
                    color: cancelConfirmMouse.containsMouse
                        ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.10))
                        : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.05))
                    border.width: 1
                    border.color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(0, 0, 0, 0.10)
                    Text {
                        anchors.centerIn: parent
                        text: "取消"
                        color: ThemeService.foregroundColor
                        font { pixelSize: 12; weight: Font.DemiBold; family: "Noto Sans CJK SC" }
                    }
                    MouseArea {
                        id: cancelConfirmMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.pendingConfirmAction = ""
                    }
                }

                Rectangle {
                    width: 100
                    height: 34
                    radius: 17
                    color: executeConfirmMouse.containsMouse ? Qt.rgba(255, 69, 58, 0.35) : Qt.rgba(255, 69, 58, 0.20)
                    border.width: 1
                    border.color: "#ff453a"
                    Text {
                        anchors.centerIn: parent
                        text: panel.pendingConfirmAction === "poweroff" ? "关机"
                            : (panel.pendingConfirmAction === "reboot" ? "重启" : "注销")
                        color: ThemeService.foregroundColor
                        font { pixelSize: 12; weight: Font.Bold; family: "Noto Sans CJK SC" }
                    }
                    MouseArea {
                        id: executeConfirmMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const action = panel.pendingConfirmAction
                            panel.pendingConfirmAction = ""
                            panel.sessionModalVisible = false
                            panel.close()
                            if (action === "poweroff") {
                                ControlCenterService.powerOffSystem()
                            } else if (action === "reboot") {
                                ControlCenterService.rebootSystem()
                            } else if (action === "logout") {
                                ControlCenterService.logoutCurrentSession()
                            }
                        }
                    }
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
