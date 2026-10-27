pragma Singleton

import QtQuick
import "NotificationCountMatch.mjs" as NotificationCountMatch

// Session-scoped unread notification events shared with the Dock. Banner
// expiry does not imply that the application content was read.
QtObject {
    id: service

    property var unreadGroups: []
    property int revision: 0

    function _replace(groups) {
        if (JSON.stringify(groups) === JSON.stringify(unreadGroups))
            return false
        unreadGroups = groups
        revision++
        return true
    }

    function recordNotification(notification) {
        return _replace(NotificationCountMatch.recordNotification(
            unreadGroups, notification))
    }

    function countForApp(appId, appName) {
        const observedRevision = revision
        return NotificationCountMatch.countForApp(unreadGroups,
            appId, appName, AppPresentationService.normalize)
    }

    function clearForApp(appId, appName, windowId, appWindowCount) {
        return _replace(NotificationCountMatch.clearForTask(unreadGroups,
            appId, appName, windowId || "", appWindowCount || 0,
            AppPresentationService.normalize))
    }

    function countForTask(appId, appName, windowId, appWindowCount) {
        const observedRevision = revision
        return NotificationCountMatch.countForTask(unreadGroups,
            appId, appName, windowId, appWindowCount,
            AppPresentationService.normalize)
    }

    function clearGroup(groupKey) {
        return _replace(NotificationCountMatch.clearGroup(
            unreadGroups, groupKey))
    }

    function clearAll() {
        return _replace([])
    }
}
