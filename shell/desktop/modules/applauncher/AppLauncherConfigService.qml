pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.desktop.modules.common

// AppLauncherConfigService — persistent launcher-only layout data.
//
// This must stay separate from DockConfigService: Dock pins and launcher
// folders have different lifecycles. The schema already understands folders,
// although the first launcher UI consumes only root app ordering.
QtObject {
    id: service

    readonly property string configDir: Quickshell.stateDir + "/applauncher"
    readonly property string configPath: configDir + "/config.json"
    property string displayMode: "bottom"
    property real iconSize: 52
    property real iconSpacing: 24
    property real fontSize: 11
    property string fontWeight: "normal" // "normal" | "medium" | "bold"
    property var rootItems: []
    property var hiddenAppIds: []
    property var appOverrides: ({})
    signal customIconImportFinished(string appId, string path, bool success)

    function isValidDisplayMode(mode) {
        return mode === "bottom" || mode === "center" || mode === "fullscreen"
    }

    function isValidFontWeight(weight) {
        return weight === "normal" || weight === "medium" || weight === "bold"
    }

    function updateDisplayMode(mode) {
        if (!isValidDisplayMode(mode) || displayMode === mode)
            return false
        displayMode = mode
        scheduleSave()
        return true
    }

    function updateIconSize(size) {
        const clamped = Math.max(40, Math.min(80, Math.round(size)))
        if (iconSize === clamped)
            return false
        iconSize = clamped
        scheduleSave()
        return true
    }

    function updateIconSpacing(spacing) {
        const clamped = Math.max(10, Math.min(48, Math.round(spacing)))
        if (iconSpacing === clamped)
            return false
        iconSpacing = clamped
        scheduleSave()
        return true
    }

    function updateFontSize(size) {
        const clamped = Math.max(9, Math.min(18, Math.round(size)))
        if (fontSize === clamped)
            return false
        fontSize = clamped
        scheduleSave()
        return true
    }

    function updateFontWeight(weight) {
        if (!isValidFontWeight(weight) || fontWeight === weight)
            return false
        fontWeight = weight
        scheduleSave()
        return true
    }

    // Layout remains launcher-local; presentation overrides are published to
    // the common service so Dock and QuickSearch consume the same record.
    function _publishPresentationOverrides() {
        AppPresentationService.setOverrides(appOverrides)
    }

    function _normalizeRootItems(rawItems) {
        const normalized = []
        const seenApps = ({})
        const items = Array.isArray(rawItems) ? rawItems : []
        for (let i = 0; i < items.length; i++) {
            const item = items[i]
            if (!item || typeof item !== "object")
                continue
            if (item.type === "app" && typeof item.appId === "string"
                    && item.appId.length > 0 && !seenApps[item.appId]) {
                seenApps[item.appId] = true
                normalized.push({ type: "app", appId: item.appId })
            } else if (item.type === "folder" && typeof item.id === "string"
                    && typeof item.name === "string" && Array.isArray(item.appIds)) {
                // Folder validation exists before folder rendering is added.
                // This prevents a future UI from accepting malformed disk data.
                const appIds = item.appIds.filter(function(appId) {
                    return typeof appId === "string" && appId.length > 0
                })
                normalized.push({ type: "folder", id: item.id,
                    name: item.name, appIds: appIds })
            }
        }
        return normalized
    }

    function setRootItems(items) {
        const normalized = _normalizeRootItems(items)
        if (JSON.stringify(normalized) === JSON.stringify(rootItems))
            return false
        rootItems = normalized
        scheduleSave()
        return true
    }

    // Current grid projection. Persisted app items keep their chosen order;
    // newly installed apps follow alphabetically without silently modifying
    // the user's layout. Folder rendering will replace this projection later.
    function orderedApplications(catalog) {
        const apps = Array.isArray(catalog) ? catalog : []
        const byId = ({})
        for (let i = 0; i < apps.length; i++)
            byId[apps[i].id] = apps[i]

        const ordered = []
        const used = ({})
        for (let i = 0; i < rootItems.length; i++) {
            const item = rootItems[i]
            if (item.type === "app" && byId[item.appId]) {
                ordered.push(byId[item.appId])
                used[item.appId] = true
            }
        }
        for (let i = 0; i < apps.length; i++) {
            if (!used[apps[i].id])
                ordered.push(apps[i])
        }
        return ordered
    }

    // Root-grid projection used by the normal launcher view. Folder children
    // are deliberately marked as used, so they never also appear as loose
    // root apps. Search uses `orderedApplications` separately and stays flat.
    function rootGridItems(catalog) {
        const apps = Array.isArray(catalog) ? catalog : []
        const byId = ({})
        for (let i = 0; i < apps.length; i++)
            byId[apps[i].id] = apps[i]

        const items = []
        const used = ({})
        for (let i = 0; i < rootItems.length; i++) {
            const item = rootItems[i]
            if (item.type === "app" && byId[item.appId]) {
                items.push({ type: "app", app: byId[item.appId] })
                used[item.appId] = true
            } else if (item.type === "folder") {
                const folderApps = []
                for (let j = 0; j < item.appIds.length; j++) {
                    const app = byId[item.appIds[j]]
                    if (app) {
                        folderApps.push(app)
                        used[app.id] = true
                    }
                }
                if (folderApps.length > 0)
                    items.push({ type: "folder", id: item.id,
                        name: item.name, apps: folderApps })
            }
        }
        for (let i = 0; i < apps.length; i++) {
            if (!used[apps[i].id])
                items.push({ type: "app", app: apps[i] })
        }
        return items
    }

    function createFolder(sourceAppId, targetAppId, catalog) {
        if (!sourceAppId || !targetAppId || sourceAppId === targetAppId)
            return false
        const grid = rootGridItems(catalog)
        let sourceIndex = -1
        let targetIndex = -1
        for (let i = 0; i < grid.length; i++) {
            if (grid[i].type !== "app")
                continue
            if (grid[i].app.id === sourceAppId)
                sourceIndex = i
            if (grid[i].app.id === targetAppId)
                targetIndex = i
        }
        if (sourceIndex < 0 || targetIndex < 0)
            return false

        const folder = {
            type: "folder",
            id: "folder-" + Date.now() + "-"
                + Math.floor(Math.random() * 1000000),
            name: "文件夹",
            appIds: [targetAppId, sourceAppId],
        }
        const replacementIndex = Math.min(sourceIndex, targetIndex)
        const next = []
        for (let i = 0; i < grid.length; i++) {
            if (i === replacementIndex)
                next.push(folder)
            const item = grid[i]
            if (item.type === "app" && (item.app.id === sourceAppId
                    || item.app.id === targetAppId))
                continue
            if (item.type === "app")
                next.push({ type: "app", appId: item.app.id })
            else
                next.push({ type: "folder", id: item.id, name: item.name,
                    appIds: item.apps.map(app => app.id) })
        }
        return setRootItems(next)
    }

    function addApplicationToFolder(appId, folderId, catalog) {
        // Work from the persisted tree itself. Rebuilding from a visual grid
        // can omit unavailable apps or accidentally rewrite a folder's prior
        // children; this transaction changes exactly two records only.
        let next = _normalizeRootItems(rootItems)
        let sourceIndex = -1
        let folderIndex = -1
        for (let i = 0; i < next.length; i++) {
            if (next[i].type === "app" && next[i].appId === appId)
                sourceIndex = i
            if (next[i].type === "folder" && next[i].id === folderId)
                folderIndex = i
        }

        // A newly installed app may not yet have been materialized into the
        // first saved root layout. Materialize once, then retry the same safe
        // direct mutation against that complete sequence.
        if (sourceIndex < 0) {
            next = rootGridItems(catalog).map(function(item) {
                return item.type === "app"
                    ? { type: "app", appId: item.app.id }
                    : { type: "folder", id: item.id, name: item.name,
                        appIds: item.apps.map(app => app.id) }
            })
            for (let i = 0; i < next.length; i++) {
                if (next[i].type === "app" && next[i].appId === appId)
                    sourceIndex = i
                if (next[i].type === "folder" && next[i].id === folderId)
                    folderIndex = i
            }
        }
        if (sourceIndex < 0 || folderIndex < 0)
            return false

        const folder = next[folderIndex]
        if (folder.appIds.indexOf(appId) >= 0)
            return false
        folder.appIds = folder.appIds.concat([appId])
        next.splice(sourceIndex, 1)
        console.log("[AppLauncherConfig] add app=" + appId
            + " folder=" + folderId + " members="
            + JSON.stringify(folder.appIds))
        return setRootItems(next)
    }

    // Keep a folder's child order separate from the root-grid order. This is
    // a small direct transaction, so dragging within an open folder cannot
    // flatten folders or disturb unrelated root applications.
    function moveApplicationWithinFolder(appId, folderId, targetIndex) {
        const next = _normalizeRootItems(rootItems)
        for (let i = 0; i < next.length; i++) {
            const folder = next[i]
            if (folder.type !== "folder" || folder.id !== folderId)
                continue
            const sourceIndex = folder.appIds.indexOf(appId)
            if (sourceIndex < 0)
                return false
            const destination = Math.max(0, Math.min(folder.appIds.length - 1,
                Math.round(targetIndex)))
            if (sourceIndex === destination)
                return false
            const appIds = folder.appIds.slice()
            const moved = appIds.splice(sourceIndex, 1)[0]
            appIds.splice(destination, 0, moved)
            folder.appIds = appIds
            return setRootItems(next)
        }
        return false
    }

    // Removing an app materializes it immediately after its former folder.
    // A one-app folder has no useful meaning, so it dissolves into two normal
    // root entries while preserving the remaining app and the removed app.
    function removeApplicationFromFolder(appId, folderId) {
        const next = _normalizeRootItems(rootItems)
        for (let i = 0; i < next.length; i++) {
            const folder = next[i]
            if (folder.type !== "folder" || folder.id !== folderId)
                continue
            const sourceIndex = folder.appIds.indexOf(appId)
            if (sourceIndex < 0)
                return false
            const remaining = folder.appIds.slice()
            remaining.splice(sourceIndex, 1)
            if (remaining.length < 2) {
                const replacement = remaining.map(function(id) {
                    return { type: "app", appId: id }
                })
                replacement.push({ type: "app", appId: appId })
                next.splice.apply(next, [i, 1].concat(replacement))
            } else {
                folder.appIds = remaining
                next.splice(i + 1, 0, { type: "app", appId: appId })
            }
            console.log("[AppLauncherConfig] remove app=" + appId
                + " folder=" + folderId + " remaining="
                + JSON.stringify(remaining))
            return setRootItems(next)
        }
        return false
    }

    function renameFolder(folderId, requestedName) {
        const name = (requestedName || "").trim() || "文件夹"
        const next = _normalizeRootItems(rootItems)
        for (let i = 0; i < next.length; i++) {
            const folder = next[i]
            if (folder.type !== "folder" || folder.id !== folderId)
                continue
            if (folder.name === name)
                return false
            folder.name = name
            console.log("[AppLauncherConfig] rename folder=" + folderId
                + " name=" + name)
            return setRootItems(next)
        }
        return false
    }

    // Per-app presentation is launcher-local. Keep the original desktop-entry
    // metadata untouched so users can always return to the system defaults.
    function updateAppOverride(appId, requestedName, requestedIcon,
                               defaultName, defaultIcon) {
        if (!appId)
            return false
        const name = (requestedName || "").trim()
        const icon = (requestedIcon || "").trim()
        const override = ({})
        if (name && name !== defaultName)
            override.name = name
        if (icon && icon !== defaultIcon)
            override.icon = icon

        const next = Object.assign({}, appOverrides)
        if (Object.keys(override).length > 0)
            next[appId] = override
        else
            delete next[appId]
        if (JSON.stringify(next) === JSON.stringify(appOverrides)) {
            // A shell surface can be recreated while this singleton retains
            // disk state. Re-publish even an unchanged save so Dock never
            // waits for a full Quickshell restart to learn the override.
            _publishPresentationOverrides()
            return false
        }
        appOverrides = next
        _publishPresentationOverrides()
        scheduleSave()
        console.log("[AppLauncherConfig] update app=" + appId
            + " override=" + JSON.stringify(override))
        return true
    }

    // Copy selected artwork into launcher-owned state. App overrides must
    // never point at arbitrary user files that may later be moved or deleted.
    function importCustomIcon(appId, fileUrl) {
        if (!appId || !fileUrl)
            return ""
        const source = decodeURIComponent(String(fileUrl).replace(/^file:\/\//, ""))
        const extensionMatch = source.match(/\.([A-Za-z0-9]{1,8})$/)
        const extension = extensionMatch ? extensionMatch[1].toLowerCase() : "png"
        const safeId = appId.replace(/[^A-Za-z0-9._-]/g, "_")
        const destination = configDir + "/icons/" + safeId + "." + extension
        const proc = _makeProcess([
            "sh", "-c",
            "mkdir -p \"$2/icons\" && cp -- \"$1\" \"$3\"",
            "applauncher-icon-import", source, configDir, destination,
        ])
        if (!proc)
            return ""
        proc.exited.connect(function(code) {
            if (code !== 0)
                console.warn("[AppLauncherConfig] icon import failed code=" + code)
            else
                console.log("[AppLauncherConfig] icon imported app=" + appId)
            service.customIconImportFinished(appId, destination, code === 0)
            proc.destroy()
        })
        proc.running = true
        return destination
    }

    // wl-paste is the standard Wayland clipboard reader used by Hyprland
    // setups. Limit this first path to PNG so a copied image has a predictable
    // extension and can be loaded by IconImage without format guessing.
    function importClipboardPngIcon(appId) {
        if (!appId)
            return ""
        const safeId = appId.replace(/[^A-Za-z0-9._-]/g, "_")
        const destination = configDir + "/icons/" + safeId + "-clipboard.png"
        const proc = _makeProcess([
            "sh", "-c",
            "command -v wl-paste >/dev/null 2>&1 && mkdir -p \"$1/icons\" && wl-paste --type image/png > \"$2\" && test -s \"$2\"",
            "applauncher-clipboard-icon", configDir, destination,
        ])
        if (!proc)
            return ""
        proc.exited.connect(function(code) {
            if (code !== 0)
                console.warn("[AppLauncherConfig] clipboard PNG import failed")
            else
                console.log("[AppLauncherConfig] clipboard icon imported app=" + appId)
            service.customIconImportFinished(appId, destination, code === 0)
            proc.destroy()
        })
        proc.running = true
        return destination
    }

    function hideApplication(appId) {
        if (!appId || hiddenAppIds.indexOf(appId) >= 0)
            return false
        hiddenAppIds = hiddenAppIds.concat([appId])
        scheduleSave()
        console.log("[AppLauncherConfig] hide app=" + appId)
        return true
    }

    function unhideApplication(appId) {
        const index = hiddenAppIds.indexOf(appId)
        if (index < 0)
            return false
        const next = hiddenAppIds.slice()
        next.splice(index, 1)
        hiddenAppIds = next
        scheduleSave()
        return true
    }

    // Reorder only root-grid entries. Rebuilding from `orderedApplications`
    // would flatten folder children back into ordinary apps, so always use the
    // typed grid projection here.
    function moveApplication(appId, targetIndex, catalog) {
        const ordered = rootGridItems(catalog)
        let sourceIndex = -1
        for (let i = 0; i < ordered.length; i++) {
            if (ordered[i].type === "app" && ordered[i].app.id === appId) {
                sourceIndex = i
                break
            }
        }
        if (sourceIndex < 0)
            return false

        const destination = Math.max(0, Math.min(ordered.length - 1,
            Math.round(targetIndex)))
        if (sourceIndex === destination)
            return false

        const moved = ordered.splice(sourceIndex, 1)[0]
        ordered.splice(destination, 0, moved)
        return setRootItems(ordered.map(function(item) {
            if (item.type === "app")
                return { type: "app", appId: item.app.id }
            return { type: "folder", id: item.id, name: item.name,
                appIds: item.apps.map(app => app.id) }
        }))
    }

    // Move either kind of root-grid entry. Folder membership is untouched;
    // only the folder tile itself changes position among root applications.
    function moveRootItem(itemType, itemKey, targetIndex, catalog) {
        const ordered = rootGridItems(catalog)
        let sourceIndex = -1
        for (let i = 0; i < ordered.length; i++) {
            const item = ordered[i]
            if ((itemType === "app" && item.type === "app"
                        && item.app.id === itemKey)
                    || (itemType === "folder" && item.type === "folder"
                        && item.id === itemKey)) {
                sourceIndex = i
                break
            }
        }
        if (sourceIndex < 0)
            return false
        const destination = Math.max(0, Math.min(ordered.length - 1,
            Math.round(targetIndex)))
        if (sourceIndex === destination)
            return false
        const moved = ordered.splice(sourceIndex, 1)[0]
        ordered.splice(destination, 0, moved)
        return setRootItems(ordered.map(function(item) {
            if (item.type === "app")
                return { type: "app", appId: item.app.id }
            return { type: "folder", id: item.id, name: item.name,
                appIds: item.apps.map(app => app.id) }
        }))
    }

    property Timer _saveTimer: Timer {
        interval: 500
        repeat: false
        onTriggered: service._save()
    }
    function scheduleSave() { _saveTimer.restart() }

    function _save() {
        const json = JSON.stringify({
            version: 2,
            displayMode: displayMode,
            iconSize: iconSize,
            iconSpacing: iconSpacing,
            fontSize: fontSize,
            fontWeight: fontWeight,
            rootItems: rootItems,
            hiddenAppIds: hiddenAppIds,
            appOverrides: appOverrides,
        }, null, 2)
        const proc = _makeProcess([
            "sh", "-c",
            "mkdir -p \"$1\" && printf %s \"$2\" > \"$1/config.json.tmp\" && mv \"$1/config.json.tmp\" \"$1/config.json\"",
            "applauncher-config-save", configDir, json,
        ])
        if (!proc)
            return
        proc.exited.connect(function(code) {
            if (code !== 0)
                console.warn("[AppLauncherConfig] save failed code=" + code)
            proc.destroy()
        })
        proc.running = true
    }

    function load() {
        const proc = _makeProcess([
            "sh", "-c", "cat \"$1\"", "applauncher-config-load", configPath,
        ])
        if (!proc)
            return
        proc.exited.connect(function(code) {
            const output = proc.stdout?.text ?? ""
            if (code === 0 && output) {
                try {
                    const saved = JSON.parse(output)
                    if (service.isValidDisplayMode(saved.displayMode))
                        displayMode = saved.displayMode
                    if (typeof saved.iconSize === "number" && saved.iconSize >= 40 && saved.iconSize <= 80)
                        iconSize = saved.iconSize
                    if (typeof saved.iconSpacing === "number" && saved.iconSpacing >= 10 && saved.iconSpacing <= 48)
                        iconSpacing = saved.iconSpacing
                    if (typeof saved.fontSize === "number" && saved.fontSize >= 9 && saved.fontSize <= 18)
                        fontSize = saved.fontSize
                    if (service.isValidFontWeight(saved.fontWeight))
                        fontWeight = saved.fontWeight
                    rootItems = _normalizeRootItems(saved.rootItems)
                    hiddenAppIds = Array.isArray(saved.hiddenAppIds)
                        ? saved.hiddenAppIds : []
                    appOverrides = saved.appOverrides ?? ({})
                    service._publishPresentationOverrides()
                    console.log("[AppLauncherConfig] loaded roots=" + rootItems.length + " mode=" + displayMode)
                } catch (error) {
                    console.warn("[AppLauncherConfig] parse failed: " + error)
                }
            }
            proc.destroy()
        })
        proc.running = true
    }

    property Component _processFactory: Component {
        Process {
            stdout: StdioCollector {}
            stderr: StdioCollector {}
        }
    }
    function _makeProcess(command) {
        try {
            return _processFactory.createObject(service, { command: command })
        } catch (error) {
            console.warn("[AppLauncherConfig] process creation failed: " + error)
            return null
        }
    }

    Component.onCompleted: load()
}
