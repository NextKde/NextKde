import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.platform
import "../../../Kos/Ui"

// Network card shared by the future top control centre. Wi-Fi selection and
// credential UI are implemented here first; the actual NetworkManager write
// operation is intentionally deferred until this interaction is validated.
PopupWindow {
    id: panel

    property Item anchorItem: null
    property bool dockHosted: false
    property string dockEdge: "bottom"
    property var selectedNetwork: null
    property string requestedUsername: ""
    property string requestedPassword: ""
    property string requestedAnonymousIdentity: ""
    // These labels are presentation-safe; NetworkService maps them to the
    // exact NetworkManager EAP/inner-auth setting pair it supports.
    property string selectedEnterpriseEap: "peap"
    property bool showAnonymousIdentity: false
    // A saved normal Wi-Fi profile is distinct from an empty password. Keep
    // that distinction visible so users know reconnect will use a secret
    // stored by NetworkManager instead of assuming it was forgotten.
    property bool useSavedCredentials: false
    property bool confirmForgetNetwork: false
    property string dialogError: ""
    // Keep the popup geometry stable while a join sheet opens. The sheet is
    // intentionally narrower than the 310px Wi-Fi list, so it reads as a
    // nested action instead of making the top-bar panel suddenly expand.
    implicitWidth: 310
    implicitHeight: 365
    color: "transparent"
    // A password field lives in this separate Wayland popup surface. It must
    // explicitly own keyboard focus; otherwise the Bar's prior focus target
    // can keep receiving text even after the modal appears.
    grabFocus: true
    anchor {
        item: panel.anchorItem
        edges: !panel.dockHosted ? Edges.Bottom
            : panel.dockEdge === "left" ? Edges.Right
            : panel.dockEdge === "right" ? Edges.Left : Edges.Top
        gravity: !panel.dockHosted ? Edges.Bottom
            : panel.dockEdge === "left" ? Edges.Right
            : panel.dockEdge === "right" ? Edges.Left : Edges.Top
        margins.top: panel.dockHosted
            && panel.dockEdge === "bottom" ? -8 : 0
        margins.bottom: panel.dockHosted ? 0 : -8
        margins.left: panel.dockHosted
            && panel.dockEdge === "right" ? -8 : 0
        margins.right: panel.dockHosted
            && panel.dockEdge === "left" ? -8 : 0
    }

    // Real liquid glass: a compositor blur region on the panel surface, so
    // windows behind the Wi-Fi list are visible through the glass (QML-only
    // surfaces cannot sample the compositor buffer). The panel owns that region
    // together with its radius and exponent (kos-surface-shape-v1), so the
    // region decides which background pixels are captured and the effect draws
    // the exact outline from the shape — no separate hand-written region.
    readonly property int blurRadius: Math.max(1, Math.min(19, Math.floor(310 / 2)))
    BackgroundEffect.blurRegion: (panel.visible
        && (AppearanceConfigService.effectiveBarBlur > 0.005
            || AppearanceConfigService.effectiveBarLiquid > 0.005))
        ? panelSurface.blurRegion : null

    function toggle(item) {
        anchorItem = item
        if (visible) {
            close()
        } else {
            open(item)
        }
    }

    function open(item) {
        anchorItem = item
        visible = true
        // Refresh first so wifiDeviceName is populated before the scan runs;
        // without it the scan request carries no ifname on a cold open.
        NetworkService.refresh()
        NetworkService.refreshWifiNetworks()
    }

    // The network list can contain a focused credentials sheet. Clear that
    // transient state whenever another top-bar panel takes its place.
    function close() {
        closeNetworkDialog()
        visible = false
    }

    Connections {
        target: ScreenLifecycle
        function onOutputAvailableChanged() {
            if (!ScreenLifecycle.outputAvailable)
                panel.close()
        }
    }

    function openWirelessSettings() {
        close()
        // KDE's NetworkManager KCM remains the full settings surface for
        // profiles, proxies and VPNs; the platform service owns launching it.
        PlatformClient.request("settings.open", { module: "kcm_networkmanagement" },
            function(response) {
                if (!response?.ok)
                    console.warn("[Network] settings unavailable: "
                        + (response?.error?.message || "platform unavailable"))
            })
    }

    function showNetworkDialog(network) {
        selectedNetwork = network
        requestedUsername = ""
        requestedPassword = ""
        requestedAnonymousIdentity = ""
        selectedEnterpriseEap = "peap"
        showAnonymousIdentity = false
        useSavedCredentials = Boolean(network.savedProfileUuid && !network.enterprise)
        confirmForgetNetwork = false
        dialogError = ""
        // TextInput keeps its own editable `text` property. Clearing only the
        // state above would leave the prior secret painted in this reusable
        // dialog when the user selects a different access point.
        usernameInput.clear()
        passwordInput.clear()
        anonymousIdentityInput.clear()
        networkDialogOverlay.open()
        passwordFocusTimer.restart()
    }

    function activeSavedWifi() {
        const networks = NetworkService.nearbyWifi
        for (let i = 0; i < networks.length; i++) {
            if (networks[i].active && networks[i].savedProfileUuid)
                return networks[i]
        }
        return null
    }

    function showForgetActiveWifi() {
        const network = activeSavedWifi()
        if (!network)
            return
        showNetworkDialog(network)
        // The current-connection button is already an intentional action;
        // enter the in-card confirmation state immediately, but never delete
        // until the user presses its explicit second “确认” action.
        confirmForgetNetwork = true
    }

    function closeNetworkDialog() {
        networkDialogOverlay.close()
        selectedNetwork = null
        requestedUsername = ""
        requestedPassword = ""
        requestedAnonymousIdentity = ""
        selectedEnterpriseEap = "peap"
        showAnonymousIdentity = false
        useSavedCredentials = false
        confirmForgetNetwork = false
        dialogError = ""
        usernameInput.clear()
        passwordInput.clear()
        anonymousIdentityInput.clear()
    }

    function confirmConnection() {
        if (!selectedNetwork)
            return
        if (selectedNetwork.active) {
            closeNetworkDialog()
            return
        }
        if (selectedNetwork.enterprise && !requestedUsername.length) {
            dialogError = "请输入用户名"
            usernameInput.forceActiveFocus()
            return
        }
        if (selectedNetwork.enterprise) {
            if (!requestedPassword.length) {
                dialogError = "请输入 Wi‑Fi 密码"
                passwordInput.forceActiveFocus()
                return
            }
            dialogError = ""
            NetworkService.connectEnterpriseWifi(selectedNetwork.ssid,
                requestedUsername, requestedPassword, selectedEnterpriseEap,
                requestedAnonymousIdentity)
            return
        }
        dialogError = ""
        NetworkService.connectWifi(selectedNetwork.ssid, requestedPassword,
            selectedNetwork.savedProfileUuid || "")
    }

    LiquidGlassPanel {
        id: panelSurface
        anchors.fill: parent
        radius: panel.blurRadius
        cornerExponent: AppearanceTokens.shape.cornerExponent
        baseColor: ThemeService.backgroundColor
        surfaceOpacity: 1.0
        ambientPrimary: WallpaperColorSource.primary
        ambientSecondary: WallpaperColorSource.secondary
        ambientStrength: 0.35 * AppearanceTokens.glass.ambientMultiplier
        material: "thick"
        adaptiveDarkScrim: true
    }

    Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 0

        Item {
            visible: false
            width: parent.width
            height: 0
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Wi‑Fi"
                color: ThemeService.foregroundColor
                style: Text.Outline
                styleColor: Qt.rgba(0, 0, 0, 0.38)
                font { pixelSize: 16; weight: Font.Bold }
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 48
                anchors.verticalCenter: parent.verticalCenter
                text: NetworkService.wifiScanInProgress ? "正在扫描…" : "↻"
                color: ThemeService.foregroundColor
                opacity: NetworkService.wifiScanInProgress ? 0.55 : 0.82
                font { pixelSize: 15; weight: Font.DemiBold }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    enabled: !NetworkService.wifiScanInProgress
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NetworkService.refreshWifiNetworks()
                }
            }
            Rectangle {
                id: wifiSwitch
                // Use the control-center radio treatment instead of a
                // separate blue toggle track: white disc when enabled, blue
                // Wi-Fi glyph, and neutral glass when it is off.
                width: 32
                height: 32
                radius: width / 2
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                color: NetworkService.wifiEnabled
                    ? (ThemeService.isDark ? "#f7fbff" : Qt.rgba(0, 0, 0, 0.08))
                    : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.05))
                opacity: NetworkService.wifiToggleInProgress ? 0.55 : 1.0
                Behavior on color { ColorAnimation { duration: 140 } }
                border.width: 1
                border.color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(0, 0, 0, 0.10)
                WifiSignalIcon {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    wifiEnabled: NetworkService.wifiEnabled
                    connected: NetworkService.deviceState === "connected"
                        && NetworkService.connectionType === "wifi"
                    signalStrength: NetworkService.signalStrength
                    glyphColor: NetworkService.wifiEnabled
                        ? "#0a84ff"
                        : AppearanceTokens.content.glassInk()
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !NetworkService.wifiToggleInProgress
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: NetworkService.setWifiEnabled(!NetworkService.wifiEnabled)
                }
            }
        }

        LiquidGlassPanel {
            id: connectionCard
            visible: false
            width: parent.width
            height: 0
            radius: 13
            cornerExponent: AppearanceTokens.shape.cornerExponent
            baseColor: ThemeService.backgroundColor
            ambientPrimary: WallpaperColorSource.primary
            ambientSecondary: WallpaperColorSource.secondary
            ambientStrength: 0.72
            surfaceOpacity: 0.94
            materialDepth: 1.8
            Column {
                anchors {
                    left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                    leftMargin: 11; rightMargin: 108
                }
                spacing: 3
                Text {
                    text: !NetworkService.wifiEnabled ? "Wi‑Fi 已关闭"
                        : (NetworkService.connectionType === "wifi"
                        ? (NetworkService.ssid || "未连接 Wi‑Fi") : "未连接 Wi‑Fi"
                        )
                    color: ThemeService.foregroundColor
                    style: Text.Outline
                    styleColor: Qt.rgba(0, 0, 0, 0.38)
                    font { pixelSize: 13; weight: Font.DemiBold }
                }
                GlassText {
                    text: !NetworkService.wifiEnabled ? "打开开关以扫描附近网络"
                        : (NetworkService.deviceState === "connected"
                        ? (NetworkService.connectivity === "full" ? "已连接互联网"
                            : (NetworkService.connectivity === "portal" ? "需要网页登录认证"
                                : (NetworkService.connectivity === "limited"
                                    ? "网络受限" : "已连接")))
                        : "未连接")
                    color: ThemeService.foregroundColor
                    opacity: 0.64
                    font.pixelSize: 10
                }
            }
            Rectangle {
                visible: panel.activeSavedWifi() !== null
                    && NetworkService.connectionType === "wifi"
                    && NetworkService.deviceState === "connected"
                width: 42
                height: 22
                radius: 11
                anchors { right: parent.right; rightMargin: 58; verticalCenter: parent.verticalCenter }
                color: Qt.rgba(1, 1, 1, 0.11)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.18)
                GlassText {
                    anchors.centerIn: parent
                    text: "忘记"
                    color: "#ff9b92"
                    font { pixelSize: 10; weight: Font.DemiBold }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.showForgetActiveWifi()
                }
            }
            Rectangle {
                visible: NetworkService.wifiEnabled
                    && NetworkService.connectionType === "wifi"
                    && NetworkService.deviceState === "connected"
                width: 42
                height: 22
                radius: 11
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                color: Qt.rgba(1, 1, 1, 0.11)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.18)
                opacity: NetworkService.wifiDisconnectInProgress ? 0.5 : 1.0
                GlassText {
                    anchors.centerIn: parent
                    text: NetworkService.wifiDisconnectInProgress ? "…" : "断开"
                    color: panelSurface.foregroundColor
                    font { pixelSize: 10; weight: Font.DemiBold }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !NetworkService.wifiDisconnectInProgress
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: NetworkService.disconnectActiveWifi()
                }
            }
        }

    }
    Rectangle {
        id: networkListCard
        anchors.fill: parent
        radius: 19
        // Transparent so the compositor blur region (BackgroundEffect on
        // this panel) shows through - real liquid glass with windows
        // visible behind it. A subtle tint + border keep text readable.
        color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 1
        border.color: Qt.rgba(0.74, 0.95, 1, 0.28)

        Text {
            visible: false
            anchors { left: parent.left; top: parent.top; leftMargin: 13; topMargin: 10 }
            text: NetworkService.wifiEnabled ? "附近 Wi‑Fi" : "Wi‑Fi 已关闭"
            color: ThemeService.foregroundColor
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.50)
            opacity: 0.78
            font { pixelSize: 11; weight: Font.DemiBold }
        }

        ListView {
            id: wifiList
            anchors {
                left: parent.left; right: parent.right; top: parent.top; bottom: settingsFooter.top
                leftMargin: 8; rightMargin: 8; topMargin: 8; bottomMargin: 0
            }
            clip: true
            spacing: 2
            model: NetworkService.wifiEnabled ? NetworkService.nearbyWifi : []
            delegate: Rectangle {
                required property var modelData
                width: wifiList.width
                height: 46
                radius: 10
                color: networkRowMouse.containsMouse
                    ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                Behavior on color { ColorAnimation { duration: 110 } }
                Text {
                    visible: modelData.active
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    text: "✓"
                    color: panelSurface.foregroundColor
                    style: Text.Outline
                    styleColor: Qt.rgba(0, 0, 0, 0.50)
                    font { pixelSize: 19; weight: Font.DemiBold }
                }
                Canvas {
                    id: rowWifiGlyph
                    width: 24
                    height: 24
                    anchors { left: parent.left; leftMargin: 32; verticalCenter: parent.verticalCenter }
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = panelSurface.foregroundColor
                        ctx.fillStyle = panelSurface.foregroundColor
                        ctx.globalAlpha = 0.92
                        ctx.lineWidth = 1.9
                        ctx.lineCap = "round"
                        const rings = modelData.signalStrength < 25 ? 1
                            : (modelData.signalStrength < 50 ? 2 : 3)
                        for (let ring = 0; ring < rings; ring++) {
                            const ringRadius = 3.3 + ring * 2.7
                            ctx.beginPath()
                            ctx.arc(12, 17.1, ringRadius,
                                Math.PI * 1.22, Math.PI * 1.78)
                            ctx.stroke()
                        }
                        ctx.beginPath()
                        ctx.arc(12, 16.7, 1.4, 0, Math.PI * 2)
                        ctx.fill()
                    }
                }
                // Draw the encryption mark instead of relying on a lock
                // glyph: the configured CJK font can lack that glyph and
                // renders it as a square on some installations.
                Canvas {
                    id: rowSecurityGlyph
                    visible: modelData.secured
                    width: 8
                    height: 11
                    // Keep one tight icon gap, then reserve a larger
                    // readable gap before the SSID (see label margin).
                    anchors { left: rowWifiGlyph.right; leftMargin: 1; verticalCenter: parent.verticalCenter }
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = panelSurface.foregroundColor
                        ctx.fillStyle = panelSurface.foregroundColor
                        ctx.globalAlpha = 0.82
                        ctx.lineWidth = 1.2
                        ctx.lineCap = "round"
                        ctx.beginPath()
                        ctx.arc(4, 4.7, 2.35, Math.PI * 1.12, Math.PI * 1.88)
                        ctx.stroke()
                        ctx.fillRect(0.7, 4.8, 6.6, 5.5)
                        ctx.fillStyle = "rgba(0, 0, 0, 0.28)"
                        ctx.beginPath()
                        ctx.arc(4, 7.3, 0.75, 0, Math.PI * 2)
                        ctx.fill()
                    }
                }
                Text {
                    // Reserve the checkmark slot in every row. Connected
                    // state changes only the checkmark, never alignment.
                    anchors {
                        left: parent.left
                        leftMargin: modelData.secured ? 73 : 64
                        right: parent.right
                        rightMargin: 12
                        verticalCenter: parent.verticalCenter
                    }
                    text: modelData.ssid
                    color: panelSurface.foregroundColor
                    style: Text.Outline
                    styleColor: Qt.rgba(0, 0, 0, 0.50)
                    elide: Text.ElideRight
                    font { pixelSize: 12; weight: Font.DemiBold }
                }
                MouseArea {
                    id: networkRowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.showNetworkDialog(modelData)
                }
            }
            GlassText {
                anchors.centerIn: parent
                visible: NetworkService.wifiEnabled && NetworkService.wifiScanInProgress
                    && NetworkService.nearbyWifi.length === 0
                text: "正在扫描…"
                color: panelSurface.secondaryForegroundColor
                opacity: 0.5
                font.pixelSize: 12
            }
            GlassText {
                anchors.centerIn: parent
                visible: NetworkService.wifiEnabled && !NetworkService.wifiScanInProgress
                    && NetworkService.nearbyWifi.length === 0
                text: "未发现可用 Wi‑Fi"
                color: panelSurface.secondaryForegroundColor
                opacity: 0.5
                font.pixelSize: 12
            }
        }

        // Match the familiar system-picker affordance: a fixed bottom
        // action, separated from the scrollable access-point list.
        Item {
            id: settingsFooter
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 50

            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 1
                color: Qt.rgba(1, 1, 1, 0.16)
            }
            Text {
                anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                text: "无线局域网设置…"
                color: panelSurface.foregroundColor
                style: Text.Outline
                styleColor: Qt.rgba(0, 0, 0, 0.50)
                font { pixelSize: 14; weight: Font.DemiBold }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.openWirelessSettings()
            }
        }
    }

    // Important credentials use the shell-wide modal primitive. Its card samples
    // the desktop beneath it and readability is carried by the card's own fixed
    // KWin scrim, so this dialog wants no desktop wash: `modal` alone already
    // provides hit testing, focus and stacking.
    KosFloatPanel {
        id: networkDialogOverlay
        modal: true
        centerOnScreen: true
        backdropMode: "none"
        dismissOnBackdrop: false
        contentPadding: 0
        onBackdropClicked: panel.closeNetworkDialog()

        Item {
            id: networkDialog
            // This is a system dialog now, independent of the narrow Wi-Fi
            // list that launched it.
            width: Math.min(420, networkDialogOverlay.width - 44)
            height: Math.min(
                panel.selectedNetwork?.enterprise
                    ? (panel.showAnonymousIdentity ? 374 : 330)
                    : 292,
                networkDialogOverlay.height - 40
            )
            focus: networkDialogOverlay.visible

            // Gaps inside the card belong to the dialog, not its dismissing
            // full-screen MouseArea below.
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                onClicked: function(mouse) { mouse.accepted = true }
            }

            Rectangle {
                id: dismissRing
                width: 30; height: 30; radius: width / 2
                anchors { left: parent.left; top: parent.top; leftMargin: 13; topMargin: 12 }
                color: networkDialogOverlay.contentControlFill
                border.width: 1; border.color: networkDialogOverlay.contentControlBorder
                GlassText { anchors.centerIn: parent; text: "×"; color: networkDialogOverlay.contentForegroundColor; font { pixelSize: 22; weight: Font.Light } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: panel.closeNetworkDialog() }
            }

            Rectangle {
                id: confirmRing
                width: 30; height: 30; radius: width / 2
                anchors { right: parent.right; top: parent.top; rightMargin: 13; topMargin: 12 }
                color: networkDialogOverlay.contentControlFill
                border.width: 1; border.color: networkDialogOverlay.contentControlBorder
                opacity: NetworkService.wifiConnectInProgress ? 0.55 : 1.0
                GlassText { anchors.centerIn: parent; text: NetworkService.wifiConnectInProgress ? "…" : "✓"; color: networkDialogOverlay.contentForegroundColor; font { pixelSize: 18; weight: Font.Light } }
                MouseArea { anchors.fill: parent; enabled: !NetworkService.wifiConnectInProgress; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: panel.confirmConnection() }
            }

            Canvas {
                id: joinWifiGlyph
                width: 58; height: 48
                anchors { top: parent.top; topMargin: 43; horizontalCenter: parent.horizontalCenter }
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.strokeStyle = "#0a84ff"
                    ctx.lineWidth = 6.5
                    ctx.lineCap = "round"
                    ctx.beginPath(); ctx.arc(width / 2, 28, 21, Math.PI * 1.18, Math.PI * 1.82); ctx.stroke()
                    ctx.beginPath(); ctx.arc(width / 2, 33, 12, Math.PI * 1.20, Math.PI * 1.80); ctx.stroke()
                    ctx.beginPath(); ctx.arc(width / 2, 38, 3, Math.PI * 1.23, Math.PI * 1.77); ctx.stroke()
                }
            }

            Column {
                anchors { left: parent.left; right: parent.right; top: joinWifiGlyph.bottom; topMargin: 10; leftMargin: 22; rightMargin: 22 }
                spacing: 9
                Text {
                    width: parent.width
                    text: "加入 “" + (panel.selectedNetwork?.ssid || "Wi‑Fi") + "”"
                    color: networkDialogOverlay.contentForegroundColor
                    elide: Text.ElideRight
                    font { pixelSize: 18; weight: Font.Bold }
                }
                GlassText {
                    width: parent.width
                    text: NetworkService.wifiConnectInProgress ? "正在加入此无线局域网…"
                        : (panel.selectedNetwork?.active ? "当前已连接此无线局域网。"
                        : (panel.selectedNetwork?.enterprise
                            ? "输入用户名和密码加入此无线局域网。"
                            : (panel.useSavedCredentials
                                ? "将使用已保存的密码加入此无线局域网。"
                                : (panel.selectedNetwork?.secured
                                ? "输入密码加入此无线局域网。" : "加入此无线局域网。"))))
                    color: networkDialogOverlay.contentSecondaryColor
                    wrapMode: Text.WordWrap
                    font.pixelSize: 14
                }

                Row {
                    visible: Boolean(panel.selectedNetwork?.enterprise)
                    spacing: 6
                    Repeater {
                        model: [
                            { id: "peap", label: "PEAP" },
                            { id: "ttls", label: "TTLS" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: 55
                            height: 24
                            radius: 12
                            color: panel.selectedEnterpriseEap === modelData.id
                                ? Qt.rgba(0.15, 0.52, 1, 0.42)
                                : networkDialogOverlay.contentControlFill
                            border.width: 1
                            border.color: panel.selectedEnterpriseEap === modelData.id
                                ? Qt.rgba(0.28, 0.64, 1, 0.78)
                                : networkDialogOverlay.contentControlBorder
                            GlassText {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: networkDialogOverlay.contentForegroundColor
                                font { pixelSize: 10; weight: Font.DemiBold }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.selectedEnterpriseEap = modelData.id
                            }
                        }
                    }
                    GlassText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: panel.selectedEnterpriseEap === "peap"
                            ? "MSCHAPv2" : "PAP"
                        color: networkDialogOverlay.contentSecondaryColor
                        font.pixelSize: 10
                    }
                    GlassText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: panel.showAnonymousIdentity ? "收起" : "匿名身份"
                        color: networkDialogOverlay.contentSecondaryColor
                        font.pixelSize: 10
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.showAnonymousIdentity = !panel.showAnonymousIdentity
                        }
                    }
                }

                Item { width: 1; height: 2 }

                Rectangle {
                    visible: Boolean(panel.selectedNetwork && !panel.selectedNetwork.active
                        && (panel.selectedNetwork.enterprise
                            || (panel.selectedNetwork.secured
                                && !panel.useSavedCredentials)))
                    width: parent.width
                    height: panel.selectedNetwork?.enterprise
                        ? (panel.showAnonymousIdentity ? 126 : 84) : 42
                    radius: 14
                    color: networkDialogOverlay.contentControlFill
                    border.width: (usernameInput.activeFocus || passwordInput.activeFocus) ? 1 : 0
                    border.color: Qt.rgba(0.15, 0.52, 1, 0.80)

                    TextInput {
                        id: usernameInput
                        visible: Boolean(panel.selectedNetwork?.enterprise)
                        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 14; rightMargin: 14 }
                        height: 42
                        verticalAlignment: TextInput.AlignVCenter
                        color: networkDialogOverlay.contentForegroundColor
                        selectionColor: Qt.rgba(0.15, 0.52, 1, 0.48)
                        selectedTextColor: networkDialogOverlay.contentForegroundColor
                        clip: true
                        font.pixelSize: 14
                        onTextEdited: panel.requestedUsername = text
                        GlassText { anchors.verticalCenter: parent.verticalCenter; visible: !usernameInput.text && !usernameInput.activeFocus; text: "用户名"; color: networkDialogOverlay.contentSecondaryColor; font.pixelSize: 14 }
                    }
                    Rectangle {
                        visible: Boolean(panel.selectedNetwork?.enterprise)
                        anchors {
                            left: parent.left; right: parent.right; top: parent.top
                            leftMargin: 14; rightMargin: 14; topMargin: 42
                        }
                        height: 1
                        color: networkDialogOverlay.contentControlBorder
                    }
                    TextInput {
                        id: passwordInput
                        anchors {
                            left: parent.left; right: parent.right; bottom: parent.bottom
                            leftMargin: 14; rightMargin: 14
                            bottomMargin: panel.showAnonymousIdentity ? 42 : 0
                        }
                        height: panel.selectedNetwork?.enterprise ? 42 : parent.height
                        verticalAlignment: TextInput.AlignVCenter
                        color: networkDialogOverlay.contentForegroundColor
                        selectionColor: Qt.rgba(0.15, 0.52, 1, 0.48)
                        selectedTextColor: networkDialogOverlay.contentForegroundColor
                        echoMode: TextInput.Password
                        clip: true
                        font.pixelSize: 14
                        onTextEdited: panel.requestedPassword = text
                        Keys.onPressed: function(event) { if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { panel.confirmConnection(); event.accepted = true } }
                        GlassText { anchors.verticalCenter: parent.verticalCenter; visible: !passwordInput.text && !passwordInput.activeFocus; text: "密码"; color: networkDialogOverlay.contentSecondaryColor; font.pixelSize: 14 }
                    }
                    Rectangle {
                        visible: Boolean(panel.selectedNetwork?.enterprise
                            && panel.showAnonymousIdentity)
                        anchors {
                            left: parent.left; right: parent.right; bottom: parent.bottom
                            leftMargin: 14; rightMargin: 14; bottomMargin: 42
                        }
                        height: 1
                        color: networkDialogOverlay.contentControlBorder
                    }
                    TextInput {
                        id: anonymousIdentityInput
                        visible: Boolean(panel.selectedNetwork?.enterprise
                            && panel.showAnonymousIdentity)
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 14; rightMargin: 14 }
                        height: 42
                        verticalAlignment: TextInput.AlignVCenter
                        color: networkDialogOverlay.contentForegroundColor
                        selectionColor: Qt.rgba(0.15, 0.52, 1, 0.48)
                        selectedTextColor: networkDialogOverlay.contentForegroundColor
                        clip: true
                        font.pixelSize: 14
                        onTextEdited: panel.requestedAnonymousIdentity = text
                        GlassText { anchors.verticalCenter: parent.verticalCenter; visible: !anonymousIdentityInput.text && !anonymousIdentityInput.activeFocus; text: "匿名身份（可选）"; color: networkDialogOverlay.contentSecondaryColor; font.pixelSize: 14 }
                    }
                }
                Rectangle {
                    visible: Boolean(panel.selectedNetwork
                        && (!panel.selectedNetwork.active || panel.confirmForgetNetwork)
                        && !panel.selectedNetwork.enterprise && panel.useSavedCredentials)
                    width: parent.width
                    height: 38
                    radius: 14
                    color: Qt.rgba(0.15, 0.52, 1, 0.16)
                    border.width: 1
                    border.color: Qt.rgba(0.28, 0.64, 1, 0.36)
                    GlassText {
                        anchors { left: parent.left; leftMargin: 13; verticalCenter: parent.verticalCenter }
                        text: panel.confirmForgetNetwork ? "忘记此网络？" : "✓  已保存密码"
                        color: networkDialogOverlay.contentForegroundColor
                        font { pixelSize: 12; weight: Font.DemiBold }
                    }
                    GlassText {
                        anchors { right: parent.right; rightMargin: 60; verticalCenter: parent.verticalCenter }
                        text: panel.confirmForgetNetwork ? "取消" : "更换"
                        color: networkDialogOverlay.contentSecondaryColor
                        font.pixelSize: 11
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -5
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (panel.confirmForgetNetwork)
                                    panel.confirmForgetNetwork = false
                                else {
                                    panel.useSavedCredentials = false
                                    passwordFocusTimer.restart()
                                }
                            }
                        }
                    }
                    GlassText {
                        anchors { right: parent.right; rightMargin: 13; verticalCenter: parent.verticalCenter }
                        text: NetworkService.wifiForgetInProgress ? "…"
                            : (panel.confirmForgetNetwork ? "确认" : "忘记")
                        color: panel.confirmForgetNetwork ? "#d93025" : networkDialogOverlay.contentSecondaryColor
                        opacity: NetworkService.wifiForgetInProgress ? 0.5 : 1.0
                        font.pixelSize: 11
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -5
                            enabled: !NetworkService.wifiForgetInProgress
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (!panel.confirmForgetNetwork) {
                                    panel.confirmForgetNetwork = true
                                } else {
                                    NetworkService.forgetWifiProfile(panel.selectedNetwork.ssid,
                                        panel.selectedNetwork.savedProfileUuid || "")
                                }
                            }
                        }
                    }
                }
                GlassText {
                    visible: !panel.selectedNetwork?.active && !panel.selectedNetwork?.enterprise
                        && !panel.useSavedCredentials
                    width: parent.width
                    text: "密码将由 NetworkManager 安全保存。"
                    color: networkDialogOverlay.contentTertiaryColor
                    wrapMode: Text.WordWrap
                    font.pixelSize: 13
                }
                GlassText {
                    visible: panel.dialogError.length > 0
                    width: parent.width
                    text: panel.dialogError
                    color: "#ff6b61"
                    wrapMode: Text.WordWrap
                    font.pixelSize: 12
                }
            }
        }
    }

    Timer {
        id: passwordFocusTimer
        interval: 16
        repeat: false
        onTriggered: {
            if (panel.selectedNetwork?.enterprise && !panel.selectedNetwork?.active) {
                networkDialog.forceActiveFocus()
                usernameInput.forceActiveFocus()
            } else if (panel.selectedNetwork?.secured && !panel.selectedNetwork?.active
                    && !panel.useSavedCredentials) {
                networkDialog.forceActiveFocus()
                passwordInput.forceActiveFocus()
            }
        }
    }

    Connections {
        target: NetworkService
        function onWifiConnectionFinished(ssid, success) {
            if (!panel.selectedNetwork || panel.selectedNetwork.ssid !== ssid)
                return
            if (success)
                panel.closeNetworkDialog()
            else {
                panel.dialogError = NetworkService.wifiConnectError
                passwordInput.forceActiveFocus()
            }
        }
        function onWifiForgetFinished(ssid, success) {
            if (!panel.selectedNetwork || panel.selectedNetwork.ssid !== ssid)
                return
            if (success) {
                // Switch this exact dialog to the new-network state instead
                // of requiring the user to close and select the row again.
                panel.selectedNetwork.savedProfileUuid = ""
                panel.useSavedCredentials = false
                panel.confirmForgetNetwork = false
                panel.dialogError = ""
                passwordFocusTimer.restart()
            } else {
                panel.confirmForgetNetwork = false
                panel.dialogError = NetworkService.wifiForgetError
            }
        }
    }
}
