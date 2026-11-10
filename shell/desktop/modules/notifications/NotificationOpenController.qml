import QtQuick
import "NotificationActivation.mjs" as Activation

// A request being accepted is not proof that a Wayland window gained focus.
// Observe the provider's actual window state before completing the handoff.
QtObject {
    id: root
    required property var windowService
    required property var launcher
    required property var lookupEntry
    property var notification: null
    property int activationTimeout: 3000
    property int launchTimeout: 15000
    readonly property bool busy: _phase !== ""
    property string _phase: ""
    property string _windowId: ""
    property string _desktopId: ""
    property string _ticket: ""
    property int _generation: 0
    property var _operation: null

    signal finished(var source, bool success)

    onNotificationChanged: cancel()
    Component.onDestruction: cancel()

    function cancel() {
        ++_generation
        if (_operation)
            _operation.active = false
        _operation = null
        deadline.stop()
        _phase = ""
        _windowId = ""
        _desktopId = ""
        _ticket = ""
    }

    function _finish(success) {
        const source = notification
        cancel()
        finished(source, success)
    }

    function _fallback() {
        const source = notification
        const action = Activation.defaultAction(source)
        // invoke() can synchronously remove/replace the notification. Stop
        // listening first, and deliver only the original source to the card.
        cancel()
        let accepted = false
        if (action) {
            try {
                action.invoke()
                accepted = true
            } catch (error) {
                console.warn("[NotificationOpen] default action failed: " + error)
            }
        }
        finished(source, accepted)
    }

    function _windows() {
        return windowService.records.map(record => ({
            windowId: String(record.windowId),
            desktopId: record.identity?.desktopId || "",
            rawAppId: record.identity?.rawAppId || "",
            name: record.identity?.name || "",
            minimized: record.toplevel?.minimized === true
        }))
    }

    function _activate(windowId) {
        _phase = "activate"
        _windowId = windowId
        _ticket = Activation.nextTicket()
        const record = windowService.windowById(windowId)
        if (!record) {
            _fallback()
            return
        }
        if (_isFocused(record)) {
            _finish(true)
            return
        }
        const generation = _generation
        deadline.interval = activationTimeout
        deadline.restart()
        let accepted = false
        try {
            accepted = windowService.activateWindow(windowId, {
                forceAnim: record.toplevel?.minimized === true,
                ticket: _ticket
            })
        } catch (error) {
            console.warn("[NotificationOpen] activation failed: " + error)
        }
        if (_generation !== generation)
            return
        if (!accepted)
            _fallback()
        else
            _observe()
    }

    function _isFocused(record) {
        // KWin's activated flag includes an optimistic animation lag guard.
        // Older bridges without confirmation must time out, not claim focus.
        const focused = record.provider === "kwin"
            ? record.toplevel?.focusConfirmed === true
            : record.toplevel?.activated === true
        return focused && !record.toplevel?.minimized
    }

    function _observe() {
        if (_phase === "launch") {
            const id = Activation.matchWindow(_windows(), {
                desktopEntry: _desktopId,
                appName: notification?.appName || ""
            })
            if (id)
                _activate(id)
        } else if (_phase === "activate") {
            const record = windowService.windowById(_windowId)
            if (!record)
                _fallback()
            else if (_isFocused(record))
                _finish(true)
        }
    }

    function open() {
        if (busy || !notification)
            return
        ++_generation
        _operation = { active: true }
        // Resolve a live installed entry; never retain its QObject across an
        // async launch or accept a synthetic AppIdentityService desktop id.
        let desktopId = ""
        for (const hint of Activation.identityCandidates(notification)) {
            const entry = lookupEntry(hint)
            if (entry?.id) {
                desktopId = String(entry.id)
                break
            }
        }
        const plan = Activation.planClick(notification, _windows(), desktopId)
        if (plan.kind === "activate") {
            _activate(plan.windowId)
        } else if (plan.kind === "launch") {
            _desktopId = plan.desktopId
            _phase = "launch"
            const generation = _generation
            const operation = _operation
            deadline.interval = launchTimeout
            deadline.restart()
            try {
                const accepted = launcher.launchApp(plan.desktopId, function(ok) {
                    // The token survives delegate destruction; never touch a
                    // dead QML object from a delayed platform callback.
                    if (operation.active && root._phase === "launch" && !ok)
                        root._fallback()
                }, function() { return operation.active })
                if (_generation === generation && !accepted)
                    _fallback()
            } catch (error) {
                if (_generation === generation)
                    _fallback()
            }
            _observe()
        } else {
            _fallback()
        }
    }

    property Timer deadline: Timer {
        // A slow launch may still succeed. Do not invoke a second action on
        // timeout: keep the notice available without duplicating the launch.
        onTriggered: root._finish(false)
    }
    property Connections windowChanges: Connections {
        target: root.windowService
        function onRevisionChanged() { root._observe() }
        function onActiveWindowIdChanged() { root._observe() }
        function onCommandFinished(action, ticket, found) {
            if (root._phase !== "activate" || action !== "activate" || ticket !== root._ticket)
                return
            if (!found)
                root._fallback()
            else
                root._observe()
        }
    }
}
