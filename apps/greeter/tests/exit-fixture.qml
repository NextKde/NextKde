import QtQuick
import Quickshell
ShellRoot {
    Timer { interval: 1000; running: true; onTriggered: Qt.quit() }
}
