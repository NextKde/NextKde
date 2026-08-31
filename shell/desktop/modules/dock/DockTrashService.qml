pragma Singleton

import QtQuick
import Quickshell.Io

// The Dock owns the destructive empty action.  Desktop file deletion itself
// remains recoverable (gio trash); only this explicit confirmation purges it.
QtObject {
    id: service

    property bool emptying: false
    property bool hasItems: false
    signal depositReceived()
    property Component processFactory: Component {
        Process { stdout: StdioCollector {} }
    }

    function refreshContentState() {
        const process = processFactory.createObject(service, {
            command: ["sh", "-c",
                "data=${XDG_DATA_HOME:-$HOME/.local/share}; "
                + "find \"$data/Trash/files\" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null",
                "dock-trash-state"]
        })
        process.exited.connect(function(exitCode) {
            hasItems = exitCode === 0 && (process.stdout?.text ?? "").trim().length > 0
            process.destroy()
        })
        process.running = true
    }

    function open() {
        refreshContentState()
        const process = processFactory.createObject(service, {
            // KDE exposes its Trash view as trash:/; the local GIO backend
            // does not implement the cross-desktop trash:/// URI here.
            command: ["dolphin", "trash:/"]
        })
        process.exited.connect(function() { process.destroy() })
        process.running = true
    }

    function empty() {
        if (emptying)
            return
        emptying = true
        const process = processFactory.createObject(service, {
            // This session's GIO backend cannot enumerate or empty trash,
            // even though Dolphin can display it via trash:/. Clear the
            // freedesktop Trash specification's two payload directories only
            // after the explicit destructive confirmation in the Dock popup.
            command: ["sh", "-c",
                "data=${XDG_DATA_HOME:-$HOME/.local/share}; trash=\"$data/Trash\"; "
                + "for location in \"$trash/files\" \"$trash/info\"; do "
                + "test -d \"$location\" || continue; "
                + "find \"$location\" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +; "
                + "done",
                "dock-empty-trash"]
        })
        process.exited.connect(function(exitCode) {
            emptying = false
            if (exitCode !== 0)
                console.warn("[DockTrash] unable to empty trash")
            else
                hasItems = false
            process.destroy()
        })
        process.running = true
    }

    function celebrateDeposit() {
        hasItems = true
        depositReceived()
    }

    Component.onCompleted: refreshContentState()
}
