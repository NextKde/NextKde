import QtQuick
import Quickshell
import "."
Scope {
    id: test
    property int stage: 0
    property int exitCount: 0
    property int expectedExits: 0
    property real collapsedHeight: 0
    property var heldKeys: []
    function assert(value, message) { if (!value) throw new Error(message) }
    function beginHistoryExit() { exitCount++ }
    function endHistoryExit() { exitCount-- }
    function historyGroupVisible(item) { return item.y + item.height > list.contentY && item.y < list.contentY + list.height }
    function historyExitDelay(source) { return source === "name:A" ? 60 : 0 }
    function push(app, id) { NotificationHistoryService.push({notifId: id, appName: app, desktopEntry: "", appIcon: "", summary: "Title " + id, body: "Body preserved through exit", urgency: 1, timestamp: Date.now()}) }
    FloatingWindow {
        visible: true
        implicitWidth: 340
        implicitHeight: 600
        color: "#252932"
        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12
            model: NotificationHistoryService.groups
            displaced: Transition { NumberAnimation { property: "y"; duration: 200; easing.type: Easing.OutCubic } }
            delegate: NotificationHistoryGroup {
                width: list.width
                coordinator: test
            }
        }
    }
    Timer {
        interval: 320
        running: true
        repeat: true
        onTriggered: {
            if (test.stage === 0) {
                test.push("A", 1); test.push("A", 2); test.push("A", 3)
            } else if (test.stage === 1) {
                const group = list.itemAtIndex(0)
                test.assert(group !== null && group.itemCount === 3 && !group.expanded, "collapsed group loads")
                test.assert(group.headerHeight === 0 && group.backHeight === 12, "collapsed header is inside card and only bottom backs remain")
                test.assert(group.leadingItem && group.leadingItem.painted.additionalCount === 2, "additional count is in leading card")
                test.assert(group.height >= group.leadingItem.height + 12, "folded card is not clipped")
                test.collapsedHeight = group.height
                NotificationHistoryService.setExpanded("name:A", true)
            } else if (test.stage === 2) {
                const group = list.itemAtIndex(0)
                test.assert(group.expanded && group.height > test.collapsedHeight + 80, "expand reaches full height")
                test.assert(group.headerHeight === 32 && group.backHeight === 0, "expanded group exposes controls without backs")
                test.assert(group.leadingItem.painted.additionalCount === 0, "expanded member has no folded count")
                NotificationHistoryService.setExpanded("name:A", false)
            } else if (test.stage === 3) {
                const group = list.itemAtIndex(0)
                test.assert(!group.expanded && Math.abs(group.height - test.collapsedHeight) < 2, "collapse settles")
                NotificationHistoryService.setExpanded("name:A", true)
            } else if (test.stage === 4) {
                NotificationHistoryService.remove(NotificationHistoryService.keysForSource("name:A")[0])
                test.expectedExits = 1; exitProbe.restart()
            } else if (test.stage === 5) {
                test.assert(test.exitCount === 0 && list.itemAtIndex(0).itemCount === 2, "single exit releases")
                NotificationHistoryService.remove(NotificationHistoryService.keysForSource("name:A")[0])
            } else if (test.stage === 6) {
                test.assert(test.exitCount === 0 && list.itemAtIndex(0).itemCount === 1, "two to one settles")
                test.heldKeys = NotificationHistoryService.allKeys()
                NotificationHistoryService.removeKeys(test.heldKeys)
                test.expectedExits = 1; exitProbe.restart()
                test.push("A", 1)
            } else if (test.stage === 7) {
                test.assert(test.exitCount === 0 && NotificationHistoryService.count === 1 && list.count === 1, "new arrival survives old group exit")
                test.assert(list.itemAtIndex(0).opacity > 0.99, "new group does not inherit exit opacity")
                test.push("B", 4)
            } else if (test.stage === 8) {
                NotificationHistoryService.removeKeys(NotificationHistoryService.allKeys())
                test.expectedExits = 2; exitProbe.restart()
            } else if (test.stage === 9) {
                test.assert(test.exitCount === 0 && list.count === 0, "clear finishes within 300ms")
                console.log("HISTORY_VISUAL_TEST_PASS")
                Qt.quit()
            }
            test.stage++
        }
    }
    Timer {
        id: exitProbe
        interval: 40
        onTriggered: test.assert(test.exitCount === test.expectedExits, "exit owner registers once")
    }
    Timer { running: true; interval: 5000; onTriggered: { throw new Error("visual test timeout") } }
}
