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
            // Count arrival events before tracked/untracked presentation is
            // decided. Replacements are new message events even though they
            // reuse one banner object.
            AppNotificationService.recordNotification({
                desktopEntry: notification.desktopEntry || "",
                appName: notification.appName || "",
                summary: notification.summary || "",
                body: notification.body || "",
                hints: notification.hints || ({})
            })
            // Keep message actions and image providers alive in history.
            // Banner visibility is separate from Notification.tracked, whose
            // false value closes the notification in the sending application.
            notification.tracked = true
            notifGroupService.showNotification(notification, ControlCenterService.doNotDisturbEnabled)
            ControlCenterService.registerLiveNotification(notification)
            notifGroupService.pushHistory(notification)
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
        visible: ScreenLifecycle.outputAvailable && root.targetScreen !== null
        groupService: notifGroupService
    }
}
