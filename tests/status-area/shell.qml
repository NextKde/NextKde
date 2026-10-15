import QtQuick
import QtTest
import Quickshell
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.platform

ShellRoot {
    id: host
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 600
        implicitHeight: 400
        BarStatusArea { id: area; x: 15; y: 20 }
        Item { id: editorAnchor; x: 40; y: 70; width: 30; height: 24 }
    }
    StatusAreaEditor { id: editor; animationEnabled: false; maximumWidth: 400; TestEvent { id: editorEvents } }
    NetworkTrafficPanel { id: dashboard; animationEnabled: false; TestEvent { id: popupEvents } }
    property int stage: 0

    function check(condition, message) {
        if (!condition) {
            console.error("STATUS_AREA_FAIL: " + message)
            throw new Error(message)
        }
    }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const match = find(child, name)
            if (match) return match
        }
        return null
    }
    function panelWith(method) {
        for (const object of area.data) {
            if (typeof object[method] === "function") return object
        }
        return null
    }
    function trayIn(item) {
        if (typeof item.trailingItemForKey === "function") return item
        for (const child of item.children || []) {
            const found = trayIn(child)
            if (found) return found
        }
        return null
    }
    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: {
            try {
                if (!AppearanceConfigService.ready || !SysTrayOrderService.ready) return
                host.stage++
                if (host.stage === 1) {
                    NetworkService.refreshTimer.stop()
                    NetworkService.trafficTimer.stop()
                    MetricsService.currentMilliC = 45000
                    MetricsService.maximum5MinuteMilliC = 60000
                    NetworkService.available = true
                    NetworkService.deviceState = "connected"
                    NetworkService.deviceName = "fixture-first"
                    NetworkService.trafficTimer.stop()
                    AppearanceConfigService.hiddenStatusCells = []
                    SysTrayOrderService.order = editor.cellKeys
                    SysTrayOrderService.moveKey("cell:traffic", 0, editor.cellKeys)
                } else if (host.stage === 2) {
                    host.check(editor.ids.includes("temperature") && editor.ids.includes("traffic"), "missing editor cards")
                    host.check(editor.ids.includes("tray"), "app tray missing from editor")
                    host.check(editor.implicitWidth <= 400 && editor.cardColumns === 3, "editor exceeds narrow output")
                    const tray = host.trayIn(area)
                    host.check(tray !== null, "tray missing")
                    const traffic = tray.trailingItemForKey("traffic")
                    const temperature = tray.trailingItemForKey("temperature")
                    host.check(traffic && temperature, "independent readouts missing")
                    host.check(tray.targetIndexFor("cell:traffic") < tray.targetIndexFor("cell:temperature"), "traffic cannot precede temperature")
                    host.check(traffic.cellExtraWidth > 0 && temperature.cellExtraWidth > 0, "readout widths missing")
                    const live = ["tray:a", "tray:b", "cell:network", "cell:temperature", "cell:controlcenter"]
                    SysTrayOrderService.order = ["tray:b", "tray:a", "cell:network", "cell:temperature", "cell:controlcenter"]
                    host.check(SysTrayOrderService.arrange(live).join() === "tray:b,tray:a,cell:network,cell:temperature,cell:controlcenter", "legacy tray position changed")
                    SysTrayOrderService.moveKey("cell:tray", 2, editor.cellKeys)
                    SysTrayOrderService.moveKey("cell:network", 0, editor.cellKeys)
                    SysTrayOrderService.moveKey("cell:temperature", 1, editor.cellKeys)
                    const grouped = SysTrayOrderService.arrange(live)
                    host.check(grouped.join() === "cell:network,cell:temperature,tray:b,tray:a,cell:controlcenter", "cannot move controls before app tray or app order lost")
                    SysTrayOrderService.moveKey("tray:a", 0, live)
                    host.check(SysTrayOrderService.arrange(live).join() === "cell:network,cell:temperature,tray:a,tray:b,cell:controlcenter", "app reorder escapes group")
                    const arrival = SysTrayOrderService.arrange(live.concat(["tray:new"]))
                    host.check(arrival.slice(0, 3).join() === "cell:network,cell:temperature,tray:new", "new app escapes group")
                    const trafficPanel = host.panelWith("recordSample")
                    const wifiPanel = host.panelWith("closeNetworkDialog")
                    host.check(trafficPanel && wifiPanel, "independent traffic panel missing")
                    traffic.control.panelToggleRequested()
                    host.check(trafficPanel.requestedOpen && !wifiPanel.requestedOpen && area.anyPanelOpen, "traffic opens Wi-Fi instead of its dashboard")
                    NetworkService.trafficSampled(NetworkService.deviceName, 2048, 1024)
                    host.check(trafficPanel.downloadHistory.slice(-1)[0] === 2048 && trafficPanel.uploadHistory.slice(-1)[0] === 1024, "traffic samples incorrect")
                    for (let i = 0; i < 65; i++) NetworkService.trafficSampled(NetworkService.deviceName, 2048, 1024)
                    host.check(trafficPanel.downloadHistory.length === 60, "traffic history is unbounded")
                    traffic.control.panelToggleRequested()
                    host.check(!trafficPanel.requestedOpen && !wifiPanel.requestedOpen, "traffic second click does not close")
                    traffic.control.panelToggleRequested()
                    NetworkService.deviceName = "fixture-next"
                    NetworkService.trafficSampled("fixture-first", 9999, 9999)
                    host.check(trafficPanel.downloadHistory.length === 0, "old interface sample accepted")
                    NetworkService.trafficSampled("fixture-next", 128, 256)
                    host.check(trafficPanel.downloadHistory.length === 1, "interface change mixes traffic history")
                    tray.trailingItemForKey("network").control.panelToggleRequested()
                    host.check(!trafficPanel.requestedOpen && wifiPanel.requestedOpen, "Wi-Fi does not replace traffic panel")
                    traffic.control.panelToggleRequested()
                    host.check(trafficPanel.requestedOpen && !wifiPanel.requestedOpen, "traffic does not replace Wi-Fi panel")
                    trafficPanel.close()
                    const battery = tray.trailingItemForKey("battery").control
                    battery.panelToggleRequested()
                    host.check(battery.panelOpen && !trafficPanel.requestedOpen && !wifiPanel.requestedOpen, "battery does not open independently")
                    battery.panelToggleRequested()
                    host.check(!battery.panelOpen, "battery second click does not close")
                    battery.panelToggleRequested()
                    traffic.control.panelToggleRequested()
                    host.check(!battery.panelOpen && trafficPanel.requestedOpen, "traffic does not replace battery")
                    trafficPanel.close()
                    AppearanceConfigService.setStatusCellVisible("tray", false)
                    host.check(tray.nativeKeys.length === 0, "hidden app tray still occupies slots")
                    AppearanceConfigService.setStatusCellVisible("tray", true)
                    AppearanceConfigService.setStatusCellVisible("temperature", false)
                } else if (host.stage === 3) {
                    const keys = area.visibleTrailingCells.map(entry => entry.key)
                    host.check(!keys.includes("temperature") && keys.includes("traffic") && keys.includes("network"), "temperature hide affects other cells")
                    AppearanceConfigService.setStatusCellVisible("traffic", false)
                } else if (host.stage === 4) {
                    const keys = area.visibleTrailingCells.map(entry => entry.key)
                    host.check(!keys.includes("traffic") && keys.includes("network"), "traffic hide affects Wi-Fi")
                    AppearanceConfigService.hiddenStatusCells = []
                    area.dockHosted = true
                } else if (host.stage === 5) {
                    const keys = area.visibleTrailingCells.map(entry => entry.key)
                    host.check(!keys.includes("traffic") && !keys.includes("temperature"), "Dock duplicates readouts")
                    editor.toggle(editorAnchor)
                    host.check(editor.requestedOpen, "right click cannot open")
                } else if (host.stage === 6) {
                    host.check(editor.visible && editor.width <= 400, "editor not actually mapped or too wide")
                    const last = host.find(editor.contentItem, "status-card-controlcenter")
                    host.check(last && last.mapToItem(editor.contentItem, 0, 0).y + last.height <= editor.height,
                        "last editor card clipped")
                    const draggedId = editor.arrangedIds[0]
                    const card = host.find(editor.contentItem, "status-card-" + draggedId)
                    editorEvents.mousePress(card, 45, 33, Qt.LeftButton, Qt.NoModifier, 0)
                    editorEvents.mouseMove(card, 45, 45, 0, Qt.LeftButton, Qt.NoModifier)
                    editorEvents.mouseMove(card, 45, 107, 0, Qt.LeftButton, Qt.NoModifier)
                    editorEvents.mouseRelease(card, 45, 107, Qt.LeftButton, Qt.NoModifier, 0)
                    host.check(editor.arrangedIds.indexOf(draggedId) === editor.cardColumns,
                        "cross-row pointer drag did not reorder editor")
                    editor.toggle(editorAnchor)
                    host.check(!editor.requestedOpen, "right click cannot close")
                    dashboard.toggle(editorAnchor)
                } else if (host.stage === 7) {
                    host.check(dashboard.visible && dashboard.interactive, "dashboard not actually mapped")
                    popupEvents.keyClick(Qt.Key_Escape, Qt.NoModifier, 0)
                    host.check(!dashboard.requestedOpen, "Escape did not dismiss dashboard")
                } else if (host.stage === 8) {
                    host.check(!dashboard.visible, "Escape left surface mapped")
                    dashboard.toggle(editorAnchor)
                } else if (host.stage === 9) {
                    const catcher = dashboard.data.find(object => object.objectName === "traffic-dismissal-catcher")
                    host.check(catcher && catcher.visible, "outside catcher not mapped")
                    const outside = host.find(catcher.contentItem, "traffic-outside-press")
                    host.check(popupEvents.mousePress(outside, 5, 5, Qt.LeftButton, Qt.NoModifier, 0), "outside press event failed")
                    popupEvents.mouseRelease(outside, 5, 5, Qt.LeftButton, Qt.NoModifier, 0)
                    host.check(!dashboard.requestedOpen, "outside click did not dismiss dashboard")
                } else if (host.stage === 10) {
                    host.check(!dashboard.visible, "outside press left surface mapped")
                    dashboard.toggle(editorAnchor)
                    NetworkService._trafficDevice = NetworkService.deviceName
                    NetworkService._previousTimestamp = 0
                    NetworkService._previousRx = -1
                    NetworkService._previousTx = -1
                    NetworkService.sampleTraffic()
                } else if (host.stage === 11) {
                    host.check(dashboard.downloadHistory.length === 0, "baseline produced a fabricated rate")
                    NetworkService._previousTimestamp = Date.now() - 1000
                    NetworkService.sampleTraffic()
                } else if (host.stage === 12) {
                    host.check(dashboard.downloadHistory.length === 1, "completed sample did not reach dashboard")
                    NetworkService.sampleTraffic()
                    NetworkService.deviceName = "fixture-third"
                } else if (host.stage === 13) {
                    host.check(dashboard.downloadHistory.length === 0, "late response mixed interface histories")
                    NetworkService.deviceState = "disconnected"
                    host.check(!dashboard.requestedOpen, "disconnect retained an orphaned popup")
                    console.error("STATUS_AREA_PASS")
                    Qt.quit()
                }
            } catch (error) {
                console.error("STATUS_AREA_FAIL: " + error)
                Qt.quit()
            }
        }
    }
    Timer {
        interval: 8000; running: true
        onTriggered: { console.error("STATUS_AREA_FAIL: timeout"); Qt.quit() }
    }
}
