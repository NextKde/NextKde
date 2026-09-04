import QtQuick

// Reusable system-status cluster. Popup panels stay anchored to the same
// visual items whether this component lives in BarWindow or inside Dock.
Item {
    id: root

    implicitWidth: statusArea.implicitWidth
    implicitHeight: 24
    property bool dockHosted: false
    property string dockEdge: "bottom"
    readonly property bool verticalDock: dockHosted && dockEdge !== "bottom"
    // DockContainer uses this stable, single-row maximum for its width solver.
    // The visible tray may then fold to two rows without feeding a discrete
    // row-count change back into the Dock height calculation.
    readonly property real layoutMaximumWidth: cpuSlot.width
        + systemTray.singleRowImplicitWidth
        + (cpuSlot.visible ? statusArea.spacing : 0)

    property bool controlCenterLoaded: false
    readonly property var controlCenter: controlCenterLoader.item
    readonly property bool controlCenterOpen: controlCenter?.isOpen ?? false
    readonly property bool anyPanelOpen: (networkPanel?.visible ?? false)
        || (bluetoothPanel?.visible ?? false) || root.controlCenterOpen

    function toggleControlCenter(anchorItem) {
        controlCenterUnloadTimer.stop()
        if (controlCenterOpen) {
            closeControlCenter()
            return
        }
        controlCenterLoaded = true
        Qt.callLater(function() {
            if (controlCenterLoaded && controlCenter
                    && !controlCenter.isOpen)
                controlCenter.toggle(anchorItem)
        })
    }

    function closeControlCenter() {
        if (controlCenter)
            controlCenter.close()
        if (controlCenterLoaded)
            controlCenterUnloadTimer.restart()
    }

    function networkStatusAnchor() {
        return systemTray.trailingItem(0)?.control ?? null
    }

    function controlCenterAnchor() {
        return systemTray.trailingItem(3)?.control ?? null
    }

    Component {
        id: networkQuickControl
        Item {
            readonly property alias control: networkStatus
            NetworkStatus {
                id: networkStatus
                anchors.centerIn: parent
                dockHosted: root.dockHosted
                dockEdge: root.dockEdge
                verticalDock: root.verticalDock
                sharedPanelOpen: networkPanel.visible
                    || bluetoothPanel.visible || root.controlCenterOpen
                onPanelToggleRequested: {
                    bluetoothPanel.close()
                    if (!networkPanel.visible)
                        root.closeControlCenter()
                    networkPanel.toggle(networkStatus)
                }
            }
        }
    }

    Component {
        id: batteryQuickControl
        Item {
            Battery {
                anchors.centerIn: parent
                dockHosted: root.dockHosted
                dockEdge: root.dockEdge
                verticalDock: root.verticalDock
            }
        }
    }

    Component {
        id: settingsQuickControl
        Item {
            SettingsButton {
                anchors.centerIn: parent
                dockHosted: root.dockHosted
                verticalDock: root.verticalDock
            }
        }
    }

    Component {
        id: controlCenterQuickControl
        Item {
            readonly property alias control: controlCenterToggle
            ControlCenterToggle {
                id: controlCenterToggle
                anchors.centerIn: parent
                panelOpen: root.controlCenterOpen
                dockHosted: root.dockHosted
                dockEdge: root.dockEdge
                verticalDock: root.verticalDock
                onPanelToggleRequested: {
                    bluetoothPanel.close()
                    if (!root.controlCenterOpen)
                        networkPanel.close()
                    root.toggleControlCenter(controlCenterToggle)
                }
            }
        }
    }

    Timer {
        id: controlCenterUnloadTimer
        interval: 180
        repeat: false
        onTriggered: {
            if (!root.controlCenterOpen)
                root.controlCenterLoaded = false
        }
    }

    Row {
        id: statusArea
        anchors.centerIn: parent
        spacing: 10

        Item {
            id: cpuSlot
            // In integrated mode the permanent Dock carousel temperature page
            // is the single compact entry. The standalone top Bar keeps this
            // summary and both views still consume MetricsService.
            visible: !root.dockHosted
            width: visible ? cpuTemperature.implicitWidth : 0
            height: root.height
            CpuTemperature {
                id: cpuTemperature
                anchors.centerIn: parent
                dockHosted: root.dockHosted
            }
        }
        Item {
            id: traySlot
            width: systemTray.implicitWidth
            height: root.height
            SysTray {
                id: systemTray
                anchors.centerIn: parent
                iconSize: 18
                visualYOffset: 0
                dockHosted: root.dockHosted
                dockEdge: root.dockEdge
                verticalDock: root.verticalDock
                availableHeight: root.height
                trailingComponents: [networkQuickControl, batteryQuickControl,
                    settingsQuickControl, controlCenterQuickControl]
            }
        }
    }

    NetworkPanel {
        id: networkPanel
        dockHosted: root.dockHosted
        dockEdge: root.dockEdge
    }
    BluetoothPanel {
        id: bluetoothPanel
        dockHosted: root.dockHosted
        dockEdge: root.dockEdge
    }
    Loader {
        id: controlCenterLoader
        active: root.controlCenterLoaded
        sourceComponent: Component {
            ControlCenterPanel {
                dockHosted: root.dockHosted
                dockEdge: root.dockEdge
                onNetworkRequested: {
                    root.closeControlCenter()
                    bluetoothPanel.close()
                    const anchor = root.networkStatusAnchor()
                    if (anchor)
                        networkPanel.open(anchor)
                }
                onBluetoothRequested: {
                    root.closeControlCenter()
                    const anchor = root.controlCenterAnchor()
                    if (anchor)
                        bluetoothPanel.open(anchor)
                }
            }
        }
    }

    Connections {
        target: ControlCenterService
        function onToggleRequested() {
            bluetoothPanel.close()
            if (!root.controlCenterOpen)
                networkPanel.close()
            const anchor = root.controlCenterAnchor()
            if (anchor)
                root.toggleControlCenter(anchor)
        }
    }
}
