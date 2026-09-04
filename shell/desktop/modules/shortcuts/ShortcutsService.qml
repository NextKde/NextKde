pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.desktop.modules.platform

// KOS global shortcuts — one owner for defaults, user rebindings, and the
// kglobalaccel handoff. Defaults mirror shared/contracts/shortcuts.v1.json
// (the CLI fallback source); a new shortcut must be added in both places.
//
// The Shell, not the daemon, composes each Exec line so the desktop entry
// always matches how this Shell instance was launched: installed shells run
// as `qs -c kos` while development shells run as `qs -p <repo>/shell`, and
// `ipc call` only reaches the instance with the matching config path.
QtObject {
    id: service

    readonly property string configDir: Quickshell.stateDir + "/shortcuts"
    readonly property string configPath: configDir + "/config.json"

    // id → combo overrides written by the Settings app. Anything absent
    // keeps its default binding.
    property var overrides: ({})
    property bool ready: false
    property string lastError: ""

    readonly property var defaults: [
        { id: "net.local.kos-launcher", description: "应用启动器",
          target: "applauncher", action: "toggle", combo: "Meta+Space" },
        { id: "net.local.kos-window-switcher", description: "快速搜索",
          target: "quicksearch", action: "toggle window", combo: "Meta+Shift+Space" },
        { id: "net.local.kos-control-center", description: "控制中心",
          target: "control-center", action: "toggle", combo: "Meta+B" },
        { id: "net.local.kos-overview", description: "工作区概览",
          target: "overview", action: "toggle", combo: "Meta+Tab" },
        { id: "net.local.kos-clipboard", description: "剪贴板历史",
          target: "quicksearch", action: "toggle clipboard", combo: "Meta+V" },
        { id: "net.local.kos-show-desktop", description: "显示/返回桌面",
          target: "desktop", action: "toggle", combo: "Meta+D" },
    ]

    function isValidCombo(combo) {
        const value = String(combo || "").trim()
        if (!value)
            return false
        // kglobalaccel PortableText: modifiers and the key joined by "+".
        return value.split("+").every(part => part.length > 0)
    }

    function defaultFor(id) {
        const found = defaults.find(item => item.id === id)
        return found ? found.combo : ""
    }

    // Defaults merged with user overrides; the effective binding set.
    function effectiveShortcuts() {
        return defaults.map(item => ({
            id: item.id,
            description: item.description,
            target: item.target,
            action: item.action,
            defaultCombo: item.combo,
            combo: overrides[item.id] || item.combo,
            custom: overrides[item.id] !== undefined,
        }))
    }

    function _snapshotObject(error) {
        return {
            version: 1,
            shortcuts: effectiveShortcuts(),
            error: error || "",
        }
    }

    function snapshot() {
        return _snapshotObject()
    }

    function updateShortcut(id, rawCombo) {
        const combo = String(rawCombo || "").trim()
        const known = defaults.find(item => item.id === id)
        if (!known)
            return _snapshotObject("未知的快捷键：" + id)
        if (!isValidCombo(combo))
            return _snapshotObject("无效的快捷键组合：" + combo)
        const duplicate = effectiveShortcuts().find(item => item.id !== id && item.combo === combo)
        if (duplicate)
            return _snapshotObject("快捷键 " + combo + " 已被「" + duplicate.description + "」使用")
        if (combo === known.combo)
            delete overrides[id]
        else
            overrides[id] = combo
        overridesChanged()
        saveTimer.restart()
        applyToPlatform()
        return _snapshotObject()
    }

    function resetShortcut(id) {
        if (!defaults.find(item => item.id === id))
            return _snapshotObject("未知的快捷键：" + id)
        delete overrides[id]
        overridesChanged()
        saveTimer.restart()
        applyToPlatform()
        return _snapshotObject()
    }

    function _execFor(item) {
        const args = "ipc call " + item.target + " " + item.action
        const configRoot = (Quickshell.env("XDG_CONFIG_HOME")
            || (Quickshell.env("HOME") + "/.config")) + "/quickshell/kos"
        // The installed layout is launched as `-c kos`; anything else is a
        // development tree and must be addressed by its explicit path.
        if (Quickshell.shellDir === configRoot)
            return "qs -c kos " + args
        return "qs --path " + Quickshell.shellDir + " " + args
    }

    // Publish the effective set to kos-platform. Applies at startup (the
    // request queues until the daemon connects) and after every change, so
    // a missing or stale kglobalaccel entry self-heals on every Shell start.
    function applyToPlatform() {
        const shortcuts = effectiveShortcuts().map(item => ({
            id: item.id,
            description: item.description,
            combo: item.combo,
            exec: _execFor(item),
        }))
        PlatformClient.request("shortcuts.apply", { shortcuts: shortcuts },
            function(response) {
                if (!response?.ok)
                    console.warn("[Shortcuts] apply failed: "
                        + (response?.error?.message || "platform unavailable"))
                else
                    console.log("[Shortcuts] applied " + shortcuts.length + " shortcuts")
            })
    }

    property Timer saveTimer: Timer {
        interval: 250
        repeat: false
        onTriggered: service._save()
    }

    property Component processFactory: Component {
        Process {
            stdout: StdioCollector {}
            stderr: StdioCollector {}
        }
    }

    function _makeProcess(command) {
        try {
            return processFactory.createObject(service, { command })
        } catch (error) {
            console.warn("[Shortcuts] cannot create process: " + error)
        }
        return null
    }

    function _save() {
        const payload = JSON.stringify({
            version: 1,
            overrides: service.overrides,
        }, null, 2)
        const process = _makeProcess([
            "sh", "-c",
            "mkdir -p \"$1\" && printf %s \"$2\" > \"$1/config.json.tmp\" && mv \"$1/config.json.tmp\" \"$1/config.json\"",
            "shortcuts-config-save",
            service.configDir,
            payload,
        ])
        if (!process)
            return
        process.exited.connect(function(code) {
            if (code !== 0) {
                console.warn("[Shortcuts] save failed code=" + code
                    + " stderr=" + (process.stderr?.text ?? ""))
            }
            process.destroy()
        })
        process.running = true
    }

    function _load() {
        const process = _makeProcess([
            "sh", "-c", "cat \"$1\"", "shortcuts-config-load",
            service.configPath,
        ])
        if (!process) {
            ready = true
            applyToPlatform()
            return
        }
        process.exited.connect(function(code) {
            if (code === 0 && process.stdout?.text) {
                try {
                    const object = JSON.parse(process.stdout.text)
                    const stored = object.overrides
                    if (stored && typeof stored === "object") {
                        // Only accept overrides that name a known shortcut.
                        const known = new Set(defaults.map(item => item.id))
                        const clean = {}
                        for (const key in stored) {
                            if (known.has(key) && isValidCombo(stored[key]))
                                clean[key] = String(stored[key])
                        }
                        service.overrides = clean
                    }
                } catch (error) {
                    console.warn("[Shortcuts] parse error: " + error)
                }
            }
            service.ready = true
            service.applyToPlatform()
            process.destroy()
        })
        process.running = true
    }

    // QtObject has no children: non-visual objects must be declared as
    // properties or they fail to instantiate with "non-existent default
    // property".
    property Connections platformConnections: Connections {
        target: PlatformClient
        function onTransportChanged(connected) {
            if (connected && service.ready)
                service.applyToPlatform()
        }
    }

    Component.onCompleted: _load()
}
