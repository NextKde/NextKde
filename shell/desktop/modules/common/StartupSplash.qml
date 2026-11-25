// Stops the login spinner (splash/shell.qml) when the arrival animation takes
// the screen over. The spinner itself is started by kos-shell.service in
// parallel with this process: no QML here runs until the whole desktop tree
// has been constructed, which is exactly the wait the spinner exists for, so
// starting it from here would miss most of it.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.desktop.modules.common

Item {
    id: root

    // Its own directory with a shell.qml: the splash must not be a lone QML
    // file next to the desktop modules, whose sibling imports the scanner
    // would try to resolve.
    readonly property string splashPath: Quickshell.shellPath("splash")

    Process {
        id: killer
        // pkill -f matches the full command line; the splash's -p argument
        // carries this exact path and nothing else in the session does.
        // starting an already-running process is a no-op, so both triggers
        // can fire without a guard.
        command: ["pkill", "-f", "--", root.splashPath]
    }

    Connections {
        target: StartupReveal
        function onStartedChanged() {
            if (StartupReveal.started)
                killer.running = true
        }
        function onActiveChanged() {
            if (!StartupReveal.active)
                killer.running = true
        }
    }
}
