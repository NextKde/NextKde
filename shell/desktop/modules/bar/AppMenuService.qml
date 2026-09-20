pragma Singleton

import QtQuick
import qs.desktop.modules.platform
import qs.desktop.modules.dock

// Keep AppMenu discovery independent from any visual delegate. A Bar item can
// legitimately have zero width when the active app has no menu; discovery must
// nevertheless track focus changes.
// The menu address only changes with the focused window or when the focused
// app (re)registers its dbusmenu, so refresh is driven by
// WindowService.activeWindowId instead of a fixed poll: one read on every
// focus change, a short bounded recheck while the window still has nothing
// to show (apps commonly export the menu a moment after activation), and a
// once-a-minute floor for the rare same-window re-registration.
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
            const newService = address.available ? (address.service || "") : ""
            const newPath = address.available ? (address.path || "") : ""
            if (newService === dbusService && newPath === dbusPath && items.length > 0) {
                _armRecheck()
                return
            }
            dbusService = newService
            dbusPath = newPath
            if (!available) {
                items = []
                _armRecheck()
                return
            }
            requestLayout(0, function(result) {
                if (!available) {
                    _armRecheck()
                    return
                }
                items = result.filter(item => item.visible !== false && !item.separator)
                _armRecheck()
            }, 2)
        })
    }

    // Menus typically appear a beat after the window itself. Keep re-reading
    // for a few seconds while there is still nothing to show, then let the
    // floor timer take over so a permanently menu-less app does not poll
    // forever. The budget is refilled on every focus change.
    property int _recheckBudget: 0
    readonly property int _recheckMax: 5
    function _armRecheck() {
        if (items.length > 0 || _recheckBudget <= 0) {
            _recheckTimer.stop()
            return
        }
        _recheckBudget--
        _recheckTimer.restart()
    }
    property Timer _recheckTimer: Timer {
        interval: 1200
        repeat: false
        onTriggered: service.refresh()
    }
    // A second short read after each focus change covers the case where the
    // first request was already in flight and resolved against the previous
    // window.
    property Timer _settleTimer: Timer {
        interval: 1500
        repeat: false
        onTriggered: service.refresh()
    }
    property Timer _floorTimer: Timer {
        interval: 60000
        repeat: true
        running: PlatformClient.socket.connected
        onTriggered: service.refresh()
    }

    property Connections windowFocus: Connections {
        target: WindowService
        function onActiveWindowIdChanged() {
            service._recheckBudget = service._recheckMax
            service._settleTimer.restart()
            service.refresh()
        }
    }

    property Connections platformTransport: Connections {
        target: PlatformClient
        function onTransportChanged(connected) {
            if (connected)
                service.refresh()
            else {
                service.requestPending = false
                service._recheckTimer.stop()
                service._settleTimer.stop()
            }
        }
    }

    Component.onCompleted: refresh()
}
