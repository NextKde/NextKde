import QtQuick
import Quickshell
import qs.desktop.modules.bar
import qs.desktop.modules.common

Item {
    id: host
    BarStatusArea { id: area }
    StatusAreaEditor { id: editor; animationEnabled: false }
    property int stage: 0

    function check(condition, message) {
        if (!condition) {
            console.error("STATUS_AREA_FAIL: " + message)
            Qt.quit()
        }
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
            if (!AppearanceConfigService.ready || !SysTrayOrderService.ready) return
            host.stage++
            if (host.stage === 1) {
                MetricsService.currentMilliC = 45000
                MetricsService.maximum5MinuteMilliC = 60000
                NetworkService.available = true
                NetworkService.deviceState = "connected"
                AppearanceConfigService.hiddenStatusCells = []
                SysTrayOrderService.order = editor.cellKeys
                SysTrayOrderService.moveKey("cell:traffic", 0, editor.cellKeys)
            } else if (host.stage === 2) {
                host.check(editor.ids.includes("temperature") && editor.ids.includes("traffic"), "missing editor cards")
                host.check(editor.ids.includes("tray"), "app tray missing from editor")
                host.check(editor.implicitWidth >= 804, "editor clips cards")
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
                NetworkService.downloadBytesPerSecond = 2048
                NetworkService.uploadBytesPerSecond = 1024
                trafficPanel.recordSample()
                host.check(trafficPanel.downloadHistory.slice(-1)[0] === 2048 && trafficPanel.uploadHistory.slice(-1)[0] === 1024, "traffic samples incorrect")
                for (let i = 0; i < 65; i++) trafficPanel.recordSample()
                host.check(trafficPanel.downloadHistory.length === 60, "traffic history is unbounded")
                traffic.control.panelToggleRequested()
                host.check(!trafficPanel.requestedOpen && !wifiPanel.requestedOpen, "traffic second click does not close")
                traffic.control.panelToggleRequested()
                NetworkService.deviceName = "fixture-next"
                trafficPanel.recordSample()
                host.check(trafficPanel.downloadHistory.length === 1, "interface change mixes traffic history")
                tray.trailingItemForKey("network").control.panelToggleRequested()
                host.check(!trafficPanel.requestedOpen && wifiPanel.requestedOpen, "Wi-Fi does not replace traffic panel")
                traffic.control.panelToggleRequested()
                host.check(trafficPanel.requestedOpen && !wifiPanel.requestedOpen, "traffic does not replace Wi-Fi panel")
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
                editor.toggle(host)
                host.check(editor.requestedOpen, "right click cannot open")
                editor.toggle(host)
                host.check(!editor.requestedOpen, "right click cannot close")
                console.error("STATUS_AREA_PASS")
                Qt.quit()
            }
        }
    }
    Timer {
        interval: 8000; running: true
        onTriggered: { console.error("STATUS_AREA_FAIL: timeout"); Qt.quit() }
    }
}
