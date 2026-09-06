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

    // A native StatusNotifierItem slot, as opposed to one of the shell's own
    // trailing cells (see the key scheme in SysTray.qml).
    function isTrayKey(key) { return key.indexOf("tray:") === 0 }
    // An item whose StatusNotifierItem id has not resolved yet is keyed by
    // its Repeater index, which changes as soon as the real id arrives; such
    // a key must never be written to the persisted order.
    function isPlaceholderKey(key) { return key.indexOf("tray:#") === 0 }

    // Returns `keys` arranged by the saved preference. Keys the preference
    // has never seen are new arrivals: a native tray icon takes the leading
    // slots, so an app launched now shows up at the left edge of the row
    // rather than behind the shell's own cells, while an unrecognised shell
    // cell stays at the tail where it is declared. On a first run nothing is
    // known yet, so this reduces to the natural declaration order.
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
        const head = keys.filter(key => !seen[key] && svc.isTrayKey(key))
        const tail = keys.filter(key => !seen[key] && !svc.isTrayKey(key))
        return head.concat(known, tail)
    }

    // Folds keys the saved order has never seen into it — tray icons at the
    // head, shell cells at the tail, matching arrange(). Recording a key on
    // sight rather than only when it is dragged is what lets "new" mean
    // "never seen before": without it every never-reordered icon stays
    // unknown, and the one that just appeared would sort among them in
    // SystemTray's own append order, i.e. last instead of first.
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
        svc.order = head.concat(svc.order, tail)
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
