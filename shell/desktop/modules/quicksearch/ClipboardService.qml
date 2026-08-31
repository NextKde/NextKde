pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.desktop.modules.platform

// Thin adapter around cliphist. Keeping it here gives QuickSearch one stable
// clipboard interface while cliphist continues to own persistence and dedupe.
QtObject {
    id: service

    readonly property string configDir: Quickshell.stateDir + "/clipboard"
    readonly property string configPath: configDir + "/config.json"
    property bool watchImages: true
    property int maxItems: 200

    property var entries: []
    property int revision: 0
    property var _listProcess: null

    // cliphist is only a database. Separate text and image watchers preserve
    // the original Wayland MIME type instead of turning image entries into a
    // filename or text preview.
    property Process textHistoryWatcher: Process {
        command: ["wl-paste", "--type", "text", "--watch", "cliphist", "store"]
        running: true
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => console.warn("[Clipboard] text watcher: " + data)
        }
    }
    property Process imageHistoryWatcher: Process {
        command: ["wl-paste", "--type", "image", "--watch", "cliphist", "store"]
        running: service.watchImages
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => console.warn("[Clipboard] image watcher: " + data)
        }
    }

    function setWatchImages(enabled) {
        if (service.watchImages === enabled)
            return
        service.watchImages = enabled
        service.scheduleSave()
    }

    function setMaxItems(count) {
        const clamped = Math.max(20, Math.min(1000, count))
        if (service.maxItems === clamped)
            return
        service.maxItems = clamped
        service.scheduleSave()
        service.refresh()
    }

    property Timer _saveTimer: Timer {
        interval: 300
        repeat: false
        onTriggered: service._save()
    }
    function scheduleSave() { _saveTimer.restart() }

    function _save() {
        const json = JSON.stringify({
            watchImages: service.watchImages,
            maxItems: service.maxItems,
        }, null, 2)
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c",
                      "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$1/config.json.tmp\" && mv \"$1/config.json.tmp\" \"$1/config.json\"",
                      "clipboard-config-save", configDir, json],
        })
        proc.exited.connect(function(code) {
            if (code !== 0)
                console.warn("[Clipboard] save config failed")
            proc.destroy()
        })
        proc.running = true
    }

    function load() {
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c", "cat \"$1\"", "clipboard-config-load", configPath],
        })
        proc.exited.connect(function(code) {
            const output = proc.stdout?.text ?? ""
            if (code === 0 && output) {
                try {
                    const saved = JSON.parse(output)
                    if (typeof saved.watchImages === "boolean")
                        service.watchImages = saved.watchImages
                    if (typeof saved.maxItems === "number" && saved.maxItems > 0)
                        service.maxItems = saved.maxItems
                } catch (e) {
                    console.warn("[Clipboard] load config parse error: " + e)
                }
            }
            proc.destroy()
        })
        proc.running = true
    }

    function refresh() {
        if (_listProcess)
            return

        const proc = processFactory.createObject(service, {
            command: ["cliphist", "list"],
        })
        _listProcess = proc
        proc.exited.connect(function(code) {
            if (service._listProcess === proc)
                service._listProcess = null
            if (code === 0)
                service._readList(proc.stdout?.text ?? "")
            else
                console.warn("[Clipboard] cliphist list failed: "
                             + (proc.stderr?.text ?? ""))
            proc.destroy()
        })
        proc.running = true
    }

    function copy(selectionRecord) {
        // cliphist decode intentionally receives the complete original list
        // row (id + tab + preview), not an id alone. Passing it positionally
        // keeps clipboard data out of shell evaluation and restores image
        // bytes with their original MIME type.
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c", "printf '%s\\n' \"$1\" | cliphist decode | wl-copy",
                      "quicksearch-clipboard-copy", String(selectionRecord)],
        })
        proc.exited.connect(function(code) {
            if (code !== 0)
                console.warn("[Clipboard] failed to copy history entry: "
                             + (proc.stderr?.text ?? ""))
            proc.destroy()
        })
        proc.running = true
    }

    function deleteEntry(selectionRecord) {
        if (!selectionRecord)
            return
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c", "printf '%s\\n' \"$1\" | cliphist delete",
                      "quicksearch-clipboard-delete", String(selectionRecord)],
        })
        proc.exited.connect(function(code) {
            if (code === 0)
                service.refresh()
            else
                console.warn("[Clipboard] failed to delete entry: "
                             + (proc.stderr?.text ?? ""))
            proc.destroy()
        })
        proc.running = true
    }

    function clearAll() {
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c", "cliphist wipe && wl-copy --clear"],
        })
        proc.exited.connect(function(code) {
            if (code === 0) {
                service.entries = []
                service.revision += 1
                service.refresh()
            } else {
                console.warn("[Clipboard] failed to clear history: "
                             + (proc.stderr?.text ?? ""))
            }
            proc.destroy()
        })
        proc.running = true
    }

    function openShortcutSettings() {
        PlatformClient.request("settings.open", { module: "kcm_keys" },
            function(response) {
                if (!response?.ok)
                    console.warn("[Clipboard] shortcut settings unavailable: "
                        + (response?.error?.message || "platform unavailable"))
            })
    }

    function _readList(output) {
        const parsed = []
        const lines = output.split("\n")
        const limit = service.maxItems > 0 ? service.maxItems : 200
        for (let i = 0; i < lines.length && parsed.length < limit; i++) {
            const tab = lines[i].indexOf("\t")
            if (tab <= 0)
                continue
            const entryId = lines[i].slice(0, tab)
            const preview = lines[i].slice(tab + 1).trim()
            if (preview) {
                // cliphist formats decoded image previews as
                // "[[ binary data 123 KiB png 1920x1080 ]]". Do not infer an
                // image from a text filename such as "screenshot.png".
                const isImage = /^\[\[ binary data .+ (png|jpe?g|gif|bmp|tiff?|webp) \d+x\d+ \]\]$/i.test(preview)
                parsed.push({
                    id: entryId,
                    preview: preview,
                    record: lines[i],
                    isImage: isImage,
                })
            }
        }
        entries = parsed
        revision += 1
    }

    Component.onCompleted: {
        load()
        refresh()
    }

    property Component processFactory: Component {
        Process {
            stdout: StdioCollector {}
            stderr: StdioCollector {}
        }
    }
}
