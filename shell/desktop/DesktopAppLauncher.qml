pragma Singleton
import QtQuick
import Quickshell
import qs.desktop.modules.dock
import qs.desktop.modules.platform

// Starts standalone Qt Quick applications without importing their UI into, or
// tying their lifetime to, the Shell process.
QtObject {
    id: launcher

    // Settings window id. `kos-settings` sets QGuiApplication::setDesktopFileName
    // to the same value, so its live window resolves to this desktop id through
    // the shared identity boundary.
    readonly property string settingsDesktopId: "kos-settings"

    // The Settings window the user already has open, or null. KWin owns these
    // windows, so the lookup stays correct after the window is minimized, moved
    // to another virtual desktop, or loses focus.
    function settingsWindow() {
        const records = WindowService.records || []
        for (let i = 0; i < records.length; i++) {
            const record = records[i]
            if (record && AppIdentityService.sameApp(record.identity, settingsDesktopId))
                return record
        }
        return null
    }

    function openSettings() {
        // Clicking the Bar/Dock entry used to fork a process on every click, so
        // each click drew another window. A daemon launch cannot activate what
        // a *new* process does not own yet, so focus the open window through
        // the compositor and only launch when none exists.
        const existing = settingsWindow()
        if (existing) {
            WindowService.activateWindow(existing.windowId)
            return
        }
        // A launch in flight has no window to focus yet; collapsing repeat
        // clicks here is what keeps a double click from drawing two windows.
        if (launchPending.running)
            return
        launchPending.restart()

        // Fixed-argv launch through the platform daemon. Quickshell.shellDir
        // is passed as data so the daemon can export KOS_SHELL_DIR: Settings
        // talks back to its Shell over Quickshell IPC, and a source-tree
        // session must open a Settings window connected to that same session
        // rather than the installed `kos` configuration.
        PlatformClient.request("settings.launch", {
            shellDir: Quickshell.shellDir
        }, function(response) {
            if (!response?.ok) {
                launchPending.stop()
                console.warn("[Launcher] kos-settings launch failed: "
                    + (response?.error?.message || "platform unavailable"))
            }
        })
    }

    // Covers the gap between the launch request returning and the compositor
    // publishing the new window in the next KWin snapshot.
    property Timer launchPending: Timer {
        interval: 3000
        repeat: false
    }

    // Release the guard the moment the window is published, so closing Settings
    // and clicking again never lands inside the in-flight window and gets
    // swallowed.
    property Connections windowConnections: Connections {
        target: WindowService
        function onRevisionChanged() {
            if (launcher.launchPending.running && launcher.settingsWindow())
                launcher.launchPending.stop()
        }
    }
}
