import QtQuick
import qs.desktop.modules.common

// Reusable system-status cluster. Popup panels stay anchored to the same
// visual items whether this component lives in BarWindow or inside Dock.
Item {
    id: root

    implicitWidth: statusArea.implicitWidth
    implicitHeight: 24
    width: implicitWidth
    height: implicitHeight
    property bool dockHosted: false
    property string dockEdge: "bottom"
    // Reveal progress of the auto-hiding Bar this cluster lives in. 1 for a
    // cluster that is not inside a sliding Bar (the Dock host) and for a Bar
    // that is permanently visible.
    property real barRevealProgress: 1
    readonly property bool contextualEditingAvailable: !dockHosted
    readonly property bool verticalDock: dockHosted && dockEdge !== "bottom"
    // DockContainer uses this stable, single-row maximum for its width solver.
    // The visible tray may then fold to two rows without feeding a discrete
    // row-count change back into the Dock height calculation.
    readonly property real layoutMaximumWidth: systemTray.singleRowImplicitWidth

    // The shell-owned cells, paired with the component that renders each one.
    // One table feeds both the rendered components and their reorder keys, so a
    // hidden cell can never desynchronise the two lists. Reading the persisted
    // hidden set here is what makes the Settings switch take effect live.
    readonly property var trailingCells: [
        { key: "temperature", component: temperatureQuickControl },
        { key: "traffic", component: trafficQuickControl },
        { key: "network", component: networkQuickControl },
        { key: "battery", component: batteryQuickControl },
        { key: "settings", component: settingsQuickControl },
        { key: "notifications", component: notificationQuickControl },
        { key: "controlcenter", component: controlCenterQuickControl }
    ]
    readonly property var visibleTrailingCells: trailingCells.filter(
        entry => !AppearanceConfigService.isStatusCellHidden(entry.key)
            && (entry.key !== "temperature" || (!root.dockHosted
                && MetricsService.currentMilliC >= 0
                && MetricsService.maximum5MinuteMilliC >= 0))
            && (entry.key !== "traffic" || (!root.dockHosted
                && NetworkService.available && NetworkService.deviceState === "connected")))

    property Item pendingControlCenterAnchor: null
    readonly property var controlCenter: controlCenterLoader.item
    readonly property bool controlCenterOpen: pendingControlCenterAnchor !== null
        || (controlCenter?.isOpen ?? false)
    readonly property bool anyPanelOpen: (networkPanel?.requestedOpen ?? false)
        || (bluetoothPanel?.requestedOpen ?? false) || root.controlCenterOpen
        || notificationPanel.requestedOpen || trafficPanel.requestedOpen || batteryPanel.requestedOpen

    // Report panel visibility into the service singleton so its fast refresh
    // only runs while a panel is actually showing the data. A count (not a
    // flag) keeps multiple BarStatusArea instances — standalone Bar plus
    // Dock host, or several outputs — from releasing each other's panels.
    property bool _panelOpenRegistered: false
    onAnyPanelOpenChanged: {
        if (anyPanelOpen === _panelOpenRegistered)
            return
        _panelOpenRegistered = anyPanelOpen
        ControlCenterService.notePanelOpen(anyPanelOpen)
    }
    Component.onDestruction: {
        if (_panelOpenRegistered)
            ControlCenterService.notePanelOpen(false)
    }

    function toggleControlCenter(anchorItem) {
        trafficPanel.close()
        batteryPanel.close()
        if (controlCenterOpen) {
            closeControlCenter()
            return
        }
        notificationPanel.close()
        if (controlCenter)
            controlCenter.toggle(anchorItem)
        else
            pendingControlCenterAnchor = anchorItem
    }

    function closeControlCenter() {
        pendingControlCenterAnchor = null
        if (controlCenter)
            controlCenter.close()
    }

    // Remote session entries (desktop context menu) open the panel anchored
    // to the control-center cell and drop the user straight into the shared
    // confirmation dialog, exactly like choosing the entry in the panel.
    property string pendingSessionAction: ""
    function presentSessionConfirmation(action) {
        notificationPanel.close()
        if (controlCenter) {
            if (!controlCenter.isOpen)
                controlCenter.toggle(controlCenterAnchor())
            controlCenter.runSessionAction(action)
        } else {
            pendingSessionAction = action
            pendingControlCenterAnchor = controlCenterAnchor()
        }
    }
    Connections {
        target: ControlCenterService
        function onSessionActionRequested(action) { root.presentSessionConfirmation(action) }
    }

    // Both panels anchor by cell key, never by rendered index: hiding a cell
    // shifts the indices of everything after it, so an index-based lookup would
    // anchor the WiFi popup to the battery glyph once network was hidden.
    // A hidden cell yields null, and every caller already handles an absent
    // anchor by falling back to a fixed position.
    function networkStatusAnchor() {
        return systemTray.trailingItemForKey("network")?.control ?? null
    }

    function controlCenterAnchor() {
        return systemTray.trailingItemForKey("controlcenter")?.control ?? null
    }

    Component {
        id: networkQuickControl
        Item {
            readonly property alias control: networkStatus
            NetworkStatus {
                id: networkStatus
                anchors.centerIn: parent
                // The Wi-Fi glyph is a thin arc fan and the battery glyph is
                // a flat capsule; both read visually smaller than the filled
                // control-center mark at the same nominal box size, so they
                // get a bit more room within the shared tray slot.
                iconSize: systemTray.iconSize + 3
                dockHosted: root.dockHosted
                dockEdge: root.dockEdge
                verticalDock: root.verticalDock
                sharedPanelOpen: networkPanel.requestedOpen
                    || bluetoothPanel.requestedOpen || root.controlCenterOpen
                    || notificationPanel.requestedOpen
                onPanelToggleRequested: {
                    notificationPanel.close()
                    bluetoothPanel.close()
                    if (!networkPanel.requestedOpen)
                        root.closeControlCenter()
                    trafficPanel.close()
                    batteryPanel.close()
                    networkPanel.toggle(networkStatus)
                }
            }
        }
    }

    Component {
        id: temperatureQuickControl
        Item {
            readonly property real cellExtraWidth: Math.max(0,
                temperature.implicitWidth - systemTray.itemSize)
            CpuTemperature {
                id: temperature
                anchors.centerIn: parent
            }
        }
    }

    Component {
        id: trafficQuickControl
        Item {
            readonly property alias control: traffic
            readonly property real cellExtraWidth: Math.max(0,
                traffic.implicitWidth - systemTray.itemSize)
            NetworkTraffic {
                id: traffic
                anchors.centerIn: parent
                onPanelToggleRequested: {
                    notificationPanel.close()
                    bluetoothPanel.close()
                    networkPanel.close()
                    root.closeControlCenter()
                    batteryPanel.close()
                    trafficPanel.toggle(traffic)
                }
            }
        }
    }

    Component {
        id: batteryQuickControl
        Item {
            readonly property alias control: battery
            Battery {
                id: battery
                panelOpen: batteryPanel.requestedOpen
                onPanelToggleRequested: {
                    notificationPanel.close()
                    bluetoothPanel.close()
                    networkPanel.close()
                    trafficPanel.close()
                    root.closeControlCenter()
                    batteryPanel.toggle(battery)
                }
                anchors.centerIn: parent
                iconSize: systemTray.iconSize + 3
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
                iconSize: systemTray.iconSize
                dockHosted: root.dockHosted
                verticalDock: root.verticalDock
            }
        }
    }

    Component {
        id: notificationQuickControl
        Item {
            readonly property alias control: notificationToggle
            NotificationHistoryToggle {
                id: notificationToggle
                anchors.centerIn: parent
                iconSize: systemTray.iconSize
                panelOpen: notificationPanel.requestedOpen
                dockHosted: root.dockHosted
                dockEdge: root.dockEdge
                verticalDock: root.verticalDock
                onPanelToggleRequested: {
                    trafficPanel.close()
                    batteryPanel.close()
                    if (!notificationPanel.requestedOpen) {
                        networkPanel.close()
                        bluetoothPanel.close()
                        root.closeControlCenter()
                    }
                    notificationPanel.toggle(notificationToggle)
                }
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
                iconSize: systemTray.iconSize
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

    Row {
        id: statusArea
        anchors.centerIn: parent
        spacing: 10

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
                trailingComponents: root.visibleTrailingCells.map(entry => entry.component)
                trailingKeys: root.visibleTrailingCells.map(entry => entry.key)
            }
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        enabled: root.contextualEditingAvailable
        onTapped: statusAreaEditor.toggle(root)
    }

    StatusAreaEditor {
        id: statusAreaEditor
    }

    NotificationHistoryPanel {
        id: notificationPanel
        dockHosted: root.dockHosted
        dockEdge: root.dockEdge
    }
    BatteryPanel {
        id: batteryPanel
        dockHosted: root.dockHosted
        dockEdge: root.dockEdge
    }
    NetworkTrafficPanel {
        id: trafficPanel
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
        // Incubate once while idle; reopening must not rebuild the whole panel.
        active: true
        asynchronous: true
        onLoaded: {
            const anchor = root.pendingControlCenterAnchor
            if (anchor)
                item.toggle(anchor)
            root.pendingControlCenterAnchor = null
            if (root.pendingSessionAction !== "") {
                item.runSessionAction(root.pendingSessionAction)
                root.pendingSessionAction = ""
            }
        }
        onStatusChanged: if (status === Loader.Error) root.pendingControlCenterAnchor = null
        sourceComponent: Component {
            ControlCenterPanel {
                dockHosted: root.dockHosted
                dockEdge: root.dockEdge
                barRevealProgress: root.barRevealProgress
                onWifiNetworkSelected: function(network) {
                    networkPanel.showNetworkDialog(network)
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
