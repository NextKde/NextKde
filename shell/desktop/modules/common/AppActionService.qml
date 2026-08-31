pragma Singleton
import QtQuick

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

    function launch(application) {
        const entry = application?.entry ?? application
        const appId = String(application?.id ?? entry?.id ?? "")
        if (!entry?.execute) {
            console.warn("[AppAction] cannot launch without DesktopEntry app=" + appId)
            return false
        }
        try {
            entry.execute()
            console.log("[AppAction] launch app=" + appId)
            return true
        } catch (error) {
            console.warn("[AppAction] failed to launch app=" + appId + ": " + error)
            return false
        }
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
