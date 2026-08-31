pragma Singleton
import QtQuick
import Quickshell

// Shared application-presentation contract. It deliberately has no Dock or
// Launcher import, so every shell surface can use the same descriptor:
// descriptor(entry, rawId) -> desktopId, displayName, iconSource, defaults.
QtObject {
    id: service

    property var _iconCache: ({})
    property var overrides: ({})
    property int revision: 0
    // Installed desktop entries can change independently of user overrides.
    // Consumers bind to this revision instead of each enumerating
    // DesktopEntries, which keeps the shell's app catalogue consistent.
    property int catalogRevision: 0

    function setOverrides(next) {
        const value = next || ({})
        if (JSON.stringify(value) === JSON.stringify(overrides)) return false
        overrides = value
        revision++
        return true
    }

    function invalidateThemeIcons() {
        // Theme icon names resolve to paths from the currently active KDE
        // icon theme. Keep custom file/resource URLs untouched logically, but
        // clear the common cache so the next descriptor obtains the new path.
        _iconCache = ({})
        revision++
    }

    function overrideFor(desktopId, rawId) {
        const direct = overrides[desktopId] ?? overrides[rawId] ?? null
        if (direct) return direct
        const a = normalize(desktopId), b = normalize(rawId)
        for (const key in overrides) {
            const normalized = normalize(key)
            if (normalized && (normalized === a || normalized === b)) return overrides[key]
        }
        return ({})
    }

    function descriptor(entry, rawId) {
        const raw = String(rawId ?? entry?.id ?? "")
        const desktopId = /\.desktop$/i.test(String(entry?.id ?? raw))
            ? String(entry?.id ?? raw) : String(entry?.id ?? raw) + ".desktop"
        const override = overrideFor(desktopId, raw)
        const defaultName = entry?.name ?? raw
        const defaultIcon = iconSource(entry?.icon ?? "") || String(entry?.icon ?? "")
        return { desktopId: desktopId, rawAppId: raw, entry: entry,
            defaultName: defaultName, defaultIcon: defaultIcon,
            displayName: override.name || defaultName,
            iconSource: iconSource(override.icon || defaultIcon) || defaultIcon,
            override: override }
    }

    // The single installed-app catalogue used by launcher/search surfaces.
    // This intentionally returns presentation descriptors rather than raw
    // DesktopEntry objects, so a custom name/icon is identical everywhere.
    function catalog() {
        const entries = DesktopEntries.applications?.values ?? []
        const apps = []
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i]
            if (!entry || entry.noDisplay)
                continue
            const rawId = entry.id ?? ""
            if (rawId)
                apps.push(descriptor(entry, rawId))
        }
        apps.sort((left, right) =>
            left.displayName.localeCompare(right.displayName))
        return apps
    }

    function iconSource(candidate) {
        const value = String(candidate ?? "").trim()
        if (!value)
            return ""
        if (_iconCache[value] !== undefined)
            return _iconCache[value]
        let resolved = ""
        // Keep shell surfaces on Quickshell's icon provider. The Dock's KWin
        // animation bridge converts provider URLs that wrap local custom
        // images at its process boundary; changing the global source to a raw
        // file URL makes the rendered Dock artwork lose provider-side sizing.
        try { resolved = Quickshell.iconPath(value, true) || "" } catch (e) {}
        if (!resolved && value.startsWith("/"))
            resolved = "file://" + value
        // Qt resource URLs are also already-renderable image sources, even
        // though they do not have a URI scheme beginning with a letter.
        if (!resolved && (value.startsWith(":/")
                          || /^[a-z][a-z0-9+.-]*:/i.test(value)))
            resolved = value
        _iconCache[value] = resolved
        return resolved
    }

    function normalize(value) {
        return String(value ?? "").replace(/<\d+>$/, "")
            .replace(/\.desktop$/i, "").toLowerCase()
            .replace(/[-_\s.]/g, "")
    }

    // QtObject has no default child property: keep this connection named so
    // the singleton loads on all Quickshell/QML versions.
    property Connections _desktopEntriesConnections: Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            // Installed-app changes affect the catalogue only. They do not
            // invalidate a themed icon path, and clearing this cache during
            // Quickshell startup makes AppLauncher-triggered identity refresh
            // repeatedly perform expensive icon lookups on the UI thread.
            service.catalogRevision++
        }
    }

    property Connections _iconThemeConnections: Connections {
        target: IconThemeReloadService
        function onRevisionChanged() {
            service.invalidateThemeIcons()
        }
    }
}
