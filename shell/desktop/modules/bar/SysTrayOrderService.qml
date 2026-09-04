pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Persists the user's Alt+drag reordering of the tray row — native
// StatusNotifierItem icons and the shell's own network/battery/settings/
// control-center cells share one continuous, freely reorderable sequence,
// keyed by a stable id (see SysTray.qml for the key scheme).
QtObject {
    id: svc

    // Kept beside dock/config.json rather than inside the shell directory so
    // Quickshell's source-file watcher never reloads the shell mid-write.
    readonly property string configDir: Quickshell.stateDir + "/bar"
    readonly property string configPath: configDir + "/tray-order.json"

    property var order: []
    property bool ready: false

    // Returns `keys` arranged by the saved preference; any key not yet known
    // to that preference is appended at the end in its natural order, so a
    // newly appeared tray icon does not jump into the middle of the row.
    function arrange(keys) {
        const known = []
        const seen = ({})
        for (let i = 0; i < svc.order.length; i++) {
            const key = svc.order[i]
            if (keys.indexOf(key) >= 0 && !seen[key]) {
                known.push(key)
                seen[key] = true
            }
        }
        const rest = keys.filter(key => !seen[key])
        return known.concat(rest)
    }

    // `currentKeys` is the live key set (arrange() needs it to place unknown
    // keys correctly); the caller passes the same set it used to compute the
    // dragged item's current position.
    function moveKey(key, targetIndex, currentKeys) {
        const arranged = arrange(currentKeys)
        const sourceIndex = arranged.indexOf(key)
        if (sourceIndex < 0)
            return
        const destination = Math.max(0, Math.min(arranged.length - 1, Math.round(targetIndex)))
        if (sourceIndex === destination)
            return
        const moved = arranged.splice(sourceIndex, 1)[0]
        arranged.splice(destination, 0, moved)
        svc.order = arranged
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
        const proc = _makeProc([
            "sh", "-c",
            "mkdir -p \"$1\" && printf %s \"$2\" > \"$1/tray-order.json.tmp\" && mv \"$1/tray-order.json.tmp\" \"$1/tray-order.json\"",
            "tray-order-save", svc.configDir, json,
        ])
        if (proc) {
            proc.exited.connect(function(code) {
                if (code !== 0)
                    console.warn("[SysTrayOrder] save failed code=" + code)
                proc.destroy()
            })
            proc.running = true
        }
    }

    function loadConfig() {
        const proc = _makeProc(["sh", "-c", "cat \"$1\"", "tray-order-load", svc.configPath])
        if (!proc) {
            svc.ready = true
            return
        }
        proc.exited.connect(function(code) {
            const output = proc.stdout?.text ?? ""
            if (code === 0 && output) {
                try {
                    const obj = JSON.parse(output)
                    if (Array.isArray(obj.order))
                        svc.order = obj.order.filter(key => typeof key === "string")
                } catch (e) {
                    console.warn("[SysTrayOrder] parse error: " + e)
                }
            }
            svc.ready = true
            proc.destroy()
        })
        proc.running = true
    }

    property Component _procFactory: Component {
        Process {
            stdout: StdioCollector {}
            stderr: StdioCollector {}
        }
    }

    function _makeProc(command) {
        try {
            return _procFactory.createObject(svc, { command: command })
        } catch (e) {
            console.warn("SysTrayOrderService: cannot create Process:", e)
        }
        return null
    }

    Component.onCompleted: loadConfig()
}
