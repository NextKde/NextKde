pragma Singleton

import QtQuick
import Quickshell.Io

// QML only consumes the shell-data-service snapshot. Directory scanning and
// ordering deliberately remain in the service so this view survives reloads
// without turning the desktop renderer into a file manager backend.
QtObject {
    id: service

    property var entries: []
    property string directory: ""
    property bool ready: false
    property string lastError: ""
    property var _readProcess: null
    property bool _reloadPending: false
    property bool desktopSubscriptionEnabled: true
    property var openWith: ({ loading: false, mime: "", defaultId: "", handlers: [] })
    // This mirrors the last operation initiated by this shell for UI state;
    // the actual paste mode is always read back from the current MIME data.
    property string clipboardMode: ""
    property var clipboardPaths: []

    function serviceEvent(event, callback) {
        const process = processFactory.createObject(service, {
            command: ["sh", "-c",
                "runtime=${XDG_RUNTIME_DIR:-/tmp}; printf '%s\\n' \"$1\" | socat - UNIX-CONNECT:\"$runtime/shell-data-service.sock\"",
                "desktop-service-event", JSON.stringify(event)]
        })
        process.exited.connect(function(exitCode) {
            let response = null
            const lines = (process.stdout?.text ?? "").trim().split(/\r?\n/)
            for (let index = lines.length - 1; index >= 0; --index) {
                try {
                    response = JSON.parse(lines[index])
                    break
                } catch (_) {}
            }
            if (callback)
                callback(response, exitCode, process.stderr?.text ?? "")
            process.destroy()
        })
        process.running = true
    }

    function requestDesktopRefresh() {
        serviceEvent({ type: "refresh_desktop" }, function() {
            // The service completes its full scan and atomic snapshot write
            // before closing this one-shot request.
            service.reload()
        })
    }

    function reload() {
        if (_readProcess) {
            _reloadPending = true
            return
        }
        _reloadPending = false
        const process = processFactory.createObject(service, {
            command: ["sh", "-c",
                "state=${XDG_STATE_HOME:-$HOME/.local/state}; cat \"$state/quickshell/shell-data-service/snapshot.json\" 2>/dev/null",
                "desktop-files-snapshot"]
        })
        _readProcess = process
        process.exited.connect(function() {
            try {
                const snapshot = JSON.parse((process.stdout?.text ?? "").trim())
                const desktop = snapshot.desktop ?? {}
                entries = Array.isArray(desktop.entries) ? desktop.entries : []
                directory = desktop.directory ?? ""
                ready = true
            } catch (_) {
                // The service has not been installed or written its first
                // snapshot yet. Keep the desktop surface visually empty.
            }
            if (service._readProcess === process)
                service._readProcess = null
            process.destroy()
            if (service._reloadPending)
                Qt.callLater(service.reload)
        })
        process.running = true
    }

    function validName(name) {
        const trimmed = (name ?? "").trim()
        return trimmed.length > 0 && trimmed !== "." && trimmed !== ".."
            && !trimmed.includes("/") && !trimmed.includes("\u0000")
    }

    function run(command, callback) {
        const process = processFactory.createObject(service, { command: command })
        process.exited.connect(function(exitCode) {
            if (exitCode !== 0)
                service.lastError = "操作未完成"
            else if (callback)
                callback()
            process.destroy()
        })
        process.running = true
    }

    function openEntry(entry) {
        if (!entry?.path)
            return
        if (entry.kind === "launcher")
            run(["gio", "launch", entry.path])
        else
            run(["xdg-open", entry.path])
    }

    // gio deliberately reports an empty file as application/x-zerosize,
    // discarding a useful suffix such as .md.  The file manager still offers
    // editors in that case, so retain the common text/source associations for
    // the desktop's “打开方式” menu.
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
        const info = processFactory.createObject(service, {
            command: ["gio", "info", "-a", "standard::content-type", entry.path]
        })
        info.exited.connect(function(exitCode) {
            const match = (info.stdout?.text ?? "").match(/standard::content-type:\s*(\S+)/)
            const detectedMime = exitCode === 0 && match ? match[1] : ""
            const mime = detectedMime === "application/x-zerosize"
                ? emptyFileMimeFromSuffix(entry.path) : detectedMime
            info.destroy()
            if (!mime) {
                service.openWith = ({ loading: false, mime: "", defaultId: "", handlers: [] })
                if (callback) callback(service.openWith)
                return
            }
            const handlers = processFactory.createObject(service, { command: ["gio", "mime", mime] })
            handlers.exited.connect(function(handlerExitCode) {
                const lines = (handlers.stdout?.text ?? "").split(/\r?\n/)
                let defaultId = ""
                const ids = []
                for (let index = 0; index < lines.length; ++index) {
                    const line = lines[index].trim()
                    const defaultMatch = line.match(/^Default application.*:\s*(\S+)/)
                    if (defaultMatch) defaultId = defaultMatch[1]
                    const idMatch = line.match(/^(\S+\.desktop)$/)
                    if (idMatch && ids.indexOf(idMatch[1]) < 0) ids.push(idMatch[1])
                }
                if (defaultId && ids.indexOf(defaultId) < 0) ids.unshift(defaultId)
                service.openWith = ({ loading: false, mime: mime, defaultId: defaultId,
                    handlers: handlerExitCode === 0 ? ids : [] })
                handlers.destroy()
                if (callback) callback(service.openWith)
            })
            handlers.running = true
        })
        info.running = true
    }

    function launchWith(entry, desktopId) {
        if (!entry?.path || !desktopId)
            return
        const script = "id=$1; target=$2; for root in \"${XDG_DATA_HOME:-$HOME/.local/share}/applications\" /usr/local/share/applications /usr/share/applications; do if test -f \"$root/$id\"; then exec gio launch \"$root/$id\" \"$target\"; fi; done; exit 1"
        run(["sh", "-c", script, "desktop-open-with", desktopId, entry.path])
    }

    function setDefaultOpenWith(mime, desktopId) {
        if (!mime || !desktopId)
            return
        run(["gio", "mime", mime, desktopId])
    }

    function showKdeOpenWith(entry) {
        if (!entry?.path)
            return
        // Installed from helpers/kde-open-with-helper. It opens KDE's modern
        // portal chooser, rather than a shell-maintained imitation.
        run(["sh", "-c", "exec \"$HOME/.local/bin/quickshell-kde-open-with\" \"$1\"",
            "quickshell-kde-open-with", entry.path])
    }

    function openDirectory() {
        if (directory)
            run(["xdg-open", directory])
    }

    function createUntitledFolder(callback) {
        if (!directory)
            return
        lastError = ""
        const script = "dir=$1; base='untitled folder'; target=\"$dir/$base\"; index=2; while test -e \"$target\"; do target=\"$dir/$base $index\"; index=$((index + 1)); done; mkdir -- \"$target\" && printf '%s' \"$target\""
        const process = processFactory.createObject(service, {
            command: ["sh", "-c", script, "desktop-new-folder", directory]
        })
        process.exited.connect(function(exitCode) {
            const createdPath = (process.stdout?.text ?? "").trim()
            if (exitCode === 0 && createdPath) {
                service.requestDesktopRefresh()
                if (callback)
                    callback(createdPath)
            } else {
                service.lastError = "无法创建文件夹"
            }
            process.destroy()
        })
        process.running = true
    }

    function createUntitledFile(callback) {
        if (!directory)
            return
        lastError = ""
        const script = "dir=$1; base='untitled file.txt'; stem='untitled file'; extension='.txt'; target=\"$dir/$base\"; index=2; while test -e \"$target\"; do target=\"$dir/$stem $index$extension\"; index=$((index + 1)); done; touch -- \"$target\" && printf '%s' \"$target\""
        const process = processFactory.createObject(service, {
            command: ["sh", "-c", script, "desktop-new-file", directory]
        })
        process.exited.connect(function(exitCode) {
            const createdPath = (process.stdout?.text ?? "").trim()
            if (exitCode === 0 && createdPath) {
                service.requestDesktopRefresh()
                if (callback)
                    callback(createdPath)
            } else {
                service.lastError = "无法创建文件"
            }
            process.destroy()
        })
        process.running = true
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
        // Guard against name collisions: mv on an existing directory target
        // would move the source inside it instead of failing, silently
        // nesting folders. Use a dedicated process (not run()) so the error
        // message is specific instead of the generic "操作未完成".
        const process = processFactory.createObject(service, {
            command: ["sh", "-c", "test -e \"$2\" && exit 1; mv -- \"$1\" \"$2\"",
                      "desktop-rename", entry.path, target]
        })
        process.exited.connect(function(exitCode) {
            if (exitCode !== 0)
                service.lastError = "该名称已被占用"
            else {
                if (onSuccess)
                    onSuccess(target)
                requestDesktopRefresh()
            }
            process.destroy()
        })
        process.running = true
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
        if (paths.some(function(path) {
            return folder.path.indexOf(path + "/") === 0
        })) {
            lastError = "不能移动到自身的子文件夹"
            return false
        }
        lastError = ""
        // Keep the same collision rule as paste: never overwrite an existing
        // entry; instead give the incoming item a deterministic copy suffix.
        const script = "destination=$1; shift\n"
            + "for source do\n"
            + "  test -e \"$source\" || continue\n"
            + "  base=${source##*/}; candidate=\"$destination/$base\"; count=1\n"
            + "  while test -e \"$candidate\"; do\n"
            + "    stem=${base%.*}; extension=.${base##*.}\n"
            + "    if test \"$stem\" = \"$base\" || test -z \"$stem\"; then candidate=\"$destination/$base (副本 $count)\"; else candidate=\"$destination/$stem (副本 $count)$extension\"; fi\n"
            + "    count=$((count + 1))\n"
            + "  done\n"
            + "  mv -- \"$source\" \"$candidate\" || exit 1\n"
            + "done"
        run(["sh", "-c", script, "desktop-move-folder", folder.path].concat(paths), function() {
            requestDesktopRefresh()
            if (onSuccess)
                onSuccess()
        })
        return true
    }

    function trashEntries(entries, onSuccess) {
        const paths = entries.map(function(entry) { return entry.path })
            .filter(function(path) { return !!path })
        if (paths.length === 0)
            return
        lastError = ""
        // gio trash follows the desktop trash specification, so this action
        // is recoverable and never directly unlinks user data.
        run(["gio", "trash"].concat(paths), function() {
            requestDesktopRefresh()
            if (onSuccess)
                onSuccess()
        })
    }

    function trashEntry(entry) {
        trashEntries(entry ? [entry] : [])
    }

    function copyEntries(entries, mode) {
        const paths = entries.map(function(entry) { return entry.path })
            .filter(function(path) { return !!path })
        if (paths.length === 0)
            return
        const operation = mode === "cut" ? "cut" : "copy"
        service.clipboardMode = operation
        service.clipboardPaths = paths
        serviceEvent({ type: "clipboard_set", mode: operation, paths: paths },
            function(response, exitCode, stderr) {
            if (!response?.ok) {
                service.clipboardMode = ""
                service.clipboardPaths = []
                service.lastError = "无法写入文件剪贴板，请安装并启动 shell-data-service"
                console.warn("[DesktopFiles] clipboard helper failed: "
                    + (response?.error ?? stderr ?? ("exit " + exitCode)))
            }
        })
    }

    function pasteIntoDesktop() {
        if (!directory)
            return
        serviceEvent({ type: "clipboard_read" }, function(response, exitCode, stderr) {
            const paths = response?.ok && Array.isArray(response.paths)
                ? response.paths : []
            if (paths.length === 0) {
                service.lastError = "剪贴板中没有可粘贴的文件"
                if (!response?.ok)
                    console.warn("[DesktopFiles] clipboard read failed: "
                        + (response?.error ?? stderr ?? ("exit " + exitCode)))
                return
            }
            // KDE's application/x-kde-cutselection and GNOME's compatible
            // MIME marker are decoded by the Qt helper. Never infer cut from
            // stale in-process state after another app replaces the clipboard.
            const mode = response.mode === "cut" ? "cut" : "copy"
            const script = "mode=$1; destination=$2; shift 2\n"
                + "for source do\n"
                + "  test -e \"$source\" || continue\n"
                + "  if test \"$mode\" = cut && test \"$(dirname \"$source\")\" = \"$destination\"; then continue; fi\n"
                + "  base=${source##*/}; candidate=\"$destination/$base\"; count=1\n"
                + "  while test -e \"$candidate\"; do\n"
                + "    stem=${base%.*}; extension=.${base##*.}\n"
                + "    if test \"$stem\" = \"$base\" || test -z \"$stem\"; then candidate=\"$destination/$base (副本 $count)\"; else candidate=\"$destination/$stem (副本 $count)$extension\"; fi\n"
                + "    count=$((count + 1))\n"
                + "  done\n"
                + "  if test \"$mode\" = cut; then mv -- \"$source\" \"$candidate\"; else cp -a -- \"$source\" \"$candidate\"; fi\n"
                + "done"
            const worker = processFactory.createObject(service, {
                command: ["sh", "-c", script, "desktop-file-paste", mode, directory].concat(paths)
            })
            worker.exited.connect(function(workerExitCode) {
                if (workerExitCode === 0) {
                    if (mode === "cut") {
                        service.clipboardMode = ""
                        service.clipboardPaths = []
                    }
                    service.requestDesktopRefresh()
                } else {
                    service.lastError = "粘贴未完成"
                }
                worker.destroy()
            })
            worker.running = true
        })
    }

    function importExternalUrls(urls, action) {
        if (!directory)
            return
        const paths = (urls ?? []).map(function(url) {
            const value = url?.toString ? url.toString() : String(url)
            return value.startsWith("file://")
                ? decodeURIComponent(value.slice("file://".length)) : ""
        }).filter(function(path) { return !!path })
        if (paths.length === 0) {
            lastError = "只能拖入本地文件"
            return
        }
        const operation = action === Qt.MoveAction ? "move" : "copy"
        const script = "mode=$1; destination=$2; shift 2\n"
            + "for source do\n"
            + "  test -e \"$source\" || continue\n"
            + "  if test \"$mode\" = move && test \"$(dirname \"$source\")\" = \"$destination\"; then continue; fi\n"
            + "  base=${source##*/}; candidate=\"$destination/$base\"; count=1\n"
            + "  while test -e \"$candidate\"; do\n"
            + "    stem=${base%.*}; extension=.${base##*.}\n"
            + "    if test \"$stem\" = \"$base\" || test -z \"$stem\"; then candidate=\"$destination/$base (副本 $count)\"; else candidate=\"$destination/$stem (副本 $count)$extension\"; fi\n"
            + "    count=$((count + 1))\n"
            + "  done\n"
            + "  if test \"$mode\" = move; then mv -- \"$source\" \"$candidate\"; else cp -a -- \"$source\" \"$candidate\"; fi || exit 1\n"
            + "done"
        lastError = ""
        run(["sh", "-c", script, "desktop-external-drop", operation,
            directory].concat(paths), requestDesktopRefresh)
    }

    property Process desktopSubscription: Process {
        // The Go service owns fsnotify and sends a marker only after its full
        // directory scan has been atomically persisted. The explicit
        // subscription also causes one immediate initial-state marker.
        command: ["sh", "-c",
            "runtime=${XDG_RUNTIME_DIR:-/tmp}; exec socat - UNIX-CONNECT:\"$runtime/shell-data-service.sock\"",
            "desktop-files-subscription"]
        running: service.desktopSubscriptionEnabled
        stdinEnabled: true
        onStarted: write('{"type":"subscribe_desktop"}\n')
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: _ => service.reload()
        }
        stderr: SplitParser { splitMarker: "\n" }
        onExited: {
            service.desktopSubscriptionEnabled = false
            service.subscriptionRetry.restart()
        }
    }
    property Timer subscriptionRetry: Timer {
        interval: 1000
        repeat: false
        onTriggered: service.desktopSubscriptionEnabled = true
    }
    property Component processFactory: Component {
        Process {
            stdout: StdioCollector {}
            stderr: StdioCollector {}
        }
    }
    Component.onCompleted: reload()
}
