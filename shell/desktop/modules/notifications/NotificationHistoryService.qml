pragma Singleton
import QtQuick
import "NotificationIdentity.mjs" as NotificationIdentity

// Session-only snapshots. Server IDs identify replacement notifications;
// stable history keys preserve their delegates when content changes.
QtObject {
    id: service
    readonly property int maximumCount: 50
    property int nextKey: 0
    property ListModel history: ListModel {}
    property ListModel groups: ListModel {}
    property var expandedSources: ({})
    readonly property int count: history.count

    function push(snapshot) {
        snapshot.sourceKey = NotificationIdentity.sourceKey(snapshot)
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
        while (history.count > maximumCount)
            history.remove(history.count - 1)
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
        for (let i = history.count - 1; i >= 0; --i)
            if (selected.has(history.get(i).historyKey)) history.remove(i)
        rebuildRows()
    }
    function clear() { removeKeys(allKeys()) }
    function rebuildRows() {
        const desired = []
        const bySource = new Map()
        for (let i = 0; i < history.count; ++i) {
            const row = history.get(i)
            const key = row.sourceKey
            if (!bySource.has(key)) {
                const group = {sourceKey: key, appName: row.appName || "其他",
                    appIcon: row.appIcon, desktopEntry: String(row.desktopEntry || ""), expanded: expandedSources[key] === true, items: []}
                bySource.set(key, group)
                desired.push(group)
            }
            bySource.get(key).items.push({historyKey: row.historyKey, summary: row.summary,
                body: row.body, timestamp: row.timestamp})
        }
        // Serialized primitives avoid nested QQmlListModel roles. Each visual
        // group reconciles its own stable member model from this snapshot.
        const rows = desired.map(group => ({sourceKey: group.sourceKey, appName: group.appName,
            appIcon: group.appIcon, desktopEntry: group.desktopEntry, expanded: group.expanded, itemCount: group.items.length,
            itemsJson: JSON.stringify(group.items)}))
        const keys = new Set(rows.map(row => row.sourceKey))
        for (let i = groups.count - 1; i >= 0; --i)
            if (!keys.has(groups.get(i).sourceKey)) groups.remove(i)
        for (let i = 0; i < rows.length; ++i) {
            let existing = -1
            for (let j = i; j < groups.count; ++j)
                if (groups.get(j).sourceKey === rows[i].sourceKey) { existing = j; break }
            if (existing < 0) groups.insert(i, rows[i])
            else {
                if (existing !== i) groups.move(existing, i, 1)
                groups.set(i, rows[i])
            }
        }
    }
}
