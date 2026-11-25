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
    readonly property var soundService: typeof NotificationSoundService !== "undefined" ? NotificationSoundService : null

    function recordNotification(notification, firstArrival) {
        if (!NotificationPolicyService.ready) return
        NotificationPolicyService.remember(notification)
        if (NotificationPolicyService.isBlocked(notification)) {
            notification.tracked = false
            return
        }
        // Everything arrives tracked: an untracked object is closed by the
        // server, and the banner pipeline hides rather than closes (P2), so
        // objects keep their actions invokable from history until the user
        // deletes them. Whether a notification may BANNER is decided by the
        // retire marker instead: a quiet arrival (DND, master banner switch
        // off, or a history surface already on screen -- the list is showing
        // it in realtime, so flying a banner too would present it twice) is
        // retired on the spot. Critical alerts punch through DND and
        // open-list suppression, but not the master switch.
        const isCritical = notification.urgency === NotificationUrgency.Critical
        const mayBanner = NotificationPolicyService.bannersEnabled
            && (isCritical || !ControlCenterService.doNotDisturbEnabled)
            && (isCritical || !NotificationHistoryService.listOpen)
        notification.tracked = true
        // Every live object registers by server id at arrival, so history
        // rows can invoke its actions for as long as the object lives.
        // Banners retire into the same registry instead of closing when
        // they expire.
        NotificationHistoryService.registerLive(notification)
        if (!mayBanner)
            NotificationHistoryService.retire(notification.id)
        // Metadata/replacement updates still refresh history, but do not chime.
        if (firstArrival && soundService) soundService.play(notification)
        AppNotificationService.recordNotification({
            desktopEntry: notification.desktopEntry || "",
            appName: notification.appName || "",
            summary: notification.summary || "",
            body: notification.body || "",
            hints: notification.hints || ({})
        })
        if (NotificationPolicyService.historyEnabled) notifGroupService.pushHistory(notification)
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
        // The master banner switch turned off: quiet the flying card and the
        // whole wait queue by retiring (objects stay alive in history), not
        // by closing -- same rule as banner expiry.
        function onBannersEnabledChanged() {
            if (!NotificationPolicyService.bannersEnabled)
                notifGroupService.retireAllBanners()
        }
        function onBlockedKeysChanged() {
            // Blocking a source stays a real close: the user explicitly
            // does not want that app's notifications kept anywhere.
            for (const notification of notifGroupService._collectNotifications())
                if (NotificationPolicyService.isBlocked(notification)
                    && !NotificationHistoryService.isRetired(notification.id))
                    notification.tracked = false
        }
    }
    Connections {
        target: ControlCenterService
        // DND turning on quiets banners by retiring them into history;
        // future arrivals are retired at the gate in recordNotification.
        function onDoNotDisturbEnabledChanged() {
            if (ControlCenterService.doNotDisturbEnabled)
                notifGroupService.retireAllBanners()
        }
    }
    Connections {
        target: NotificationHistoryService
        // A history surface just came on screen: the flying banner AND the
        // whole wait queue are content the list is already showing in
        // realtime, so retire them all -- anything less would promote the
        // next queued card seconds later, flying a banner over the open
        // list. Arrivals while the list stays open are retired at the gate
        // in recordNotification.
        function onListOpenChanged() {
            if (NotificationHistoryService.listOpen)
                notifGroupService.retireAllBanners()
        }
    }

    // Groups trackedNotifications by desktopEntry into a project-owned
    // ListModel. The banner popup binds to this -- and only the banner
    // popup: the model is a single-slot serial queue, while history reads
    // its own snapshots from NotificationHistoryService.
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
