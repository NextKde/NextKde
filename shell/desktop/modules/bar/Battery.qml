import Quickshell
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Effects
import qs.desktop.modules.dock
import qs.desktop.modules.common

// Compact battery indicator with charging-state colours and hover details.
Item {
    id: root

    property bool dockHosted: false
    property string dockEdge: "bottom"
    property bool verticalDock: false
    property real iconSize: 18
    rotation: verticalDock ? -90 : 0
    readonly property bool tintActive: IconAppearanceService.mode === "tint"
    readonly property color dockTintColor: tintActive
        ? IconAppearanceService.styledSymbolicColor()
        : ThemeService.foregroundColor
    opacity: tintActive ? IconAppearanceService.opacity : 1.0
    layer.enabled: tintActive
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.82)
        shadowOpacity: 0.62
        shadowBlur: 0.32
        shadowVerticalOffset: 0.7
        shadowScale: 1.04
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

    Text {
        anchors.centerIn: outline
        visible: root.isCharging
        text: "⚡"
        color: root.boltColor
        font.pixelSize: Math.max(7, root.iconSize * 0.44)
        font.bold: true
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
    }

    PopupWindow {
        id: tooltip
        visible: hoverArea.containsMouse && batteryDevice.ready
        implicitWidth: tooltipText.implicitWidth + 16
        implicitHeight: tooltipText.implicitHeight + 10
        color: "transparent"

        Connections {
            target: ScreenLifecycle
            function onOutputAvailableChanged() {
                if (!ScreenLifecycle.outputAvailable)
                    tooltip.visible = false
            }
        }
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
            radius: 6
            color: ThemeService.tooltipBackground

            Text {
                id: tooltipText
                anchors.centerIn: parent
                text: root.isCharging
                    ? "充电中 · " + root.percent + "%"
                    : "电池 · " + root.percent + "%"
                color: ThemeService.foregroundColor
                font {
                    family: "Noto Sans CJK SC"
                    pixelSize: 12
                    weight: Font.DemiBold
                }
            }
        }
    }

    readonly property var batteryDevice: UPower.displayDevice
    readonly property real level: batteryDevice.ready
        ? Math.max(0, Math.min(1, batteryDevice.percentage))
        : 0
    readonly property int percent: Math.round(level * 100)
    readonly property bool isCharging: batteryDevice.ready
        && (batteryDevice.state === UPowerDeviceState.Charging
            || batteryDevice.state === UPowerDeviceState.PendingCharge)
    readonly property color fillColor: tintActive ? dockTintColor
        : percent > 95
        ? "#30d158"
        : percent >= 50
            ? ThemeService.foregroundColor
            : percent >= 15
                ? "#ff9f0a"
                : "#ff453a"
    readonly property color boltColor: tintActive ? dockTintColor
        : percent >= 50 && percent <= 95
        ? "#ff9f0a" : ThemeService.foregroundColor
}
