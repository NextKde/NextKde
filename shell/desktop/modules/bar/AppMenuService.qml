pragma Singleton

import QtQuick
import qs.desktop.modules.platform

// Keep AppMenu discovery independent from any visual delegate. A Bar item can
// legitimately have zero width when the active app has no menu; the D-Bus
// polling must nevertheless continue so it can wake when focus changes.
QtObject {
    id: service

    property string dbusService: ""
    property string dbusPath: ""
    property var items: []
    property bool requestPending: false

    readonly property bool available: dbusService.length > 0 && dbusPath.length > 0

    function requestLayout(id, callback, depth) {
        PlatformClient.request("appmenu.layout", {
            service: dbusService,
            path: dbusPath,
            id: id,
            depth: depth || 1
        }, function(response) {
            callback(response?.ok ? (response.result?.items || []) : [])
        })
    }

    function refresh() {
        if (requestPending)
            return
        requestPending = true
        PlatformClient.request("appmenu.active", {}, function(response) {
            requestPending = false
            const address = response?.ok ? (response.result || {}) : ({})
            dbusService = address.available ? (address.service || "") : ""
            dbusPath = address.available ? (address.path || "") : ""
            if (!available) {
                items = []
                return
            }
            requestLayout(0, function(result) {
                if (!available)
                    return
                items = result.filter(item => item.visible !== false && !item.separator)
            }, 2)
        })
    }

    property Timer refreshTimer: Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: service.refresh()
    }

    Component.onCompleted: refresh()
}
