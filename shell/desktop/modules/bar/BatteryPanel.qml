import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.platform

AnimatedPopupWindow {
    id: panel
    property Item anchorItem: null
    property bool dockHosted: false
    property string dockEdge: "bottom"
    // Injectable sources also let the isolated panel fixture cover battery states.
    property var battery: UPower.displayDevice
    property bool batteryPowered: UPower.onBattery
    property var hardware: ({})
    property bool hardwarePending: false
    property int hardwareGeneration: 0
    readonly property var targetScreen: anchorItem
        ? (anchorItem.QsWindow.window?.screen ?? ScreenLifecycle.activeScreen)
        : ScreenLifecycle.activeScreen
    implicitWidth: 280
    // Reserve a stable Wayland surface; changing charging state or mode help
    // only changes the card within it, never the mapped OpenGL allocation.
    implicitHeight: Math.min(780, Math.max(240, (targetScreen?.height ?? 900) - 80))
    readonly property real surfaceHeight: Math.min(batteryBody.implicitHeight + 8, height)
    mask: interactive ? panelInputRegion : panelEmptyRegion
    Region { id: panelInputRegion; item: panelSurface }
    Region { id: panelEmptyRegion }
    color: "transparent"
    grabFocus: interactive
    motionOrigin: !dockHosted ? Item.Top : dockEdge === "left" ? Item.Left : dockEdge === "right" ? Item.Right : Item.Bottom
    PopupAnchorBinding { popupAnchor: panel.anchor; sourceItem: panel.anchorItem }
    anchor {
        edges: !panel.dockHosted ? Edges.Bottom : panel.dockEdge === "left" ? Edges.Right : panel.dockEdge === "right" ? Edges.Left : Edges.Top
        gravity: !panel.dockHosted ? Edges.Bottom : panel.dockEdge === "left" ? Edges.Right : panel.dockEdge === "right" ? Edges.Left : Edges.Top
        adjustment: PopupAdjustment.Slide
    }
    BackgroundEffect.blurRegion: panel.visible && panel.revealProgress > 0
        && AppearanceTokens.surface.usesBackdrop ? surface.blurRegion : null
    function toggle(item) {
        if (requestedOpen) { close(); return }
        anchorItem = item
        PowerProfileService.refresh()
        show()
    }
    function close() { hide() }
    function refreshHardware() {
        if (!requestedOpen || hardwarePending || !PlatformClient.connected) return
        hardwarePending = true
        const generation = hardwareGeneration
        PlatformClient.request("power.battery", {}, function(response) {
            if (generation !== panel.hardwareGeneration) return
            panel.hardwarePending = false
            panel.hardware = response?.ok ? response.result : ({})
        })
    }
    onRequestedOpenChanged: {
        hardwareGeneration++
        hardwarePending = false
        if (requestedOpen) refreshHardware()
        else hardware = ({})
    }
    Timer {
        interval: 10000
        running: panel.requestedOpen && PlatformClient.connected
        repeat: true
        onTriggered: panel.refreshHardware()
    }
    Connections {
        target: PlatformClient
        function onConnectedChanged() {
            panel.hardwareGeneration++
            panel.hardwarePending = false
            panel.hardware = ({})
            if (PlatformClient.connected) panel.refreshHardware()
        }
    }
    onAnchorItemChanged: if (!anchorItem && requestedOpen) close()
    onClosed: if (requestedOpen) close()
    Connections {
        target: ScreenLifecycle
        function onOutputAvailableChanged() { if (!ScreenLifecycle.outputAvailable) panel.close() }
    }
    Connections {
        target: WindowService
        function onActiveWindowIdChanged() { if (panel.requestedOpen) panel.close() }
    }
    Connections {
        target: ContextMenuCoordinator
        function onActiveMenuChanged() { if (ContextMenuCoordinator.activeMenu) panel.close() }
    }
    Shortcut { sequence: "Escape"; enabled: panel.requestedOpen; onActivated: panel.close() }
    PanelWindow {
        objectName: "battery-dismissal-catcher"
        screen: panel.targetScreen
        visible: ScreenLifecycle.outputAvailable && panel.targetScreen !== null && panel.requestedOpen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-batterypanel-backdrop"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }
        MouseArea { anchors.fill: parent; onPressed: panel.close() }
    }
    Item {
        id: panelSurface
        objectName: "battery-panel-surface"
        anchors { left: parent.left; right: parent.right }
        y: panel.dockHosted && panel.dockEdge === "bottom" ? panel.height - height : 0
        height: panel.surfaceHeight
        LiquidGlassPanel {
            id: surface
            anchors.fill: parent
            radius: 16
            cornerExponent: AppearanceTokens.shape.cornerExponent
            maskContent: false
            baseColor: AppearanceTokens.colors.surfaceContainer
            surfaceOpacity: 1
            scrimEnabled: AppearanceTokens.surface.usesBackdrop
            scrimLevel: AppearanceTokens.bar.popupScrimLevel
        }
        BatteryBody {
            id: batteryBody
            objectName: "battery-panel-body"
            anchors.fill: parent
            battery: panel.battery
            batteryPowered: panel.batteryPowered
            hardware: panel.hardware
            ink: surface.foregroundColor
            mutedInk: surface.secondaryForegroundColor
            dark: AppearanceTokens.isDarkTheme
            onCloseRequested: panel.close()
        }
    }
}
