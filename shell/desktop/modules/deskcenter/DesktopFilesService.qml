pragma Singleton

import QtQuick
import QtCore
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.platform
import "DesktopOutputs.mjs" as DesktopOutputs

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
    property var availableOutputs: DesktopOutputs.outputNames(ScreenLifecycle.usableScreens)
    readonly property string defaultOutput: ScreenLifecycle.activeScreen?.name ?? ""

    // One writer for the existing module settings. Multiple desktop windows
    // must not hold independent caches of the same Settings file.
    property Settings layout: Settings {
        location: "file://" + Quickshell.stateDir + "/deskcenter-desktop-files.ini"
        category: "DesktopFiles"
        property string orderJson: "[]"
        property int iconSize: 56
        property bool showExtensions: true
        property string folderCustomJson: "{}"
    }

    function entriesForOutput(output) {
        return DesktopOutputs.entriesForOutput(entries, output, availableOutputs, defaultOutput)
    }

    function configureOutputs() {
        const outputs = availableOutputs
        const selectedDefault = outputs.indexOf(defaultOutput) >= 0
            ? defaultOutput : (outputs[0] ?? "")
        DataClient.request("desktop.outputs", { outputs: outputs, defaultOutput: selectedDefault }, function(response) {
            if (response?.ok)
                service.applySnapshot(response.result?.desktop)
        })
    }

    function applySnapshot(desktop) {
        if (!desktop)
            return
        entries = Array.isArray(desktop.entries) ? desktop.entries : []
        directory = desktop.directory ?? ""
        ready = true
    }

    function placeEntries(paths, output, callback) {
        if (!paths.length)
            return
        DataClient.request("desktop.place", { paths: paths, output: output || defaultOutput }, function(response) {
            _result(response, function(result) {
                service.applySnapshot(result.desktop)
                if (callback)
                    callback()
            }, function(message) {
                service.lastError = message
                service.requestDesktopRefresh()
            })
        })
    }

    function claimDesktopIcons() {
        if (ready && directory && availableOutputs.length > 0)
            _platform("desktop.icons.claim", {})
    }

    // Give Plasma time to create a new desktop containment after hotplug.
    // The platform also watches its config and owns automatic lease cleanup.
    property Timer iconLeaseTimer: Timer {
        interval: 750
        onTriggered: service.claimDesktopIcons()
    }
    onReadyChanged: if (ready && iconLeaseTimer) iconLeaseTimer.restart()
    onAvailableOutputsChanged: {
        configureOutputs()
        if (iconLeaseTimer)
            iconLeaseTimer.restart()
    }
    onDefaultOutputChanged: configureOutputs()

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
            applySnapshot(response.result?.desktop ?? response.result)
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

    function createUntitledFolder(callback, output) {
        if (!directory)
            return
        _platform("file.create-folder", { directory: directory }, function(result) {
            placeEntries([result.path], output, function() {
                if (callback)
                    callback(result.path)
            })
        })
    }

    function createUntitledFile(callback, output) {
        if (!directory)
            return
        _platform("file.create-file", { directory: directory }, function(result) {
            placeEntries([result.path], output, function() {
                if (callback)
                    callback(result.path)
            })
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

    function transfer(paths, mode, callback, output) {
        if (!paths.length || !directory)
            return false
        // Cutting and pasting between desktop surfaces moves the icon, not
        // the backing file. Copy/paste still explicitly creates a new copy.
        if (mode === "move") {
            const local = paths.filter(function(path) { return DesktopOutputs.isDesktopPath(path, service.directory) })
            if (local.length > 0)
                placeEntries(local, output, local.length === paths.length ? callback : undefined)
            paths = paths.filter(function(path) { return !DesktopOutputs.isDesktopPath(path, service.directory) })
            if (!paths.length)
                return true
        }
        _platform("file.transfer", { paths: paths, destination: directory, mode: mode }, function(result) {
            placeEntries(result.paths || [], output, callback)
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

    function pasteIntoDesktop(output) {
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
            }, output)
        })
    }

    function importExternalUrls(urls, action, output) {
        const paths = DesktopOutputs.localPaths(urls)
        if (!paths.length) {
            lastError = "只能拖入本地文件"
            return
        }
        const local = paths.filter(function(path) { return DesktopOutputs.isDesktopPath(path, service.directory) })
        const incoming = paths.filter(function(path) { return !DesktopOutputs.isDesktopPath(path, service.directory) })
        if (local.length)
            placeEntries(local, output)
        if (incoming.length)
            transfer(incoming, action === Qt.MoveAction ? "move" : "copy", undefined, output)
    }

    property Connections dataConnection: Connections {
        target: DataClient
        function onEventReceived(eventName, payload) {
            if (eventName === "desktop.changed")
                service.reload()
        }
        function onTransportChanged(connected) {
            if (connected) {
                service.configureOutputs()
                service.reload()
            }
        }
    }

    property Connections platformConnection: Connections {
        target: PlatformClient
        function onTransportChanged(connected) {
            if (connected)
                service.iconLeaseTimer.restart()
        }
    }

    Component.onCompleted: {
        configureOutputs()
        reload()
        iconLeaseTimer.restart()
    }
}
