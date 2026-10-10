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

    // Launch by desktop id. Callers may pass a DesktopEntry itself, or any
    // object that carries an id (presentation descriptor, identity result,
    // catalogue item). The entry is resolved here, at call time: it must never
    // be stored on the caller's side, because DesktopEntries destroys and
    // replaces entries on every catalogue rescan.
    function launch(application) {
        const provided = application && typeof application.execute === "function"
            ? application : null
        const appId = String(provided?.id ?? application?.desktopId
            ?? application?.id ?? application?.rawAppId ?? "")
        if (!appId) {
            console.warn("[AppAction] cannot launch without an app id")
            return false
        }
        const entry = provided ?? AppPresentationService.entryFor(appId)

        // Terminal entries (Terminal=true, e.g. nvim/htop) must NOT go through
        // DesktopEntry.execute(): Quickshell spawns the bare command with no
        // TTY and terminal apps die immediately. Route them through the
        // platform daemon here; KIO::ApplicationLauncherJob wraps them in the
        // user's configured terminal.
        if (!PlatformClient.connected) {
            if (!entry || entry.runInTerminal) {
                console.warn("[AppAction] launch needs the platform daemon, "
                             + "no TTY fallback exists app=" + appId)
                return false
            }
            return _executeDirect(entry, appId, "platform-unavailable")
        }
        return _requestDaemonLaunch(appId)
    }

    // The daemon op accepts only {desktopId, urls}, so it still works when the
    // entry could not be resolved -- for example it was uninstalled between the
    // catalogue snapshot and the click. Only the direct argv fallback needs a
    // live entry.
    function _requestDaemonLaunch(appId) {
        PlatformClient.request("application.launch", {
            desktopId: appId,
            urls: []
        }, function(response) {
            if (!response.ok) {
                // DesktopEntries may have rescanned while the daemon request
                // was pending. Resolve at use time instead of capturing a
                // DesktopEntry that the catalogue can destroy.
                const entry = AppPresentationService.entryFor(appId)
                if (!entry || entry.runInTerminal) {
                    // Spawning a terminal app without a TTY always dies; a
                    // silent dead process is worse than a logged refusal.
                    console.warn("[AppAction] launch failed, no direct fallback "
                                 + "exists app=" + appId)
                    return
                }
                service._executeDirect(entry, appId, "platform-launch")
            }
        })
        console.log("[AppAction] platform launch app=" + appId)
        return true
    }

    // Widgets use the desktop entry as the executable authority, then append
    // app-owned deep-link arguments. With no arguments the regular launcher
    // path remains in use, including all DesktopEntry environment handling.
    function launchById(desktopId, launchArguments) {
        const entry = AppPresentationService.entryFor(desktopId)
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
