pragma Singleton

import QtQuick
import qs.desktop.modules.platform

QtObject {
    id: root

    property var packages: []
    property var invalidPackages: []
    property int snapshotRevision: 0
    property bool loading: false
    property string error: ""
    property int refreshInterval: 30000
    property Connections capabilityConnection: Connections {
        target: PlatformClient
        function onCapabilityProbeCompleteChanged() {
            if (PlatformClient.supports("widget-package.snapshot")) root.refresh()
        }
        function onTransportChanged(connected) {
            if (connected) root.refresh()
        }
        function onEventReceived(eventName, payload) {
            if (eventName === "widget-package.changed" && payload)
                root._applySnapshot(payload)
        }
    }
    // Fallback timer only when talking to an older daemon without push watch.
    property Timer refreshTimer: Timer {
        interval: root.refreshInterval
        repeat: true
        running: PlatformClient.connected && !PlatformClient.supports("widget-package.watch")
        onTriggered: root.refresh()
    }

    Component.onCompleted: if (PlatformClient.supports("widget-package.snapshot")) refresh()

    function _applySnapshot(result) {
        if (!result || !Array.isArray(result.packages)) return false
        root.error = ""
        const rejected = (result.invalidPackages
            && typeof result.invalidPackages.length === "number")
            ? result.invalidPackages : []
        root.invalidPackages = rejected
        for (let i = 0; i < rejected.length; i++) {
            const item = rejected[i]
            console.warn("[WidgetPackageService] Rejected package:", item.id, "[" + (item.code ?? "invalid") + "]", "-", item.reason, "(" + item.path + ")")
        }
        root.packages = result.packages
        root.snapshotRevision++
        return true
    }

    function refresh() {
        if (loading || !PlatformClient.supports("widget-package.snapshot")) return
        loading = true
        PlatformClient.request("widget-package.snapshot", {}, function(response) {
            root.loading = false
            if (!response?.ok || !root._applySnapshot(response.result)) {
                root.error = response?.error?.message || "组件索引暂不可用"
            }
        })
    }
}
