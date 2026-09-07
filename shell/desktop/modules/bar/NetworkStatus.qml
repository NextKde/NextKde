import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock

// Passive first-stage network indicator. Wi-Fi uses the same live signal
// glyph as the power controls; Ethernet keeps its dedicated cable icon.
Item {
    id: root

    signal panelToggleRequested()
    property bool sharedPanelOpen: false
    property bool dockHosted: false
    property string dockEdge: "bottom"
    property bool verticalDock: false
    property real iconSize: 18
    rotation: verticalDock ? -90 : 0

    // Reserve the same visual footprint as the adjacent status glyphs while
    // allowing differently proportioned system-theme icons to stay centred.
    implicitWidth: 23
    implicitHeight: 20
    width: implicitWidth
    height: implicitHeight
    visible: NetworkService.available

    // A local TUN/proxy can make NetworkManager's internet probe return
    // "limited" despite a working Wi-Fi connection. Keep connection state
    // authoritative and warn only for captive/no-route states.
    readonly property bool hasIssue: NetworkService.connectivity === "portal"
        || (NetworkService.deviceState === "connected"
            && NetworkService.connectivity === "none")
    readonly property bool connected: NetworkService.deviceState === "connected"
    readonly property color statusIconColor: IconAppearanceService.mode === "tint"
        ? IconAppearanceService.styledSymbolicColor()
        : (ThemeService.isDark ? ThemeService.foregroundColor : "#000000")
    readonly property real statusIconOpacity: IconAppearanceService.mode !== "color"
        ? IconAppearanceService.opacity : 1.0

    DockStatusSvgIcon {
        id: networkGlyph
        visible: NetworkService.connectionType === "ethernet"
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        source: Qt.resolvedUrl("../../assets/status-ethernet.svg")
        opacity: root.connected ? 0.96 : 0.68
    }

    WifiSignalIcon {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 2
        visible: NetworkService.connectionType !== "ethernet"
        width: root.iconSize
        height: root.iconSize
        wifiEnabled: NetworkService.wifiEnabled
        connected: root.connected
            && NetworkService.connectionType === "wifi"
        signalStrength: NetworkService.signalStrength
        glyphColor: root.statusIconColor
        opacity: root.statusIconOpacity * (root.connected ? 0.96 : 0.68)
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: IconAppearanceService.mode !== "color"
                || ThemeService.isDark
            shadowColor: Qt.rgba(0, 0, 0, 0.82)
            shadowOpacity: 0.62
            shadowBlur: 0.32
            shadowVerticalOffset: 0.7
            shadowScale: 1.04
        }
    }

    Rectangle {
        // Preserve the connection medium icon and add only a tiny warning
        // badge; replacing it with a generic offline mark hides useful info.
        visible: root.hasIssue
        width: 6
        height: 6
        radius: width / 2
        anchors { right: parent.right; bottom: parent.bottom }
        color: NetworkService.connectivity === "none" ? "#ff9f0a" : "#ffb340"
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.35)
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.panelToggleRequested()
    }

    PopupWindow {
        id: tooltip
        visible: hoverArea.containsMouse && !root.sharedPanelOpen

        Connections {
            target: ScreenLifecycle
            function onOutputAvailableChanged() {
                if (!ScreenLifecycle.outputAvailable)
                    tooltip.visible = false
            }
        }
        implicitWidth: Math.max(150, tooltipColumn.implicitWidth + 18)
        implicitHeight: tooltipColumn.implicitHeight + 14
        color: "transparent"
        anchor {
            item: root
            edges: !root.dockHosted ? Edges.Bottom
                : root.dockEdge === "left" ? Edges.Right
                : root.dockEdge === "right" ? Edges.Left : Edges.Top
            gravity: !root.dockHosted ? Edges.Bottom
                : root.dockEdge === "left" ? Edges.Right
                : root.dockEdge === "right" ? Edges.Left : Edges.Top
            margins.top: root.dockHosted
                && root.dockEdge === "bottom" ? -6 : 0
            margins.bottom: root.dockHosted ? 0 : -6
            margins.left: root.dockHosted
                && root.dockEdge === "right" ? -6 : 0
            margins.right: root.dockHosted
                && root.dockEdge === "left" ? -6 : 0
        }

        Rectangle {
            anchors.fill: parent
            radius: 7
            color: ThemeService.tooltipBackground
            Column {
                id: tooltipColumn
                anchors.centerIn: parent
                spacing: 3
                Text {
                    text: root.connected
                        ? (NetworkService.connectionType === "ethernet"
                            ? "有线网络" : (NetworkService.ssid || "Wi‑Fi"))
                        : (NetworkService.deviceState === "connecting"
                            ? "正在连接网络…" : "未连接网络")
                    color: ThemeService.foregroundColor
                    style: Text.Outline
                    styleColor: Qt.rgba(0, 0, 0, 0.38)
                    font { pixelSize: 12; weight: Font.DemiBold }
                }
                Text {
                    visible: root.connected
                    text: root.hasIssue
                        ? (NetworkService.connectivity === "portal"
                            ? "需要网页登录认证" : "网络受限，无法访问互联网")
                        : (NetworkService.ipv4.length > 0
                            ? "已连接 · " + NetworkService.ipv4 : "已连接互联网")
                    color: ThemeService.foregroundColor
                    opacity: 0.66
                    font.pixelSize: 10
                }
            }
        }
    }

}
