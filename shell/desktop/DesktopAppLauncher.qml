pragma Singleton
import QtQuick
import Quickshell
import qs.desktop.modules.dock

// Starts standalone Qt Quick applications without importing their UI into, or
// tying their lifetime to, the Shell process.
QtObject {
    id: launcher

    // Settings window id. `kos-settings` sets QGuiApplication::setDesktopFileName
    // to the same value, so its live window resolves to this desktop id through
    // the shared identity boundary.
    readonly property string settingsDesktopId: "kos-settings"

    readonly property string settingsBinary:
        Quickshell.shellDir + "/../.build/kosctl/apps/settings/kos-settings"

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
        // each click drew another window. execDetached cannot activate what a
        // *new* process does not own yet, so focus the open window through the
        // compositor and only launch when none exists.
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

        Quickshell.execDetached([
            "sh", "-c",
            // Settings talks back to its Shell over Quickshell IPC. Preserve
            // the active Shell directory so a source-tree session opens a
            // Settings window connected to that same session rather than the
            // installed `kos` configuration. Candidates are deliberately
            // limited to the canonical kosctl build artifact plus the
            // installed copy: a second build tree would drift and open a
            // Settings build that does not match the running Shell.
            "export KOS_SHELL_DIR=\"$2\"; "
            + "if [ -x \"$1\" ]; then exec \"$1\"; fi; "
            + "if command -v kos-settings >/dev/null 2>&1; then exec kos-settings; fi; "
            + "if [ -x \"$HOME/.local/bin/kos-settings\" ]; then exec \"$HOME/.local/bin/kos-settings\"; fi; "
            + "echo 'kos-settings is not built; run ./tools/kosctl build' >&2; exit 1",
            "kos-settings-launch",
            launcher.settingsBinary,
            Quickshell.shellDir
        ])
    }

    // Covers the gap between execDetached returning and the compositor
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
