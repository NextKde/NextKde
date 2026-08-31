pragma Singleton

import QtQuick
import Quickshell.Io

// Publishes the current compositor-global Dock icon rectangles to the private
// KOS KWin effect. Geometry is sampled from the rendered AppIcon item, not its
// larger layout slot, so windows land exactly on the visible icon.
QtObject {
    id: service

    property var _icons: []
    property string _lastPayload: ""
    property string _queuedPayload: ""
    property var _publisher: null
    property double _retryAfter: 0
    property bool _animationMonitorEnabled: true

    function registerIcon(icon) {
        if (!icon || _icons.indexOf(icon) >= 0)
            return
        const next = _icons.slice()
        next.push(icon)
        _icons = next
        schedulePublish()
    }

    function unregisterIcon(icon) {
        const next = _icons.filter(item => item && item !== icon)
        _icons = next
        schedulePublish()
    }

    function schedulePublish() {
        publishTimer.restart()
    }

    function _payload() {
        const targets = []
        const live = []
        for (let index = 0; index < _icons.length; index++) {
            const icon = _icons[index]
            if (!icon)
                continue
            live.push(icon)
            const target = icon.windowAnimationTarget()
            if (target)
                targets.push(target)
        }
        if (live.length !== _icons.length)
            _icons = live
        targets.sort((left, right) => String(left.appId).localeCompare(String(right.appId))
            || String(left.windowId).localeCompare(String(right.windowId)))
        return JSON.stringify({ targets })
    }

    function _send(payload) {
        if (_publisher) {
            _queuedPayload = payload
            return
        }
        const process = processFactory.createObject(service, {
            command: ["qdbus6", "org.kde.KWin", "/KOSDockWindowAnimation",
                "org.kos.KWin.DockWindowAnimation.updateTargets", payload]
        })
        _publisher = process
        process.exited.connect(function(code) {
            if (service._publisher === process)
                service._publisher = null
            if (code !== 0) {
                service._lastPayload = ""
                service._retryAfter = Date.now() + 2000
            }
            process.destroy()
            if (service._queuedPayload) {
                const queued = service._queuedPayload
                service._queuedPayload = ""
                service._send(queued)
            }
        })
        process.running = true
    }

    function publishNow() {
        const payload = _payload()
        if (payload === _lastPayload || Date.now() < _retryAfter)
            return
        _lastPayload = payload
        _send(payload)
    }

    function _normalizedAppId(value) {
        return String(value || "").trim().toLowerCase()
            .replace(/\.desktop$/i, "")
    }

    function _consumeAnimationSignal(line) {
        const match = String(line || "").match(
            /animationStarted \('([^']*)', '([^']*)', '([^']*)', (?:uint32 )?([0-9]+)\)/)
        if (!match || match[3] !== "minimize")
            return

        const appId = _normalizedAppId(match[1])
        const windowId = match[2]
        let selected = null
        for (let index = 0; index < _icons.length; index++) {
            const candidate = _icons[index]
            if (candidate && windowId
                    && String(candidate.animationWindowId || "") === windowId) {
                selected = candidate
                break
            }
        }
        if (!selected) {
            for (let index = 0; index < _icons.length; index++) {
                const candidate = _icons[index]
                if (candidate && _normalizedAppId(candidate.appId) === appId) {
                    selected = candidate
                    break
                }
            }
        }
        if (selected)
            selected.playWindowToIconHandoff(Number(match[4]))
    }

    // Arm KWin before executing the application. The callback is deliberately
    // invoked only after qdbus exits, which guarantees that the one-shot
    // ticket exists before the new client can create its first window.
    function prepareLaunch(application, callback) {
        const appId = String(application?.desktopId
            ?? application?.id ?? "")
        const wanted = _normalizedAppId(appId)
        let selectedTarget = null
        for (let index = 0; index < _icons.length; index++) {
            const icon = _icons[index]
            if (!icon)
                continue
            const target = icon.windowAnimationTarget()
            if (target && !target.windowId
                    && _normalizedAppId(target.appId) === wanted) {
                selectedTarget = target
                break
            }
        }

        if (!selectedTarget) {
            callback()
            return false
        }

        const entry = application?.entry
        const payload = JSON.stringify({
            target: selectedTarget,
            aliases: [appId,
                      application?.rawAppId ?? "",
                      entry?.id ?? "",
                      entry?.startupClass ?? ""],
            expiresInMs: 5000
        })
        const process = processFactory.createObject(service, {
            command: ["qdbus6", "org.kde.KWin", "/KOSDockWindowAnimation",
                "org.kos.KWin.DockWindowAnimation.prepareLaunch", payload]
        })
        process.exited.connect(function(code) {
            if (code !== 0)
                console.warn("[DockAnimation] could not arm launch ticket app=" + appId)
            else
                console.log("[DockAnimation] armed launch ticket app=" + appId)
            callback()
            process.destroy()
        })
        process.running = true
        return true
    }

    property Timer publishTimer: Timer {
        interval: 80
        repeat: false
        onTriggered: service.publishNow()
    }

    // Covers animated Dock layout changes and re-sends after the Effect is
    // enabled or KWin restarts. Payload equality prevents needless D-Bus calls.
    property Timer geometryTimer: Timer {
        interval: 250
        repeat: true
        running: service._icons.length > 0
        onTriggered: service.publishNow()
    }

    property Timer heartbeatTimer: Timer {
        interval: 3000
        repeat: true
        running: service._icons.length > 0
        onTriggered: {
            service._lastPayload = ""
            service.publishNow()
        }
    }

    property Process animationMonitor: Process {
        command: ["gdbus", "monitor", "--session",
            "--dest", "org.kde.KWin",
            "--object-path", "/KOSDockWindowAnimation"]
        running: service._animationMonitorEnabled
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => service._consumeAnimationSignal(data)
        }
        stderr: SplitParser { splitMarker: "\n" }
        onExited: function(code) {
            service._animationMonitorEnabled = false
            animationMonitorRetry.restart()
        }
    }

    property Timer animationMonitorRetry: Timer {
        interval: 1000
        repeat: false
        onTriggered: service._animationMonitorEnabled = true
    }

    property Component processFactory: Component {
        Process {
            stdout: StdioCollector {}
            stderr: StdioCollector {}
        }
    }
}
