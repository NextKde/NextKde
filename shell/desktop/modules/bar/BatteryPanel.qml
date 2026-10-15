import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import "../../../shared/qml/i18n"
import qs.desktop.modules.common
import qs.desktop.modules.dock

AnimatedPopupWindow {
    id: panel
    property Item anchorItem: null
    property bool dockHosted: false
    property string dockEdge: "bottom"
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery.ready && battery.isPresent && battery.isLaptopBattery
    readonly property bool charging: hasBattery && (battery.state === UPowerDeviceState.Charging
        || battery.state === UPowerDeviceState.PendingCharge)
    readonly property var targetScreen: ScreenLifecycle.activeScreen
    readonly property color ink: surface.foregroundColor
    readonly property color mutedInk: surface.secondaryForegroundColor
    readonly property color accent: AppearanceTokens.colors.primary
    readonly property var modes: [
        {key: "power-saver", title: I18n.tr("Power Saver"), detail: I18n.tr("Reduce energy use and extend battery life")},
        {key: "balanced", title: I18n.tr("Balanced"), detail: I18n.tr("Balance responsiveness and energy use")},
        {key: "performance", title: I18n.tr("Performance"), detail: I18n.tr("Prioritize performance with higher energy use")}
    ]
    readonly property string modeDescription: modes.find(mode => mode.key === PowerProfileService.activeProfile)?.detail || ""
    implicitWidth: 348
    implicitHeight: Math.min(content.implicitHeight + 36, Math.max(240, (targetScreen?.height ?? 900) - 100))
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
    function tint(color, alpha) { return Qt.rgba(color.r, color.g, color.b, alpha) }
    function duration(seconds) {
        const minutes = Math.ceil(seconds / 60)
        return I18n.tr("%1 h %2 min").arg(Math.floor(minutes / 60)).arg(minutes % 60)
    }
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
        objectName: "battery-panel-surface"
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
        objectName: "battery-panel-body"
        anchors { fill: parent; margins: 20 }
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ColumnLayout {
            id: content
            width: parent.width
            spacing: 18
            RowLayout {
                Layout.fillWidth: true
                Text { text: I18n.tr("Battery"); color: panel.ink; font { pixelSize: 14; weight: Font.DemiBold } Layout.fillWidth: true }
                Item {
                    width: 28; height: 28
                    StatusPanelGlyph { anchors.centerIn: parent; kind: "close"; ink: panel.mutedInk; width: 18; height: 18 }
                    TapHandler { onTapped: panel.close() }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 20
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        text: panel.hasBattery ? Math.round(panel.battery.percentage * 100) + "%" : I18n.tr("AC power")
                        color: panel.ink
                        font { pixelSize: 36; weight: Font.DemiBold }
                    }
                    Text {
                        text: !panel.hasBattery ? I18n.tr("No battery detected") : panel.charging ? I18n.tr("Charging")
                            : panel.battery.state === UPowerDeviceState.FullyCharged ? I18n.tr("Fully charged") : I18n.tr("On battery")
                        color: panel.mutedInk
                        font.pixelSize: 12
                    }
                }
                Item {
                    visible: panel.hasBattery
                    Layout.preferredWidth: 70; Layout.preferredHeight: 36
                    Rectangle {
                        width: 64; height: 34; radius: 9
                        color: "transparent"; border.width: 2; border.color: panel.mutedInk
                        Rectangle {
                            x: 5; y: 5; height: 24; radius: 5
                            width: 54 * Math.max(0, Math.min(1, panel.battery.percentage))
                            color: panel.battery.percentage < 0.2 ? "#f06b65" : panel.accent
                        }
                    }
                    Rectangle { x: 66; y: 11; width: 4; height: 12; radius: 2; color: panel.mutedInk }
                }
            }
            ColumnLayout {
                visible: timeText.visible || healthText.visible
                spacing: 5
                Text {
                    id: timeText
                    visible: panel.hasBattery && (panel.charging ? panel.battery.timeToFull : panel.battery.timeToEmpty) > 0
                    text: panel.charging ? I18n.tr("Full in %1").arg(panel.duration(panel.battery.timeToFull))
                        : I18n.tr("About %1 remaining").arg(panel.duration(panel.battery.timeToEmpty))
                    color: panel.mutedInk; font.pixelSize: 11
                }
                Text {
                    id: healthText
                    visible: panel.hasBattery && panel.battery.healthSupported
                    text: I18n.tr("Battery health · %1%").arg(Math.round(panel.battery.healthPercentage * 100))
                    color: panel.mutedInk; font.pixelSize: 11
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: panel.tint(panel.ink, 0.08) }
            Text { text: I18n.tr("Power mode"); color: panel.mutedInk; font { pixelSize: 11; weight: Font.Medium } }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: panel.modes
                    delegate: Rectangle {
                        id: modeTile
                        required property var modelData
                        readonly property bool supported: PowerProfileService.profiles.includes(modelData.key)
                        readonly property bool selected: PowerProfileService.activeProfile === modelData.key
                        readonly property bool pending: PowerProfileService.pendingProfile === modelData.key
                        objectName: "power-mode-" + modelData.key
                        Layout.fillWidth: true
                        Layout.preferredHeight: 78
                        radius: 14
                        color: selected ? panel.tint(panel.accent, 0.14) : panel.tint(panel.ink, modeHover.hovered ? 0.08 : 0.04)
                        border.width: selected ? 1 : 0
                        border.color: panel.tint(panel.accent, 0.55)
                        opacity: supported ? 1 : 0.35
                        Column {
                            anchors.centerIn: parent
                            spacing: 8
                            StatusPanelGlyph {
                                width: 22; height: 22
                                anchors.horizontalCenter: parent.horizontalCenter
                                kind: modeTile.modelData.key
                                ink: modeTile.selected ? panel.accent : panel.ink
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modeTile.modelData.title
                                color: modeTile.selected ? panel.accent : panel.ink
                                font { pixelSize: 11; weight: Font.Medium }
                            }
                        }
                        StatusPanelGlyph {
                            visible: modeTile.selected
                            anchors { right: parent.right; top: parent.top; margins: 5 }
                            width: 12; height: 12; kind: "check"; ink: panel.accent
                        }
                        HoverHandler { id: modeHover; cursorShape: modeTile.supported ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler {
                            enabled: modeTile.supported && !PowerProfileService.loading && !PowerProfileService.changing
                            onTapped: PowerProfileService.setProfile(modeTile.modelData.key)
                        }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                Layout.minimumHeight: 28
                text: PowerProfileService.changing || PowerProfileService.pendingProfile ? I18n.tr("Changing power mode…")
                    : PowerProfileService.loading && !PowerProfileService.profiles.length ? I18n.tr("Loading power modes…")
                    : PowerProfileService.error || panel.modeDescription
                wrapMode: Text.Wrap
                color: PowerProfileService.error ? "#ef827b" : panel.mutedInk
                font.pixelSize: 11
            }
            Text {
                Layout.fillWidth: true
                visible: PowerProfileService.degraded.length > 0
                text: I18n.tr("Performance is limited: %1").arg(PowerProfileService.degraded)
                wrapMode: Text.Wrap; color: panel.mutedInk; font.pixelSize: 11
            }
        }
    }
    }
}
