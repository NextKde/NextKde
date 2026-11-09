import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../../shared/qml/i18n"
import qs.desktop.modules.platform
import "ApplicationTraffic.mjs" as ApplicationTraffic
import "NetworkTrafficHistory.mjs" as TrafficHistory
import "networktraffic"
import qs.desktop.modules.common
import qs.desktop.modules.dock

// A read-only dashboard for the active interface, independent of Wi-Fi setup.
// The whole card is QML; the only custom paint is the two Canvas charts.
AnimatedPopupWindow {
    id: panel
    animationEnabled: false
    property Item anchorItem: null
    readonly property bool connected: NetworkService.available
        && NetworkService.deviceState === "connected"
    property var history: TrafficHistory.empty()
    // A sample is visible immediately, while the coalesced commit below is
    // what notifies long-lived bindings once per tick.
    readonly property var downloadHistory: (pendingHistory !== null
        ? pendingHistory : history).download
    readonly property var uploadHistory: (pendingHistory !== null
        ? pendingHistory : history).upload
    property var connectivityHistory: []
    property bool detailsExpanded: false
    property var applicationRows: []
    // Bounded name -> iconSource map. The Qt image cache does the actual
    // pixmap caching; this only avoids repeating the window lookup while a
    // panel session is open. Never more than 64 entries and released on close.
    property var iconCache: ({})
    property var previousSockets: ({})
    property bool applicationsPending: false
    property string applicationsError: ""
    property int applicationsGeneration: 0
    property real uploadBaseline: 0
    property real downloadBaseline: 0
    // One sample per second is merged into a single commit so the charts and
    // the history properties change (and repaint) at most once per sample.
    property int sampleRevision: 0
    property var pendingHistory: null
    property var pendingConnectivity: []
    property bool sampleCommitScheduled: false

    readonly property alias processModel: trafficBody.processModel
    readonly property alias processCount: trafficBody.processCount

    function iconSourceFor(name, source) {
        if (!source)
            return ""
        if (iconCache[name] === source)
            return source
        if (Object.keys(iconCache).length >= 64)
            iconCache = ({})
        iconCache[name] = source
        return source
    }
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
            // Reuse the existing canonical window presentation; never guess an
            // application identity from a process basename. The rows come fresh
            // from the sampler, so annotate them in place instead of allocating
            // a second array of copies every two seconds.
            const rows = result.rows
            for (const row of rows) {
                const window = WindowService.records.find(record => row.processes.indexOf(record.pid) >= 0)
                row.iconSource = panel.iconSourceFor(row.name, window?.iconSource || "")
            }
            applicationRows = rows
        })
    }
    function releaseApplications() {
        trafficBody.clearApplications()
        applicationRows = []
        previousSockets = ({})
        iconCache = ({})
        applicationsError = ""
        applicationsPending = false
    }
    onApplicationRowsChanged: {
        if (requestedOpen && detailsExpanded)
            trafficBody.setApplications(applicationRows)
        else if (applicationRows.length === 0)
            trafficBody.clearApplications()
    }
    onRequestedOpenChanged: {
        applicationsGeneration++
        applicationsPending = false
        previousSockets = ({})
        if (requestedOpen) {
            detailsExpanded = false
            applicationRows = []
            applicationsError = ""
            iconCache = ({})
            refreshApplications()
        } else {
            // Closing must leave nothing resident for the next open.
            releaseApplications()
            pendingHistory = null
            pendingConnectivity = []
        }
    }
    onDetailsExpandedChanged: {
        applicationsGeneration++
        applicationsPending = false
        previousSockets = ({})
        applicationRows = []
        applicationsError = ""
        if (detailsExpanded) {
            refreshApplications()
        } else {
            trafficBody.clearApplications()
            iconCache = ({})
        }
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
        connectivityHistory = []
        detailsExpanded = false
        show()
    }
    function close() { hide() }
    function recordSample(device, download, upload) {
        if (!(requestedOpen && connected) || device !== NetworkService.deviceName)
            return
        const baseHistory = pendingHistory !== null ? pendingHistory : history
        pendingHistory = TrafficHistory.append(baseHistory, device, download, upload)
        const connectivity = NetworkService.connectivity
        const next = connectivity === "full" ? true
            : ["limited", "none", "portal"].indexOf(connectivity) >= 0 ? false : null
        const baseConnectivity = sampleCommitScheduled ? pendingConnectivity : connectivityHistory
        pendingConnectivity = baseConnectivity.concat([next]).slice(-90)
        sampleRevision++
        if (!sampleCommitScheduled) {
            sampleCommitScheduled = true
            Qt.callLater(commitSample)
        }
    }
    function commitSample() {
        sampleCommitScheduled = false
        if (!requestedOpen) {
            pendingHistory = null
            return
        }
        if (pendingHistory !== null)
            history = pendingHistory
        connectivityHistory = pendingConnectivity
        pendingHistory = null
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
            panel.connectivityHistory = []
            panel.pendingHistory = null
            panel.previousSockets = ({})
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
            // Content is plain QML at the window's physical DPR. A second
            // offscreen content layer would resample its glyphs and cost an FBO.
            maskContent: false
            baseColor: AppearanceTokens.colors.surfaceContainer
            surfaceOpacity: 1
            scrimEnabled: AppearanceTokens.surface.usesBackdrop
            scrimLevel: AppearanceTokens.bar.popupScrimLevel
        }
        TrafficBody {
            id: trafficBody
            objectName: "traffic-panel-body"
            anchors.fill: parent
            ink: surface.foregroundColor
            mutedInk: surface.secondaryForegroundColor
            dark: AppearanceTokens.isDarkTheme
            connected: panel.connected
            connectivity: NetworkService.connectivity
            downloadRate: NetworkService.downloadBytesPerSecond
            uploadRate: NetworkService.uploadBytesPerSecond
            totalDownload: NetworkService.totalRxBytes < 0 ? -1
                : Math.max(0, NetworkService.totalRxBytes - panel.downloadBaseline)
            totalUpload: NetworkService.totalTxBytes < 0 ? -1
                : Math.max(0, NetworkService.totalTxBytes - panel.uploadBaseline)
            interfaceName: NetworkService.deviceName
            networkName: NetworkService.ssid || NetworkService.connectionName
            macAddress: NetworkService.macAddress
            localIp: NetworkService.ipv4
            publicIp: ""
            downloadHistory: panel.downloadHistory
            uploadHistory: panel.uploadHistory
            connectivityHistory: panel.connectivityHistory
            detailsExpanded: panel.detailsExpanded
            applications: panel.applicationRows
            applicationsError: panel.applicationsError
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
