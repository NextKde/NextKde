import QtQuick
import Quickshell
import "."
Scope {
    Component.onCompleted: {
        function assert(value, message) { if (!value) throw new Error(message) }
        function push(app, id, desktop = "") {
            NotificationHistoryService.push({notifId: id, appName: app, desktopEntry: desktop,
                appIcon: "", summary: "test " + id, body: "body", urgency: 1, timestamp: Date.now()})
        }
        function items(index = 0) { return JSON.parse(NotificationHistoryService.groups.get(index).itemsJson) }
        push("Same Name", 1, "org.test.one"); push("Same Name", 2, "org.test.two")
        assert(NotificationHistoryService.groups.count === 2, "desktop identity isolates matching names")
        push("Same Name", 3, "org.test.one"); push("Same Name", 4, "org.test.one")
        assert(NotificationHistoryService.groups.count === 2 && items().length === 3, "three-member stack")
        assert(NotificationHistoryService.groups.get(0).expanded === false, "stack starts collapsed")
        NotificationHistoryService.setExpanded("desktop:org.test.one", true)
        push("Same Name", 5, "org.test.one")
        assert(NotificationHistoryService.groups.get(0).expanded, "arrival preserves expansion")
        const replacementKey = items()[0].historyKey
        push("Renamed", 5, "org.test.one.desktop")
        assert(NotificationHistoryService.groups.get(0).itemCount === 4, "replacement does not duplicate")
        assert(items()[0].historyKey === replacementKey, "replacement preserves history key")
        assert(NotificationHistoryService.groups.get(0).appName === "Renamed", "group label follows newest event")
        NotificationHistoryService.removeKeys(items().slice(2).map(item => item.historyKey))
        assert(items().length === 2, "reduce group to two")
        NotificationHistoryService.remove(items()[0].historyKey)
        assert(items().length === 1, "two to one")
        NotificationHistoryService.remove(items()[0].historyKey)
        assert(NotificationHistoryService.groups.count === 1, "one to zero removes only that source")
        const clicked = NotificationHistoryService.allKeys()
        push("New", 20, "org.test.new")
        NotificationHistoryService.removeKeys(clicked)
        assert(NotificationHistoryService.count === 1 && items()[0].summary === "test 20", "clear snapshot preserves new arrival")
        const clearedKey = items()[0].historyKey
        NotificationHistoryService.removeKeys(NotificationHistoryService.allKeys())
        push("New", 20, "org.test.new")
        assert(items()[0].historyKey !== clearedKey, "replacement after removal gets new key")
        const groupKeys = NotificationHistoryService.keysForSource("desktop:org.test.new")
        push("New", 21, "org.test.new")
        NotificationHistoryService.removeKeys(groupKeys)
        assert(items().length === 1 && items()[0].summary === "test 21", "group snapshot preserves new member")
        for (let i=0; i<60; ++i) push("A", 100 + i)
        assert(NotificationHistoryService.count === 50, "capacity")
        assert(NotificationHistoryService.groups.get(0).itemCount === 50, "group capacity")
        NotificationHistoryService.clear()
        assert(NotificationHistoryService.groups.count === 0 && NotificationHistoryService.count === 0, "clear")
        push("Same Name", 900, "org.test.one")
        assert(NotificationHistoryService.groups.get(0).expanded, "expanded state lasts through group disappearance")
        console.log("HISTORY_MODEL_TEST_PASS")
        Qt.callLater(function() { Qt.quit() })
    }
}
