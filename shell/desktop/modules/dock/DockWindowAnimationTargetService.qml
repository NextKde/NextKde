pragma Singleton

import QtQuick
import qs.desktop.modules.common
import qs.desktop.modules.platform
import org.kde.taskmanager as TaskManager
import "NativeMinimizeTarget.mjs" as NativeTarget

// Publishes the current compositor-global Dock icon rectangles to the private
// KOS KWin effect and Plasma's native taskbar geometry protocol. Geometry uses
// the layout slot centre and static iconSize,
// so hover magnification does not move the window animation endpoint.
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

    function _targetEntries() {
        const entries = []
        const live = []
        for (let index = 0; index < _icons.length; index++) {
            const icon = _icons[index]
            if (!icon)
                continue
            live.push(icon)
            const target = icon.windowAnimationTarget()
            if (target)
                entries.push({ icon, target })
        }
        if (live.length !== _icons.length)
            _icons = live
        return entries
    }

    function _payload(entries) {
        const targets = entries.map(entry => entry.target)
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

    function publishNow(forceNative) {
        const entries = _targetEntries()
        // Native publication must run even when our private effect is missing,
        // its payload is unchanged, or HideAnimation=None delegates to KWin.
        for (let index = 0; index < nativeDelegates.count; index++)
            nativeDelegates.objectAt(index)?.publish(entries, forceNative === true)
        const payload = _payload(entries)
        if (payload === _lastPayload || Date.now() < _retryAfter)
            return
        _lastPayload = payload
        _send(payload)
    }

    // This model is only the protocol adapter. WindowService remains the
    // authoritative model for identity, Dock presentation and actions.
    property TaskManager.TasksModel nativeTasks: TaskManager.TasksModel {
        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortDisabled
    }

    property Component nativeRectComponent: Component {
        Item { visible: false }
    }

    property Instantiator nativeDelegates: Instantiator {
        model: service.nativeTasks
        delegate: QtObject {
            id: nativeDelegate
            required property int index
            required property var model
            property var rectItem: null
            property string lastRect: ""

            function publishRect() {
                // On Wayland the explicit QRect parameter is ignored by
                // libtaskmanager. It reads this actual QQuickItem and uses its
                // window's wl_surface, exactly as Plasma's taskbar does.
                service.nativeTasks.requestPublishDelegateGeometry(
                    service.nativeTasks.makeModelIndex(index),
                    Qt.rect(0, 0, 0, 0), rectItem)
            }

            function invalidate() {
                if (!rectItem || lastRect === "")
                    return
                rectItem.width = 0
                rectItem.height = 0
                publishRect()
                lastRect = ""
            }

            function publish(entries, force) {
                const ids = model.WinIdList || []
                const windowId = ids.length ? String(ids[0]) : ""
                const apps = [model.AppId]
                for (const record of WindowService.records) {
                    if (windowId && NativeTarget.windowKey(record.handleId)
                            === NativeTarget.windowKey(windowId)) {
                        apps.push(record.identity?.desktopId || "",
                                  record.identity?.rawAppId || "")
                        break
                    }
                }
                const entry = NativeTarget.selectTarget(entries, windowId, apps)
                const root = entry?.icon.windowAnimationSurface
                const rect = entry && root ? NativeTarget.surfaceRect(entry.target,
                    entry.icon.surfaceOriginX, entry.icon.surfaceOriginY,
                    root.width, root.height) : null
                if (!rect) {
                    invalidate()
                    return
                }
                if (rectItem && rectItem.parent !== root) {
                    invalidate()
                    rectItem.destroy()
                    rectItem = null
                }
                if (!rectItem) {
                    rectItem = service.nativeRectComponent.createObject(root)
                    lastRect = ""
                }
                if (!rectItem)
                    return
                const key = JSON.stringify(rect)
                if (key === lastRect && !force)
                    return
                rectItem.x = rect.x
                rectItem.y = rect.y
                rectItem.width = rect.width
                rectItem.height = rect.height
                publishRect()
                lastRect = key
            }

            Component.onDestruction: {
                // A removed task's row may already refer to another window;
                // never issue a request using that stale model index. Its
                // protocol resource disappears with the task. Surface removal
                // also lets KWin discard all geometries associated with it.
                if (rectItem)
                    rectItem.destroy()
            }
        }
        onObjectAdded: service.schedulePublish()
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

        // The caller passes a descriptor or an identity result, so the entry is
        // resolved here rather than read off it.
        const entry = AppPresentationService.entryFor(appId)
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
            // The Qt Wayland surface can appear after the first attempt.
            // libtaskmanager offers no acknowledgement for publication.
            service.publishNow(true)
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
