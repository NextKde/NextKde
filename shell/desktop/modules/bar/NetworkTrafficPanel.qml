import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Kos.FormaNetwork 1.0
import "../../../shared/qml/i18n"
import qs.desktop.modules.platform
import "ApplicationTraffic.mjs" as ApplicationTraffic
import "NetworkTrafficHistory.mjs" as TrafficHistory
import qs.desktop.modules.common
import qs.desktop.modules.dock

// A read-only dashboard for the active interface, independent of Wi-Fi setup.
AnimatedPopupWindow {
    id: panel
    animationEnabled: false
    property Item anchorItem: null
    readonly property bool connected: NetworkService.available
        && NetworkService.deviceState === "connected"
    property var history: TrafficHistory.empty()
    readonly property var downloadHistory: history.download
    readonly property var uploadHistory: history.upload
    property bool detailsExpanded: false
    property var applicationRows: []
    property var previousSockets: ({})
    property bool applicationsPending: false
    property string applicationsError: ""
    property int applicationsGeneration: 0
    function refreshApplications() {
        if (!requestedOpen || !detailsExpanded || applicationsPending) return
        applicationsPending = true
        const generation = applicationsGeneration
        PlatformClient.request("network.applications", {}, function(response) {
            if (generation !== applicationsGeneration) return
            applicationsPending = false
            if (!response?.ok) {
                applicationRows = []
                previousSockets = ({})
                applicationsError = I18n.tr("Application traffic is unavailable. Check that the platform service is up to date and ss is installed.")
                return
            }
            applicationsError = ""
            const result = ApplicationTraffic.sample(previousSockets, response.result.sockets || [], Date.now())
            previousSockets = result.previous
            applicationRows = result.rows.map(row => {
                // Reuse the existing canonical window presentation; never
                // guess an application identity from a process basename.
                const window = WindowService.records.find(record => row.processes.indexOf(record.pid) >= 0)
                return Object.assign({}, row, { iconSource: window?.iconSource || "" })
            })
        })
    }
    onRequestedOpenChanged: {
        applicationsGeneration++
        applicationsPending = false
        previousSockets = ({})
        if (requestedOpen) {
            detailsExpanded = false
            applicationRows = []
            applicationsError = ""
            refreshApplications()
        }
    }
    onDetailsExpandedChanged: {
        applicationsGeneration++
        applicationsPending = false
        previousSockets = ({})
        applicationRows = []
        applicationsError = ""
        if (detailsExpanded) refreshApplications()
    }
    readonly property var targetScreen: anchorItem
        ? (anchorItem.QsWindow.window?.screen ?? ScreenLifecycle.activeScreen)
        : ScreenLifecycle.activeScreen
    implicitWidth: 280
    // Like ControlCenterPanel, keep the Wayland surface allocation stable while
    // content unfolds. Resizing a mapped OpenGL popup can stop frame delivery.
    // Only the visible card receives input; the unused envelope is click-through.
    implicitHeight: Math.min(940, Math.max(160, (targetScreen?.height ?? 900) - 80))
    readonly property real surfaceHeight: Math.min(detailsExpanded ? 924 : 712, height)
    property alias nativeView: nativeTrafficView
    property var connectivityHistory: []
    property real uploadBaseline: 0
    property real downloadBaseline: 0
    mask: interactive ? panelInputRegion : panelEmptyRegion
    Region { id: panelInputRegion; item: panelSurface }
    Region { id: panelEmptyRegion }
    color: "transparent"
    grabFocus: interactive
    PopupAnchorBinding { popupAnchor: panel.anchor; sourceItem: panel.anchorItem }
    anchor {
        edges: Edges.Bottom
        gravity: Edges.Bottom
        adjustment: PopupAdjustment.Slide
        margins.bottom: -8
    }
    BackgroundEffect.blurRegion: panel.visible && panel.revealProgress > 0
        && AppearanceTokens.surface.usesBackdrop ? surface.blurRegion : null

    function toggle(item) {
        if (requestedOpen) {
            close()
            return
        }
        anchorItem = item
        history = TrafficHistory.empty(NetworkService.deviceName)
        detailsExpanded = false
        nativeTrafficView.ensurePolished()
        show()
    }
    function close() { hide() }
    function recordSample(device, download, upload) {
        if (requestedOpen && connected && device === NetworkService.deviceName) {
            history = TrafficHistory.append(history, device, download, upload)
            const connectivity = NetworkService.connectivity
            connectivityHistory = connectivityHistory.concat([connectivity === "full" ? true
                : ["limited", "none", "portal"].indexOf(connectivity) >= 0 ? false : null]).slice(-90)
        }
    }
    onConnectedChanged: if (!connected) close()
    onAnchorItemChanged: if (!anchorItem && requestedOpen) close()
    Connections {
        target: NetworkService
        function onTrafficSampled(device, download, upload) {
            panel.recordSample(device, download, upload)
        }
        function onDeviceNameChanged() {
            panel.history = TrafficHistory.empty(NetworkService.deviceName)
            panel.previousSockets = ({})
            panel.connectivityHistory = []
            panel.uploadBaseline = 0
            panel.downloadBaseline = 0
        }
    }
    Timer {
        interval: 2000
        running: panel.requestedOpen && panel.detailsExpanded
        repeat: true
        onTriggered: panel.refreshApplications()
    }
    onClosed: if (requestedOpen) close()
    Connections {
        target: ScreenLifecycle
        function onOutputAvailableChanged() {
            if (!ScreenLifecycle.outputAvailable) panel.close()
        }
    }
    Connections {
        target: WindowService
        function onActiveWindowIdChanged() {
            if (panel.requestedOpen) panel.close()
        }
    }
    Connections {
        target: ContextMenuCoordinator
        function onActiveMenuChanged() {
            if (ContextMenuCoordinator.activeMenu) panel.close()
        }
    }
    Shortcut {
        sequence: "Escape"
        enabled: panel.requestedOpen
        onActivated: panel.close()
    }
    PanelWindow {
        objectName: "traffic-dismissal-catcher"
        screen: panel.targetScreen
        visible: ScreenLifecycle.outputAvailable && panel.targetScreen !== null && panel.requestedOpen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-trafficpanel-backdrop"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }
        MouseArea { objectName: "traffic-outside-press"; anchors.fill: parent; onPressed: panel.close() }
    }
    Item {
        id: panelSurface
        objectName: "traffic-panel-surface"
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: panel.surfaceHeight
        LiquidGlassPanel {
            id: surface
            anchors.fill: parent
            radius: 16
            cornerExponent: AppearanceTokens.shape.cornerExponent
            // The native item already renders at the window's physical DPR.
            // A second offscreen content layer would resample its glyphs.
            maskContent: false
            baseColor: AppearanceTokens.colors.surfaceContainer
            surfaceOpacity: 1
            scrimEnabled: AppearanceTokens.surface.usesBackdrop
            scrimLevel: AppearanceTokens.bar.popupScrimLevel
        }
        NetworkTrafficView {
            id: nativeTrafficView
            objectName: "traffic-panel-body"
            anchors.fill: parent
            dark: AppearanceTokens.isDarkTheme
            ink: surface.foregroundColor
            mutedInk: surface.secondaryForegroundColor
            detailsExpanded: panel.detailsExpanded
            snapshot: ({
                translations: ({
                    "Network": I18n.tr("Network"),
                    "Download": I18n.tr("Download"),
                    "Upload": I18n.tr("Upload"),
                    "Usage history": I18n.tr("Usage history"),
                    "Connectivity history": I18n.tr("Connectivity history"),
                    "Interface": I18n.tr("Interface"),
                    "Total upload:": I18n.tr("Total upload:"),
                    "Total download:": I18n.tr("Total download:"),
                    "Status:": I18n.tr("Status:"),
                    "Internet connection:": I18n.tr("Internet connection:"),
                    "Latency:": I18n.tr("Latency:"),
                    "Jitter:": I18n.tr("Jitter:"),
                    "Interface:": I18n.tr("Interface:"),
                    "Physical address:": I18n.tr("Physical address:"),
                    "Network:": I18n.tr("Network:"),
                    "Address": I18n.tr("Address"),
                    "Local IP:": I18n.tr("Local IP:"),
                    "Public IP:": I18n.tr("Public IP:"),
                    "Top processes": I18n.tr("Top processes"),
                    "Process": I18n.tr("Process"),
                    "UP": I18n.tr("UP"),
                    "DOWN": I18n.tr("DOWN"),
                    "Sampling application traffic…": I18n.tr("Sampling application traffic…"),
                    "Visible TCP connections only. Proxy traffic may be counted twice; UDP/QUIC is excluded.": I18n.tr("Visible TCP connections only. Proxy traffic may be counted twice; UDP/QUIC is excluded."),
                }),
                connected: panel.connected,
                connectivity: NetworkService.connectivity,
                download: NetworkService.downloadBytesPerSecond,
                upload: NetworkService.uploadBytesPerSecond,
                totalDownload: NetworkService.totalRxBytes < 0 ? -1
                    : Math.max(0, NetworkService.totalRxBytes - panel.downloadBaseline),
                totalUpload: NetworkService.totalTxBytes < 0 ? -1
                    : Math.max(0, NetworkService.totalTxBytes - panel.uploadBaseline),
                interface: NetworkService.deviceName,
                network: NetworkService.ssid || NetworkService.connectionName,
                macAddress: NetworkService.macAddress,
                localIp: NetworkService.ipv4,
                downloadHistory: panel.downloadHistory,
                uploadHistory: panel.uploadHistory,
                connectivityHistory: panel.connectivityHistory,
                applications: panel.applicationRows,
                iconRevision: IconThemeReloadService.revision,
                applicationsError: panel.applicationsError
            })
            onCloseRequested: panel.close()
            onDetailsToggleRequested: panel.detailsExpanded = !panel.detailsExpanded
            onRefreshRequested: NetworkService.refresh()
            onResetTotalsRequested: {
                panel.uploadBaseline = Math.max(0, NetworkService.totalTxBytes)
                panel.downloadBaseline = Math.max(0, NetworkService.totalRxBytes)
            }
        }
    }
}
