// Desktop grouped view: the one place that decides which desktop entry belongs
// to which preset category. Pure data so both QML and the node test can use it.
//
// The fallback bucket is deliberate. Anything the desktop service adds later
// (a new kind, or an unknown one) lands in "files" instead of disappearing
// from the grouped view.

export const CATEGORY_ORDER = ["shortcuts", "pictures", "folders", "files"]

export function categoryOf(kind) {
    switch (kind) {
    case "launcher":
        return "shortcuts"
    case "image":
        return "pictures"
    case "folder":
        return "folders"
    default:
        return "files"
    }
}

export function labelKey(category) {
    switch (category) {
    case "shortcuts":
        return "App shortcuts"
    case "pictures":
        return "Pictures"
    case "folders":
        return "Folders"
    case "files":
        return "Files"
    default:
        return ""
    }
}

// The bundled glyph shown on the left tab for each preset category.
export function iconName(category) {
    switch (category) {
    case "shortcuts":
        return "desktop.file.launcher"
    case "pictures":
        return "desktop.file.image"
    case "folders":
        return "desktop.file.folder"
    default:
        return "desktop.file.text"
    }
}

// Preserve the caller's order inside each group. The desktop grid already
// publishes the user's saved order, so the grouped view must not re-sort it.
export function buildGroups(entries) {
    const buckets = {
        shortcuts: [],
        pictures: [],
        folders: [],
        files: []
    }
    const list = Array.isArray(entries) ? entries : []
    for (let index = 0; index < list.length; ++index) {
        const entry = list[index]
        if (!entry)
            continue
        buckets[categoryOf(entry.kind)].push(entry)
    }
    return CATEGORY_ORDER.map(function(category) {
        return { category: category, entries: buckets[category] }
    }).filter(function(group) {
        return group.entries.length > 0
    })
}
