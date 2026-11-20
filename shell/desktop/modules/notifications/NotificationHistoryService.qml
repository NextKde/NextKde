pragma Singleton
import QtQuick
import "NotificationIdentity.mjs" as NotificationIdentity
import "../../../shared/qml/i18n"

// Session-only snapshots. Server IDs identify replacement notifications;
// stable history keys preserve their delegates when content changes.
QtObject {
    id: service
    readonly property int maximumCount: 50
    property int nextKey: 0
    property ListModel history: ListModel {}
    property ListModel groups: ListModel {}
    property ListModel previewGroups: ListModel {}
    property var expandedSources: ({})
    readonly property int count: history.count
    signal historyUpdated()

    // ---- live-object registry ----------------------------------------------
    //
    // Banners retire instead of closing: expireGroupByKey marks the object
    // retired (see retiredIds) and registers it here, so a history row can
    // still invoke its actions long after the banner is gone -- macOS/Plasma
    // semantics. The object stays tracked with the server; untracking would
    // close it (Quickshell releases untracked notifications). Arrival
    // registers every live object (NotificationCenter.recordNotification);
    // user dismissals unregister, and dead refs (replaces_id destroys the
    // old object within ~2ms) are pruned lazily by liveNotification's
    // liveness probe.
    property var liveById: ({})
    // Retired server ids: tracked with the server (actions stay invokable)
    // but hidden from the banner list. GroupService filters its collects by
    // this set; deleting/clearing history removes the marker together with
    // the real dismiss.
    property var retiredIds: ({})

    // ---- open-list suppression -----------------------------------------------
    //
    // While a surface showing the history list is on screen (the dock's
    // notification panel or the control center), new notifications skip the
    // banner slot entirely and land straight in the list -- no "the list is
    // growing AND a banner is flying" double presentation. The hosts push
    // their own flag; the arrival path and the banner cleanup read the
    // combined listOpen.
    property bool historyPanelOpen: false
    property bool controlCenterHistoryOpen: false
    readonly property bool listOpen: historyPanelOpen || controlCenterHistoryOpen

    function registerLive(notification) {
        if (!notification || notification.id === undefined)
            return
        liveById[notification.id] = notification
    }

    function retire(notifId) {
        retiredIds[notifId] = true
    }

    function isRetired(notifId) {
        return retiredIds[notifId] === true
    }

    function unregisterLive(notifId) {
        delete liveById[notifId]
        delete retiredIds[notifId]
    }

    // Cheap liveness probe: a destroyed object's dismiss is no longer a
    // function and appName reads undefined (same pattern as
    // NotificationGroupService._isAlive).
    function _liveAlive(n) {
        return n && typeof n.dismiss === "function" && n.appName !== undefined
    }

    function liveNotification(notifId) {
        const n = liveById[notifId]
        if (!_liveAlive(n)) {
            delete liveById[notifId]
            return null
        }
        return n
    }

    // Invoke a stored action on the live object. Returns false when the
    // object is gone (the app replaced or closed it) or the action no
    // longer exists; callers fall back to relaunching the app.
    function invokeAction(notifId, actionIdentifier) {
        const n = liveNotification(notifId)
        if (!n)
            return false
        const actions = n.actions || []
        for (let i = 0; i < actions.length; ++i) {
            if (String(actions[i].identifier || "") === String(actionIdentifier)) {
                actions[i].invoke()
                return true
            }
        }
        return false
    }

    function push(snapshot) {
        snapshot.sourceKey = NotificationIdentity.sourceKey(snapshot)
        // Action rows are serialized JSON on every snapshot _pushHistory
        // builds; older/foreign pushers (test fixtures, previews) may not
        // carry the field, so default it rather than bind delegates to a
        // missing role.
        if (typeof snapshot.actionsJson !== "string" || snapshot.actionsJson.length === 0)
            snapshot.actionsJson = "[]"
        let existing = -1
        for (let i = 0; i < history.count; ++i) {
            if (history.get(i).notifId === snapshot.notifId) {
                existing = i
                break
            }
        }
        if (existing >= 0) {
            snapshot.historyKey = history.get(existing).historyKey
            history.set(existing, snapshot)
            if (existing > 0) history.move(existing, 0, 1)
        } else {
            snapshot.historyKey = ++nextKey
            history.insert(0, snapshot)
        }
        while (history.count > maximumCount) {
            // A real close for evicted objects: retirement must never leak
            // more live objects than the history window shows.
            const evicted = history.get(history.count - 1)
            const live = liveNotification(evicted.notifId)
            if (live) {
                unregisterLive(evicted.notifId)
                live.dismiss()
            }
            history.remove(history.count - 1)
        }
        rebuildRows()
    }
    function keysForSource(key) {
        const keys = []
        for (let i = 0; i < history.count; ++i)
            if (history.get(i).sourceKey === key) keys.push(history.get(i).historyKey)
        return keys
    }
    function allKeys() {
        const keys = []
        for (let i = 0; i < history.count; ++i) keys.push(history.get(i).historyKey)
        return keys
    }
    function setExpanded(source, expanded) {
        const next = Object.assign({}, expandedSources)
        next[source] = expanded
        expandedSources = next
        rebuildRows()
    }
    function remove(key) { removeKeys([key]) }
    function removeKeys(keys) {
        const selected = new Set(keys)
        for (let i = history.count - 1; i >= 0; --i) {
            if (!selected.has(history.get(i).historyKey))
                continue
            // Deleting from the visible history is the user asking the
            // notification to go away entirely: close the live object,
            // not just the snapshot row.
            const row = history.get(i)
            const live = liveNotification(row.notifId)
            if (live) {
                unregisterLive(row.notifId)
                live.dismiss()
            }
            history.remove(i)
        }
        rebuildRows()
    }
    function clear() { removeKeys(allKeys()) }
    function rebuildRows() {
        rebuildModel(groups, history.count, false)
        rebuildModel(previewGroups, Math.min(3, history.count), true)
        historyUpdated()
    }
    function rebuildModel(target, limit, preview) {
        const desired = []
        const bySource = new Map()
        for (let i = 0; i < limit; ++i) {
            const row = history.get(i)
            const key = row.sourceKey
            if (!bySource.has(key)) {
                const group = {sourceKey: key, appName: row.appName || I18n.tr("Other"),
                    appIcon: row.appIcon, desktopEntry: String(row.desktopEntry || ""), expanded: !preview && expandedSources[key] === true, items: []}
                bySource.set(key, group)
                desired.push(group)
            }
            bySource.get(key).items.push({historyKey: row.historyKey, notifId: row.notifId,
                actionsJson: String(row.actionsJson || "[]"), summary: row.summary,
                body: row.body, timestamp: row.timestamp})
        }
        // Serialized primitives avoid nested QQmlListModel roles. Each visual
        // group reconciles its own stable member model from this snapshot.
        const rows = desired.map(group => ({sourceKey: group.sourceKey, appName: group.appName,
            appIcon: group.appIcon, desktopEntry: group.desktopEntry, expanded: group.expanded, itemCount: group.items.length,
            itemsJson: JSON.stringify(group.items)}))
        const keys = new Set(rows.map(row => row.sourceKey))
        for (let i = target.count - 1; i >= 0; --i)
            if (!keys.has(target.get(i).sourceKey)) target.remove(i)
        for (let i = 0; i < rows.length; ++i) {
            let existing = -1
            for (let j = i; j < target.count; ++j)
                if (target.get(j).sourceKey === rows[i].sourceKey) { existing = j; break }
            if (existing < 0) target.insert(i, rows[i])
            else {
                if (existing !== i) target.move(existing, i, 1)
                target.set(i, rows[i])
            }
        }
    }
}
