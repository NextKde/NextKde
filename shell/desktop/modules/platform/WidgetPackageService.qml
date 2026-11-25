pragma Singleton

import QtQuick
import qs.desktop.modules.platform

QtObject {
    id: root

    property var packages: []
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
    }
    property Timer refreshTimer: Timer {
        interval: root.refreshInterval
        repeat: true
        running: PlatformClient.connected
        onTriggered: root.refresh()
    }

    Component.onCompleted: if (PlatformClient.supports("widget-package.snapshot")) refresh()

    function refresh() {
        if (loading || !PlatformClient.supports("widget-package.snapshot")) return
        loading = true
        PlatformClient.request("widget-package.snapshot", {}, function(response) {
            root.loading = false
            if (!response?.ok || !Array.isArray(response.result?.packages)) {
                root.error = response?.error?.message || "组件索引暂不可用"
                return
            }
            root.error = ""
            root.packages = response.result.packages
        })
    }
}
