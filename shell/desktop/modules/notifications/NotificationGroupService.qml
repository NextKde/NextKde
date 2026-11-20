import QtQuick
import Quickshell.Services.Notifications
import qs.desktop.modules.bar
import qs.desktop.modules.common
import "../../../shared/qml/i18n"

// Groups tracked notifications by desktopEntry (fallback appName) into a
// ListModel that the banner popup binds to. Quickshell's
// trackedNotifications is a read-only UntypedObjectModel (no .get(), no sort,
// no filter), so -- like WindowService for the Dock -- we bridge it with an
// Instantiator that collects the live notification objects, debounce
// changes, then diff into a ListModel of groups.
//
// IMPORTANT: ListModel rows can only hold primitive roles (strings, ints,
// bools). Storing a JS array/object role turns it into a nested QQmlListModel
// whose elements are unreadable as JS objects -- that corrupted every
// notification access. So the live Notification objects live in a sidecar JS
// map `_groupsByKey` keyed by groupKey, and the ListModel only carries
// presentation primitives plus the groupKey to look the sidecar up.
//
// The banner slot is strictly serial (P3): groupsModel holds at most ONE
// row -- the group currently flying. Every other live group waits in
// first-seen order and is promoted when the slot frees, so cards can never
// stack, shove each other, or freeze mid-animation. Critical groups preempt
// a non-critical active card (the preempted group retires into history).
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

    // FIFO stamps for groups waiting for the banner slot: groupKey -> the
    // arrival index of the group's newest notification (see _buildGroups,
    // append-order = arrival order). The slot drains the smallest stamp
    // first. Entries are pruned when the group leaves the live set and
    // dropped on promotion.
    property var _queuedAt: ({})

    // Revision counter bumped on every sidecar rebuild. QML bindings that read
    // the sidecar (e.g. card.notification = latestForKey(key)) cannot track a
    // plain JS object's internal changes, so they depend on this counter
    // instead -- bumping it forces those bindings to re-evaluate and pick up
    // the new sidecar state (e.g. a notification that was expired externally).
    property int sidecarRevision: 0

    // ---- source bridge: hidden Instantiator over the read-only model -------

    property Instantiator _sourceBridge: Instantiator {
        model: svc.sourceModel
        delegate: QtObject {
            id: srcDelegate
            readonly property var notification: modelData
            // Trigger a rebuild when a source notification enters or leaves
            // the bridge. This is ESSENTIAL for replaces_id: when an app
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
            property var _conn: Connections {
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
            if (svc._lastCount !== svc._sourceBridge.count) {
                svc._lastCount = svc._sourceBridge.count
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

    // Collect live notification objects off the hidden Instantiator (the only
    // way to read an UntypedObjectModel without QQuickItem hierarchy warnings).
    function _collectNotifications() {
        const result = []
        for (let i = 0; i < _sourceBridge.count; i++) {
            const item = _sourceBridge.objectAt(i)
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
    // fresh from the Instantiator guarantees we only ever touch live objects.
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
            // Arrival-ordered queue stamp (smaller = arrived earlier). The
            // index in the append-ordered source array IS the arrival order,
            // so a burst that coalesces into one rebuild batch still drains
            // FIFO; a per-pass Date.now() would tie every group in the batch
            // and fall back to scan order (newest first). Indexes compress
            // uniformly when earlier objects retire, preserving the relative
            // order of the survivors.
            g.queueStamp = notifications.lastIndexOf(latest)
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

    // Apply the next groups to the single banner slot. groupsModel holds at
    // most ONE row -- the group currently flying as a banner; every other
    // live group waits (FIFO by first-seen stamp) and is promoted when the
    // slot frees. This is what makes banners strictly serial: cards can no
    // longer stack, shove each other, or freeze mid-animation.
    function _applyGroups(nextGroups) {
        const model = svc.groupsModel
        const rowKeys = ["groupKey", "appName", "appIcon", "count", "collapsed",
                         "latestSummary", "latestBody", "latestUrgency",
                         "latestImage", "hasActions", "hasInlineReply", "createdAt"]

        // 1. Refresh the sidecar from the new groups -- all of them, the
        // waiting ones too, so a promoted card resolves its live objects
        // without waiting for another rebuild.
        const nextByKey = {}
        const nextKeys = new Set()
        for (let i = 0; i < nextGroups.length; i++) {
            const g = nextGroups[i]
            nextByKey[g.groupKey] = {
                notifications: g.notifications,
                collapsed: g.collapsed
            }
            nextKeys.add(g.groupKey)
        }
        svc._groupsByKey = nextByKey
        // Bump the revision so bindings that read the sidecar (card.notification,
        // expand-list Repeater models) re-evaluate against the new state.
        svc.sidecarRevision = svc.sidecarRevision + 1

        // 2. Queue stamps: a group's wait position is fixed at first sight,
        // by its newest notification's arrival index (see _buildGroups);
        // the slot drains the smallest stamp first.
        for (let i = 0; i < nextGroups.length; i++) {
            const g = nextGroups[i]
            if (svc._queuedAt[g.groupKey] === undefined)
                svc._queuedAt[g.groupKey] = g.queueStamp
        }
        for (const key of Object.keys(svc._queuedAt)) {
            if (!nextKeys.has(key))
                delete svc._queuedAt[key]
        }

        // 3. The active group is whatever row holds the slot right now.
        let activeKey = model.count > 0 ? model.get(0).groupKey : ""
        let activeGroup = null
        if (activeKey) {
            for (let i = 0; i < nextGroups.length; i++) {
                if (nextGroups[i].groupKey === activeKey) {
                    activeGroup = nextGroups[i]
                    break
                }
            }
            if (!activeGroup) {
                // The active group's objects all left (dismissed or replaced
                // away) without a synchronous row removal -- free the slot.
                model.remove(0)
                activeKey = ""
            }
        }

        // 4. Critical preemption: a newer critical group takes the slot NOW
        // when a non-critical card is flying. The preempted group retires
        // into history (its actions stay invokable there); the queue does
        // not replay content the user has been pushed past. Step 6 hands
        // the freed slot straight to the preempting critical (criticals
        // jump the queue), so the waiters behind it are never promoted into
        // a slot a critical outranks -- which would cascade-retire them one
        // rebuild at a time.
        let skipKey = ""
        if (activeGroup && activeGroup.latestUrgency !== NotificationUrgency.Critical) {
            const activeIdx = nextGroups.indexOf(activeGroup)
            for (let i = 0; i < activeIdx; i++) {
                if (nextGroups[i].latestUrgency === NotificationUrgency.Critical) {
                    skipKey = activeKey
                    svc.expireGroupByKey(activeKey)
                    activeGroup = null
                    activeKey = ""
                    break
                }
            }
        }

        // 5. Refresh the active row in place. A newer notification that
        // joined the ACTIVE group updates the flying card (same-group
        // stacking) -- that is not a new slot, so nothing is queued.
        if (activeGroup) {
            const row = model.get(0)
            for (let k = 0; k < rowKeys.length; k++) {
                const prop = rowKeys[k]
                if (row[prop] !== activeGroup[prop])
                    model.setProperty(0, prop, activeGroup[prop])
            }
        }

        // 6. Promote into the empty slot. A waiting critical jumps the queue
        // outright -- the newest one, since nextGroups is newest-first --
        // whether the slot freed by expiry or by preemption; otherwise the
        // oldest waiter (FIFO) plays. Promoting a non-critical while a
        // critical waits would arm the preemption against it on the very
        // next rebuild and cascade-retire the queue.
        if (model.count === 0 && nextGroups.length > 0) {
            let head = null
            let headStamp = 0
            for (let i = 0; i < nextGroups.length; i++) {
                const g = nextGroups[i]
                if (g.groupKey === skipKey)
                    continue
                const stamp = svc._queuedAt[g.groupKey]
                if (stamp === undefined)
                    continue
                if (g.latestUrgency === NotificationUrgency.Critical) {
                    head = g
                    break
                }
                if (!head || stamp < headStamp) {
                    head = g
                    headStamp = stamp
                }
            }
            if (head) {
                delete svc._queuedAt[head.groupKey]
                const row = {}
                for (const prop of rowKeys)
                    row[prop] = head[prop]
                model.insert(0, row)
            }
        }
    }

    function _rebuild() {
        // Retired objects stay in trackedNotifications (alive with the
        // server) but must never come back to the banner: filter them out
        // before grouping, so a sidecar refresh after retirement cannot
        // resurrect the card.
        const notifications = svc._collectNotifications()
            .filter(n => !NotificationHistoryService.isRetired(n.id))
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

    // Dismiss every notification in a group (by key). History was recorded
    // on arrival and must not be re-added after a user deletes it. Keyed by
    // groupKey (stable across rebuilds) rather than index (which can drift).
    // Re-collects LIVE objects instead of trusting the sidecar: replaces_id
    // destroys the old object within ~2ms, and the sidecar (debounce-refreshed)
    // can still hold a dead reference whose dismiss() is a no-op.
    function dismissGroupByKey(key) {
        const arr = svc._liveNotificationsForKey(key)
            .filter(n => n && typeof n.dismiss === "function")
        AppNotificationService.clearGroup(key)
        for (let j = arr.length - 1; j >= 0; j--)
            arr[j].dismiss()

        // Synchronous cleanup fallback: remove the group from groupsModel immediately
        // so the card exit animation is never stalled by delayed D-Bus/Repeater signals.
        for (let idx = groupsModel.count - 1; idx >= 0; idx--) {
            if (groupsModel.get(idx).groupKey === key)
                groupsModel.remove(idx)
        }
        delete svc._groupsByKey[key]
        svc.sidecarRevision++
    }

    // Retire every notification in a group (by key). Used by the auto-expire
    // timer so a stacked group leaves the banner list all at once. Expiry is
    // no longer a close: the banner goes away, but each live object stays
    // with the server -- marked retired, filtered out of every banner
    // collect -- so its actions keep working from the history list
    // (macOS/Plasma semantics). The object must stay tracked: Quickshell
    // closes a notification the moment it is untracked (verified on the VM:
    // reason-2 close fires at the retire instant, even with a 60s app
    // timeout). A real close remains the user's: dismissGroupByKey, or
    // deleting/clearing from the history view.
    // Re-collects LIVE objects (see dismissGroupByKey for why).
    function expireGroupByKey(key) {
        const arr = svc._liveNotificationsForKey(key)
            .filter(n => n)
        for (let j = arr.length - 1; j >= 0; j--) {
            NotificationHistoryService.registerLive(arr[j])
            NotificationHistoryService.retire(arr[j].id)
        }

        // Synchronous cleanup fallback: remove the group from groupsModel immediately.
        for (let idx = groupsModel.count - 1; idx >= 0; idx--) {
            if (groupsModel.get(idx).groupKey === key)
                groupsModel.remove(idx)
        }
        delete svc._groupsByKey[key]
        svc.sidecarRevision++
        // The slot just freed: schedule a rebuild so the oldest waiter is
        // promoted. The retire markers only take effect on the next collect,
        // and the objects stay alive (no destruction signal will trigger
        // it), so without this the queue would stall until the next arrival.
        svc._scheduleUpdate()
    }

    // Retire every non-retired tracked notification -- DND turning on, the
    // master banner switch turning off, or a history surface coming on
    // screen: all of them quiet the flying card and the entire wait queue by
    // hiding, not closing, so the objects stay alive with their actions
    // invokable from history (same rule as banner expiry).
    function retireAllBanners() {
        for (const notification of svc._collectNotifications()) {
            if (!NotificationHistoryService.isRetired(notification.id))
                NotificationHistoryService.retire(notification.id)
        }
        svc._rebuild()
    }

    // Dismiss every notification in a group (by index).
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
        AppNotificationService.clearGroup(svc._groupKey(notification))
        notification.dismiss()
    }

    // ---- history -----------------------------------------------------------

    // Snapshot on arrival, before tracking or DND presentation is decided.
    function pushHistory(notification) {
        _pushHistory(notification)
    }

    // Copy primitive fields into session history. The live object outlives
    // the banner now (retirement keeps it with the server), but the row
    // still carries only serialized primitives -- ListModel object roles
    // corrupt -- so actions travel as JSON and invoke through the live
    // registry (NotificationHistoryService.liveById) by notifId.
    function _pushHistory(notification) {
        if (!notification)
            return
        const actions = []
        const raw = notification.actions || []
        for (let i = 0; i < raw.length; ++i) {
            const a = raw[i]
            const text = a.text || a.identifier || ""
            actions.push({
                identifier: a.identifier || "",
                label: I18n.tr(text) || text
            })
        }
        const snapshot = {
            notifId: notification.id,
            appName: notification.appName || "",
            desktopEntry: notification.desktopEntry || "",
            appIcon: notification.appIcon || "",
            summary: notification.summary || "",
            body: notification.body || "",
            urgency: notification.urgency,
            actionsJson: JSON.stringify(actions),
            timestamp: Date.now()
        }
        NotificationHistoryService.push(snapshot)
    }

    function clearHistory() {
        NotificationHistoryService.clear()
    }

    // Build on first load.
    Component.onCompleted: svc._scheduleUpdate()
}
