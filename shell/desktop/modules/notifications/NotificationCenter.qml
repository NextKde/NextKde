import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.notifications

// The session D-Bus permits only one org.freedesktop.Notifications owner.
// When Plasma's daemon owns it, this server stays inactive, so notifications
// are never displayed twice.
Scope {
    id: root

    readonly property var targetScreen: ScreenLifecycle.activeScreen

    function recordNotification(notification) {
        if (!NotificationPolicyService.ready) return
        NotificationPolicyService.remember(notification)
        if (NotificationPolicyService.isBlocked(notification)) {
            notification.tracked = false
            return
        }
        notification.tracked = !ControlCenterService.doNotDisturbEnabled
        AppNotificationService.recordNotification({
            desktopEntry: notification.desktopEntry || "",
            appName: notification.appName || "",
            summary: notification.summary || "",
            body: notification.body || "",
            hints: notification.hints || ({})
        })
        notifGroupService.pushHistory(notification)
    }
    Component {
        id: historyObserver
        NotificationHistoryObserver {}
    }

    NotificationServer {
        id: server
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true
        imageSupported: true
        bodyImagesSupported: true
        inlineReplySupported: true
        keepOnReload: false

        onNotification: notification => {
            // Quickshell updates a replacement in place without another
            // server.notification signal. Watch the live object, including
            // objects that DND leaves untracked, until its own destruction.
            historyObserver.createObject(notification, {
                notification: notification, record: root.recordNotification,
                ready: Qt.binding(function() { return NotificationPolicyService.ready })
            })
            // Retain startup notifications until persistent policy is loaded;
            // the banner surface stays hidden during that short window.
            if (!NotificationPolicyService.ready)
                notification.tracked = true
        }
    }

    Connections {
        target: NotificationPolicyService
        function onBlockedKeysChanged() {
            for (const notification of notifGroupService._collectNotifications())
                if (NotificationPolicyService.isBlocked(notification))
                    notification.tracked = false
        }
    }
    Connections {
        target: ControlCenterService
        function onDoNotDisturbEnabledChanged() {
            if (ControlCenterService.doNotDisturbEnabled)
                for (const notification of notifGroupService._collectNotifications())
                    notification.tracked = false
        }
    }

    // Groups trackedNotifications by desktopEntry into a project-owned
    // ListModel. The popup and history views bind to this, not to the raw
    // read-only server model.
    NotificationGroupService {
        id: notifGroupService
        sourceModel: server.trackedNotifications
    }

    NotificationWindow {
        screen: root.targetScreen
        visible: NotificationPolicyService.ready && ScreenLifecycle.outputAvailable && root.targetScreen !== null
        groupService: notifGroupService
    }
}
