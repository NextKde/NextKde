import QtQuick
import Quickshell.Services.Notifications
import qs.desktop.modules.bar

// Groups tracked notifications by desktopEntry (fallback appName) into a
// ListModel that the popup and history views consume. Quickshell's
// trackedNotifications is a read-only UntypedObjectModel (no .get(), no sort,
// no filter), so -- like WindowService for the Dock -- we bridge it with a
// hidden Repeater that collects the live notification objects, debounce
// changes, then diff into a ListModel of groups.
//
// IMPORTANT: ListModel rows can only hold primitive roles (strings, ints,
// bools). Storing a JS array/object role turns it into a nested QQmlListModel
// whose elements are unreadable as JS objects -- that corrupted every
// notification access. So the live Notification objects live in a sidecar JS
// map `_groupsByKey` keyed by groupKey, and the ListModel only carries
// presentation primitives plus the groupKey to look the sidecar up.
//
// Each ListModel row exposes:
//   groupKey        string  desktopEntry || appName || "unknown"
//   appName         string
//   appIcon         string
//   count           int
//   collapsed       bool    true = stacked (show latest only), false = expanded
//   latestSummary   string
//   latestBody      string
//   latestUrgency   int     0 Low, 1 Normal, 2 Critical
//   latestImage     string
//   hasActions      bool
//   hasInlineReply  bool
//   createdAt       real
//
// Live Notification objects (for actions, inline reply, expand-list, close)
// are fetched via notificationsForKey(key) / latestForKey(key).
//
// The model is sorted newest-group-first so the freshest app sits on top.

QtObject {
    id: svc

    // The read-only source model (set by NotificationCenter).
    required property var sourceModel

    // The grouped, project-owned model the UI binds to. Primitive roles only.
    property ListModel groupsModel: ListModel {}

    // Sidecar: groupKey -> { notifications: [Notification, ...] (oldest first),
    // collapsed: bool }. Holds the live Notification objects the ListModel
    // cannot store. Rebuilt on every _rebuild.
    property var _groupsByKey: ({})

    // Revision counter bumped on every sidecar rebuild. QML bindings that read
    // the sidecar (e.g. card.notification = latestForKey(key)) cannot track a
    // plain JS object's internal changes, so they depend on this counter
    // instead -- bumping it forces those bindings to re-evaluate and pick up
    // the new sidecar state (e.g. a notification that was expired externally).
    property int sidecarRevision: 0

    // ---- source bridge: hidden Repeater over the read-only model -----------

    property Repeater _sourceRepeater: Repeater {
        model: svc.sourceModel
        delegate: Item {
            id: srcDelegate
            readonly property var notification: modelData
            // Trigger a rebuild when a source notification enters or leaves
            // the Repeater. This is ESSENTIAL for replaces_id: when an app
            // replaces a notification, Quickshell destroys the old object and
            // creates a new one (count stays 1->1, no property Changed signals
            // fire on the dead object). Without these hooks, the sidecar would
            // forever hold the destroyed reference and the card would freeze
            // (no auto-expire, stale display). The count poll can't catch this
            // because the count doesn't change.
            Component.onCompleted: svc._scheduleUpdate()
            Component.onDestruction: svc._scheduleUpdate()
            // Watch the properties that affect grouping/preview. Any change
            // schedules a short debounce-gated rebuild.
            Connections {
                target: srcDelegate.notification
                ignoreUnknownSignals: true
                function onSummaryChanged() { svc._scheduleUpdate() }
                function onBodyChanged() { svc._scheduleUpdate() }
                function onAppNameChanged() { svc._scheduleUpdate() }
                function onAppIconChanged() { svc._scheduleUpdate() }
                function onImageChanged() { svc._scheduleUpdate() }
                function onUrgencyChanged() { svc._scheduleUpdate() }
                function onActionsChanged() { svc._scheduleUpdate() }
                function onHasInlineReplyChanged() { svc._scheduleUpdate() }
                function onInlineReplyPlaceholderChanged() { svc._scheduleUpdate() }
            }
        }
    }

    // A count poll as a safety net: some providers don't emit per-item
    // signals reliably. Mirrors WindowService._countPoll.
    property Timer _countPoll: Timer {
        interval: 500
        repeat: true
        running: true
        onTriggered: {
            if (svc._lastCount !== svc._sourceRepeater.count) {
                svc._lastCount = svc._sourceRepeater.count
                svc._scheduleUpdate()
            }
        }
    }
    property int _lastCount: -1

    property Timer _updateTimer: Timer {
        interval: 10
        repeat: false
        onTriggered: svc._rebuild()
    }

    function _scheduleUpdate() {
        _updateTimer.restart()
    }

    // Collect live notification objects off the hidden Repeater (the only way
    // to read an UntypedObjectModel -- it has no .get()).
    function _collectNotifications() {
        const result = []
        for (let i = 0; i < _sourceRepeater.count; i++) {
            const item = _sourceRepeater.itemAt(i)
            if (item && item.notification)
                result.push(item.notification)
        }
        return result
    }

    // Re-collect the live notification objects for a key RIGHT NOW. Used by
    // dismiss/expire instead of the sidecar, because replaces_id destroys the
    // old object within ~2ms of the new one arriving -- the sidecar (refreshed
    // on a 10ms debounce) can still hold a reference to the destroyed object,
    // and calling dismiss()/expire() on it silently does nothing. Collecting
    // fresh from the Repeater guarantees we only ever touch live objects.
    function _liveNotificationsForKey(key) {
        const all = svc._collectNotifications()
        const out = []
        for (let i = 0; i < all.length; i++) {
            const n = all[i]
            if (svc._groupKey(n) === key)
                out.push(n)
        }
        return out
    }

    function _groupKey(n) {
        if (n.desktopEntry && n.desktopEntry.length > 0)
            return n.desktopEntry
        if (n.appName && n.appName.length > 0)
            return n.appName
        return "unknown"
    }

    // Build the next set of groups from the live notification list.
    // Returns an array of group objects carrying both the live notification
    // array (for the sidecar) and the primitive presentation fields (for the
    // ListModel). Preserves `collapsed` from the existing sidecar entry.
    function _buildGroups(notifications) {
        const map = {}      // key -> group object (with .notifications array)
        const order = []    // keys in arrival order
        for (let i = 0; i < notifications.length; i++) {
            const n = notifications[i]
            const key = svc._groupKey(n)
            let g = map[key]
            if (!g) {
                // Carry over collapsed state from the existing sidecar so an
                // expanded group stays expanded across rebuilds.
                let collapsed = true
                const prev = svc._groupsByKey[key]
                if (prev)
                    collapsed = prev.collapsed
                g = {
                    groupKey: key,
                    appName: n.appName || "",
                    appIcon: n.appIcon || "",
                    notifications: [],
                    count: 0,
                    collapsed: collapsed,
                    latestSummary: "",
                    latestBody: "",
                    latestUrgency: 1,
                    latestImage: "",
                    hasActions: false,
                    hasInlineReply: false,
                    createdAt: 0
                }
                map[key] = g
                order.push(key)
            }
            g.notifications.push(n)
            g.count++
        }
        // Fill preview fields from the newest notification in each group.
        // trackedNotifications is append-order (oldest first), so the newest
        // is the last one pushed.
        for (let k = 0; k < order.length; k++) {
            const g = map[order[k]]
            const latest = g.notifications[g.notifications.length - 1]
            g.latestSummary = latest.summary || ""
            g.latestBody = latest.body || ""
            g.latestUrgency = latest.urgency
            g.latestImage = latest.image || ""
            g.appName = latest.appName || g.appName
            g.appIcon = latest.appIcon || g.appIcon
            g.hasActions = latest.actions && latest.actions.length > 0
            g.hasInlineReply = !!latest.hasInlineReply
            g.createdAt = Date.now()
        }
        // Sort groups newest-first. Since trackedNotifications is append-order,
        // the group whose latest notification arrived last is the freshest.
        // Use the index of the latest notification in the source array as the
        // sort key (higher index = newer = first).
        const groups = order.map(key => map[key])
        groups.sort((a, b) => {
            const aNewestIdx = notifications.lastIndexOf(a.notifications[a.notifications.length - 1])
            const bNewestIdx = notifications.lastIndexOf(b.notifications[b.notifications.length - 1])
            return bNewestIdx - aNewestIdx
        })
        return groups
    }

    // Diff the next groups into groupsModel (primitive roles only) and refresh
    // the sidecar _groupsByKey with the live notification arrays.
    function _applyGroups(nextGroups) {
        const model = svc.groupsModel
        // Refresh the sidecar from the new groups.
        const nextByKey = {}
        for (let i = 0; i < nextGroups.length; i++) {
            const g = nextGroups[i]
            nextByKey[g.groupKey] = {
                notifications: g.notifications,
                collapsed: g.collapsed
            }
        }
        svc._groupsByKey = nextByKey
        // Bump the revision so bindings that read the sidecar (card.notification,
        // expand-list Repeater models) re-evaluate against the new state.
        svc.sidecarRevision = svc.sidecarRevision + 1

        // Truncate the model from the tail.
        while (model.count > nextGroups.length)
            model.remove(model.count - 1)

        const keys = ["groupKey", "appName", "appIcon", "count", "collapsed",
                      "latestSummary", "latestBody", "latestUrgency",
                      "latestImage", "hasActions", "hasInlineReply", "createdAt"]
        for (let i = 0; i < nextGroups.length; i++) {
            const g = nextGroups[i]
            if (i >= model.count) {
                model.append(g)
                continue
            }
            const row = model.get(i)
            for (let j = 0; j < keys.length; j++) {
                const key = keys[j]
                if (row[key] !== g[key])
                    model.setProperty(i, key, g[key])
            }
        }
    }

    function _rebuild() {
        const notifications = svc._collectNotifications()
        const nextGroups = svc._buildGroups(notifications)
        svc._applyGroups(nextGroups)
    }

    // ---- sidecar accessors for the UI -------------------------------------

    // Is a notification object still alive? replaces_id destroys the old
    // Notification within ~2ms of the new one arriving, but the JS reference
    // in the sidecar doesn't become null -- it becomes a dangling wrapper.
    // Touching a cheap property (appName) and checking for a sane type is a
    // reliable liveness probe (destroyed objects return undefined/empty).
    function _isAlive(n) {
        return n && typeof n.dismiss === "function" && n.appName !== undefined
    }

    // Live Notification objects for a group key (oldest first), or [].
    // Filters out any destroyed objects the sidecar may still hold (replaces_id
    // race). If the sidecar is stale, callers that need guaranteed-live objects
    // use _liveNotificationsForKey instead.
    function notificationsForKey(key) {
        const g = svc._groupsByKey[key]
        if (!g)
            return []
        return g.notifications.filter(n => svc._isAlive(n))
    }

    // The newest Notification object for a group key, or null.
    function latestForKey(key) {
        const arr = svc.notificationsForKey(key)
        return arr.length > 0 ? arr[arr.length - 1] : null
    }

    // ---- public API for the UI --------------------------------------------

    // Toggle a group's collapsed state by index. Updates both the model role
    // (so the delegate re-evaluates `expanded`) and the sidecar (so the state
    // survives the next rebuild).
    function toggleCollapsed(index) {
        if (index < 0 || index >= groupsModel.count)
            return
        const key = groupsModel.get(index).groupKey
        const collapsed = groupsModel.get(index).collapsed
        groupsModel.setProperty(index, "collapsed", !collapsed)
        const g = svc._groupsByKey[key]
        if (g)
            g.collapsed = !collapsed
    }

    // Dismiss every notification in a group (by key). Snapshots each into
    // history before dismissing -- the objects vanish on dismiss. Keyed by
    // groupKey (stable across rebuilds) rather than index (which can drift).
    // Re-collects LIVE objects instead of trusting the sidecar: replaces_id
    // destroys the old object within ~2ms, and the sidecar (debounce-refreshed)
    // can still hold a dead reference whose dismiss() is a no-op.
    function dismissGroupByKey(key) {
        const arr = svc._liveNotificationsForKey(key)
            .filter(n => n && typeof n.dismiss === "function")
        if (arr.length === 0)
            return
        for (let i = 0; i < arr.length; i++)
            svc._pushHistory(arr[i])
        for (let j = arr.length - 1; j >= 0; j--)
            arr[j].dismiss()
    }

    // Expire every notification in a group (by key). Used by the auto-expire
    // timer so a stacked group disappears all at once instead of one-by-one.
    // Re-collects LIVE objects (see dismissGroupByKey for why).
    function expireGroupByKey(key) {
        const arr = svc._liveNotificationsForKey(key)
            .filter(n => n && typeof n.expire === "function")
        if (arr.length === 0)
            return
        for (let i = 0; i < arr.length; i++)
            svc._pushHistory(arr[i])
        for (let j = arr.length - 1; j >= 0; j--)
            arr[j].expire()
    }

    // Dismiss every notification in a group (by index). Snapshots each into
    // history before dismissing -- the objects vanish on dismiss.
    function dismissGroup(index) {
        if (index < 0 || index >= groupsModel.count)
            return
        svc.dismissGroupByKey(groupsModel.get(index).groupKey)
    }

    // Expire every notification in a group (by index). Used by the auto-expire
    // timer so a stacked group disappears all at once instead of one-by-one.
    function expireGroup(index) {
        if (index < 0 || index >= groupsModel.count)
            return
        svc.expireGroupByKey(groupsModel.get(index).groupKey)
    }

    // Dismiss a single notification (by object reference). The UI calls this
    // after the exit animation finishes, like the old card.close() flow.
    function dismissNotification(notification) {
        if (!svc._isAlive(notification))
            return
        svc._pushHistory(notification)
        notification.dismiss()
    }

    function expireNotification(notification) {
        if (!svc._isAlive(notification))
            return
        svc._pushHistory(notification)
        notification.expire()
    }

    // ---- history -----------------------------------------------------------

    // Public entry: snapshot a notification into the history store. DND uses
    // this to keep a Do-Not-Disturb notification in the session history even
    // though it is never shown as a banner (untracked notifications never
    // reach dismiss/expire, so they would otherwise be lost entirely).
    function pushHistory(notification) {
        _pushHistory(notification)
    }

    // Snapshot a notification into ControlCenterService.notificationHistory
    // before it's destroyed. History lives on the ControlCenterService
    // singleton so the ControlCenter panel can read it without a cross-module
    // reference. We copy primitive fields only (the Notification object is
    // about to be deleted).
    function _pushHistory(notification) {
        if (!notification)
            return
        const history = ControlCenterService.notificationHistory
        const snapshot = {
            notifId: notification.id,
            appName: notification.appName || "",
            appIcon: notification.appIcon || "",
            summary: notification.summary || "",
            body: notification.body || "",
            urgency: notification.urgency,
            timestamp: Date.now()
        }
        history.insert(0, snapshot)
        while (history.count > ControlCenterService.notificationHistoryMax)
            history.remove(history.count - 1)
    }

    function clearHistory() {
        ControlCenterService.notificationHistory.clear()
    }

    // Build on first load.
    Component.onCompleted: svc._scheduleUpdate()
}
