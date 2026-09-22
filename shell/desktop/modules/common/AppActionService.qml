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

    signal pinRequested(string appId)
    signal unpinRequested(string appId)
    signal hideRequested(string appId)
    signal editRequested(var application)

    // execDetached exemption (R12): the desktop-entry Exec line runs through
    // DesktopEntry.execute(), not through a shell or system-control command.
    // This path is only a last resort -- application.launch (daemon) is the
    // primary route; reaching here means the daemon is gone or the KIO launch
    // failed, so there is no op left that could carry the entry.
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

    // execDetached exemption (R12): deep-link argv is `entry.command` -- the
    // argv the desktop entry already declares -- plus app-owned arguments.
    // The daemon's application.launch op accepts only {desktopId, urls}; it
    // cannot append arbitrary argv, so a whitelist would mean either a new
    // contract op or hardcoding each app's deep-link flags in the daemon.
    // This is a direct argv exec (no shell), kept until the deep-link surface
    // is redesigned around URLs.
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
        // Terminal entries (Terminal=true, e.g. nvim/htop) must NOT go through
        // DesktopEntry.execute(): Quickshell spawns the bare command with no
        // TTY and terminal apps die immediately. Route them through the
        // platform daemon here; KIO::ApplicationLauncherJob wraps them in the
        // user's configured terminal.
        if (!PlatformClient.connected) {
            if (entry.runInTerminal) {
                console.warn("[AppAction] terminal app needs the daemon, "
                             + "no TTY fallback exists app=" + appId)
                return false
            }
            return _executeDirect(entry, appId, "platform-unavailable")
        }
        PlatformClient.request("application.launch", {
            desktopId: appId,
            urls: []
        }, function(response) {
            if (!response.ok) {
                if (entry.runInTerminal) {
                    // Spawning a terminal app without a TTY always dies; a
                    // silent dead process is worse than a logged refusal.
                    console.warn("[AppAction] terminal app launch failed, "
                                 + "no TTY fallback app=" + appId)
                    return
                }
                service._executeDirect(entry, appId, "platform-launch")
            }
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

    // Widgets use the desktop entry as the executable authority, then append
    // app-owned deep-link arguments. With no arguments the regular launcher
    // path remains in use, including all DesktopEntry environment handling.
    function launchById(desktopId, launchArguments) {
        const entry = entryForId(desktopId)
        if (!entry) {
            console.warn("[AppAction] desktop entry is not installed: " + desktopId)
            return false
        }
        const extra = launchArguments ?? []
        if (extra.length === 0)
            return launch(entry)
        const baseCommand = entry.command ?? []
        if (baseCommand.length === 0) {
            console.warn("[AppAction] desktop entry has no launch command: " + desktopId)
            return false
        }
        if (entry.runInTerminal)
            return _executeDirect(entry, desktopId, "terminal-deep-link")
        console.log("[AppAction] deep link app=" + desktopId
                    + " args=" + JSON.stringify(extra))
        // KOS-owned deep links currently use explicit argv rather than URLs.
        // Keep that narrow path until each app publishes a URL scheme.
        return _executeCommandDirect(Array.from(baseCommand).concat(extra), desktopId)
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
