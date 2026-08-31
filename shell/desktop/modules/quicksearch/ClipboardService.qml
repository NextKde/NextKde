pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.desktop.modules.platform

// Presentation adapter for the platform-owned clipboard history. cliphist is
// supervised by kos-platform, while QuickSearch only keeps the parsed model.
QtObject {
    id: service

    readonly property string configDir: Quickshell.stateDir + "/clipboard"
    readonly property string configPath: configDir + "/config.json"
    property bool watchImages: true
    property int maxItems: 200

    property var entries: []
    property int revision: 0
    property var _listProcess: null

    function setWatchImages(enabled) {
        if (service.watchImages === enabled)
            return
        service.watchImages = enabled
        _syncWatchImages()
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

    function _syncWatchImages() {
        PlatformClient.request("clipboard.history.watch-images",
            { enabled: service.watchImages }, function(response) {
            if (!response?.ok)
                console.warn("[Clipboard] image history watcher unavailable: "
                    + (response?.error?.message || "platform unavailable"))
        })
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
            service._syncWatchImages()
            proc.destroy()
        })
        proc.running = true
    }

    function refresh() {
        if (_listProcess)
            return

        _listProcess = true
        PlatformClient.request("clipboard.history.list", {}, function(response) {
            _listProcess = null
            if (response?.ok)
                service._readList(response.result?.stdout ?? "")
            else
                console.warn("[Clipboard] cliphist list failed: "
                    + (response?.error?.message || "platform unavailable"))
        })
    }

    function copy(selectionRecord) {
        PlatformClient.request("clipboard.history.copy",
            { record: String(selectionRecord) }, function(response) {
            if (!response?.ok)
                console.warn("[Clipboard] failed to copy history entry: "
                    + (response?.error?.message || "platform unavailable"))
        })
    }

    function deleteEntry(selectionRecord) {
        if (!selectionRecord)
            return
        PlatformClient.request("clipboard.history.delete",
            { record: String(selectionRecord) }, function(response) {
            if (response?.ok)
                service.refresh()
            else
                console.warn("[Clipboard] failed to delete entry: "
                    + (response?.error?.message || "platform unavailable"))
        })
    }

    function clearAll() {
        PlatformClient.request("clipboard.history.clear", {}, function(response) {
            if (response?.ok) {
                service.entries = []
                service.revision += 1
                service.refresh()
            } else {
                console.warn("[Clipboard] failed to clear history: "
                    + (response?.error?.message || "platform unavailable"))
            }
        })
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

    property Connections platformTransport: Connections {
        target: PlatformClient
        function onTransportChanged(connected) {
            if (connected) {
                service._syncWatchImages()
                service.refresh()
            }
        }
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
