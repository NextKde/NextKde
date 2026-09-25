pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.desktop.modules.common
import qs.desktop.modules.platform

// ────────────────────────────────────────────────────────────────
// DockConfigService — Persistent JSON configuration.
//
// Reads/writes dock/config.json on disk.  All values have sensible
// defaults so the dock works before the first config file exists.
//
// Writes are debounced (500 ms) so rapid changes batch into one save.
// ────────────────────────────────────────────────────────────────

QtObject {
    id: svc

    // Pin state is runtime user data, not QML source. Keeping it outside the
    // shell directory prevents Quickshell's source-file watcher from reloading
    // the shell while a temporary config file is being atomically replaced.
    readonly property string configDir:  Quickshell.stateDir + "/dock"
    readonly property string configPath: configDir + "/config.json"

    // ── Default proportion constants ──
    readonly property var defaultProportions: ({
        vpad:      0.20,
        hpad:      0.4,
        spacing:   0.09,
        divmargin: 0.20,
    })

    // ═══════════════════════════════════════════════════════════
    // Runtime values (backed by JSON when available)
    // ═══════════════════════════════════════════════════════════
    property real   baseHeight:   60
    property string theme:        "system"
    property string position:     "bottom"
    // Product-level presentation. Geometry details are derived from this one
    // choice so settings cannot create a stretched-but-floating hybrid.
    property string dockStyle:    "floating"
    // Compact keeps the whole content group together. Relaxed spends any
    // taskbar slack between apps/windows and the trailing information area.
    property string contentStyle: "compact"
    // Internal compatibility projections while renderers consume the concise
    // product model. They are derived, never persisted or exposed in settings.
    readonly property string widthMode: dockStyle === "taskbar" ? "stretch" : "auto"
    readonly property bool stretchFloating: false
    // Reserved strip of the top status bar. Side docks subtract it from the
    // screen height so their column cap never overlaps the bar. The bar reads
    // this value too, keeping one source of truth; a future bar-visibility
    // setting will decide whether it is applied at all.
    property real   barHeight:    35
    // Icon appearance source of truth. Shader inputs are derived from iconMode
    // instead of persisted separately, preventing impossible mixed states.
    property string iconMode:        "color"       // "color" | "grayscale" | "tint"
    property real   iconOpacity:     0.5
    property string iconTintColor:   "#a855f7"
    readonly property real iconSaturation: iconMode === "color" ? 1.0 : 0.0
    readonly property real iconTintEnabled: iconMode === "tint" ? 1.0 : 0.0
    readonly property color resolvedIconTintColor: iconTintColor

    // Shared projection for non-icon Dock artwork such as weather, clock and
    // temperature card backgrounds. It mirrors the icon shader contract:
    // colour is untouched, grayscale preserves luminance, and tint preserves
    // luminance while introducing the selected hue.
    function styledDockColor(source) {
        if (iconMode === "color")
            return source
        const luminance = source.r * 0.299 + source.g * 0.587
            + source.b * 0.114
        if (iconMode === "grayscale")
            return Qt.rgba(luminance, luminance, luminance, source.a)
        const tint = resolvedIconTintColor
        return Qt.rgba(
            (tint.r + (1 - tint.r) * luminance) * luminance,
            (tint.g + (1 - tint.g) * luminance) * luminance,
            (tint.b + (1 - tint.b) * luminance) * luminance,
            source.a)
    }

    // Flat shell SVGs have no internal light/dark pixels for the application
    // icon shader to preserve. Treat them as a 72% luminance glyph so tint
    // mode receives the same restrained tonal colour instead of a fully
    // saturated paint bucket.
    function styledDockIconColor() {
        if (iconMode !== "tint")
            return Qt.rgba(1, 1, 1, 1)
        return styledDockColor(Qt.rgba(0.72, 0.72, 0.72, 1))
    }
    // Dock show mode. Single mutually-exclusive enum: "always" | "smart" |
    // "persistent". Never store two booleans — that allows impossible states.
    property string visibilityMode: "always"
    // Window grouping mode: "grouped" (macOS style - 1 icon per app) | "separate" (classic taskbar)
    property string windowGrouping: "grouped"
    // Becomes true once config load finishes (success, missing file, or parse
    // error). The auto-hide controller waits on this before its first reveal
    // decision so a saved smart/persistent dock never flashes fully shown.
    property bool ready: false

    function isValidIconMode(value) {
        return value === "color" || value === "grayscale" || value === "tint"
    }

    function isValidWindowGrouping(value) {
        return value === "grouped" || value === "separate"
    }

    function isValidRgbColor(value) {
        return /^#[0-9a-f]{6}$/.test(String(value).toLowerCase())
    }
    // Legacy compatibility field. New app name/icon edits live in
    // AppLauncherConfigService and are published through AppPresentationService.
    // Keep existing values round-trippable so older config files are not lost.
    property var iconOverrides:   ({})
    // `dockItems` is the canonical ordered list of pinned applications.
    // App item: { type: "app", appId: "code.desktop" }
    property var dockItems: [
        { type: "app", appId: "org.kde.dolphin.desktop" },
        { type: "app", appId: "org.kde.kate.desktop" },
        { type: "app", appId: "code.desktop" },
    ]

    // Compatibility projection for the current Dock UI and AppGroupService.
    // Never edit this directly in new code: use setDockItems/addAppItem/
    // removeAppItem so all Dock persistence has one source of truth.
    property var pinnedAppIds: [
        "org.kde.dolphin.desktop",
        "org.kde.kate.desktop",
        "code.desktop",
    ]
    property var    proportions:  defaultProportions

    // ═══════════════════════════════════════════════════════════
    // Proportion accessor — safe fallback to defaults
    // ═══════════════════════════════════════════════════════════
    function prop(key) {
        if (svc.proportions && svc.proportions[key] !== undefined) {
            return svc.proportions[key]
        }
        return svc.defaultProportions[key] ?? 0
    }

    // ═══════════════════════════════════════════════════════════
    // Debounced save
    // ═══════════════════════════════════════════════════════════
    property Timer _saveTimer: Timer {
        interval: 500
        repeat: false
        onTriggered: svc._doSave()
    }

    function scheduleSave() { _saveTimer.restart() }

    // Public settings contract. Keeping validation and persistence here means
    // external callers cannot put the Dock into an impossible layout state.
    function updateLayout(rawHeight) {
        const height = Math.max(40, Math.min(100, Number(rawHeight)))
        if (!Number.isFinite(height))
            return false
        if (Math.abs(baseHeight - height) <= 0.01)
            return false
        baseHeight = height
        scheduleSave()
        return true
    }

    function isValidTheme(value) {
        return value === "light" || value === "dark" || value === "system"
    }

    function isValidPosition(value) {
        return value === "bottom" || value === "left" || value === "right"
    }

    function updatePosition(rawPosition) {
        const nextPosition = String(rawPosition)
        if (!isValidPosition(nextPosition))
            return false
        if (position === nextPosition)
            return false
        position = nextPosition
        scheduleSave()
        return true
    }

    function isValidDockStyle(value) {
        return value === "floating" || value === "taskbar"
            || value === "transparent"
    }

    function updateDockStyle(rawStyle) {
        const nextStyle = String(rawStyle)
        if (!isValidDockStyle(nextStyle))
            return false
        if (dockStyle === nextStyle)
            return false
        dockStyle = nextStyle
        scheduleSave()
        return true
    }

    function isValidContentStyle(value) {
        return value === "compact" || value === "relaxed"
    }

    function updateContentStyle(rawStyle) {
        const nextStyle = String(rawStyle)
        if (!isValidContentStyle(nextStyle))
            return false
        if (contentStyle === nextStyle)
            return false
        contentStyle = nextStyle
        scheduleSave()
        return true
    }

    // ── Information cards (music / weather / clock / metrics) ──
    // "carousel" keeps the historical single shared slot that rotates through
    // the enabled cards; "expanded" gives every enabled card its own place in
    // the row so nothing rotates any more.
    property string infoCardMode: "carousel"
    property bool infoCardAutoRotate: true
    property bool desktopLyricsEnabled: true
    function updateDesktopLyricsEnabled(enabled) {
        desktopLyricsEnabled = Boolean(enabled)
        scheduleSave()
    }
    readonly property var knownInfoCardIds: ["music", "weather", "clock", "metrics"]
    // One ordered list is the whole component model. Zero items hides the
    // region, one is naturally fixed, and multiple items rotate or expand.
    property var infoCardOrder: ["music", "weather", "clock", "metrics"]
    readonly property bool infoCardMusic: infoCardOrder.indexOf("music") >= 0
    readonly property bool infoCardWeather: infoCardOrder.indexOf("weather") >= 0
    readonly property bool infoCardClock: infoCardOrder.indexOf("clock") >= 0
    readonly property bool infoCardMetrics: infoCardOrder.indexOf("metrics") >= 0
    readonly property bool infoClockSeconds: true
    readonly property bool infoClockDate: true
    readonly property bool infoClockSolar: true
    readonly property bool infoMetricAverage: true
    readonly property bool infoMetricPeak: true
    readonly property bool infoMetricCpu: true
    readonly property bool infoMetricMemory: true
    readonly property bool infoMetricStorage: true

    function isValidInfoCardMode(value) {
        return value === "carousel" || value === "expanded"
    }

    function updateInfoCardMode(rawMode) {
        const nextMode = String(rawMode)
        if (!isValidInfoCardMode(nextMode))
            return false
        if (infoCardMode === nextMode)
            return false
        infoCardMode = nextMode
        scheduleSave()
        return true
    }

    function updateInfoCardAutoRotate(enabled) {
        const nextValue = Boolean(enabled)
        if (infoCardAutoRotate === nextValue)
            return false
        infoCardAutoRotate = nextValue
        scheduleSave()
        return true
    }

    function normalizedInfoCardOrder(rawOrder) {
        const input = Array.isArray(rawOrder) ? rawOrder : []
        const result = []
        for (const rawId of input) {
            const id = String(rawId) === "temperature" ? "metrics" : String(rawId)
            if (knownInfoCardIds.indexOf(id) < 0 || result.indexOf(id) >= 0)
                continue
            result.push(id)
        }
        return result
    }

    function updateInfoCardOrder(rawOrder) {
        const next = normalizedInfoCardOrder(rawOrder)
        if (JSON.stringify(next) === JSON.stringify(infoCardOrder))
            return false
        infoCardOrder = next
        scheduleSave()
        return true
    }

    function addInfoCard(rawId, rawIndex) {
        const id = String(rawId) === "temperature" ? "metrics" : String(rawId)
        if (knownInfoCardIds.indexOf(id) < 0 || infoCardOrder.indexOf(id) >= 0)
            return false
        const next = infoCardOrder.slice()
        const index = Math.max(0, Math.min(next.length,
            Number.isFinite(Number(rawIndex)) ? Number(rawIndex) : next.length))
        next.splice(index, 0, id)
        return updateInfoCardOrder(next)
    }

    function removeInfoCard(rawId) {
        const id = String(rawId)
        return updateInfoCardOrder(infoCardOrder.filter(candidate => candidate !== id))
    }

    function moveInfoCard(rawId, rawIndex) {
        const id = String(rawId)
        const next = infoCardOrder.filter(candidate => candidate !== id)
        if (next.length === infoCardOrder.length)
            return false
        const index = Math.max(0, Math.min(next.length, Number(rawIndex)))
        next.splice(index, 0, id)
        return updateInfoCardOrder(next)
    }

    function updateTheme(rawTheme) {
        const nextTheme = String(rawTheme)
        if (!isValidTheme(nextTheme))
            return false
        const dockChanged = theme !== nextTheme
        const appearanceChanged = AppearanceConfigService.updateThemeMode(nextTheme)
        if (dockChanged) {
            theme = nextTheme
            scheduleSave()
        }
        return dockChanged || appearanceChanged
    }

    function updateIconMode(rawMode) {
        const requestedMode = String(rawMode)
        const nextMode = requestedMode === "duotone" ? "tint" : requestedMode
        if (!isValidIconMode(nextMode))
            return false
        if (iconMode === nextMode)
            return false
        iconMode = nextMode
        scheduleSave()
        return true
    }

    function updateIconOpacity(rawOpacity) {
        const value = Math.max(0.0, Math.min(1.0, Number(rawOpacity)))
        if (!Number.isFinite(value))
            return false
        if (Math.abs(iconOpacity - value) <= 0.001)
            return false
        iconOpacity = value
        scheduleSave()
        return true
    }

    function updateIconTintColor(rawColor) {
        const color = String(rawColor).toLowerCase()
        if (!isValidRgbColor(color) || iconTintColor === color)
            return false
        iconTintColor = color
        scheduleSave()
        return true
    }

    function isValidVisibilityMode(value) {
        return value === "always" || value === "smart" || value === "persistent"
    }

    function updateVisibilityMode(rawMode) {
        const nextMode = String(rawMode)
        if (!isValidVisibilityMode(nextMode) || visibilityMode === nextMode)
            return false
        visibilityMode = nextMode
        scheduleSave()
        return true
    }

    function updateWindowGrouping(rawMode) {
        const nextMode = String(rawMode)
        if (!isValidWindowGrouping(nextMode) || windowGrouping === nextMode)
            return false
        windowGrouping = nextMode
        scheduleSave()
        return true
    }


    // ═══════════════════════════════════════════════════════════
    // Dock item model — Phase 1 persistence API
    // ═══════════════════════════════════════════════════════════
    function _normalizeDockItems(rawItems) {
        const normalized = []
        const items = Array.isArray(rawItems) ? rawItems : []

        for (let i = 0; i < items.length; i++) {
            const item = items[i]
            if (!item || typeof item !== "object")
                continue

            if (item.type === "app" && typeof item.appId === "string"
                    && item.appId.length > 0) {
                normalized.push({ type: "app", appId: item.appId })
                continue
            }

            // Folder support was removed. Flatten legacy entries in-place so
            // no previously pinned application disappears after the upgrade.
            if (item.type === "folder" && typeof item.id === "string"
                    && item.id.length > 0) {
                const appIds = Array.isArray(item.appIds)
                    ? item.appIds.filter(appId => typeof appId === "string" && appId.length > 0)
                    : []
                for (let j = 0; j < appIds.length; j++)
                    normalized.push({ type: "app", appId: appIds[j] })
            }
        }
        return normalized
    }

    function _pinnedIdsFromDockItems(items) {
        const ids = []
        for (let i = 0; i < items.length; i++) {
            const item = items[i]
            if (item.type === "app")
                ids.push(item.appId)
        }
        return ids
    }

    // All future editor and drag operations must go through this transaction.
    // It updates the legacy projection atomically, so the current Dock cannot
    // observe a half-updated configuration while the model is being extended.
    function setDockItems(rawItems) {
        const items = _normalizeDockItems(rawItems)
        const before = JSON.stringify(svc.dockItems)
        const after = JSON.stringify(items)
        if (before === after)
            return false

        svc.dockItems = items
        svc.pinnedAppIds = _pinnedIdsFromDockItems(items)
        return true
    }

    function addAppItem(appId) {
        if (typeof appId !== "string" || !appId.length)
            return false
        const items = _normalizeDockItems(svc.dockItems)
        if (_pinnedIdsFromDockItems(items).indexOf(appId) >= 0)
            return false
        items.push({ type: "app", appId: appId })
        const changed = setDockItems(items)
        if (changed)
            scheduleSave()
        return changed
    }

    // Reorder one pinned application.
    // `sourceKey` deliberately uses the persisted identifier so this remains
    // stable even while application metadata is still resolving.
    function moveDockItem(sourceType, sourceKey, targetIndex) {
        const items = _normalizeDockItems(svc.dockItems)
        let sourceIndex = -1
        for (let i = 0; i < items.length; i++) {
            const item = items[i]
            if (sourceType === "app" && item.type === "app" && item.appId === sourceKey) {
                sourceIndex = i
                break
            }
        }

        if (sourceIndex < 0)
            return false

        const destination = Math.max(0, Math.min(items.length - 1,
                                                   Math.round(targetIndex)))
        if (sourceIndex === destination)
            return false

        const moved = items.splice(sourceIndex, 1)[0]
        items.splice(destination, 0, moved)
        const changed = setDockItems(items)
        if (changed)
            scheduleSave()
        return changed
    }

    function removeAppItem(appId) {
        const items = _normalizeDockItems(svc.dockItems)
        const remaining = []
        let removed = false
        for (let i = 0; i < items.length; i++) {
            const item = items[i]
            if (item.type === "app" && item.appId === appId) {
                removed = true
                continue
            }
            remaining.push(item)
        }
        if (!removed)
            return false
        const changed = setDockItems(remaining)
        if (changed)
            scheduleSave()
        return changed
    }

    // ═══════════════════════════════════════════════════════════
    // Persistence — JSON through the platform daemon's state ops
    // ═══════════════════════════════════════════════════════════
    function _doSave() {
        const obj = {
            version: 8,
            baseHeight:    svc.baseHeight,
            theme:         svc.theme,
            position:      svc.position,
            // Product-level layout (v6)
            dockStyle:     svc.dockStyle,
            contentStyle:  svc.contentStyle,
            barHeight:     svc.barHeight,
            iconOverrides: svc.iconOverrides,
            dockItems:     svc.dockItems,
            // Kept for one compatibility release. New code reads dockItems.
            pinnedAppIds:  svc.pinnedAppIds,
            proportions:   svc.proportions,
            // Icon appearance style
            iconMode:        svc.iconMode,
            iconOpacity:     svc.iconOpacity,
            iconTintColor:    svc.iconTintColor,
            // Show mode (v3)
            visibilityMode: svc.visibilityMode,
            // Grouping mode (macOS style vs separate)
            windowGrouping: svc.windowGrouping,
            // Information cards (v6)
            infoCardMode: svc.infoCardMode,
            infoCardAutoRotate: svc.infoCardAutoRotate,
            desktopLyricsEnabled: svc.desktopLyricsEnabled,
            infoCardOrder: svc.infoCardOrder,
        }
        const json = JSON.stringify(obj, null, 2)
        console.log("[DockConfig] save requested path=" + svc.configPath
                    + " items=" + JSON.stringify(obj.dockItems))
        JsonConfigStore.writePath(svc.configPath, json, function(ok) {
            if (ok)
                console.log("[DockConfig] save complete path=" + svc.configPath)
        })
    }

    function loadConfig() {
        console.log("[DockConfig] load requested path=" + svc.configPath)
        JsonConfigStore.readPath(svc.configPath, function(data, exists) {
            if (exists && data) {
                try {
                    const obj = JSON.parse(data)
                    _apply(obj)
                    console.log("[DockConfig] load complete pinned="
                                + JSON.stringify(svc.pinnedAppIds))
                } catch (e) {
                    console.warn("[DockConfig] parse error, using defaults: " + e)
                }
            } else if (!exists) {
                console.log("[DockConfig] no saved config yet")
            }
            svc.ready = true
        })
    }

    function _apply(obj) {
        if (obj.baseHeight   !== undefined) svc.baseHeight   = obj.baseHeight
        if (obj.position !== undefined) {
            if (isValidPosition(obj.position)) {
                svc.position = obj.position
            } else {
                console.warn("[DockConfig] invalid position ignored")
                scheduleSave()
            }
        }
        // v6 productises both experimental PR schemas. A stretched dock or a
        // zero-margin edge dock becomes the taskbar preset; all other legacy
        // configurations keep the historical floating presentation.
        if (obj.dockStyle !== undefined) {
            if (isValidDockStyle(obj.dockStyle)) {
                svc.dockStyle = obj.dockStyle
            } else {
                console.warn("[DockConfig] invalid dockStyle ignored")
                scheduleSave()
            }
        } else if (obj.widthMode === "stretch" || Number(obj.edgeMargin) === 0) {
            svc.dockStyle = "taskbar"
        }
        if (obj.contentStyle !== undefined) {
            if (isValidContentStyle(obj.contentStyle)) {
                svc.contentStyle = obj.contentStyle
            } else {
                console.warn("[DockConfig] invalid contentStyle ignored")
                scheduleSave()
            }
        }

        // Accept both proposed PR card schemas, then persist only the ordered
        // component model. Missing keys retain the historical four cards.
        if (obj.infoCardMode !== undefined) {
            if (isValidInfoCardMode(obj.infoCardMode)) {
                svc.infoCardMode = obj.infoCardMode
            } else {
                console.warn("[DockConfig] invalid infoCardMode ignored")
                scheduleSave()
            }
        }
        if (obj.infoCardAutoRotate !== undefined)
            svc.infoCardAutoRotate = Boolean(obj.infoCardAutoRotate)
        if (obj.desktopLyricsEnabled !== undefined)
            svc.desktopLyricsEnabled = Boolean(obj.desktopLyricsEnabled)
        if (Array.isArray(obj.infoCardOrder)) {
            svc.infoCardOrder = normalizedInfoCardOrder(obj.infoCardOrder)
        } else if (obj.showWidgets === false) {
            svc.infoCardOrder = []
        } else if (obj.widgetMode === "fixed" && obj.fixedWidget !== undefined) {
            svc.infoCardOrder = normalizedInfoCardOrder([obj.fixedWidget])
        } else if (obj.enabledWidgets && typeof obj.enabledWidgets === "object") {
            svc.infoCardOrder = normalizedInfoCardOrder(knownInfoCardIds.filter(id => {
                const legacyId = id === "metrics" ? "temperature" : id
                return Boolean(obj.enabledWidgets[legacyId])
            }))
        } else if (obj.infoCardMusic !== undefined || obj.infoCardWeather !== undefined
                || obj.infoCardClock !== undefined || obj.infoCardMetrics !== undefined) {
            svc.infoCardOrder = normalizedInfoCardOrder([
                obj.infoCardMusic === false ? "" : "music",
                obj.infoCardWeather === false ? "" : "weather",
                obj.infoCardClock === false ? "" : "clock",
                obj.infoCardMetrics === false ? "" : "metrics"
            ])
        }

        if (obj.barHeight !== undefined) {
            const barHeight = Math.max(0, Math.min(100, Number(obj.barHeight)))
            if (Number.isFinite(barHeight))
                svc.barHeight = barHeight
        }
        if (obj.theme !== undefined) {
            if (isValidTheme(obj.theme)) {
                svc.theme = obj.theme
                AppearanceConfigService.updateThemeMode(obj.theme)
            } else {
                // Do not let a malformed legacy value leak into the IPC
                // contract. The next ordinary save rewrites it as "dark".
                console.warn("[DockConfig] invalid theme ignored")
                scheduleSave()
            }
        }
        if (obj.iconOverrides !== undefined) svc.iconOverrides = obj.iconOverrides

        if (obj.dockItems !== undefined) {
            const flattened = _normalizeDockItems(obj.dockItems)
            const requiresFolderMigration = JSON.stringify(obj.dockItems)
                !== JSON.stringify(flattened)
            setDockItems(flattened)
            // Rewrite legacy folder entries as ordinary pinned apps once the
            // configuration has loaded, so the removed feature cannot return
            // after a later shell restart.
            if (requiresFolderMigration)
                scheduleSave()
        } else if (obj.pinnedAppIds !== undefined) {
            // Version 1 migration: retain the order of the old flat list,
            // then write version 2 after loading. This migration is safe to
            // repeat because dockItems wins once it exists on disk.
            setDockItems(obj.pinnedAppIds.map(appId => ({
                type: "app", appId: appId,
            })))
            console.log("[DockConfig] migrated pinnedAppIds to dockItems")
            scheduleSave()
        }
        if (obj.proportions  !== undefined) svc.proportions   = obj.proportions
        if (obj.iconMode !== undefined) {
            // Migrate the experimental hard-duotone mode back to tonal tint.
            const loadedIconMode = obj.iconMode === "duotone" ? "tint" : obj.iconMode
            if (isValidIconMode(loadedIconMode)) {
                svc.iconMode = loadedIconMode
                if (obj.iconMode === "duotone")
                    scheduleSave()
            } else {
                console.warn("[DockConfig] invalid iconMode ignored")
                scheduleSave()
            }
        }
        if (obj.iconOpacity !== undefined) svc.iconOpacity = obj.iconOpacity

        const migratedTintColor = obj.iconTintColor ?? obj.iconDuotoneShadowColor
        if (migratedTintColor !== undefined && isValidRgbColor(migratedTintColor))
            svc.iconTintColor = String(migratedTintColor).toLowerCase()

        if (obj.iconMode === undefined || obj.iconDuotoneShadowColor !== undefined)
            scheduleSave()
        if (obj.windowGrouping !== undefined) {
            if (isValidWindowGrouping(obj.windowGrouping)) {
                svc.windowGrouping = obj.windowGrouping
            } else {
                console.warn("[DockConfig] invalid windowGrouping ignored")
                scheduleSave()
            }
        }
        applyVisibilityMode(obj)
    }

    // v3: read / migrate the single show-mode enum. Legacy experimental fields
    // (smartHideEnabled, autoHide) migrate onto the one enum so the old wrong
    // "both enabled" state cannot survive.
    function applyVisibilityMode(obj) {
        if (obj.visibilityMode !== undefined) {
            if (isValidVisibilityMode(obj.visibilityMode)) {
                svc.visibilityMode = obj.visibilityMode
            } else {
                console.warn("[DockConfig] invalid visibilityMode ignored -> always")
                scheduleSave()
            }
            return
        }
        const hadSmart = obj.smartHideEnabled === true
        const hadAuto = obj.autoHide === true
        if (hadSmart || hadAuto) {
            if (hadSmart && hadAuto)
                console.log("[DockConfig] migrated smartHideEnabled+autoHide -> smart")
            else
                console.log("[DockConfig] migrated legacy show-mode -> "
                            + (hadSmart ? "smart" : "persistent"))
            svc.visibilityMode = hadSmart ? "smart" : "persistent"
            scheduleSave()
        }
    }

    // ── Init: load on startup ──
    Component.onCompleted: loadConfig()
}
