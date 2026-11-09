import Quickshell
import Quickshell.Services.UPower
import QtQuick
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
    // The bar text carries a Text.Outline edge so it holds over a bright
    // backdrop; the battery is drawn from QML rectangles, which have no text
    // style, so the same edge comes from a shadow layer instead. The mac-style ground
    // paints a plate under the glyph, so the edge is dropped there.
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

    Rectangle {
        id: outline
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
        }
        width: Math.max(12, root.iconSize - 2)
        height: Math.max(8, Math.round(root.iconSize * 0.56))
        radius: 3
        color: "transparent"
        border {
            width: 1.5
            color: root.dockTintColor
        }
    }

    Rectangle {
        anchors {
            left: outline.right
            verticalCenter: outline.verticalCenter
        }
        width: Math.max(1.5, root.iconSize - outline.width)
        height: Math.max(3, root.iconSize * 0.20)
        radius: 1
        color: root.dockTintColor
    }

    Rectangle {
        visible: !root.isCharging
        anchors {
            left: outline.left
            verticalCenter: outline.verticalCenter
            leftMargin: 2
        }
        width: batteryDevice.ready && root.percent > 0
            ? Math.max(2, (outline.width - 4) * root.level)
            : 0
        height: outline.height - 4
        radius: 2
        color: root.fillColor
    }

    BundledIcon {
        anchors.centerIn: outline
        visible: root.isCharging
        name: "status-battery-charging"
        color: root.boltColor
        width: Math.max(7, root.iconSize * 0.44)
        height: width
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
