pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.desktop.modules.platform

// Persists the user's Alt+drag reordering of the tray row — native
// StatusNotifierItem icons form a movable group alongside the shell's
// network, temperature and other system cells in one continuous sequence,
// keyed by a stable id (see SysTray.qml for the key scheme).
QtObject {
    id: svc

    // Kept beside dock/config.json rather than inside the shell directory so
    // Quickshell's source-file watcher never reloads the shell mid-write.
    readonly property string configDir: Quickshell.stateDir + "/bar"
    readonly property string configPath: configDir + "/tray-order.json"

    property var order: []
    property bool ready: false

    // A native StatusNotifierItem slot, as opposed to one of the shell's own
    // trailing cells (see the key scheme in SysTray.qml).
    function isTrayKey(key) { return key.indexOf("tray:") === 0 }
    // An item whose StatusNotifierItem id has not resolved yet is keyed by
    // its Repeater index, which changes as soon as the real id arrives; such
    // a key must never be written to the persisted order.
    function isPlaceholderKey(key) { return key.indexOf("tray:#") === 0 }

    // A virtual cell positions the native icons as a single group. Native
    // keys keep their own saved order and are expanded only in the live tray.
    function arrange(keys) {
        const live = keys || []
        const native = live.filter(k => svc.isTrayKey(k))
        const known = svc.order.filter((k, i, all) => native.indexOf(k) >= 0
            && all.indexOf(k) === i)
        const tray = native.filter(k => known.indexOf(k) < 0).concat(known)
        const cells = live.filter(k => !svc.isTrayKey(k))
        if (native.length && cells.indexOf("cell:tray") < 0)
            cells.unshift("cell:tray")
        const saved = svc.order.filter((k, i, all) => cells.indexOf(k) >= 0
            && all.indexOf(k) === i)
        // Old configurations have no group marker: keep their tray leading.
        if (cells.indexOf("cell:tray") >= 0 && saved.indexOf("cell:tray") < 0)
            saved.unshift("cell:tray")
        const result = saved.concat(cells.filter(k => saved.indexOf(k) < 0))
            .filter(k => k !== "cell:controlcenter")
        if (cells.indexOf("cell:controlcenter") >= 0)
            result.push("cell:controlcenter")
        if (!native.length)
            return result
        let expanded = []
        for (const key of result)
            expanded = expanded.concat(key === "cell:tray" ? tray : [key])
        return expanded
    }

    // Folds keys the saved order has never seen into it — tray icons at the
    // head of the tray section, shell cells at the tail of the cell section.
    function register(keys) {
        if (!svc.ready)
            return
        const existing = ({})
        for (let i = 0; i < svc.order.length; i++)
            existing[svc.order[i]] = true
        const head = []
        const tail = []
        for (let i = 0; i < keys.length; i++) {
            const key = keys[i]
            if (existing[key] || svc.isPlaceholderKey(key))
                continue
            existing[key] = true
            if (svc.isTrayKey(key))
                head.push(key)
            else
                tail.push(key)
        }
        if (head.length === 0 && tail.length === 0)
            return
        const currentTray = svc.order.filter(k => svc.isTrayKey(k))
        const currentCell = svc.order.filter(k => !svc.isTrayKey(k))
        svc.order = head.concat(currentTray, currentCell, tail)
        scheduleSave()
    }

    // `currentKeys` is the live key set (arrange() needs it to place unknown
    // keys correctly); the caller passes the same set it used to compute the
    // dragged item's current position.
    function moveKey(key, targetIndex, currentKeys) {
        const arranged = arrange(currentKeys)
        const sourceIndex = arranged.indexOf(key)
        if (sourceIndex < 0)
            return

        // Control Center is pinned to the far right trailing edge
        if (key === "cell:controlcenter")
            return

        let destination = Math.round(targetIndex)
        if (svc.isTrayKey(key)) {
            // Alt+drag within the app group must never split that group.
            const start = arranged.findIndex(k => svc.isTrayKey(k))
            const count = arranged.filter(k => svc.isTrayKey(k)).length
            destination = Math.max(start, Math.min(start + count - 1, destination))
        } else {
            destination = Math.max(0, Math.min(arranged.length - 2, destination))
        }
        if (sourceIndex === destination)
            return
        const moved = arranged.splice(sourceIndex, 1)[0]
        arranged.splice(destination, 0, moved)
        // Collapse native keys back to their marker for persistence. Keep
        // absent keys too: editor drags must preserve the app-internal order.
        const native = arranged.filter(k => svc.isTrayKey(k))
        const cells = []
        for (const entry of arranged) {
            const cell = svc.isTrayKey(entry) ? "cell:tray" : entry
            if (cells.indexOf(cell) < 0) cells.push(cell)
        }
        const absent = svc.order.filter(k => arranged.indexOf(k) < 0
            && cells.indexOf(k) < 0 && native.indexOf(k) < 0)
        svc.order = native.concat(cells, absent)

        scheduleSave()
    }

    property Timer _saveTimer: Timer {
        interval: 500
        repeat: false
        onTriggered: svc._doSave()
    }
    function scheduleSave() { _saveTimer.restart() }

    function _doSave() {
        const json = JSON.stringify({ version: 1, order: svc.order }, null, 2)
        JsonConfigStore.writePath(svc.configPath, json)
    }

    function loadConfig() {
        JsonConfigStore.readPath(svc.configPath, function(data, exists) {
            if (exists && data) {
                try {
                    const obj = JSON.parse(data)
                    if (Array.isArray(obj.order)) {
                        const raw = obj.order.filter(key => typeof key === "string")
                        const trayPart = raw.filter(k => svc.isTrayKey(k))
                        const cellPart = raw.filter(k => !svc.isTrayKey(k))
                        svc.order = trayPart.concat(cellPart)
                    }
                } catch (e) {
                    console.warn("[SysTrayOrder] parse error: " + e)
                }
            }
            svc.ready = true
        })
    }

    Component.onCompleted: loadConfig()
}
