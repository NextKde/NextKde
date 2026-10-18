import QtQuick
import Quickshell.Services.UPower
import qs.desktop.modules.common
import "../common/VisibilityPolicy.mjs" as VisibilityPolicy

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
    readonly property bool collectionExpanded: systemTray.collectionExpanded
    readonly property bool statusDragActive: systemTray.draggedKey !== ""
    readonly property bool verticalDock: dockHosted && dockEdge !== "bottom"
    // DockContainer uses this stable, single-row maximum for its width solver.
    // The visible tray may then fold to two rows without feeding a discrete
    // row-count change back into the Dock height calculation.
    readonly property real layoutMaximumWidth: collectionSlot.width + cpuSlot.width
        + systemTray.singleRowImplicitWidth
        + statusArea.spacing * (cpuSlot.width > 0 ? 2 : 1)

    // The shell-owned cells, paired with the component that renders each one.
    // One table feeds both the rendered components and their reorder keys, so a
    // hidden cell can never desynchronise the two lists. Reading the persisted
    // hidden set here is what makes the Settings switch take effect live.
    readonly property var trailingCells: [
        { key: "network", component: networkQuickControl },
        { key: "battery", component: batteryQuickControl },
        { key: "settings", component: settingsQuickControl },
        { key: "notifications", component: notificationQuickControl },
        { key: "controlcenter", component: controlCenterQuickControl }
    ]
    // A desktop exposes a UPower DisplayDevice that is `ready` but has no
    // battery, so readiness alone cannot decide this — the tray used to draw a
    // 0% battery on battery-less machines. VisibilityPolicy owns the three-way
    // decision (unready = keep, ready without battery = hide) and is unit
    // tested, so an unready or unavailable UPower cannot hide a laptop's cell.
    readonly property bool showBatteryCell: VisibilityPolicy.shouldShowBatteryCell(
        UPower.displayDevice.ready, UPower.displayDevice.isPresent)
    readonly property var visibleTrailingCells: trailingCells.filter(
        entry => !AppearanceConfigService.isStatusCellHidden(entry.key)
            && (entry.key !== "battery" || root.showBatteryCell))

    property Item pendingControlCenterAnchor: null
    readonly property var controlCenter: controlCenterLoader.item
    readonly property bool controlCenterOpen: pendingControlCenterAnchor !== null
        || (controlCenter?.isOpen ?? false)
    readonly property bool anyPanelOpen: (networkPanel?.requestedOpen ?? false)
        || (bluetoothPanel?.requestedOpen ?? false) || root.controlCenterOpen
        || notificationPanel.requestedOpen

    readonly property bool keepBarOpen: anyPanelOpen || collectionExpanded || statusDragActive

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
    function closeCollectionOutside(x, y) { systemTray.closeCollectionOutside(x, y) }

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
            // The transfer-rate readout lives inside the network cell, left of
            // the Wi-Fi glyph, so native tray icons never come between them.
            // Exposing the overflow lets the grid widen this one cell (single
            // row only); the integrated Dock keeps its cell uniform because
            // the readout hides there per the cpuSlot visibility rule.
            readonly property real cellExtraWidth: networkTraffic.visible
                ? networkTraffic.implicitWidth + networkCell.spacing : 0
            Row {
                id: networkCell
                anchors.centerIn: parent
                spacing: 6
                NetworkStatus {
                    id: networkStatus
                    anchors.verticalCenter: parent.verticalCenter
                    // The Wi-Fi glyph is a thin arc fan and the battery glyph is
                    // a flat capsule; both read visually smaller than the filled
                    // control-center mark at the same nominal box size, so they
                    // get a bit more room within the shared tray slot.
                    iconSize: systemTray.iconSize + 3
                    dockHosted: root.dockHosted
                    dockEdge: root.dockEdge
                    verticalDock: root.verticalDock && !SysTrayOrderService.isCollected("cell:network")
                    sharedPanelOpen: networkPanel.requestedOpen
                        || bluetoothPanel.requestedOpen || root.controlCenterOpen
                        || notificationPanel.requestedOpen
                    onPanelToggleRequested: {
                        notificationPanel.close()
                        bluetoothPanel.close()
                        if (!networkPanel.requestedOpen)
                            root.closeControlCenter()
                        networkPanel.toggle(networkStatus)
                    }
                }
                NetworkTraffic {
                    id: networkTraffic
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.dockHosted && !SysTrayOrderService.isCollected("cell:network")
                        && NetworkService.available
                        && NetworkService.deviceState === "connected"
                    onPanelToggleRequested: networkStatus.panelToggleRequested()
                }
            }
        }
    }

    Component {
        id: batteryQuickControl
        Item {
            Battery {
                anchors.centerIn: parent
                iconSize: systemTray.iconSize + 3
                dockHosted: root.dockHosted
                dockEdge: root.dockEdge
                verticalDock: root.verticalDock && !SysTrayOrderService.isCollected("cell:battery")
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
                verticalDock: root.verticalDock && !SysTrayOrderService.isCollected("cell:settings")
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
                verticalDock: root.verticalDock && !SysTrayOrderService.isCollected("cell:notifications")
                onPanelToggleRequested: {
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
                verticalDock: root.verticalDock && !SysTrayOrderService.isCollected("cell:controlcenter")
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
            id: collectionSlot
            width: systemTray.itemSize
            height: root.height
        }
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
                collectionToggleHost: collectionSlot
                anchors.centerIn: parent
                iconSize: 18
                visualYOffset: 0
                dockHosted: root.dockHosted
                dockEdge: root.dockEdge
                verticalDock: root.verticalDock
                availableHeight: root.height
                collectionKeepOpen: root.anyPanelOpen
                onCollectionCollapseRequested: {
                    networkPanel.close()
                    bluetoothPanel.close()
                    notificationPanel.close()
                    root.closeControlCenter()
                }
                trailingComponents: root.visibleTrailingCells.map(entry => entry.component)
                trailingKeys: root.visibleTrailingCells.map(entry => entry.key)
            }
        }
    }

    NotificationHistoryPanel {
        id: notificationPanel
        dockHosted: root.dockHosted
        dockEdge: root.dockEdge
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
