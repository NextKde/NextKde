pragma Singleton

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import "WidgetPreviewCacheLogic.mjs" as Logic

// Disk-backed PNG preview cache and render throttle for WidgetGallery.
// Stores rendered card previews in `$XDG_CACHE_HOME/kos/widgets/` keyed by
// package revision, declared size, and active desktop style/theme/DPI so the
// gallery opens quickly and frees live QML scenes once cached.
QtObject {
    id: cache

    readonly property string cacheDir: {
        const xdgCache = String(Quickshell.env("XDG_CACHE_HOME") || "")
        const home = String(Quickshell.env("HOME") || "")
        const base = xdgCache.startsWith("/") ? xdgCache : (home + "/.cache")
        return base + "/kos/widgets"
    }

    property bool dirReady: false
    property int revision: 0
    property int queueRevision: 0

    property var _index: ({})
    property var _queue: Logic.createQueueState()
    property var _pendingDeletes: []
    property bool _touchDirty: false

    property Settings _settings: Settings {
        location: "file://" + Quickshell.stateDir + "/widget-preview-cache.ini"
        category: "PreviewCache"
        property string indexJson: "{}"
    }

    property Process _mkdirProc: Process {
        command: ["mkdir", "-p", cache.cacheDir]
        onExited: exitCode => {
            if (exitCode === 0)
                cache.dirReady = true
            else
                console.warn("[WidgetPreviewCache] Failed to create cache directory:", cache.cacheDir, "exit=", exitCode)
        }
    }

    property Process _rmProc: Process {
        onExited: _drainDeletes()
    }

    property Timer _touchPersistTimer: Timer {
        interval: 1000
        repeat: false
        running: false
        onTriggered: {
            if (cache._touchDirty) {
                cache._touchDirty = false
                cache._persistNow()
            }
        }
    }

    function _persistNow() {
        cache._touchDirty = false
        _settings.indexJson = JSON.stringify(cache._index)
        _settings.sync()
    }

    function _enqueueDeletes(fileNames) {
        if (!fileNames || fileNames.length === 0) return
        const next = cache._pendingDeletes.slice()
        let added = false
        for (let i = 0; i < fileNames.length; i++) {
            const f = String(fileNames[i] || "")
            if (Logic.safeFileName(f) && next.indexOf(f) < 0) {
                next.push(f)
                added = true
            }
        }
        if (added) {
            cache._pendingDeletes = next
            _drainDeletes()
        }
    }

    function _drainDeletes() {
        if (_rmProc.running || cache._pendingDeletes.length === 0) return
        const batch = cache._pendingDeletes.slice(0, 32)
        cache._pendingDeletes = cache._pendingDeletes.slice(batch.length)
        const paths = []
        for (let i = 0; i < batch.length; i++) {
            if (Logic.safeFileName(batch[i]))
                paths.push(cache.cacheDir + "/" + batch[i])
        }
        if (paths.length === 0) {
            _drainDeletes()
            return
        }
        _rmProc.command = ["rm", "-f"].concat(paths)
        _rmProc.running = true
    }

    function slotKeyFor(widgetId, sizeValue) {
        return Logic.buildSlotKey(widgetId, sizeValue)
    }

    function themeKeyFor(appearance, paintInQml, layer1Color, dpr) {
        return Logic.buildThemeKey(appearance, paintInQml, layer1Color, dpr)
    }

    function fileNameFor(widgetId, rev, sizeValue, themeKey) {
        return Logic.buildCacheFileName(widgetId, rev, sizeValue, themeKey)
    }

    function filePathFor(fileName) {
        if (!Logic.safeFileName(fileName)) return ""
        return cache.cacheDir + "/" + fileName
    }

    function fileUrlFor(fileName) {
        const path = filePathFor(fileName)
        return path.length > 0 ? ("file://" + path) : ""
    }

    function resolve(slotKey, desiredFileName) {
        const _r = cache.revision
        const res = Logic.resolveSlot(cache._index, slotKey, desiredFileName)
        return {
            status: res.status,
            exactFileName: res.exactFileName,
            fallbackFileName: res.fallbackFileName,
            exactUrl: res.exactFileName ? fileUrlFor(res.exactFileName) : "",
            fallbackUrl: res.fallbackFileName ? fileUrlFor(res.fallbackFileName) : ""
        }
    }

    function requestRender(slotKey, desiredFileName, isDefaultSize) {
        const prev = cache._queue
        const next = Logic.enqueueRender(prev, {
            slotKey: slotKey,
            fileName: desiredFileName,
            isDefaultSize: !!isDefaultSize
        }, Logic.DEFAULT_MAX_CONCURRENT)
        cache._queue = next
        cache.queueRevision++
    }

    function isRenderGranted(slotKey, desiredFileName) {
        const _q = cache.queueRevision
        return Logic.isRenderActive(cache._queue, slotKey, desiredFileName)
    }

    function releaseRender(slotKey) {
        cache._queue = Logic.releaseRender(cache._queue, slotKey, Logic.DEFAULT_MAX_CONCURRENT)
        cache.queueRevision++
    }

    function commit(meta) {
        const res = Logic.commitEntry(cache._index, Object.assign({}, meta, {
            lastUsedMs: Date.now()
        }), Logic.DEFAULT_MAX_ENTRIES)
        cache._index = res.entries
        cache._persistNow()
        cache._enqueueDeletes(res.removedFiles)
        cache._queue = Logic.releaseRender(cache._queue, slotKeyFor(meta.widgetId, meta.sizeValue), Logic.DEFAULT_MAX_CONCURRENT)
        cache.revision++
        cache.queueRevision++
    }

    function touch(slotKey) {
        const res = Logic.touchEntry(cache._index, slotKey, Date.now())
        if (!res.changed) return
        cache._index = res.entries
        cache._touchDirty = true
        _touchPersistTimer.restart()
    }

    function invalidateFile(slotKey, fileName) {
        const res = Logic.invalidateSlotFile(cache._index, slotKey, fileName)
        if (!res.changed) return
        cache._index = res.entries
        cache._persistNow()
        if (Logic.safeFileName(fileName))
            cache._enqueueDeletes([fileName])
        cache.revision++
    }

    function syncCatalog(catalogEntries, trippedPackages) {
        const validIds = []
        if (catalogEntries != null && typeof catalogEntries !== "string" && typeof catalogEntries.length === "number") {
            for (let i = 0; i < catalogEntries.length; i++) {
                const entry = catalogEntries[i]
                if (entry && entry.id) validIds.push(String(entry.id))
            }
        }
        const blockedIds = []
        if (trippedPackages != null && typeof trippedPackages !== "string" && typeof trippedPackages.length === "number") {
            for (let i = 0; i < trippedPackages.length; i++) {
                const item = trippedPackages[i]
                const pkgId = item && typeof item === "object" ? String(item.id ?? "") : String(item ?? "")
                if (pkgId.length > 0) blockedIds.push(pkgId)
            }
        }
        const res = Logic.pruneForCatalog(cache._index, validIds, blockedIds)
        if (!res.changed) return
        cache._index = res.entries
        cache._persistNow()
        cache._enqueueDeletes(res.removedFiles)
        cache.revision++
    }

    function clearPendingRenders() {
        cache._queue = Logic.createQueueState()
        cache.queueRevision++
    }

    Component.onCompleted: {
        cache._index = Logic.parseIndex(_settings.indexJson)
        _mkdirProc.running = true
    }

    Component.onDestruction: {
        _touchPersistTimer.stop()
        if (cache._touchDirty)
            cache._persistNow()
    }
}
