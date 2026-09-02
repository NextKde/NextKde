pragma Singleton

import QtQuick
import qs.desktop.modules.platform

// Presentation-facing desktop file model. All filesystem, MIME, clipboard,
// and launcher work is delegated to the two resident services; this object
// only keeps UI state and validates user-facing names before sending requests.
QtObject {
    id: service

    property var entries: []
    property string directory: ""
    property bool ready: false
    property string lastError: ""
    property bool desktopSubscriptionEnabled: true
    property var openWith: ({ loading: false, mime: "", defaultId: "", handlers: [] })
    property string clipboardMode: ""
    property var clipboardPaths: []

    function _result(response, success, failure) {
        if (response?.ok) {
            if (success)
                success(response.result || ({}))
        } else if (failure) {
            failure(response?.error?.message || "操作未完成")
        }
    }

    function requestDesktopRefresh() {
        DataClient.request("desktop.refresh", {}, function(response) {
            _result(response, function() { reload() }, function(message) {
                service.lastError = message
            })
        })
    }

    function reload() {
        DataClient.request("desktop.snapshot", {}, function(response) {
            if (!response?.ok)
                return
            const desktop = response.result?.desktop ?? response.result ?? {}
            entries = Array.isArray(desktop.entries) ? desktop.entries : []
            directory = desktop.directory ?? ""
            ready = true
        })
    }

    function validName(name) {
        const trimmed = (name ?? "").trim()
        return trimmed.length > 0 && trimmed !== "." && trimmed !== ".."
            && !trimmed.includes("/") && !trimmed.includes("\u0000")
    }

    function _platform(operation, payload, callback) {
        PlatformClient.request(operation, payload, function(response) {
            _result(response, callback, function(message) {
                service.lastError = message
            })
        })
    }

    function openEntry(entry) {
        if (!entry?.path)
            return
        _platform(entry.kind === "launcher" ? "file.launch" : "file.open",
            entry.kind === "launcher" ? { desktopFile: entry.path } : { path: entry.path })
    }

    function emptyFileMimeFromSuffix(path) {
        const suffix = (path ?? "").split(".").pop().toLowerCase()
        const textSuffixes = ["txt", "text", "log", "md", "markdown", "rst",
            "csv", "tsv", "json", "xml", "yaml", "yml", "ini", "conf",
            "js", "ts", "jsx", "tsx", "qml", "py", "go", "rs", "c", "cc",
            "cpp", "h", "hpp", "java", "sh", "zsh", "bash", "html", "css"]
        if (["md", "markdown"].indexOf(suffix) >= 0)
            return "text/markdown"
        return textSuffixes.indexOf(suffix) >= 0 ? "text/plain" : ""
    }

    function queryOpenWith(entry, callback) {
        if (!entry?.path)
            return
        openWith = ({ loading: true, mime: "", defaultId: "", handlers: [] })
        PlatformClient.request("file.open-with", { path: entry.path }, function(response) {
            if (response?.ok) {
                const result = response.result || ({})
                const mime = result.mime === "application/x-zerosize"
                    ? emptyFileMimeFromSuffix(entry.path) : result.mime
                openWith = ({ loading: false, mime: mime || result.mime || "",
                    defaultId: result.defaultId || "", handlers: result.handlers || [] })
            } else {
                openWith = ({ loading: false, mime: "", defaultId: "", handlers: [] })
            }
            if (callback)
                callback(openWith)
        })
    }

    function launchWith(entry, desktopId) {
        if (entry?.path && desktopId)
            _platform("file.launch", { path: entry.path, desktopId: desktopId })
    }

    function setDefaultOpenWith(mime, desktopId) {
        if (mime && desktopId)
            _platform("file.set-default", { mime: mime, desktopId: desktopId })
    }

    function showKdeOpenWith(entry) {
        if (entry?.path)
            _platform("file.open-kde", { path: entry.path })
    }

    function openDirectory() {
        if (directory)
            _platform("file.open", { path: directory })
    }

    function createUntitledFolder(callback) {
        if (!directory)
            return
        _platform("file.create-folder", { directory: directory }, function(result) {
            requestDesktopRefresh()
            if (callback)
                callback(result.path || "")
        })
    }

    function createUntitledFile(callback) {
        if (!directory)
            return
        _platform("file.create-file", { directory: directory }, function(result) {
            requestDesktopRefresh()
            if (callback)
                callback(result.path || "")
        })
    }

    function renameEntry(entry, name, onSuccess) {
        if (!entry?.path || !directory || !validName(name)) {
            lastError = "名称不能为空，且不能包含 /"
            return false
        }
        const target = directory + "/" + name.trim()
        if (target === entry.path)
            return true
        lastError = ""
        _platform("file.rename", { source: entry.path, target: target }, function(result) {
            if (onSuccess)
                onSuccess(result.path || target)
            requestDesktopRefresh()
        })
        return true
    }

    function transfer(paths, mode, callback) {
        if (!paths.length || !directory)
            return false
        _platform("file.transfer", { paths: paths, destination: directory, mode: mode }, function() {
            requestDesktopRefresh()
            if (callback)
                callback()
        })
        return true
    }

    function moveEntriesToFolder(entries, folder, onSuccess) {
        const paths = (entries ?? []).map(function(entry) { return entry?.path })
            .filter(function(path, index, source) {
                return !!path && path !== folder?.path && source.indexOf(path) === index
            })
        if (paths.length === 0 || !folder?.path || folder.kind !== "folder") {
            lastError = "无法移动到该文件夹"
            return false
        }
        if (paths.some(function(path) { return folder.path.indexOf(path + "/") === 0 })) {
            lastError = "不能移动到自身的子文件夹"
            return false
        }
        _platform("file.transfer", { paths: paths, destination: folder.path, mode: "move" }, function() {
            requestDesktopRefresh()
            if (onSuccess)
                onSuccess()
        })
        return true
    }

    function trashEntries(entries, onSuccess) {
        const paths = (entries ?? []).map(function(entry) { return entry?.path })
            .filter(function(path) { return !!path })
        if (!paths.length)
            return
        _platform("file.trash", { paths: paths }, function() {
            requestDesktopRefresh()
            if (onSuccess)
                onSuccess()
        })
    }

    function trashEntry(entry) { trashEntries(entry ? [entry] : []) }

    function copyEntries(entries, mode) {
        const paths = (entries ?? []).map(function(entry) { return entry?.path })
            .filter(function(path) { return !!path })
        if (!paths.length)
            return
        const operation = mode === "cut" ? "cut" : "copy"
        PlatformClient.request("clipboard.set", { mode: operation, paths: paths }, function(response) {
            if (response?.ok) {
                service.clipboardMode = operation
                service.clipboardPaths = paths
            } else {
                service.clipboardMode = ""
                service.clipboardPaths = []
                service.lastError = "无法写入文件剪贴板"
            }
        })
    }

    function pasteIntoDesktop() {
        if (!directory)
            return
        PlatformClient.request("clipboard.read", {}, function(response) {
            const result = response?.ok ? response.result || ({}) : ({})
            const paths = Array.isArray(result.paths) ? result.paths : []
            if (!paths.length) {
                service.lastError = "剪贴板中没有可粘贴的文件"
                return
            }
            const mode = result.mode === "cut" ? "move" : "copy"
            service.transfer(paths, mode, function() {
                if (mode === "move") {
                    service.clipboardMode = ""
                    service.clipboardPaths = []
                }
            })
        })
    }

    function importExternalUrls(urls, action) {
        const paths = (urls ?? []).map(function(url) {
            const value = url?.toString ? url.toString() : String(url)
            return value.startsWith("file://") ? decodeURIComponent(value.slice(7)) : ""
        }).filter(function(path) { return !!path })
        if (!paths.length) {
            lastError = "只能拖入本地文件"
            return
        }
        transfer(paths, action === Qt.MoveAction ? "move" : "copy")
    }

    property Connections dataConnection: Connections {
        target: DataClient
        function onEventReceived(eventName, payload) {
            if (eventName === "desktop.changed")
                service.reload()
        }
        function onTransportChanged(connected) {
            if (connected)
                service.reload()
        }
    }

    Component.onCompleted: reload()
}
