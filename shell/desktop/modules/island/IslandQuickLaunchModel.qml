pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.desktop.modules.common

// IslandQuickLaunchModel — the pinned-application list behind the island's
// quick-launch strip.
//
// Ported from the NookX Dynamic Island. The original keeps a QuickLaunch list
// with a custom order, a sort option, a filter option and a page cursor, and
// reads application icons through NSWorkspace and caches them in
// AppIconCache.
//
// The Linux equivalent enumerates desktop entries through Quickshell's
// DesktopEntries model, keeps the user's pinned order in
// IslandConfigService.pinnedApps, and resolves each pinned id back to its
// live entry so a launch can go through AppActionService (and therefore the
// platform contract) rather than a shell command.
QtObject {
    id: service

    // The live desktop-entry catalogue. DesktopEntries replaces its model on
    // every scan, so the list is re-derived whenever that happens.
    property var allEntries: []

    // --- Stable views -------------------------------------------------------
    //
    // The views below are cached and only replaced when their *content*
    // changes. DesktopEntries replaces its model on every rescan, and a view
    // derived straight from it would hand the island a brand new array of
    // brand new entry objects each time: every tile's modelData would change
    // identity, its icon binding would re-resolve, the artwork would reload,
    // and a drag in progress would lose its target. The symptom was a strip
    // that flickered and could not be picked up.
    //
    // The key is the order plus each entry's name -- what the view actually
    // shows. The cached entry object keeps the artwork with it, so a
    // rescan that changes nothing does not disturb the view.
    property var _entryCache: []
    property string _entryKey: ""
    property var _availableCache: []
    property string _availableKey: ""

    // Pinned entries resolved against the live catalogue. An id that is no
    // longer installed is dropped from the view but stays in the persisted
    // order, so reinstalling the app brings the pin back.
    readonly property var entries: _entryCache

    // The unpinned catalogue, used by the Settings page when the user picks
    // which applications to add to the island.
    readonly property var availableEntries: _availableCache

    function _entryById(id) {
        const list = allEntries
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].id === id)
                return list[i]
        }
        return null
    }

    function _pinnedKey() {
        const pinned = IslandConfigService.pinnedApps || []
        const parts = []
        for (let i = 0; i < pinned.length; i++) {
            const e = _entryById(pinned[i])
            parts.push(pinned[i] + "" + (e ? e.name : ""))
        }
        return parts.join("")
    }

    function _availableEntriesKey() {
        const pinned = IslandConfigService.pinnedApps || []
        const parts = []
        for (let i = 0; i < allEntries.length; i++) {
            const e = allEntries[i]
            if (e && e.id && pinned.indexOf(e.id) < 0)
                parts.push(e.id + "" + (e.name || ""))
        }
        return parts.join("")
    }

    function _rebuild() {
        const pinnedKey = _pinnedKey()
        if (pinnedKey !== _entryKey) {
            _entryKey = pinnedKey
            const out = []
            const pinned = IslandConfigService.pinnedApps || []
            for (let i = 0; i < pinned.length; i++) {
                const entry = _entryById(pinned[i])
                // A dropped file is pinned as "file:/abs/path" and has no
                // desktop entry behind it. It still belongs on the deck -- the
                // drop is a shortcut, not a copy -- so it is synthesised here
                // as an ordinary entry with a file icon and the path attached.
                if (!entry && String(pinned[i]).indexOf("file:") === 0) {
                    const path = String(pinned[i]).slice(5)
                    const name = path.replace(/^.*\//, "") || path
                    out.push({
                        id: pinned[i],
                        icon: iconFor("text-x-generic"),
                        name: name,
                        kind: "file",
                        path: path
                    })
                    continue
                }
                if (entry) {
                    out.push({
                        id: entry.id,
                        // Resolved, not raw: a desktop entry carries an icon
                        // *name* ("firefox"), and Qt reads a bare name as a
                        // relative file URL, fails the load, and leaves the
                        // tile with no artwork at all. AppPresentationService
                        // is the shell's single resolver for this (it is what
                        // the Dock and the Launcher use), and its generic
                        // fallback guarantees a tile is never blank.
                        icon: iconFor(entry.icon),
                        name: entry.name || entry.id,
                        entry: entry
                    })
                }
            }
            _entryCache = out
        }

        const availableKey = _availableEntriesKey()
        if (availableKey !== _availableKey) {
            _availableKey = availableKey
            const free = []
            const pinned = IslandConfigService.pinnedApps || []
            for (let i = 0; i < allEntries.length; i++) {
                const e = allEntries[i]
                if (e && e.id && pinned.indexOf(e.id) < 0)
                    free.push({ id: e.id, name: e.name || e.id, icon: iconFor(e.icon) })
            }
            _availableCache = free
        }
    }

    // The one place the island turns a desktop entry's artwork into something
    // an Image can load. Public because the app picker resolves entries
    // straight from the catalogue instead of going through `entries`.
    function iconFor(raw) {
        return AppPresentationService.iconSource(raw) || AppPresentationService.genericIconSource()
    }

    onAllEntriesChanged: _rebuild()

    function entryFor(id) {
        const list = allEntries
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].id === id)
                return list[i]
        }
        return null
    }

    function isPinned(id) {
        return (IslandConfigService.pinnedApps || []).indexOf(String(id)) >= 0
    }

    function togglePin(id) {
        if (isPinned(id))
            IslandConfigService.unpinApp(id)
        else
            IslandConfigService.pinApp(id)
    }

    // Reorders the resolved entries and writes the full pinned order back —
    // the port of the original's QuickLaunchDragProvider/DropDelegate pair.
    // Ids that are not currently installed keep their relative order at the
    // end, so reinstalling an app restores the pin where the user left it.
    function moveEntry(from, to) {
        const resolved = entries
        if (from < 0 || to < 0 || from >= resolved.length || to >= resolved.length)
            return
        const ids = resolved.map(function(e) { return e.id })
        const moved = ids.splice(from, 1)[0]
        ids.splice(to, 0, moved)
        const pinned = IslandConfigService.pinnedApps || []
        const leftovers = pinned.filter(function(id) { return ids.indexOf(id) < 0 })
        IslandConfigService.setPinnedApps(ids.concat(leftovers))
    }

    // --- Catalogue tracking -------------------------------------------------
    // QtObject has no default property, so the watcher is wrapped in a
    // property, matching the platform singletons.
    property Connections _applicationsWatcher: Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            const apps = DesktopEntries.applications
            service.allEntries = apps && apps.values ? Array.from(apps.values) : []
        }
    }

    // Pinning and unpinning change the catalogue the island shows, and the
    // cache has to follow.
    property Connections _pinWatcher: Connections {
        target: IslandConfigService
        function onPinnedAppsChanged() { service._rebuild() }
    }

    Component.onCompleted: {
        const apps = DesktopEntries.applications
        service.allEntries = apps && apps.values ? Array.from(apps.values) : []
        service._rebuild()
    }
}
