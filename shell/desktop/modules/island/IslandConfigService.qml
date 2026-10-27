pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../../shared/qml/i18n"
import qs.desktop.modules.platform

// IslandConfigService — persistent configuration for the top-edge island.
//
// Ported from the NookX Dynamic Island (com.monsterwl.NookX, 2026.10.6) which
// was analysed statically with Ghidra 12.1.4. The original keeps a widget
// catalogue, a persisted enabled-widget order, a shape/background mode, and an
// expansion policy; this service keeps the same model so the two behave
// alike, while every value stays inside this project's state directory.
//
// The original persists through a UserDefaults-style key/value bag
// (`defaultWidgetOrder`, `enabledWidgetOrder`, `widgetEnabledStatusString`,
// `com.nookx.island-widget-position`). Here the same three concepts become
// explicit JSON fields, because the platform contract only offers
// state.read/state.write with a single bounded payload.
//
// Everything is a plain QML property so the Settings process can drive it
// through the island-settings IPC target without importing Shell modules.
QtObject {
    id: service

    // --- Enablement -----------------------------------------------------
    // The master switch. Everything below is inert while this is false; the
    // island window stays undisplayed rather than being torn down, so
    // toggling back on restores the same session.
    //
    // Defaults to on: the original shows its island as part of the desktop
    // rather than behind a setting, and a fresh install must look like the
    // app it was ported from.
    property bool enabled: true

    // --- Geometry / shape ------------------------------------------------
    // The original stores an island shape mode, a background mode and a
    // display policy (see IslandShapeMode / IslandBackgroundMode /
    // DynamicIslandDisplayPolicy in the analysed binary).
    // Accent palette. The colours are taken from the shell's own traditional-
    // colour table (Kos/Ui/colorize/ChineseColors.mjs) so the island's themes
    // are the same vocabulary the rest of NextKde uses, not a private palette.
    //   graphite  neutral light grey -- the reference panel carries no accent
    //   celadon   石绿 #57c3c2
    //   azure     群青 #1772b4
    //   cinnabar  银朱 #f43e06
    // Notes live as one .md file per note in this folder; the index below is
    // only the list of what exists, so the island can render titles without
    // reading every file. Empty means "use the default" -- resolved at load
    // because the expansion needs $HOME.
    property string notesFolder: ""
    property var    notesIndex: []
    // How the expanded panel arranges itself: "columns" is the two-column
    // shelf (the NookX arrangement), "cards" is Notchy's -- a rail picks the
    // page and one card is shown at a time.
    // How much the glass holds back. 0 is a bare blur, 1 is the near-opaque
    // slab the reference shows over a bright wallpaper. This is the one
    // material knob that can be tuned without a screenshot: the compositor
    // path, the client tint and the specular all follow it.
    property real glassStrength: 0.65
    property string layoutMode: "columns"
    property string theme: "graphite"
    // Resolved once here so the surface (window) and the interior (content)
    // cannot drift apart over which preset is active.
    readonly property color accentColor: theme === "celadon" ? "#57c3c2"
        : theme === "azure" ? "#1772b4"
        : theme === "cinnabar" ? "#f43e06" : "#c9cdd6"
    property string shapeMode: "squircle"     // capsule | rounded | squircle
    property string backgroundMode: "glass"    // glass | solid | none
    property string expandMode: "hover"        // hover | click | always
    property real   width: 320
    property real   height: 44
    property real   topMargin: 6
    // Multiplier on the computed expanded size. NookX derives its panel from
    // the screen and then lets the user nudge it (its own defaults carry
    // DynamicIslandWidthOffset / HeightOffset); a single factor keeps the
    // reference proportions while making the size adjustable.
    property real   expandedScale: 1.0
    property int    expandDurationMs: 220
    property int    collapseDurationMs: 180

    // --- Widget catalogue -------------------------------------------------
    // Mirrors the original's IslandWidgetCatalog: a fixed set of known
    // widgets, each with an id, a display name and an enablement flag.
    // The catalogue is defined here rather than persisted, because the
    // original also derives it from code (its entries map onto native view
    // classes such as TodoView, WeatherWidgetStore, PomodoroView, ...).
    readonly property var catalogue: [
        { id: "todo",      name: I18n.tr("To-do and habits"),  defaultEnabled: true },
        { id: "weather",   name: I18n.tr("Weather"),            defaultEnabled: true },
        { id: "clock",     name: I18n.tr("Clock"),              defaultEnabled: true },
        { id: "pomodoro",  name: I18n.tr("Pomodoro"),           defaultEnabled: false },
        { id: "notes",     name: I18n.tr("Notes"),              defaultEnabled: false },
        { id: "battery",   name: I18n.tr("Battery"),            defaultEnabled: false },
        // NookX's catalogue carries a "systemPanel" widget; this is that
        // entry, fed by the shell's shared metrics snapshot.
        { id: "system",    name: I18n.tr("System"),             defaultEnabled: false },
        // The shell already has MPRIS and timed lyrics for the desktop
        // overlay; this puts the same thing in the island.
        { id: "lyrics",    name: I18n.tr("Lyrics"),             defaultEnabled: false },
        // Notchy's first home card is today's screen time. The shell already
        // accounts foreground time per application, so this reads the same
        // snapshot the DeskCenter reads.
        { id: "usage",     name: I18n.tr("Screen time"),        defaultEnabled: false },
        // Notchy's "displays" card.
        { id: "displays",  name: I18n.tr("Displays"),            defaultEnabled: false },
        // Notchy's "quickActions" card.
        { id: "actions",   name: I18n.tr("Quick actions"),        defaultEnabled: false },
        { id: "calendar",  name: I18n.tr("Calendar"),           defaultEnabled: false },
    ]

    // The user's enabled order. Persisted as `enabledWidgetOrder`.
    property var enabledWidgetOrder: []
    // Per-widget free-form state, persisted alongside the order.
    property var widgetState: ({})

    // --- Quick launch (the "add app" surface) ----------------------------
    // The original keeps a QuickLaunch list of applications with a custom
    // order, a sort option, a filter option and a page cursor. Here the
    // pinned set is a list of desktop ids; ordering and paging are derived.
    property var pinnedApps: []
    property int  quickLaunchPageSize: 12
    property bool quickLaunchShowLabels: true
    property bool quickLaunchEnabled: true

    // --- Drag and drop (the "snap" surface) ------------------------------
    // The original accepts files dropped onto the island and stores them
    // ("save into notes"). The Linux equivalent is a configurable drop
    // action; a file manager hands the drop to the platform contract.
    property bool dropFilesEnabled: true
    // What a dropped *file* becomes. "shortcut" pins its path on the deck
    // (the island never holds the file itself); the others are the older
    // open/copy/reveal behaviours.
    property string dropAction: "shortcut"   // shortcut | open | copyPath | reveal

    // --- Pomodoro defaults -------------------------------------------------
    // The original persists pomodoro.shortBreakMinutes /
    // pomodoro.longBreakMinutes / pomodoro.longBreakTriggerCount (plus the
    // work length) in UserDefaults; IslandPomodoroService reads them here.
    property int pomodoroWorkMinutes: 25
    property int pomodoroShortBreakMinutes: 5
    property int pomodoroLongBreakMinutes: 15
    property int pomodoroLongBreakTriggerCount: 4

    // --- Persistence ------------------------------------------------------
    readonly property string configDir: Quickshell.stateDir + "/island"
    readonly property string configFile: "config.json"
    // Bumped when a stored value stops being meaningful. Version 1 files
    // were written while the island still defaulted to off, so their
    // `enabled` flag records the old default rather than a user decision.
    readonly property int configVersion: 4
    // Writable: the loader sets it once the stored configuration has been
    // applied. A read-only property here would raise a TypeError during the
    // load and abort the whole shell.
    property bool ready: false
    property string lastError: ""

    function _defaultEnabledOrder() {
        const ids = []
        for (let i = 0; i < catalogue.length; i++) {
            if (catalogue[i].defaultEnabled)
                ids.push(catalogue[i].id)
        }
        return ids
    }

    // Accepts only ids the catalogue knows, and never duplicates them.
    function _sanitizeOrder(raw) {
        const known = {}
        for (let i = 0; i < catalogue.length; i++)
            known[catalogue[i].id] = true
        const seen = {}
        const out = []
        if (!raw || !Array.isArray(raw))
            return _defaultEnabledOrder()
        for (let i = 0; i < raw.length; i++) {
            const id = String(raw[i])
            if (known[id] && !seen[id]) {
                seen[id] = true
                out.push(id)
            }
        }
        return out
    }

    function _sanitizeApps(raw) {
        if (!raw || !Array.isArray(raw))
            return []
        const seen = {}
        const out = []
        for (let i = 0; i < raw.length; i++) {
            const id = String(raw[i] || "").trim()
            if (id && !seen[id]) {
                seen[id] = true
                out.push(id)
            }
        }
        return out
    }

    function _isValidLayoutMode(value) {
        return value === "columns" || value === "cards"
    }
    function _isValidTheme(value) {
        return value === "graphite" || value === "celadon"
            || value === "azure" || value === "cinnabar"
    }
    function _isValidShape(mode) {
        return mode === "capsule" || mode === "rounded" || mode === "squircle"
            || mode === "notch"
    }
    function _isValidBackground(mode) {
        return mode === "glass" || mode === "solid" || mode === "none"
    }
    function _isValidExpand(mode) {
        return mode === "hover" || mode === "click" || mode === "always"
    }
    function _isValidDropAction(action) {
        return action === "shortcut" || action === "open"
            || action === "copyPath" || action === "reveal"
    }

    function _applySnapshot(data) {
        const raw = data ? JSON.parse(data) : ({})

        // Only an explicit stored value overrides the default. Reading a
        // missing field as "off" would silently disable the island on every
        // fresh install, because the default is "on".
        //
        // Files written before version 2 stored the old default rather than
        // a user decision, so their flag is ignored and the island comes up
        // enabled, exactly like the app it was ported from.
        const home = Quickshell.env("HOME") || ""
        notesFolder = String(raw.notesFolder || "")
        if (notesFolder.length === 0 && home.length > 0)
            notesFolder = home + "/Documents/NextKde/notes"
        notesIndex = Array.isArray(raw.notesIndex) ? raw.notesIndex : []

        const storedVersion = Number(raw.configVersion) || 0
        // Keyed to version 2, not to the current version: bumping the version
        // for an unrelated migration must not resurrect an island a user had
        // deliberately switched off.
        if (storedVersion >= 2) {
            if (raw.enabled !== undefined)
                enabled = raw.enabled === true
        } else if (raw.enabled === true) {
            enabled = true
        }

        if (raw.glassStrength !== undefined)
            glassStrength = Math.max(0, Math.min(1, Number(raw.glassStrength) || 0))
        if (_isValidLayoutMode(raw.layoutMode)) layoutMode = raw.layoutMode
        if (_isValidTheme(raw.theme)) theme = raw.theme
        if (_isValidShape(raw.shapeMode)) shapeMode = raw.shapeMode
        // Version 3 measures the reference: its corner is a continuous
        // (superellipse) corner, exponent 2.8, not the circular arc that
        // "capsule" drew. Files written before that keep "capsule" only
        // because it was the old default, so remap it once.
        if (storedVersion < 3 && shapeMode === "capsule")
            shapeMode = "squircle"
        // Version 4 turns a dropped file into a shortcut instead of opening
        // it. Files written before that only carry "open" because it was the
        // old default, so remap it once -- the same reasoning as the shape.
        if (storedVersion < 4 && dropAction === "open")
            dropAction = "shortcut"
        if (_isValidBackground(raw.backgroundMode)) backgroundMode = raw.backgroundMode
        if (_isValidExpand(raw.expandMode)) expandMode = raw.expandMode

        width = Math.max(180, Math.min(720, Number(raw.width) || 320))
        height = Math.max(28, Math.min(120, Number(raw.height) || 44))
        topMargin = Math.max(0, Math.min(80, Number(raw.topMargin) || 0))
        expandedScale = Math.max(0.6, Math.min(1.4,
            raw.expandedScale === undefined ? 1.0 : Number(raw.expandedScale) || 1.0))
        expandDurationMs = Math.max(0, Math.min(2000, Number(raw.expandDurationMs) || 220))
        collapseDurationMs = Math.max(0, Math.min(2000, Number(raw.collapseDurationMs) || 180))

        enabledWidgetOrder = _sanitizeOrder(raw.enabledWidgetOrder)
        widgetState = (raw.widgetState && typeof raw.widgetState === "object")
            ? raw.widgetState : ({})

        pinnedApps = _sanitizeApps(raw.pinnedApps)
        quickLaunchPageSize = Math.max(4, Math.min(32, Number(raw.quickLaunchPageSize) || 12))
        quickLaunchShowLabels = raw.quickLaunchShowLabels !== false
        quickLaunchEnabled = raw.quickLaunchEnabled !== false

        dropFilesEnabled = raw.dropFilesEnabled !== false
        if (_isValidDropAction(raw.dropAction)) dropAction = raw.dropAction

        pomodoroWorkMinutes = Math.max(1, Math.min(120, Number(raw.pomodoroWorkMinutes) || 25))
        pomodoroShortBreakMinutes = Math.max(1, Math.min(60, Number(raw.pomodoroShortBreakMinutes) || 5))
        pomodoroLongBreakMinutes = Math.max(1, Math.min(120, Number(raw.pomodoroLongBreakMinutes) || 15))
        pomodoroLongBreakTriggerCount = Math.max(2, Math.min(12, Number(raw.pomodoroLongBreakTriggerCount) || 4))
    }

    function _serialize() {
        return JSON.stringify({
            configVersion: configVersion,
            enabled: enabled,
            theme: theme,
            glassStrength: glassStrength,
            layoutMode: layoutMode,
            notesFolder: notesFolder,
            notesIndex: notesIndex,
            shapeMode: shapeMode,
            backgroundMode: backgroundMode,
            expandMode: expandMode,
            width: width,
            height: height,
            topMargin: topMargin,
            expandedScale: expandedScale,
            expandDurationMs: expandDurationMs,
            collapseDurationMs: collapseDurationMs,
            enabledWidgetOrder: enabledWidgetOrder,
            widgetState: widgetState,
            pinnedApps: pinnedApps,
            quickLaunchPageSize: quickLaunchPageSize,
            quickLaunchShowLabels: quickLaunchShowLabels,
            quickLaunchEnabled: quickLaunchEnabled,
            dropFilesEnabled: dropFilesEnabled,
            dropAction: dropAction,
            pomodoroWorkMinutes: pomodoroWorkMinutes,
            pomodoroShortBreakMinutes: pomodoroShortBreakMinutes,
            pomodoroLongBreakMinutes: pomodoroLongBreakMinutes,
            pomodoroLongBreakTriggerCount: pomodoroLongBreakTriggerCount,
        })
    }

    function load() {
        JsonConfigStore.read(configDir, configFile, function(data, exists) {
            try {
                _applySnapshot(data)
            } catch (error) {
                console.warn("[IslandConfigService] parse failed, using defaults: " + error)
                _applySnapshot("")
            }
            service.ready = true
        })
    }

    function save() {
        JsonConfigStore.write(configDir, configFile, _serialize(), function(ok) {
            if (!ok)
                service.lastError = "write failed"
            else
                service.lastError = ""
        })
    }

    // --- Mutators (each one persists) -------------------------------------
    function setEnabled(value) { enabled = !!value; save() }
    function setNotesFolder(path) {
        notesFolder = String(path || ""); save()
    }
    function setNotesIndex(list) {
        notesIndex = Array.isArray(list) ? list : []; save()
    }
    function setGlassStrength(value) {
        glassStrength = Math.max(0, Math.min(1, Number(value) || 0)); save()
    }
    function setLayoutMode(value) {
        if (!_isValidLayoutMode(value)) return
        layoutMode = value; save()
    }
    function setTheme(value) {
        if (!_isValidTheme(value)) return
        theme = value; save()
    }
    function setShapeMode(mode) {
        if (!_isValidShape(mode)) return
        shapeMode = mode; save()
    }
    function setBackgroundMode(mode) {
        if (!_isValidBackground(mode)) return
        backgroundMode = mode; save()
    }
    function setExpandMode(mode) {
        if (!_isValidExpand(mode)) return
        expandMode = mode; save()
    }
    function setGeometry(w, h) {
        width = Math.max(180, Math.min(720, Number(w) || width))
        height = Math.max(28, Math.min(120, Number(h) || height))
        save()
    }
    function setTopMargin(v) {
        topMargin = Math.max(0, Math.min(80, Number(v) || 0)); save()
    }
    function setExpandedScale(v) {
        expandedScale = Math.max(0.6, Math.min(1.4, Number(v) || 1.0)); save()
    }
    function setExpandDuration(v) {
        expandDurationMs = Math.max(0, Math.min(2000, Number(v) || 0)); save()
    }
    function setCollapseDuration(v) {
        collapseDurationMs = Math.max(0, Math.min(2000, Number(v) || 0)); save()
    }
    function setEnabledWidgetOrder(order) {
        enabledWidgetOrder = _sanitizeOrder(order); save()
    }
    function toggleWidget(id, on) {
        const list = enabledWidgetOrder.slice()
        const key = String(id)
        const index = list.indexOf(key)
        if (on && index < 0) list.push(key)
        else if (!on && index >= 0) list.splice(index, 1)
        enabledWidgetOrder = list
        save()
    }
    function setWidgetState(id, state) {
        const next = Object.assign({}, widgetState)
        next[String(id)] = state
        widgetState = next
        save()
    }
    function setPinnedApps(list) {
        pinnedApps = _sanitizeApps(list); save()
    }
    function pinApp(id) {
        const list = pinnedApps.slice()
        const key = String(id || "").trim()
        if (key && list.indexOf(key) < 0) {
            list.push(key)
            pinnedApps = list
            save()
        }
    }
    // A dropped file becomes a shortcut, so what is stored is the path --
    // prefixed so it can never collide with a desktop-entry id.
    function pinPath(path) {
        const trimmed = String(path || "").trim()
        if (trimmed.length === 0)
            return
        pinApp("file:" + trimmed)
    }
    // A shelved file that moved keeps its place in the deck; only the path
    // it points at changes.
    function repinPath(oldPath, newPath) {
        const oldId = "file:" + oldPath
        const newId = "file:" + newPath
        if (oldId === newId)
            return
        const list = pinnedApps.slice()
        const index = list.indexOf(oldId)
        if (index < 0)
            return
        list[index] = newId
        pinnedApps = list
        save()
    }
    function unpinApp(id) {
        const list = pinnedApps.filter(function(x) { return x !== String(id) })
        if (list.length !== pinnedApps.length) {
            pinnedApps = list
            save()
        }
    }
    function setQuickLaunchPageSize(v) {
        quickLaunchPageSize = Math.max(4, Math.min(32, Number(v) || 12)); save()
    }
    function setQuickLaunchShowLabels(on) {
        quickLaunchShowLabels = !!on; save()
    }
    function setQuickLaunchEnabled(on) {
        quickLaunchEnabled = !!on; save()
    }
    function setDropFilesEnabled(on) {
        dropFilesEnabled = !!on; save()
    }
    function setDropAction(action) {
        if (!_isValidDropAction(action)) return
        dropAction = action; save()
    }
    function setPomodoroConfig(work, shortBreak, longBreak, trigger) {
        pomodoroWorkMinutes = Math.max(1, Math.min(120, Number(work) || pomodoroWorkMinutes))
        pomodoroShortBreakMinutes = Math.max(1, Math.min(60, Number(shortBreak) || pomodoroShortBreakMinutes))
        pomodoroLongBreakMinutes = Math.max(1, Math.min(120, Number(longBreak) || pomodoroLongBreakMinutes))
        pomodoroLongBreakTriggerCount = Math.max(2, Math.min(12, Number(trigger) || pomodoroLongBreakTriggerCount))
        save()
    }

    // --- Snapshot for the Settings process --------------------------------
    function snapshot() {
        return {
            enabled: enabled,
            ready: ready,
            theme: theme,
            notesFolder: notesFolder,
            notesIndex: notesIndex,
            shapeMode: shapeMode,
            backgroundMode: backgroundMode,
            expandMode: expandMode,
            width: width,
            height: height,
            topMargin: topMargin,
            expandedScale: expandedScale,
            expandDurationMs: expandDurationMs,
            collapseDurationMs: collapseDurationMs,
            catalogue: catalogue,
            enabledWidgetOrder: enabledWidgetOrder,
            pinnedApps: pinnedApps,
            // Resolved names/icons for the pinned ids, so the Settings page
            // can show and remove them without enumerating desktop entries.
            pinnedAppsDetail: (IslandQuickLaunchModel.entries || []).map(function(e) {
                return { id: e.id, name: e.name || e.id, icon: e.icon || "" }
            }),
            quickLaunchPageSize: quickLaunchPageSize,
            quickLaunchShowLabels: quickLaunchShowLabels,
            quickLaunchEnabled: quickLaunchEnabled,
            dropFilesEnabled: dropFilesEnabled,
            dropAction: dropAction,
            pomodoroWorkMinutes: pomodoroWorkMinutes,
            pomodoroShortBreakMinutes: pomodoroShortBreakMinutes,
            pomodoroLongBreakMinutes: pomodoroLongBreakMinutes,
            pomodoroLongBreakTriggerCount: pomodoroLongBreakTriggerCount,
            lastError: lastError,
            // The Settings process cannot import Shell modules, so its
            // pinned-app picker reads the live desktop entries from here
            // instead of enumerating them itself.
            availableApps: (IslandQuickLaunchModel.availableEntries || []).map(function(e) {
                return { id: e.id, name: e.name || e.id, icon: e.icon || "" }
            }),
        }
    }

    Component.onCompleted: load()
}
