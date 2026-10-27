import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../../shared/qml/i18n"
import "BatteryData.mjs" as BatteryData
import "networktraffic"
import qs.desktop.modules.common

// Stats' Battery dashboard/sections, adapted to Linux power_supply telemetry.
// See battery/Stats-LICENSE for the upstream design attribution and license.
// The mode selector stays visible while the battery details scroll.
Item {
    id: body
    property var battery: null
    property bool batteryPowered: false
    property var hardware: ({})
    property color ink: "white"
    property color mutedInk: Qt.rgba(1, 1, 1, 0.7)
    property bool dark: true
    readonly property bool hasBattery: !!battery && battery.ready && battery.isPresent && battery.isLaptopBattery
    readonly property bool charging: hasBattery && battery.state === UPowerDeviceState.Charging
    readonly property bool pluggedIn: hasBattery && !batteryPowered
    readonly property real level: hasBattery ? Math.max(0, Math.min(1, battery.percentage)) : 0
    readonly property var detail: BatteryData.summary(hardware.batteries, hardware.complete !== false)
    readonly property real fullCapacity: Number.isFinite(detail.full) ? detail.full
        : hasBattery && detail.unit === "Wh" && battery.energyCapacity > 0 ? battery.energyCapacity : NaN
    readonly property real health: Number.isFinite(detail.health) ? detail.health
        : hasBattery && battery.healthSupported ? battery.healthPercentage : -1
    readonly property color statusColor: !hasBattery ? mutedInk : level <= 0.15 && batteryPowered ? "#ff453a"
        : pluggedIn ? "#30c85a" : mutedInk
    readonly property color fillColor: level <= 0.15 && batteryPowered ? "#ff453a"
        : level <= 0.2 && batteryPowered ? "#ffcc00" : "#30c85a"
    readonly property string statusText: !hasBattery ? I18n.tr("No battery detected")
        : charging ? I18n.tr("Charging")
        : battery.state === UPowerDeviceState.FullyCharged ? I18n.tr("Fully charged")
        : battery.state === UPowerDeviceState.PendingCharge ? I18n.tr("On hold")
        : battery.state === UPowerDeviceState.Unknown ? I18n.tr("Unknown")
        : batteryPowered ? I18n.tr("On battery") : I18n.tr("Plugged in")
    readonly property string timeText: !hasBattery ? "—"
        : battery.state === UPowerDeviceState.FullyCharged ? I18n.tr("Fully charged")
        : battery.state === UPowerDeviceState.PendingCharge ? I18n.tr("On hold")
        : batteryPowered ? runtimeText
        : charging ? duration(battery.timeToFull) : "—"
    readonly property var runtimeSeconds: hasBattery && batteryPowered
        ? BatteryData.estimateRuntime(battery.timeToEmpty, battery.energy,
            battery.changeRate > 0 ? battery.changeRate : detail.powerWatts) : null
    readonly property string runtimeText: !hasBattery ? "—"
        : !batteryPowered ? I18n.tr("Unplug to estimate")
        : runtimeSeconds === null ? I18n.tr("Calculating…")
        : runtimeSeconds < 60 ? I18n.tr("Less than 1 min") : duration(runtimeSeconds)
    readonly property var modes: [
        {key: "power-saver", title: I18n.tr("Power Saver"), detail: I18n.tr("Reduce energy use and extend battery life")},
        {key: "balanced", title: I18n.tr("Balanced"), detail: I18n.tr("Balance responsiveness and energy use")},
        {key: "performance", title: I18n.tr("Performance"), detail: I18n.tr("Prioritize performance with higher energy use")}
    ]
    readonly property string modeDescription: modes.find(mode => mode.key === PowerProfileService.activeProfile)?.detail || ""
    implicitHeight: 42 + scroll.contentHeight + footer.implicitHeight
    signal closeRequested()

    function duration(seconds) {
        if (!(Number.isFinite(seconds) && seconds > 0)) return I18n.tr("Calculating…")
        const minutes = Math.ceil(seconds / 60)
        return I18n.tr("%1 h %2 min").arg(Math.floor(minutes / 60)).arg(minutes % 60)
    }
    function measured(value, unit, decimals) { return BatteryData.measurement(value, unit, decimals) }
    function adapterPower(adapter) {
        const actual = adapter.powerWatts, rated = adapter.ratedPowerWatts
        if (Number.isFinite(actual) && Number.isFinite(rated))
            return measured(Math.abs(actual), "W", 2) + " / " + measured(rated, "W", 0)
        if (Number.isFinite(actual)) return measured(Math.abs(actual), "W", 2)
        if (Number.isFinite(rated)) return I18n.tr("%1 W rated").arg(rated.toFixed(0))
        return "—"
    }

    component Section: TrafficSection {
        width: parent.width
        ink: body.ink
        dark: body.dark
    }
    component Field: TrafficFieldRow {
        width: parent.width
        ink: body.ink
        mutedInk: body.mutedInk
    }

    Item {
        id: header
        width: parent.width
        height: 42
        // Same small module glyph and centered heading as the traffic panel.
        Item {
            x: 10; anchors.verticalCenter: parent.verticalCenter
            width: 15; height: 10
            Rectangle {
                width: 13; height: 9; radius: 2
                color: "transparent"; border.width: 1; border.color: body.mutedInk
                Rectangle { x: 2; y: 2; width: 7; height: 5; radius: 1; color: body.mutedInk }
            }
            Rectangle { x: 14; y: 3; width: 1; height: 3; color: body.mutedInk }
        }
        Text {
            objectName: "battery-heading"
            anchors.centerIn: parent
            width: parent.width - 68
            text: I18n.tr("Battery")
            color: body.ink
            font { pixelSize: 14; weight: Font.DemiBold }
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
        TrafficActionButton {
            objectName: "battery-close"
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            width: 22; height: 22; glyphSize: 12
            kind: "close"; ink: body.mutedInk
            onClicked: body.closeRequested()
        }
    }

    Flickable {
        id: scroll
        objectName: "battery-details-scroll"
        anchors { top: header.bottom; bottom: footer.top; left: parent.left; right: parent.right }
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: content
            x: 8
            width: scroll.width - 16
            Item {
                objectName: "battery-dashboard"
                width: parent.width
                height: 160
                Item {
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 18 }
                    width: 120; height: 58
                    Rectangle {
                        id: batteryOutline
                        width: 112; height: 55; radius: 16
                        color: "transparent"
                        border { width: 1.5; color: body.mutedInk }
                        Rectangle {
                            x: 4; y: 4; height: parent.height - 8
                            width: (parent.width - 8) * body.level
                            radius: 12
                            color: body.fillColor
                        }
                        Item {
                            visible: body.pluggedIn
                            anchors.centerIn: parent
                            width: 32; height: 26
                            // Power plug, drawn in QML to avoid a font dependency.
                            Rectangle { x: 10; y: 7; width: 15; height: 12; radius: 4; color: "white" }
                            Rectangle { x: 22; y: 6; width: 5; height: 3; radius: 1; color: "white" }
                            Rectangle { x: 22; y: 17; width: 5; height: 3; radius: 1; color: "white" }
                            Rectangle { x: 4; y: 11; width: 10; height: 4; radius: 2; color: "white" }
                        }
                    }
                    Rectangle { x: 115; y: 17; width: 4; height: 21; radius: 2; color: body.mutedInk }
                }
                Row {
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 87 }
                    spacing: 2
                    Text {
                        id: percentageNumber
                        objectName: "battery-percentage"
                        text: body.hasBattery ? Math.round(body.level * 100) : "—"
                        color: body.ink
                        font { pixelSize: 28; weight: Font.Medium }
                    }
                    Text {
                        visible: body.hasBattery
                        text: "%"; color: body.mutedInk
                        font { pixelSize: 16; weight: Font.Medium }
                        anchors.baseline: percentageNumber.baseline
                    }
                }
                Rectangle {
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 125 }
                    width: Math.min(parent.width, statusLabel.implicitWidth + 16); height: 21; radius: 7
                    color: Qt.rgba(body.statusColor.r, body.statusColor.g, body.statusColor.b, 0.15)
                    Text {
                        id: statusLabel
                        objectName: "battery-status"
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        text: body.statusText; color: body.statusColor
                        font { pixelSize: 11; weight: Font.DemiBold }
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }
            Section { title: I18n.tr("Details") }
            Field {
                title: I18n.tr("Source:")
                value: body.batteryPowered ? I18n.tr("Battery") : I18n.tr("AC power")
                valueObjectName: "battery-source"
            }
            Field {
                title: I18n.tr("Estimated runtime:")
                value: body.runtimeText
                valueObjectName: "battery-runtime"
            }
            Field {
                visible: !body.batteryPowered
                title: I18n.tr("Time to charge:")
                value: body.timeText
                valueObjectName: "battery-time"
            }
            Column {
                width: parent.width
                visible: body.hasBattery
                Section { title: I18n.tr("Battery") }
                Item {
                    objectName: "battery-capacity"
                    width: parent.width; height: 50
                    Column {
                        spacing: 2
                        Text { text: I18n.tr("Max capacity"); color: body.mutedInk; font.pixelSize: 9 }
                        Text {
                            objectName: "battery-full-capacity"
                            text: body.measured(body.fullCapacity, body.detail.unit, body.detail.unit === "mAh" ? 0 : 2)
                            color: body.ink; font.pixelSize: 11
                        }
                    }
                    Column {
                        anchors.right: parent.right
                        spacing: 2
                        Text { anchors.right: parent.right; text: I18n.tr("Design capacity"); color: body.mutedInk; font.pixelSize: 9 }
                        Text {
                            objectName: "battery-design-capacity"
                            anchors.right: parent.right
                            text: body.measured(body.detail.design, body.detail.unit, body.detail.unit === "mAh" ? 0 : 2)
                            color: body.ink; font.pixelSize: 11
                        }
                    }
                    Rectangle {
                        objectName: "battery-health-bar"
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 8 }
                        height: 8; radius: 2
                        color: Qt.rgba(body.ink.r, body.ink.g, body.ink.b, 0.10)
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, body.health))
                            height: parent.height; radius: parent.radius
                            color: body.health < 0.6 ? "#ff453a" : body.health < 0.8 ? "#ffcc00" : "#30c85a"
                        }
                    }
                }
                Field {
                    title: I18n.tr("Power:")
                    value: body.measured(Number.isFinite(body.detail.powerWatts) ? body.detail.powerWatts
                        : body.hasBattery ? body.battery.changeRate : null, "W", 2)
                    valueObjectName: "battery-power"
                }
                Field { title: I18n.tr("Current:"); value: body.measured(body.detail.currentMa, "mA", 0) }
                Field { title: I18n.tr("Voltage:"); value: body.measured(body.detail.voltage, "V", 2) }
                Field { title: I18n.tr("Health:"); value: body.health >= 0 ? Math.round(body.health * 100) + "%" : "—" }
                Field { title: I18n.tr("Cycles:"); value: Number.isFinite(body.detail.cycles) ? String(body.detail.cycles) : "—" }
                Field { title: I18n.tr("Temperature:"); value: body.measured(body.detail.temperature, "°C", 1) }
            }
            Column {
                objectName: "battery-adapter-section"
                width: parent.width
                visible: !body.batteryPowered
                Section { title: I18n.tr("Power adapter") }
                Item {
                    width: parent.width; height: 22
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Is charging:"); color: body.mutedInk; font.pixelSize: 12
                    }
                    Rectangle {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: Math.max(44, chargingLabel.implicitWidth + 14); height: 16; radius: 4
                        color: body.charging ? "#30c85a" : "#ff453a"
                        Text {
                            id: chargingLabel
                            objectName: "battery-charging-badge"
                            anchors.centerIn: parent
                            text: body.charging ? I18n.tr("Yes") : I18n.tr("No")
                            color: "white"; font { pixelSize: 10; weight: Font.DemiBold }
                        }
                    }
                }
                Repeater {
                    model: body.hardware.adapters?.length ? body.hardware.adapters : [{}]
                    delegate: Column {
                        required property var modelData
                        required property int index
                        width: parent.width
                        Section {
                            visible: body.hardware.adapters?.length > 1
                            title: modelData.name || "—"
                        }
                        Field {
                            title: I18n.tr("Power:")
                            value: body.adapterPower(modelData)
                            valueObjectName: index === 0 ? "battery-adapter-power" : "battery-adapter-power-" + index
                        }
                        Field { title: I18n.tr("Current:"); value: body.measured(modelData.currentMa, "mA", 0) }
                        Field { title: I18n.tr("Voltage:"); value: body.measured(modelData.voltage, "V", 2) }
                    }
                }
            }
            Item { width: 1; height: 10 }
        }
    }

    Column {
        id: footer
        objectName: "battery-power-modes"
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 8; rightMargin: 8; bottomMargin: 8 }
        spacing: 0
        Section { title: I18n.tr("Power mode") }
        RowLayout {
            width: parent.width
            spacing: 4
            Repeater {
                model: body.modes
                delegate: Rectangle {
                    id: modeTile
                    required property var modelData
                    readonly property bool supported: PowerProfileService.profiles.includes(modelData.key)
                    readonly property bool selected: PowerProfileService.activeProfile === modelData.key
                    objectName: "power-mode-" + modelData.key
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 7
                    color: selected ? Qt.rgba(0.19, 0.78, 0.35, 0.2)
                        : Qt.rgba(body.ink.r, body.ink.g, body.ink.b, modeHover.hovered ? 0.10 : 0.05)
                    border.width: selected ? 1 : 0
                    border.color: Qt.rgba(0.19, 0.78, 0.35, 0.65)
                    opacity: supported ? 1 : 0.35
                    Accessible.role: Accessible.Button
                    Accessible.name: modeTile.modelData.title
                    Accessible.checkable: true
                    Accessible.checked: selected
                    Accessible.onPressAction: if (modeTap.enabled) PowerProfileService.setProfile(modeTile.modelData.key)
                    Text {
                        anchors { fill: parent; leftMargin: 3; rightMargin: 3 }
                        text: modeTile.modelData.title
                        color: body.ink
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        font { pixelSize: 11; weight: modeTile.selected ? Font.DemiBold : Font.Normal }
                    }
                    HoverHandler { id: modeHover; cursorShape: modeTile.supported ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler {
                        id: modeTap
                        enabled: modeTile.supported && !PowerProfileService.loading && !PowerProfileService.changing
                        onTapped: PowerProfileService.setProfile(modeTile.modelData.key)
                    }
                }
            }
        }
        Text {
            width: parent.width
            topPadding: 8; bottomPadding: 2
            text: PowerProfileService.changing || PowerProfileService.pendingProfile ? I18n.tr("Changing power mode…")
                : PowerProfileService.loading && !PowerProfileService.profiles.length ? I18n.tr("Loading power modes…")
                : PowerProfileService.error || body.modeDescription
            wrapMode: Text.Wrap
            color: PowerProfileService.error ? "#ff6961" : body.mutedInk
            font.pixelSize: 10
        }
        Text {
            width: parent.width
            visible: PowerProfileService.degraded.length > 0
            text: I18n.tr("Performance is limited: %1").arg(PowerProfileService.degraded)
            wrapMode: Text.Wrap; color: body.mutedInk; font.pixelSize: 10
        }
    }
}
