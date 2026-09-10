pragma Singleton
import QtQuick
import Quickshell
import qs.desktop.modules.platform

// Shared application-action contract.
//
// This singleton deliberately does not import Dock or AppLauncher. Launching
// a DesktopEntry is provider-neutral, while persistence actions are emitted
// as requests and handled by their owning module. That prevents a dependency
// cycle and lets future surfaces (Alt+Tab, Stage Manager, search) use the
// exact same public actions.
QtObject {
    id: service

    property var _pendingDeepLinks: []

    // Give the platform-authorized launch enough time to create (or activate)
    // the primary instance before a second invocation forwards widget context.
    // This keeps compositor activation on the KDE/KIO path.
    property Timer _deepLinkDelay: Timer {
        interval: 150
        repeat: false
        onTriggered: service._flushDeepLinks()
    }

    signal pinRequested(string appId)
    signal unpinRequested(string appId)
    signal hideRequested(string appId)
    signal editRequested(var application)

    function _executeDirect(entry, appId, reason) {
        try {
            entry.execute()
            console.log("[AppAction] native launch app=" + appId
                        + (reason ? " fallback=" + reason : ""))
            return true
        } catch (error) {
            console.warn("[AppAction] failed to launch app=" + appId + ": " + error)
            return false
        }
    }

    function _executeCommandDirect(command, appId) {
        try {
            Quickshell.execDetached(command)
            console.log("[AppAction] direct command fallback app=" + appId)
            return true
        } catch (error) {
            console.warn("[AppAction] direct command failed app=" + appId
                         + ": " + error)
            return false
        }
    }

    function launch(application) {
        const entry = application?.entry ?? application
        const appId = String(entry?.id ?? application?.id ?? "")
        if (!entry?.execute) {
            console.warn("[AppAction] cannot launch without DesktopEntry app=" + appId)
            return false
        }
        // DesktopEntry.execute() knows how to select the user's terminal. Keep
        // that native path for terminal entries rather than guessing one here.
        if (entry.runInTerminal)
            return _executeDirect(entry, appId, "terminal-entry")
        if (!PlatformClient.socket.connected)
            return _executeDirect(entry, appId, "platform-unavailable")
        PlatformClient.request("application.launch", {
            desktopId: appId,
            urls: []
        }, function(response) {
            if (!response.ok)
                service._executeDirect(entry, appId, "platform-launch")
        })
        console.log("[AppAction] platform launch app=" + appId)
        return true
    }

    function entryForId(desktopId) {
        const raw = String(desktopId ?? "")
        const candidates = [raw, raw.replace(/\.desktop$/i, ""),
                            raw.endsWith(".desktop") ? raw : raw + ".desktop"]
        for (let index = 0; index < candidates.length; index++) {
            try {
                const entry = DesktopEntries.byId(candidates[index])
                if (entry)
                    return entry
            } catch (_) {}
        }
        return null
    }

    function _queueDeepLink(desktopId, command, launchArguments) {
        const pending = _pendingDeepLinks.slice()
        pending.push({
            desktopId: desktopId,
            command: command,
            launchArguments: launchArguments
        })
        _pendingDeepLinks = pending
        if (!_deepLinkDelay.running)
            _deepLinkDelay.start()
    }

    function _flushDeepLinks() {
        const pending = _pendingDeepLinks
        _pendingDeepLinks = []
        for (let index = 0; index < pending.length; index++) {
            const request = pending[index]
            try {
                Quickshell.execDetached(request.command.concat(request.launchArguments))
                console.log("[AppAction] deep link app=" + request.desktopId
                            + " args=" + JSON.stringify(request.launchArguments))
            } catch (error) {
                console.warn("[AppAction] deep-link launch failed app="
                             + request.desktopId + ": " + error)
            }
        }
    }

    // The platform request (with DesktopEntry fallback) remains the
    // authoritative launch path so the compositor receives activation
    // metadata. A delayed second invocation only forwards widget context to
    // the app's single-instance activation handler.
    function launchById(desktopId, launchArguments) {
        const entry = entryForId(desktopId)
        if (!entry) {
            console.warn("[AppAction] desktop entry is not installed: " + desktopId)
            return false
        }
        const extra = launchArguments ?? []
        if (!launch(entry))
            return false
        if (extra.length === 0)
            return true
        const baseCommand = entry.command ?? []
        if (baseCommand.length === 0) {
            console.warn("[AppAction] desktop entry has no launch command: " + desktopId)
            return true
        }
        _queueDeepLink(desktopId, [String(baseCommand[0])], extra)
        return true
    }

    function pin(appId) {
        if (!appId)
            return false
        pinRequested(String(appId))
        return true
    }

    function unpin(appId) {
        if (!appId)
            return false
        unpinRequested(String(appId))
        return true
    }

    function hide(appId) {
        if (!appId)
            return false
        hideRequested(String(appId))
        return true
    }

    function edit(application) {
        if (!application)
            return false
        editRequested(application)
        return true
    }

}
