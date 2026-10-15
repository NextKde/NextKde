import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../../shared/qml/i18n"
import qs.desktop.modules.common
import qs.desktop.modules.dock

// A read-only dashboard for the active interface, independent of Wi-Fi setup.
AnimatedPopupWindow {
    id: panel
    property Item anchorItem: null
    readonly property bool connected: NetworkService.available
        && NetworkService.deviceState === "connected"
    property var downloadHistory: []
    property var uploadHistory: []
    property string historyDevice: ""
    readonly property var targetScreen: ScreenLifecycle.activeScreen
    implicitWidth: 340
    implicitHeight: 340
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
        downloadHistory = []
        uploadHistory = []
        historyDevice = NetworkService.deviceName
        recordSample()
        show()
    }
    function close() { hide() }
    function recordSample() {
        if (historyDevice !== NetworkService.deviceName || !connected) {
            downloadHistory = []
            uploadHistory = []
            historyDevice = NetworkService.deviceName
        }
        if (!connected) return
        downloadHistory = downloadHistory.concat([Math.max(0, NetworkService.downloadBytesPerSecond)]).slice(-60)
        uploadHistory = uploadHistory.concat([Math.max(0, NetworkService.uploadBytesPerSecond)]).slice(-60)
    }
    Timer {
        interval: 1000
        running: panel.requestedOpen
        repeat: true
        onTriggered: panel.recordSample()
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
        screen: panel.targetScreen
        visible: ScreenLifecycle.outputAvailable && panel.targetScreen !== null && panel.requestedOpen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-trafficpanel-backdrop"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }
        MouseArea { anchors.fill: parent; onPressed: panel.close() }
    }
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
    ColumnLayout {
        anchors { fill: parent; margins: 18 }
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: I18n.tr("Network Traffic")
                color: ThemeService.foregroundColor
                font { pixelSize: 16; weight: Font.DemiBold }
                Layout.fillWidth: true
            }
            Text {
                text: "×"
                color: ThemeService.foregroundColor
                font.pixelSize: 22
                TapHandler { onTapped: panel.close() }
            }
        }
        Text {
            Layout.fillWidth: true
            text: panel.connected
                ? [NetworkService.connectionName || NetworkService.ssid, NetworkService.deviceName].filter(value => value).join(" · ")
                : I18n.tr("No active connection")
            elide: Text.ElideRight
            color: ThemeService.foregroundColor
            opacity: 0.65
            font.pixelSize: 11
        }
        Repeater {
            model: [
                { label: I18n.tr("Download speed"), rate: panel.connected ? NetworkService.downloadBytesPerSecond : 0, samples: panel.downloadHistory, ink: "#30b0ff" },
                { label: I18n.tr("Upload speed"), rate: panel.connected ? NetworkService.uploadBytesPerSecond : 0, samples: panel.uploadHistory, ink: "#32c795" }
            ]
            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 104
                radius: 12
                color: Qt.rgba(ThemeService.foregroundColor.r, ThemeService.foregroundColor.g, ThemeService.foregroundColor.b, 0.06)
                ColumnLayout {
                    anchors { fill: parent; margins: 10 }
                    spacing: 4
                    RowLayout {
                        Text {
                            text: modelData.label
                            color: ThemeService.foregroundColor
                            font.pixelSize: 12
                            Layout.fillWidth: true
                        }
                        Text {
                            text: NetworkService.formatRate(modelData.rate)
                            color: ThemeService.foregroundColor
                            font { pixelSize: 17; weight: Font.DemiBold }
                        }
                    }
                    Text {
                        text: I18n.tr("Peak %1").arg(NetworkService.formatRate(Math.max(0, ...modelData.samples)))
                        color: ThemeService.foregroundColor
                        opacity: 0.55
                        font.pixelSize: 10
                    }
                    UsageSparkline {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        lineColor: modelData.ink
                        values: {
                            const peak = Math.max(1, ...modelData.samples)
                            return modelData.samples.map(value => value / peak)
                        }
                    }
                }
            }
        }
        Text {
            text: I18n.tr("Recent speed · updates every second")
            color: ThemeService.foregroundColor
            opacity: 0.5
            font.pixelSize: 10
        }
    }
}
