pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "AppLaunchIsolation.mjs" as AppLaunchIsolation

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

    function _isolatedLaunch(entry, appId, command, preserveCommandOnFallback) {
        const nonce = Date.now().toString(36)
            + "-" + Math.floor(Math.random() * 0x1000000).toString(36)
        const scopedCommand = AppLaunchIsolation.systemdCommand(
            command, appId, nonce, entry?.workingDirectory ?? "")
        if (scopedCommand.length === 0)
            return _executeDirect(entry, appId, "missing-command")

        const process = launchProcessFactory.createObject(service, {
            command: scopedCommand
        })
        process.exited.connect(function(exitCode) {
            if (exitCode !== 0) {
                const detail = String(process.stderr?.text ?? "").trim()
                console.warn("[AppAction] isolated launch failed app=" + appId
                    + " exit=" + exitCode + (detail ? " error=" + detail : ""))
                if (preserveCommandOnFallback)
                    service._executeCommandDirect(command, appId)
                else
                    service._executeDirect(entry, appId, "systemd-run")
            }
            process.destroy()
        })
        process.running = true
        console.log("[AppAction] isolated launch app=" + appId)
        return true
    }

    function launch(application) {
        const entry = application?.entry ?? application
        const appId = String(application?.id ?? entry?.id ?? "")
        if (!entry?.execute) {
            console.warn("[AppAction] cannot launch without DesktopEntry app=" + appId)
            return false
        }
        // DesktopEntry.execute() knows how to select the user's terminal. Keep
        // that native path for terminal entries rather than guessing one here.
        if (entry.runInTerminal)
            return _executeDirect(entry, appId, "terminal-entry")
        return _isolatedLaunch(entry, appId,
            Array.from(entry.command ?? []), false)
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
        return _isolatedLaunch(entry, desktopId,
            Array.from(baseCommand).concat(extra), true)
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

    property Component launchProcessFactory: Component {
        Process {
            stdout: StdioCollector {}
            stderr: StdioCollector {}
        }
    }

}
