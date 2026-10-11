import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.desktop.modules.bar
import qs.desktop.modules.notifications
import qs.desktop.modules.deskcenter
ShellRoot {
    NotificationServer {
        id: server
        actionsSupported: true
        bodySupported: true
        inlineReplySupported: true
        onNotification: n => {
            n.tracked = true
            groups.showNotification(n, false)
            ControlCenterService.registerLiveNotification(n)
            groups.pushHistory(n)
        }
    }
    NotificationGroupService { id: groups; sourceModel: server.trackedNotifications }
    NotificationWindow { id: popup; groupService: groups; TestEvent { id: events } }
    FloatingWindow {
        visible: true; implicitWidth: 390; implicitHeight: 600
        DeskNotificationWidget { id: historyWidget }
        TestEvent { id: historyEvents }
    }
    function find(item, key, value) {
        if (item[key] === value) return item
        for (const child of item.children || []) {
            const match = find(child, key, value)
            if (match) return match
        }
        return null
    }
    IpcHandler {
        target: "test"
        function state(): string {
            const notices = server.trackedNotifications.values.map(n => ({id:n.id, app:n.appName, actions:n.actions.length}))
            return JSON.stringify({notices:notices, groups:groups.groupsModel.count})
        }
        function click(group: string, label: string): bool {
            const card = find(popup.contentItem, "groupKey", group)
            if (!card) return false
            const item = label === "body" ? find(card, "objectName", "notification-body") : find(card, "text", label)
            if (!item) return false
            return events.mousePress(item, item.width/2, item.height/2, Qt.LeftButton, Qt.NoModifier, 0)
                && events.mouseRelease(item, item.width/2, item.height/2, Qt.LeftButton, Qt.NoModifier, 0)
        }
        function invoke(id: int): bool { return ControlCenterService.invokeNotificationAction(id, "", "") }
        function historyHover(id: int): bool {
            const list = find(historyWidget, "objectName", "desk-notification-list")
            for (let i = 0; i < historyWidget.filteredHistory.count; i++) {
                if (historyWidget.filteredHistory.get(i).notifId === id) {
                    list.positionViewAtIndex(i, ListView.Contain)
                    list.forceLayout()
                    break
                }
            }
            const row = find(historyWidget, "notifId", id)
            return row !== null && historyEvents.mouseMove(row, row.width/2, row.height/2, 0, Qt.NoButton, Qt.NoModifier)
        }
        function historyState(id: int): string {
            const row = find(historyWidget, "notifId", id)
            if (!row) return "{}"
            return JSON.stringify({hovered:row.isHovered, hasAction:row.hasAction,
                openVisible:find(row,"objectName","notification-history-open").visible,
                deleteVisible:find(row,"objectName","notification-history-delete").visible})
        }
        function historyClick(id: int): bool {
            const row = find(historyWidget,"notifId",id)
            if (!row) return false
            return historyEvents.mousePress(row,row.width/2,row.height/2,Qt.LeftButton,Qt.NoModifier,0)
                && historyEvents.mouseRelease(row,row.width/2,row.height/2,Qt.LeftButton,Qt.NoModifier,0)
        }
        function clear(): void { ControlCenterService.clearAllNotifications() }
    }
}
