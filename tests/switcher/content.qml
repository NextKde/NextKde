import QtQuick
import Quickshell
import qs.desktop.modules.switcher

// Real glass and card imports; no compositor, window capture or layout writes.
FloatingWindow {
    id: window
    implicitWidth: 760
    implicitHeight: 240
    visible: true
    color: "transparent"
    SwitcherContent {
        id: content
        anchors.centerIn: parent
        width: 720
        height: implicitHeight
    }
    Timer {
        interval: 250
        running: true
        onTriggered: {
            if (content.mapped || content.selectedIndex !== -1)
                throw new Error("Empty switcher must stay hidden")
            content.windows = [
                { handleId: "", windowId: "", title: "Kate", iconSource: "" },
                { handleId: "", windowId: "", title: "Dolphin", iconSource: "" },
                { handleId: "", windowId: "", title: "Konsole", iconSource: "" }
            ]
            content.requestedOpen = true
            finish.start()
        }
    }
    Timer {
        id: finish
        interval: 500
        onTriggered: {
            if (!content.mapped || content.revealProgress !== 1)
                throw new Error("Switcher did not reveal")
            console.info("SWITCHER_CONTENT_PASS")
            Qt.quit()
        }
    }
}
