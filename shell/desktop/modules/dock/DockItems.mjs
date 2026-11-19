// DockItems.mjs — persisted dock-item normalization and separator policy.
// Pure ES module, no QML dependencies.
//
// Schema 13 stores separators beside pinned apps:
//   { type: "separator", id: "<unique>" }
// Normalization keeps them. The display filter does not rewrite storage.

const DOCK_CONFIG_VERSION = 13

export function createSeparatorId() {
    return "sep-" + Date.now().toString(36) + "-"
        + Math.random().toString(36).slice(2, 10)
}

function asArray(value) {
    if (Array.isArray(value))
        return value
    if (value && typeof value === "object" && typeof value.length === "number")
        return Array.from(value)
    return []
}

function mintSeparatorId(used, createId) {
    const mint = typeof createId === "function" ? createId : createSeparatorId
    for (let attempt = 0; attempt < 8; attempt++) {
        const id = mint(used)
        if (typeof id === "string" && id.length > 0 && !used.has(id))
            return id
    }
    let salt = used.size
    let id = "sep-" + salt
    while (used.has(id))
        id = "sep-" + (++salt)
    return id
}

function takeSeparatorId(requested, used, createId) {
    if (typeof requested === "string" && requested.length > 0 && !used.has(requested)) {
        used.add(requested)
        return requested
    }
    const id = mintSeparatorId(used, createId)
    used.add(id)
    return id
}

// Keep pinned apps (including apps flattened out of legacy folders) and
// separators. Unknown types are dropped. Duplicate app ids collapse; a
// separator with a missing or repeated id receives a new one. Leading,
// trailing and consecutive separators stay in the stored list.
export function normalizeDockItems(rawItems, createId = createSeparatorId) {
    const normalized = []
    const seenApps = new Set()
    const seenSeparators = new Set()
    function appendApp(appId) {
        if (seenApps.has(appId))
            return
        seenApps.add(appId)
        normalized.push({ type: "app", appId: appId })
    }
    const items = asArray(rawItems)
    for (let i = 0; i < items.length; i++) {
        const item = items[i]
        if (!item || typeof item !== "object")
            continue
        if (item.type === "app" && typeof item.appId === "string"
                && item.appId.length > 0) {
            appendApp(item.appId)
            continue
        }
        if (item.type === "separator") {
            normalized.push({
                type: "separator",
                id: takeSeparatorId(item.id, seenSeparators, createId),
            })
            continue
        }
        // Folder support was removed. Flatten legacy entries in place so no
        // previously pinned application disappears after the upgrade.
        if (item.type === "folder" && typeof item.id === "string"
                && item.id.length > 0) {
            const appIds = asArray(item.appIds).filter(appId =>
                typeof appId === "string" && appId.length > 0)
            for (let j = 0; j < appIds.length; j++)
                appendApp(appIds[j])
        }
    }
    return normalized
}

// Display-only. Drop separators that lead or trail the pinned run, collapse
// adjacent duplicates to the first id, and drop a separator whose neighbouring
// apps are not in this run (removed, or moved into the window section).
// `items` is not modified.
export function visibleDockItems(items, isAppVisible = () => true) {
    const shown = []
    const list = asArray(items)
    for (let i = 0; i < list.length; i++) {
        const item = list[i]
        if (!item || typeof item !== "object")
            continue
        if (item.type === "app") {
            if (isAppVisible(item))
                shown.push(item)
            continue
        }
        if (item.type === "separator" && typeof item.id === "string" && item.id.length > 0)
            shown.push(item)
    }
    const collapsed = []
    for (let i = 0; i < shown.length; i++) {
        const item = shown[i]
        if (item.type === "separator" && collapsed.length > 0
                && collapsed[collapsed.length - 1].type === "separator")
            continue
        collapsed.push(item)
    }
    let start = 0
    let end = collapsed.length
    while (start < end && collapsed[start].type === "separator")
        start++
    while (end > start && collapsed[end - 1].type === "separator")
        end--
    return collapsed.slice(start, end)
}

// True only when the next *visible* pinned item is an application. A last
// icon, or one that already has a separator on its right, must not gain
// another separator that the display filter would hide.
export function canAddSeparatorAfter(items, appId, sameApp = (left, right) => left === right, isAppVisible = () => true) {
    const visible = visibleDockItems(items, isAppVisible)
    let index = -1
    for (let i = 0; i < visible.length; i++) {
        const item = visible[i]
        if (item.type === "app" && sameApp(item.appId, appId)) {
            index = i
            break
        }
    }
    if (index < 0)
        return false
    const next = visible[index + 1]
    return !!(next && next.type === "app")
}

export function addSeparatorAfter(items, appId, id, sameApp = (left, right) => left === right, isAppVisible = () => true) {
    if (typeof id !== "string" || id.length === 0)
        return null
    if (!canAddSeparatorAfter(items, appId, sameApp, isAppVisible))
        return null
    const list = asArray(items).slice()
    let index = -1
    for (let i = 0; i < list.length; i++) {
        const item = list[i]
        if (item && item.type === "app" && sameApp(item.appId, appId)) {
            index = i
            break
        }
    }
    if (index < 0)
        return null
    list.splice(index + 1, 0, { type: "separator", id: id })
    return compactDockItems(list)
}

// Drop separators that are not strictly between two stored apps. Explicit
// reorder and unpin use this so a separator dragged to either end, or left
// beside another separator, is removed from the saved list. The display
// filter still does not write on its own.
export function compactDockItems(items) {
    const collapsed = []
    const list = asArray(items)
    for (let i = 0; i < list.length; i++) {
        const item = list[i]
        if (!item)
            continue
        if (item.type === "separator" && collapsed.length > 0
                && collapsed[collapsed.length - 1].type === "separator")
            continue
        collapsed.push(item)
    }
    let start = 0
    let end = collapsed.length
    while (start < end && collapsed[start].type === "separator")
        start++
    while (end > start && collapsed[end - 1].type === "separator")
        end--
    return collapsed.slice(start, end)
}

export function removeSeparator(items, id) {
    if (typeof id !== "string" || id.length === 0)
        return null
    const list = asArray(items)
    let found = false
    const next = []
    for (let i = 0; i < list.length; i++) {
        const item = list[i]
        if (item && item.type === "separator" && item.id === id) {
            found = true
            continue
        }
        next.push(item)
    }
    return found ? next : null
}

// Same index arithmetic as the historical app reorder: the destination is
// chosen before the source is removed, then the source is inserted there.
export function moveDockItem(items, sourceType, sourceKey, targetIndex) {
    const list = asArray(items).slice()
    let sourceIndex = -1
    for (let i = 0; i < list.length; i++) {
        const item = list[i]
        if (!item)
            continue
        if (sourceType === "app" && item.type === "app" && item.appId === sourceKey) {
            sourceIndex = i
            break
        }
        if (sourceType === "separator" && item.type === "separator" && item.id === sourceKey) {
            sourceIndex = i
            break
        }
    }
    if (sourceIndex < 0)
        return null
    const destination = Math.max(0, Math.min(list.length - 1, Math.round(Number(targetIndex))))
    if (!Number.isFinite(destination) || sourceIndex === destination)
        return null
    const moved = list.splice(sourceIndex, 1)[0]
    list.splice(destination, 0, moved)
    return list
}

export { DOCK_CONFIG_VERSION }
