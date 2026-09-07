pragma Singleton

import QtQuick

// Combines the independently-owned Bar and Dock geometry into one bounded
// platform update. Values are full-reveal global logical coordinates.
QtObject {
    id: service

    property string outputName: ""
    property var outputRect: null
    property real barReservedHeight: 0
    property string dockPosition: "bottom"
    property var dockRect: null
    property real workspaceGap: 0
    property string _lastPayload: ""

    function _screenName(screen) {
        return String(screen?.name || "")
    }

    function _updateOutput(screen) {
        if (!screen)
            return false
        const name = _screenName(screen)
        const rect = {
            x: Number(screen.x), y: Number(screen.y),
            width: Number(screen.width), height: Number(screen.height)
        }
        if (!name || rect.width <= 0 || rect.height <= 0)
            return false
        if (service.outputName !== name) {
            service.outputName = name
            service.barReservedHeight = 0
            service.dockRect = null
        }
        service.outputRect = rect
        return true
    }

    function updateBar(screen, reservedHeight) {
        if (!_updateOutput(screen))
            return
        service.barReservedHeight = Math.max(0, Number(reservedHeight) || 0)
        publishTimer.restart()
    }

    function updateDock(screen, position, rect, gap) {
        if (!_updateOutput(screen) || !rect)
            return
        service.dockPosition = String(position || "bottom")
        service.dockRect = {
            x: Number(rect.x), y: Number(rect.y),
            width: Number(rect.width), height: Number(rect.height)
        }
        service.workspaceGap = Math.max(0, Number(gap) || 0)
        publishTimer.restart()
    }

    function clearBar(screen) {
        if (!_updateOutput(screen))
            return
        service.barReservedHeight = 0
        publishTimer.restart()
    }

    function _publish() {
        if (!service.outputName || !service.outputRect || !service.dockRect
                || service.dockRect.width <= 0 || service.dockRect.height <= 0)
            return
        const payload = {
            outputName: service.outputName,
            outputRect: service.outputRect,
            barReservedHeight: service.barReservedHeight,
            dockPosition: service.dockPosition,
            dockRect: service.dockRect,
            workspaceGap: service.workspaceGap
        }
        const serialized = JSON.stringify(payload)
        if (serialized === service._lastPayload)
            return
        service._lastPayload = serialized
        PlatformClient.request("kwin.layout.update", payload, function(response) {
            if (!response?.ok)
                console.warn("[WorkspaceLayout] update failed: "
                    + (response?.error?.message || "platform unavailable"))
        })
    }

    property Timer publishTimer: Timer {
        interval: 24
        repeat: false
        onTriggered: service._publish()
    }

    property Connections transportConnection: Connections {
        target: PlatformClient
        function onTransportChanged(connected) {
            if (connected) {
                service._lastPayload = ""
                publishTimer.restart()
            }
        }
    }
}
