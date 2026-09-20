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
    // Kill switch for the click-to-paste half: with it off every activation
    // degrades to plain "copy", which isolates a broken paste to either the
    // clipboard write or the key injection.
    property bool pasteEnabled: true

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
            else if (response?.error?.code !== "command-unavailable")
                console.warn("[Clipboard] cliphist list failed: "
                    + (response?.error?.message || "platform unavailable"))
        })
    }

    // ================================================================ pinned
    // A pin is a copy the platform keeps on its own, so history rotation can
    // never take it away. The panel only mirrors that store.
    property var pinned: []
    property int pinnedRevision: 0
    readonly property int pinnedCount: pinned.length
    property bool _pinnedInFlight: false

    function refreshPinned() {
        if (service._pinnedInFlight)
            return
        service._pinnedInFlight = true
        PlatformClient.request("clipboard.pinned.list", {}, function(response) {
            service._pinnedInFlight = false
            if (response?.ok) {
                service.pinned = response.result?.items ?? []
                service.pinnedRevision += 1
            } else {
                console.warn("[Clipboard] pinned list failed: "
                    + (response?.error?.message || "platform unavailable"))
            }
        })
    }

    function pinEntry(selectionRecord, preview) {
        if (!selectionRecord)
            return
        PlatformClient.request("clipboard.pinned.add",
            { record: String(selectionRecord), preview: String(preview ?? "") },
            function(response) {
            if (response?.ok)
                service.refreshPinned()
            else
                console.warn("[Clipboard] pin failed: "
                    + (response?.error?.message || "platform unavailable"))
        })
    }

    // Unpinning is what frees the pinned payload and its preview file, so this
    // is the call that keeps the state directory from accumulating entries the
    // user has already dropped.
    function unpinById(pinId) {
        if (!pinId)
            return
        PlatformClient.request("clipboard.pinned.remove", { pinId: String(pinId) },
            function(response) {
            if (response?.ok) {
                service.refreshPinned()
                service.thumbnailRevision += 1
            } else {
                console.warn("[Clipboard] unpin failed: "
                    + (response?.error?.message || "platform unavailable"))
            }
        })
    }

    // cliphist ids rotate with the history, so a pinned entry is matched by
    // what the user actually sees: the preview text and its type.
    function pinIdFor(entry) {
        if (!entry)
            return ""
        for (let i = 0; i < service.pinned.length; i++) {
            const item = service.pinned[i]
            if (item.preview === entry.preview && item.isImage === entry.isImage)
                return item.pinId
        }
        return ""
    }

    // ============================================================== previews
    // record -> file:// URL of the rendered image preview. Failures are
    // remembered too, so a row that decoded once never spawns a decoder again
    // on every refresh.
    property var thumbnails: ({})
    property int thumbnailRevision: 0
    property var _thumbFailed: ({})
    property var _thumbPending: ({})

    function thumbnailSourceFor(entry) {
        if (!entry || !entry.isImage || !entry.record)
            return ""
        const cached = service.thumbnails[entry.record]
        if (cached !== undefined)
            return cached
        if (service._thumbFailed[entry.record]
            || service._thumbPending[entry.record])
            return ""
        // Requesting is a side effect, and the result-list binding reads both
        // bookkeeping maps, so writing _thumbPending inline makes that binding
        // invalidate itself — QML reports it as a binding loop and rebuilds
        // every row once per image. Deferring to the next event-loop turn keeps
        // the binding pure; the guard is re-checked there because several rows
        // can be evaluated before the first deferred call runs.
        Qt.callLater(service._requestThumbnail, String(entry.record))
        return ""
    }

    function _requestThumbnail(record) {
        if (service._thumbFailed[record] || service._thumbPending[record])
            return
        service._thumbPending[record] = true
        PlatformClient.request("clipboard.thumb", { record: String(record) },
            function(response) {
            delete service._thumbPending[record]

            const path = response?.ok ? (response.result?.path ?? "") : ""
            if (path) {
                const next = Object.assign({}, service.thumbnails)
                next[record] = "file://" + path
                service.thumbnails = next
                service.thumbnailRevision += 1
            } else {
                // Remembered so a non-image row never re-spawns a decoder —
                // but only for a genuine daemon-side failure. A transport
                // error means the record was never even decoded, so leave it
                // retryable or every preview would go blank after a restart.
                const code = String(response?.error?.code || "")
                if (code !== "disconnected" && code !== "timeout"
                        && code !== "queue-overflow")
                    service._thumbFailed[record] = true
            }
        })
    }

    // The platform already deleted the file; this drops its cached URL so the
    // delegate stops pointing at something that no longer exists.
    function _forgetThumbnail(record) {
        delete service._thumbFailed[record]
        if (service.thumbnails[record] === undefined)
            return
        const next = Object.assign({}, service.thumbnails)
        delete next[record]
        service.thumbnails = next
        service.thumbnailRevision += 1
    }

    // done(ok) is the only reliable "content is in place" edge: the platform
    // replies after wl-copy has actually exited, so callers can chain work that
    // must not run against a half-written clipboard.
    function copy(selectionRecord, done) {
        if (!selectionRecord) {
            if (done)
                done(false)
            return
        }
        PlatformClient.request("clipboard.history.copy",
            { record: String(selectionRecord) }, function(response) {
            const ok = !!response?.ok
            if (!ok)
                console.warn("[Clipboard] failed to copy history entry: "
                    + (response?.error?.message || "platform unavailable"))
            if (done)
                done(ok)
        })
    }

    function copyPinned(pinId, done) {
        if (!pinId) {
            if (done)
                done(false)
            return
        }
        PlatformClient.request("clipboard.pinned.copy", { pinId: String(pinId) },
            function(response) {
            const ok = !!response?.ok
            if (!ok)
                console.warn("[Clipboard] pinned copy failed: "
                    + (response?.error?.message || "platform unavailable"))
            if (done)
                done(ok)
        })
    }

    // One entry point for "put this on the clipboard", whichever store the row
    // came from, so the paste controller never has to know about pins.
    function copyEntry(item, done) {
        if (!item) {
            if (done)
                done(false)
            return
        }
        if (item.pinId)
            copyPinned(item.pinId, done)
        else
            copy(item.selectionRecord, done)
    }

    function deleteEntry(selectionRecord) {
        if (!selectionRecord)
            return
        PlatformClient.request("clipboard.history.delete",
            { record: String(selectionRecord) }, function(response) {
            if (response?.ok) {
                // The platform removed the preview file with the entry; drop
                // its cached URL so nothing points at a missing path.
                service._forgetThumbnail(selectionRecord)
                service.refresh()
            } else {
                console.warn("[Clipboard] failed to delete entry: "
                    + (response?.error?.message || "platform unavailable"))
            }
        })
    }

    function clearAll() {
        PlatformClient.request("clipboard.history.clear", {}, function(response) {
            if (response?.ok) {
                service.entries = []
                service.revision += 1
                // Every preview went with the history it described.
                service.thumbnails = ({})
                service._thumbFailed = ({})
                service._thumbPending = ({})
                service.thumbnailRevision += 1
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
        service._pruneThumbnails()
    }

    // Thumbnail bookkeeping is keyed by record, and records die with history
    // rotation. Rebuilding the maps against the live entry list keeps them
    // bounded; a stale in-flight reply for a dead record is simply pruned
    // again on the next refresh. Pinned rows render item.thumbnailPath from
    // the pinned list itself, so they never need an entry in these maps.
    function _pruneThumbnails() {
        const live = {}
        for (let i = 0; i < entries.length; i++)
            live[entries[i].record] = true
        let evicted = false
        const nextThumbs = {}
        for (const record in service.thumbnails) {
            if (live[record])
                nextThumbs[record] = service.thumbnails[record]
            else
                evicted = true
        }
        if (evicted) {
            service.thumbnails = nextThumbs
            service.thumbnailRevision += 1
        }
        for (const record in service._thumbFailed)
            if (!live[record]) delete service._thumbFailed[record]
        for (const record in service._thumbPending)
            if (!live[record]) delete service._thumbPending[record]
    }

    property Connections platformTransport: Connections {
        target: PlatformClient
        function onTransportChanged(connected) {
            if (connected) {
                service._syncWatchImages()
                service.refresh()
                service.refreshPinned()
            } else {
                // Outstanding callbacks are failed by the client; reset the
                // guards too so the panel can never be stuck "refreshing".
                service._listProcess = null
                service._pinnedInFlight = false
            }
        }
    }

    Component.onCompleted: {
        load()
        refresh()
        refreshPinned()
    }

    property Component processFactory: Component {
        Process {
            stdout: StdioCollector {}
            stderr: StdioCollector {}
        }
    }
}
