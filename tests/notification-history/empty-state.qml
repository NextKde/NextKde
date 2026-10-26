import QtQuick
import Quickshell
import qs.desktop.modules.bar
import qs.desktop.modules.notifications
import "Kos/Ui"

Scope {
    id: test
    property int stage: 0
    property bool sawExit: false
    property bool sawShrink: false
    property bool sawFade: false
    property bool sawOverlappingFade: false
    property real fadeStartedAt: 0
    property real removalStartedAt: 0
    function assert(value, message) { if (!value) throw new Error(message) }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const result = find(child, name)
            if (result) return result
        }
        return null
    }
    function push(id) {
        NotificationHistoryService.push({notifId:id, appName:"Test", desktopEntry:"org.test.empty", appIcon:"",
            summary:"Message " + id, body:"Empty state transition", timestamp:Date.now(), urgency:1})
    }
    function settled() { return Math.abs(pane.height - pane.desiredHeight) < 0.01 }
    FloatingWindow {
        visible: true
        implicitWidth: 336; implicitHeight: 600
        NotificationHistoryPane {
            id: pane
            x: 20; y: 20; width: 296
            height: desiredHeight
            compositorGlass: false
        }
    }
    Timer {
        running: true; repeat: true; interval: 16
        onTriggered: {
            const empty = test.find(pane, "notification-history-empty")
            const list = test.find(pane, "notification-history-list")
            if (empty.visible) {
                test.assert(NotificationHistoryService.count === 0 && pane.historyExitCount === 0 && pane.historyEmptyReady,
                    "empty card never overlaps outgoing or incoming messages")
                test.assert(Math.abs(empty.height - 68) < 0.01,
                    "empty card keeps its final size throughout deck contraction")
                test.assert(Math.abs(empty.materialOpacity - pane.glassOpacity * empty.opacity) < 0.001,
                    "native glass follows the empty card fade")
            }
            if (test.stage === 0 && empty.visible && empty.opacity === 1) {
                for (let i = 1; i <= 4; ++i) test.push(i)
                test.stage = 1
            } else if (test.stage === 1 && test.settled() && list.itemAtIndex(0)) {
                pane.clearHistory()
                test.removalStartedAt = Date.now()
                test.stage = 2
            } else if (test.stage === 2) {
                if (pane.historyExitCount > 0) test.sawExit = true
                if (pane.historyEmptyReady && pane.height > pane.previewHeight + 1) test.sawShrink = true
                if (empty.visible && empty.opacity > 0 && empty.opacity < 1) {
                    test.sawFade = true
                    if (!test.fadeStartedAt) {
                        test.fadeStartedAt = Date.now()
                        test.assert(empty.opacity < 0.15, "empty state starts gently near transparent")
                        test.assert(test.fadeStartedAt - test.removalStartedAt < 400,
                            "empty state follows exits without waiting for a second layout animation")
                    }
                    if (pane.height > pane.previewHeight + 1) test.sawOverlappingFade = true
                }
                if (empty.visible && empty.opacity === 1) {
                    test.assert(test.sawExit && test.sawShrink && test.sawFade && test.sawOverlappingFade,
                        "clear preserves exits and fades a fixed card during contraction")
                    test.assert(Date.now() - test.fadeStartedAt >= 280, "empty fade remains gradual instead of flashing on")
                    test.push(5)
                    test.stage = 3
                }
            } else if (test.stage === 3 && test.settled() && list.itemAtIndex(0)) {
                test.find(list.itemAtIndex(0).cardItem, "notification-remove-button").clicked()
                test.stage = 4
            } else if (test.stage === 4 && pane.historyEmptyReady && pane.height > pane.previewHeight + 1) {
                // A new arrival during the final shrink cancels the empty card.
                test.push(6)
                test.stage = 5
            } else if (test.stage === 5 && test.settled() && list.itemAtIndex(0)) {
                test.assert(!empty.visible && NotificationHistoryService.count === 1, "arrival cancels pending empty state")
                test.find(list.itemAtIndex(0).cardItem, "notification-remove-button").clicked()
                test.stage = 6
            } else if (test.stage === 6 && empty.visible && empty.opacity > 0.15 && empty.opacity < 0.8) {
                test.push(8)
                test.assert(!empty.visible, "arrival during the fade hides the empty card immediately")
                test.stage = 7
            } else if (test.stage === 7 && test.settled() && list.itemAtIndex(0)) {
                test.find(list.itemAtIndex(0).cardItem, "notification-remove-button").clicked()
                test.stage = 8
            } else if (test.stage === 8 && empty.visible && empty.opacity === 1) {
                AppTheme.reduceMotion = true
                test.push(7)
                test.stage = 9
            } else if (test.stage === 9 && test.settled() && list.itemAtIndex(0)) {
                pane.clearHistory()
                test.stage = 10
            } else if (test.stage === 10 && empty.visible) {
                test.assert(empty.opacity === 1 && test.settled(), "reduced motion shows settled empty card without fading")
                pane.showEmptyState = false
                test.assert(!empty.visible, "embedded history keeps its empty card hidden")
                console.log("HISTORY_EMPTY_STATE_PASS")
                Qt.quit()
            }
        }
    }
    Timer { running:true; interval:6500; onTriggered: { throw new Error("empty state test timeout at stage " + test.stage); Qt.quit() } }
}
