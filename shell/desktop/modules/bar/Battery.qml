import Quickshell
import Quickshell.Services.UPower
import QtQuick
import "../../../shared/Icons" as Symbols
import QtQuick.Effects
import "../../../shared/qml/i18n"
import qs.desktop.modules.dock
import qs.desktop.modules.common

// Compact battery indicator using the same monochrome ink as other status cells.
Item {
    id: root

    signal panelToggleRequested()
    property bool panelOpen: false
    property bool dockHosted: false
    property string dockEdge: "bottom"
    property bool verticalDock: false
    property real iconSize: 18
    rotation: verticalDock ? -90 : 0
    readonly property color dockTintColor: ThemeService.barInk
    // Keep the existing contrast treatment over the wallpaper.
    readonly property bool iconOutlined: AppearanceTokens.isDarkTheme && !AppearanceTokens.bar.macStyle
    layer.enabled: iconOutlined
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.40)
        shadowBlur: 0.22
    }

    implicitWidth: iconSize
    implicitHeight: iconSize
    width: implicitWidth
    height: implicitHeight

    Symbols.BatteryIcon {
        anchors.fill: parent
        level: root.batteryDevice.ready ? root.level : 0
        charging: root.isCharging
        color: root.dockTintColor
        fillColor: root.fillColor
        chargeColor: root.boltColor
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.panelToggleRequested()
    }

    StatusTooltip {
        anchorItem: root
        shown: hoverArea.containsMouse && batteryDevice.ready && !root.panelOpen
        dockHosted: root.dockHosted
        dockEdge: root.dockEdge
        primaryText: root.isCharging
            ? I18n.tr("Charging · %1%").arg(root.percent)
            : I18n.tr("Battery · %1%").arg(root.percent)
    }

    readonly property var batteryDevice: UPower.displayDevice
    readonly property real level: batteryDevice.ready
        ? Math.max(0, Math.min(1, batteryDevice.percentage))
        : 0
    readonly property int percent: Math.round(level * 100)
    readonly property bool isCharging: batteryDevice.ready
        && (batteryDevice.state === UPowerDeviceState.Charging
            || batteryDevice.state === UPowerDeviceState.PendingCharge)
    readonly property color fillColor: ThemeService.barInk
    readonly property color boltColor: ThemeService.barInk
}
