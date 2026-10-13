import QtQuick
import Quickshell
import Quickshell.Io
import qs.desktop.modules.notifications
import qs.desktop.modules.bar
import qs.desktop.modules.common
Scope {
    NotificationCenter {}
    IpcHandler {
        target: "notifications"
        function dnd(enabled: bool): void { ControlCenterService.doNotDisturbEnabled = enabled }
        function block(key: string, blocked: bool): void { NotificationPolicyService.setBlocked(key, blocked) }
        function clear(): void { NotificationHistoryService.clear(); AppNotificationService.clearAll() }
        function stats(): string {
            const rows = []
            for (let i=0; i<NotificationHistoryService.history.count; ++i) {
                const row = NotificationHistoryService.history.get(i)
                rows.push({id: row.notifId, key: row.historyKey, summary: row.summary, body: row.body})
            }
            return JSON.stringify({ready: NotificationPolicyService.ready, rows: rows,
                sources: NotificationPolicyService.sources, blocked: NotificationPolicyService.blockedKeys,
                unread: AppNotificationService.unreadGroups,
                banners: ScreenLifecycle.testBannerCount, dnd: ControlCenterService.doNotDisturbEnabled})
        }
    }
}
