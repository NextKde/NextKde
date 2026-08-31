pragma Singleton

import QtQuick
import Quickshell.Io
import qs.desktop.modules.dock

// Activity data lives in shell-data-service: boot uptime is seeded from
// journald by the Go service and the running session is settled there every
// second. This singleton only reads the activity section of the atomic
// snapshot and reports the foreground app back to the service, which
// attributes time to it. No QML process polls journalctl or writes ledgers.
QtObject {
    id: service

    property var uptimeByDay: ({})
    property var todayAppsById: ({})
    property bool ready: false
    property string activeAppId: ""
    property string activeAppName: ""
    property string activeAppIcon: ""
    // The active-app sidecar updates the moment a window becomes foreground;
    // a consumer needs this counter to re-read the derived state.
    property int activeAppRevision: 0
    property var _readProcess: null
    property var _activeProcess: null

    function dayKey(time) {
        return Qt.formatDate(new Date(time), "yyyy-MM-dd")
    }

    function reload() {
        if (_readProcess)
            return
        const process = processFactory.createObject(service, {
            command: ["sh", "-c",
                "state=${XDG_STATE_HOME:-$HOME/.local/state}; cat \"$state/quickshell/shell-data-service/snapshot.json\" 2>/dev/null",
                "activity-snapshot"]
        })
        _readProcess = process
        process.exited.connect(function() {
            try {
                const snapshot = JSON.parse((process.stdout?.text ?? "").trim())
                const activity = snapshot.activity ?? {}
                uptimeByDay = activity.uptimeByDay ?? ({})
                todayAppsById = activity.todayApps ?? ({})
                ready = true
            } catch (_) {
                // The service has not written its first snapshot yet.
            }
            if (service._readProcess === process)
                service._readProcess = null
            process.destroy()
        })
        process.running = true
    }

    // Today's apps ordered by session duration, the format the activity card
    // renders. Reads the in-memory snapshot so its bindings track updates.
    function todayApps() {
        return Object.keys(todayAppsById).map(id => Object.assign({ id: id }, todayAppsById[id]))
            .sort((left, right) => right.seconds - left.seconds)
    }

    function recentUptimeDays(count) {
        const result = []
        const start = new Date()
        start.setHours(0, 0, 0, 0)
        start.setDate(start.getDate() - count + 1)
        for (let i = 0; i < count; i++) {
            const date = new Date(start)
            date.setDate(start.getDate() + i)
            const key = dayKey(date.getTime())
            result.push({ key: key, seconds: Number(uptimeByDay[key]) || 0 })
        }
        return result
    }

    function updateActiveApp() {
        const record = WindowService.windowById(WindowService.activeWindowId)
        const id = record?.identity?.desktopId ?? ""
        const name = record?.identity?.name ?? ""
        const icon = record?.iconSource ?? ""
        if (id === activeAppId && name === activeAppName && icon === activeAppIcon)
            return
        activeAppId = id
        activeAppName = name
        activeAppIcon = icon
        activeAppRevision++
        sendActiveApp()
    }

    // Report the foreground desktop id to the service so it can attribute
    // session time. An empty appID ends attribution while no window is active.
    function sendActiveApp() {
        if (_activeProcess)
            return
        const payload = JSON.stringify({
            type: "active_app",
            appID: activeAppId,
            name: activeAppName,
            icon: activeAppIcon
        })
        const process = processFactory.createObject(service, {
            command: ["sh", "-c",
                "runtime=${XDG_RUNTIME_DIR:-/tmp}; printf '%s\\n' \"$1\" | socat - UNIX-CONNECT:\"$runtime/shell-data-service.sock\"",
                "activity-active-app", payload]
        })
        _activeProcess = process
        process.exited.connect(function() {
            if (service._activeProcess === process)
                service._activeProcess = null
            process.destroy()
        })
        process.running = true
    }

    property Component processFactory: Component {
        Process {
            stdout: StdioCollector {}
            stderr: StdioCollector {}
        }
    }
    property Connections windowConnection: Connections {
        target: WindowService
        function onRevisionChanged() { service.updateActiveApp() }
    }
    property Timer refreshTimer: Timer {
        interval: 10000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: service.reload()
    }
    Component.onCompleted: reload()
}
