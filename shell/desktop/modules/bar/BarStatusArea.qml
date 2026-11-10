import QtQuick
import Quickshell.Services.UPower
import qs.desktop.modules.common
import qs.desktop.modules.inputmethod
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
        { key: "inputmethod", component: inputMethodQuickControl },
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
        || notificationPanel.requestedOpen || trafficPanel.requestedOpen || batteryPanel.requestedOpen

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

    function closeDetailPanels() {
        trafficPanel.close()
        batteryPanel.close()
    }

    function toggleControlCenter(anchorItem) {
        closeDetailPanels()
        if (controlCenterOpen) {
            closeControlCenter()
            return
        }
        if (controlCenter && Date.now() < controlCenter._suppressToggleUntil)
            return
        notificationPanel.close()
        const placement = _panelPlacement(anchorItem)
        if (controlCenter) {
            _applyPlacement(controlCenter, placement)
            controlCenter.toggle(anchorItem)
        } else {
            pendingControlCenterAnchor = anchorItem
            pendingControlCenterPlacement = placement
        }
    }

    function closeControlCenter() {
        pendingControlCenterAnchor = null
        if (controlCenter)
            controlCenter.close()
    }

    // Persistent panels stay mapped, so they cannot rely on a popup anchor any
    // more. The host surface (Bar or Dock) knows where the cell sits, and the
    // panel is placed from that in screen coordinates.
    readonly property var targetScreen: ScreenLifecycle.activeScreen
    property var pendingControlCenterPlacement: null
    readonly property var hostWindow: Window.window
    function _hostOrigin() {
        const screen = targetScreen
        const win = hostWindow
        const sx = screen ? screen.x : 0
        const sy = screen ? screen.y : 0
        const sw = screen ? screen.width : 0
        const sh = screen ? screen.height : 0
        if (!win || !root.dockHosted)
            return Qt.point(sx, sy)
        if (root.dockEdge === "bottom")
            return Qt.point(sx, sy + sh - win.height)
        if (root.dockEdge === "right")
            return Qt.point(sx + sw - win.width, sy)
        return Qt.point(sx, sy)
    }
    function _panelPlacement(item) {
        const screen = targetScreen
        const sx = screen ? screen.x : 0
        const sy = screen ? screen.y : 0
        const sw = screen ? screen.width : 0
        const sh = screen ? screen.height : 0
        const origin = _hostOrigin()
        const local = item ? item.mapToItem(null, 0, 0) : Qt.point(0, 0)
        const iw = item ? item.width : 0
        const ih = item ? item.height : 0
        const gx = origin.x + local.x
        const gy = origin.y + local.y
        const edge = root.dockHosted ? root.dockEdge : "top"
        if (edge === "top")
            return { edge: edge, offset: gy + ih + 6 - sy, center: gx + iw / 2 }
        if (edge === "bottom")
            return { edge: edge, offset: sy + sh - gy + 6, center: gx + iw / 2 }
        if (edge === "left")
            return { edge: edge, offset: gx + iw + 6 - sx, center: gy + ih / 2 }
        return { edge: edge, offset: sx + sw - gx + 6, center: gy + ih / 2 }
    }
    function _applyPlacement(panel, placement) {
        if (!panel || !placement)
            return
        panel.panelEdge = placement.edge
        panel.panelOffset = placement.offset
        panel.panelCenter = placement.center
    }

    // Remote session entries (desktop context menu) open the panel anchored
    // to the control-center cell and drop the user straight into the shared
    // confirmation dialog, exactly like choosing the entry in the panel.
    property string pendingSessionAction: ""
    function presentSessionConfirmation(action) {
        closeDetailPanels()
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
        id: inputMethodQuickControl
        Item {
            readonly property alias control: imControl
            InputMethodStatus {
                id: imControl
                anchors.centerIn: parent
                dockHosted: root.dockHosted
                dockEdge: root.dockEdge
                verticalDock: root.verticalDock && !SysTrayOrderService.isCollected("cell:inputmethod")
            }
        }
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
                        root.closeDetailPanels()
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
                    onPanelToggleRequested: {
                        batteryPanel.close()
                        notificationPanel.close()
                        bluetoothPanel.close()
                        networkPanel.close()
                        root.closeControlCenter()
                        trafficPanel.toggle(networkTraffic)
                    }
                }
            }
        }
    }

    Component {
        id: batteryQuickControl
        Item {
            Battery {
                id: battery
                panelOpen: batteryPanel.requestedOpen
                onPanelToggleRequested: {
                    trafficPanel.close()
                    notificationPanel.close()
                    bluetoothPanel.close()
                    networkPanel.close()
                    root.closeControlCenter()
                    batteryPanel.toggle(battery)
                }
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
                    root.closeDetailPanels()
                    if (!notificationPanel.requestedOpen) {
                        networkPanel.close()
                        bluetoothPanel.close()
                        root.closeControlCenter()
                    }
                    if (Date.now() < notificationPanel._suppressToggleUntil)
                        return
                    root._applyPlacement(notificationPanel,
                        root._panelPlacement(notificationToggle))
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
                    root.closeDetailPanels()
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
    BatteryPanel {
        id: batteryPanel
        dockHosted: root.dockHosted
        dockEdge: root.dockEdge
    }
    NetworkTrafficPanel { id: trafficPanel }
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
            if (anchor) {
                root._applyPlacement(item,
                    root.pendingControlCenterPlacement || root._panelPlacement(anchor))
                item.toggle(anchor)
            }
            root.pendingControlCenterAnchor = null
            root.pendingControlCenterPlacement = null
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
