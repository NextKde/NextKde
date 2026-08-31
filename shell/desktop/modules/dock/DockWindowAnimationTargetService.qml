pragma Singleton

import QtQuick
import qs.desktop.modules.platform

// Publishes the current compositor-global Dock icon rectangles to the private
// KOS KWin effect. Geometry is sampled from the rendered AppIcon item, not its
// larger layout slot, so windows land exactly on the visible icon.
QtObject {
    id: service

    property var _icons: []
    property string _lastPayload: ""
    property double _retryAfter: 0

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
        PlatformClient.request("kwin.animation.update-targets", { payload: payload },
            function(response) {
            if (!response?.ok) {
                service._lastPayload = ""
                service._retryAfter = Date.now() + 2000
            }
        })
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

    function _consumeAnimationEvent(event) {
        if (!event || event.transition !== "minimize")
            return

        const appId = _normalizedAppId(event.appId)
        const windowId = String(event.windowId || "")
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
            selected.playWindowToIconHandoff(Number(event.durationMs || 0))
    }

    // Arm KWin before executing the application. The callback is deliberately
    // invoked only after the platform daemon acknowledges the one-shot ticket,
    // which guarantees it exists before the new client creates its first
    // window.
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
        PlatformClient.request("kwin.animation.prepare-launch", { payload: payload },
            function(response) {
            if (!response?.ok)
                console.warn("[DockAnimation] could not arm launch ticket app=" + appId)
            else
                console.log("[DockAnimation] armed launch ticket app=" + appId)
            callback()
        })
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

    property Connections platformEvents: Connections {
        target: PlatformClient
        function onEventReceived(eventName, payload) {
            if (eventName === "animation.started")
                service._consumeAnimationEvent(payload)
        }
    }

}
