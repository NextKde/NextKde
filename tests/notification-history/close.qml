import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.notifications

Scope {
    id: test
    property int phase: 0
    property bool failed: false

    function check(condition, message) {
        if (!condition) {
            failed = true
            console.error("HISTORY_CLOSE_FAIL", message)
            Qt.quit()
        }
    }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const found = find(child, name)
            if (found) return found
        }
        return null
    }

    PanelWindow {
        anchors { top: true; right: true }
        WlrLayershell.layer: WlrLayer.Top
        implicitWidth: 360
        implicitHeight: 32
        Item { id: anchor; x: 260; width: 24; height: 24 }
        NotificationHistoryPanel { id: history; anchorItem: anchor; closeDuration: 500 }
        StatusTooltip {
            anchorItem: anchor
            shown: test.phase > 0 && !history.requestedOpen
            primaryText: "Notification History"
        }
    }
    Timer {
        running: true
        interval: 1500
        onTriggered: {
            for (let i = 0; i < 4; ++i)
                NotificationHistoryService.push({notifId: i, appName: "QA", appIcon: "",
                    desktopEntry: "org.test.close", urgency: 1, summary: "Notification " + i,
                    body: "Closing cards must disappear smoothly.", timestamp: Date.now()})
            history.show()
        }
    }
    Timer {
        running: true
        repeat: true
        interval: 16
        onTriggered: {
            const blur = history.BackgroundEffect.blurRegion
            test.check(blur === null || blur.regions.length > 0, "empty legacy blur request")
            const pane = test.find(history.contentItem, "notification-history-pane")
            if (!pane || test.failed) return
            if (test.phase === 0 && history.revealProgress === 1) {
                test.check(pane.paintedCards.length === 3, "three painted cards")
                test.check(pane.paintedCards.every(card => card.fixedCaptureSupported), "native fixed capture")
                history.close()
                test.phase = 1
            } else if (test.phase === 1 && history.revealProgress > 0 && history.revealProgress < 0.8) {
                test.check(history.visible && !history.interactive, "exit retains mapping without input")
                const progress = history.revealProgress
                history.show()
                test.check(history.revealProgress === progress, "continuous reversal")
                test.phase = 2
            } else if (test.phase === 2 && history.revealProgress === 1) {
                history.close()
                test.phase = 3
            } else if (test.phase === 3 && !history.visible) {
                test.check(blur === null, "blur retired on hide")
                test.phase = 4
                regularSettle.start()
            } else if (test.phase === 5 && history.revealProgress === 1 && pane.emptyStateReady) {
                history.close()
                test.phase = 6
            } else if (test.phase === 6 && !history.visible) {
                test.phase = 7
                settle.start()
            }
        }
    }
    // Observe KWin's popup fade after the client has unmapped its surface.
    // Do this before reopening as well, so a new popup cannot cover the flash.
    Timer {
        id: regularSettle
        interval: 1000
        onTriggered: {
            NotificationHistoryService.clear()
            history.show()
            test.phase = 5
        }
    }
    Timer {
        id: settle
        interval: 1000
        onTriggered: {
            if (!test.failed) console.log("HISTORY_CLOSE_PASS")
            Qt.quit()
        }
    }
    Timer { running: true; interval: 10000; onTriggered: { console.error("HISTORY_CLOSE_FAIL timeout"); Qt.quit() } }
}
