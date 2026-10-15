import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../../shared/qml/i18n"
import qs.desktop.modules.platform
import "ApplicationTraffic.mjs" as ApplicationTraffic
import "NetworkTrafficHistory.mjs" as TrafficHistory
import qs.desktop.modules.common
import qs.desktop.modules.dock

// A read-only dashboard for the active interface, independent of Wi-Fi setup.
AnimatedPopupWindow {
    id: panel
    property Item anchorItem: null
    readonly property bool connected: NetworkService.available
        && NetworkService.deviceState === "connected"
    property var history: TrafficHistory.empty()
    readonly property var downloadHistory: history.download
    readonly property var uploadHistory: history.upload
    property var applicationRows: []
    readonly property color ink: surface.foregroundColor
    readonly property color mutedInk: surface.secondaryForegroundColor
    readonly property color downloadInk: AppearanceTokens.isDarkTheme ? "#69bcff" : "#1970c2"
    readonly property color uploadInk: AppearanceTokens.isDarkTheme ? "#61d3ad" : "#138163"
    readonly property real chartMaximum: Math.max(1, ...downloadHistory, ...uploadHistory)
    function tint(color, alpha) { return Qt.rgba(color.r, color.g, color.b, alpha) }
    ListModel { id: appsModel }
    onApplicationRowsChanged: {
        // Preserve delegates and hover/scroll position when only rates change.
        for (let i = 0; i < applicationRows.length; i++) {
            const row = applicationRows[i]
            let existing = -1
            for (let j = i; j < appsModel.count; j++) {
                if (appsModel.get(j).name === row.name) { existing = j; break }
            }
            if (existing < 0) appsModel.insert(i, {name: row.name, download: row.download, upload: row.upload})
            else {
                if (existing !== i) appsModel.move(existing, i, 1)
                if (appsModel.get(i).download !== row.download) appsModel.setProperty(i, "download", row.download)
                if (appsModel.get(i).upload !== row.upload) appsModel.setProperty(i, "upload", row.upload)
            }
        }
        if (appsModel.count > applicationRows.length)
            appsModel.remove(applicationRows.length, appsModel.count - applicationRows.length)
    }
    property var previousSockets: ({})
    property bool applicationsPending: false
    property string applicationsError: ""
    property int applicationsGeneration: 0
    function refreshApplications() {
        if (!requestedOpen || applicationsPending) return
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
            applicationRows = result.rows
        })
    }
    onRequestedOpenChanged: {
        applicationsGeneration++
        applicationsPending = false
        previousSockets = ({})
        if (requestedOpen) {
            applicationRows = []
            applicationsError = ""
            refreshApplications()
        }
    }
    readonly property var targetScreen: ScreenLifecycle.activeScreen
    implicitWidth: 380
    implicitHeight: Math.min(510, Math.max(240, (targetScreen?.height ?? 900) - 100))
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
        show()
    }
    function close() { hide() }
    function recordSample(device, download, upload) {
        if (requestedOpen && connected && device === NetworkService.deviceName)
            history = TrafficHistory.append(history, device, download, upload)
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
        }
    }
    Timer {
        interval: 2000
        running: panel.requestedOpen
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
        objectName: "traffic-panel-surface"
        anchors.fill: parent
    LiquidGlassPanel {
        id: surface
        anchors.fill: parent
        radius: 20
        cornerExponent: AppearanceTokens.shape.cornerExponent
        baseColor: AppearanceTokens.colors.surfaceContainer
        surfaceOpacity: 1
        scrimEnabled: AppearanceTokens.surface.usesBackdrop
        scrimLevel: "subtle"
    }
    Flickable {
        objectName: "traffic-panel-body"
        anchors { fill: parent; margins: 20 }
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ColumnLayout {
            id: content
            width: parent.width
            spacing: 16
            RowLayout {
                Layout.fillWidth: true
                Text { text: I18n.tr("Network Traffic"); color: panel.ink; font { pixelSize: 14; weight: Font.DemiBold } Layout.fillWidth: true }
                Item {
                    width: 28; height: 28
                    StatusPanelGlyph { anchors.centerIn: parent; width: 18; height: 18; kind: "close"; ink: panel.mutedInk }
                    TapHandler { onTapped: panel.close() }
                }
            }
            Text {
                Layout.fillWidth: true
                text: panel.connected ? [NetworkService.connectionName || NetworkService.ssid, NetworkService.deviceName].filter(value => value).join(" · ") : I18n.tr("No active connection")
                textFormat: Text.PlainText; elide: Text.ElideRight
                color: panel.mutedInk; font.pixelSize: 11
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    RowLayout {
                        spacing: 5
                        StatusPanelGlyph { width: 16; height: 16; kind: "download"; ink: panel.downloadInk }
                        Text { text: I18n.tr("Download"); color: panel.mutedInk; font.pixelSize: 11 }
                    }
                    Text {
                        text: NetworkService.formatRate(panel.connected ? NetworkService.downloadBytesPerSecond : 0)
                        color: panel.ink; font { pixelSize: 23; weight: Font.DemiBold }
                    }
                }
                Rectangle { width: 1; Layout.preferredHeight: 46; color: panel.tint(panel.ink, 0.08) }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    RowLayout {
                        spacing: 5
                        StatusPanelGlyph { width: 16; height: 16; kind: "upload"; ink: panel.uploadInk }
                        Text { text: I18n.tr("Upload"); color: panel.mutedInk; font.pixelSize: 11 }
                    }
                    Text {
                        text: NetworkService.formatRate(panel.connected ? NetworkService.uploadBytesPerSecond : 0)
                        color: panel.ink; font { pixelSize: 23; weight: Font.DemiBold }
                    }
                }
            }
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                Rectangle { anchors.fill: parent; radius: 10; color: panel.tint(panel.ink, 0.025) }
                UsageSparkline {
                    anchors { fill: parent; margins: 8 }
                    lineColor: panel.downloadInk
                    values: panel.downloadHistory.map(value => value / panel.chartMaximum)
                }
                UsageSparkline {
                    anchors { fill: parent; margins: 8 }
                    lineColor: panel.uploadInk
                    values: panel.uploadHistory.map(value => value / panel.chartMaximum)
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Text { text: I18n.tr("Applications"); color: panel.ink; font { pixelSize: 12; weight: Font.DemiBold } Layout.fillWidth: true }
                Text { text: I18n.tr("Download"); Layout.preferredWidth: 82; horizontalAlignment: Text.AlignRight; color: panel.downloadInk; font.pixelSize: 10 }
                Text { text: I18n.tr("Upload"); Layout.preferredWidth: 82; horizontalAlignment: Text.AlignRight; color: panel.uploadInk; font.pixelSize: 10 }
            }
            ListView {
                id: applicationList
                objectName: "traffic-application-list"
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(170, Math.max(68, appsModel.count * 38))
                clip: true
                model: appsModel
                reuseItems: true
                boundsBehavior: Flickable.StopAtBounds
                delegate: Item {
                    required property string name
                    required property real download
                    required property real upload
                    required property int index
                    width: ListView.view.width
                    height: 38
                    Rectangle { anchors.fill: parent; radius: 8; color: panel.tint(panel.ink, rowHover.hovered ? 0.06 : 0) }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                        spacing: 8
                        Text { text: name; textFormat: Text.PlainText; elide: Text.ElideRight; Layout.fillWidth: true; color: panel.ink; font.pixelSize: 12 }
                        Text { text: NetworkService.formatRate(download); Layout.preferredWidth: 82; horizontalAlignment: Text.AlignRight; color: panel.mutedInk; font.pixelSize: 11 }
                        Text { text: NetworkService.formatRate(upload); Layout.preferredWidth: 82; horizontalAlignment: Text.AlignRight; color: panel.mutedInk; font.pixelSize: 11 }
                    }
                    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; visible: index < appsModel.count - 1; color: panel.tint(panel.ink, 0.055) }
                    HoverHandler { id: rowHover }
                }
                Text {
                    anchors.fill: parent
                    visible: appsModel.count === 0
                    text: panel.applicationsError || (panel.applicationsPending ? I18n.tr("Sampling application traffic…") : I18n.tr("No visible TCP applications"))
                    color: panel.mutedInk; font.pixelSize: 11
                    wrapMode: Text.Wrap; verticalAlignment: Text.AlignVCenter
                }
            }
            Text {
                Layout.fillWidth: true
                text: I18n.tr("TCP apps · refreshes every 2 s · excludes UDP/QUIC")
                color: panel.mutedInk; opacity: 0.75; font.pixelSize: 10
            }
        }
    }
    }
}
