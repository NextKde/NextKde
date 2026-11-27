pragma Singleton

import QtQuick
import QtCore
import Quickshell
import qs.desktop.modules.common
import "WidgetLayout.mjs" as WidgetLayout
import "WidgetInstanceConfig.mjs" as WidgetInstanceConfig

QtObject {
    id: service

    signal instanceConfigChanged(string instanceId)

    property int revision: 0
    property var projectedPositions: ({})
    property var _instanceConfigs: null
    readonly property var defaultSizes: ({
        clock: "small",
        weather: "medium",
        calendar: "medium",
        todo: "medium",
        system: "medium",
        activity: "medium",
        music: "medium",
        groups: "medium"
    })
    readonly property var sizeOrder: WidgetLayout.sizeOrder
    readonly property var defaultOrder: [
        "clock", "weather", "calendar", "todo", "system", "activity", "music",
        "groups"
    ]

    property Settings _settings: Settings {
        location: "file://" + Quickshell.stateDir + "/deskcenter-widgets.ini"
        category: "Widgets"
        property int schemaVersion: 2
        property string clockStyle: "analog"
        property string sizesJson: "{}"
        property string orderJson: "[]"
        property string positionsJson: "{}"
        // Placed package instances per output, plus the id-suffix counter.
        // Both live here because the desktop surface is recreated on every
        // login and must re-expand the placements from disk (R4).
        property string instancesJson: "{}"
        property string instanceConfigsJson: "{}"
        property int instanceSeq: 1
        property bool desktopLyricsEnabled: true
        property real desktopLyricsX: 0.5
        property real desktopLyricsY: 1.0
    }

    Component.onCompleted: {
        desktopLyricsEnabled = _settings.desktopLyricsEnabled
        desktopLyricsX = Math.max(0, Math.min(1, _settings.desktopLyricsX))
        desktopLyricsY = Math.max(0, Math.min(1, _settings.desktopLyricsY))
    }

    readonly property string clockStyle: _settings.clockStyle === "digital" ? "digital" : "analog"

    function setClockStyle(style) {
        if (style !== "analog" && style !== "digital") return false
        if (clockStyle === style) return false
        _settings.clockStyle = style
        _settings.sync()
        return true
    }

    function parsedSizes() {
        try {
            const value = JSON.parse(_settings.sizesJson)
            return value && typeof value === "object" && !Array.isArray(value)
                ? value : {}
        } catch (_) { return {} }
    }

    function orderedIds() {
        let stored = []
        try { stored = JSON.parse(_settings.orderJson) } catch (_) { stored = [] }
        const result = []
        if (Array.isArray(stored)) {
            for (const rawId of stored) {
                const id = String(rawId)
                if (defaultOrder.indexOf(id) >= 0 && result.indexOf(id) < 0)
                    result.push(id)
            }
        }
        for (const id of defaultOrder) {
            if (result.indexOf(id) < 0)
                result.push(id)
        }
        return result
    }

    function moveWidget(widgetId, rawIndex) {
        const id = String(widgetId)
        const next = orderedIds().filter(candidate => candidate !== id)
        if (next.length === defaultOrder.length)
            return false
        const index = Math.max(0, Math.min(next.length, Number(rawIndex)))
        next.splice(index, 0, id)
        _settings.orderJson = JSON.stringify(next)
        _settings.sync()
        revision++
        return true
    }

    function positionsForOutput(output) {
        try {
            const positions = JSON.parse(_settings.positionsJson)[String(output)]
            return positions && typeof positions === "object" && !Array.isArray(positions)
                ? positions : {}
        } catch (_) { return {} }
    }

    function displayPositionsForOutput(output, geometry) {
        const projection = projectedPositions[String(output)]
        return projection?.geometry === geometry ? projection.positions : positionsForOutput(output)
    }

    function savePosition(output, placements, widgetId, column, row, geometry) {
        if (typeof widgetId !== "string" || widgetId.length === 0 || !Number.isInteger(column)
                || !Number.isInteger(row) || column < 0 || row < 0) return false
        let all = ({})
        try {
            const stored = JSON.parse(_settings.positionsJson)
            if (stored && typeof stored === "object" && !Array.isArray(stored)) all = stored
        } catch (_) {}
        all[String(output)] = WidgetLayout.savedPositionsAfterMove(
            positionsForOutput(output), placements, widgetId, column, row)
        // Freeze only this geometry's projection. Do not persist the temporary
        // fallback positions of other cards after a screen/layout change.
        const displayed = Object.assign({}, all[String(output)])
        for (const placement of placements)
            displayed[placement.id] = { column: placement.column, row: placement.row }
        displayed[widgetId] = { column, row }
        const projections = Object.assign({}, projectedPositions)
        projections[String(output)] = { geometry, positions: displayed }
        projectedPositions = projections
        _settings.positionsJson = JSON.stringify(all)
        _settings.sync()
        revision++
        return true
    }

    // Placed package instances (instance id + owning package id), keyed by
    // output. Disk is the only cross-restart source: DeskCenterWindow
    // re-expands these into widgetInstances on startup, so the persisted
    // position/size keys keep pointing at the same cards. Records whose
    // package is missing or not executable are kept here untouched instead of
    // being dropped, so a later package deployment can still revive them
    // (see WidgetGalleryPreviewPlan R7).
    function instancesForOutput(output) {
        const list = parsedInstances()[String(output)]
        const result = []
        if (!Array.isArray(list)) return result
        for (const item of list) {
            if (!validInstanceRecord(item)) continue
            if (result.some(record => record.id === item.id)) continue
            result.push({ id: item.id, packageId: item.packageId })
        }
        return result
    }

    function saveInstancesForOutput(output, instances) {
        const all = parsedInstances()
        const records = []
        for (const item of instances ?? []) {
            if (!validInstanceRecord(item)) continue
            if (records.some(record => record.id === item.id)) continue
            records.push({ id: item.id, packageId: item.packageId })
        }
        all[String(output)] = records
        _settings.instancesJson = JSON.stringify(all)
        _settings.sync()
        revision++
    }

    // Per-instance state files (e.g. the clock's format24h) are keyed by
    // instance id, so the counter must stay unique across outputs: two screens
    // must not both hand out "…#1". The stored counter is the fast path; the
    // scan keeps it ahead of ids written by an older build or a hand-edited
    // file.
    function allocateInstanceSeq() {
        let next = Math.max(1, _settings.instanceSeq)
        const all = parsedInstances()
        for (const key of Object.keys(all)) {
            const list = Array.isArray(all[key]) ? all[key] : []
            for (const record of list) {
                const match = typeof record?.id === "string" ? /#(\d+)$/.exec(record.id) : null
                if (match) next = Math.max(next, Number(match[1]) + 1)
            }
        }
        _settings.instanceSeq = next + 1
        _settings.sync()
        return next
    }

    // Removing a card also retires its saved position, span, and per-instance
    // settings, so a later instance cannot inherit stale state or leave orphan
    // config entries behind.
    function removeInstance(output, instanceId) {
        const key = String(output)
        let changed = false
        let configRemoved = false
        const all = parsedInstances()
        const list = Array.isArray(all[key]) ? all[key] : []
        const next = list.filter(record => record?.id !== instanceId)
        if (next.length !== list.length) {
            all[key] = next
            _settings.instancesJson = JSON.stringify(all)
            changed = true
        }
        const allPositions = parsedObject(_settings.positionsJson)
        const positions = allPositions[key]
        if (positions && typeof positions === "object" && !Array.isArray(positions)
                && Object.prototype.hasOwnProperty.call(positions, instanceId)) {
            delete positions[instanceId]
            _settings.positionsJson = JSON.stringify(allPositions)
            changed = true
        }
        const sizes = parsedObject(_settings.sizesJson)
        if (Object.prototype.hasOwnProperty.call(sizes, instanceId)) {
            delete sizes[instanceId]
            _settings.sizesJson = JSON.stringify(sizes)
            changed = true
        }
        const removedCfg = WidgetInstanceConfig.removeInstanceConfig(_ensureInstanceConfigs(), instanceId)
        if (removedCfg.changed) {
            _instanceConfigs = removedCfg.map
            _settings.instanceConfigsJson = JSON.stringify(removedCfg.map)
            changed = true
            configRemoved = true
        }
        if (changed) {
            _settings.sync()
            revision++
        }
        if (configRemoved)
            instanceConfigChanged(String(instanceId))
        return changed
    }

    function _ensureInstanceConfigs() {
        if (_instanceConfigs === null)
            _instanceConfigs = WidgetInstanceConfig.parseConfigMap(_settings.instanceConfigsJson)
        return _instanceConfigs
    }

    function instanceConfigFor(instanceId) {
        return WidgetInstanceConfig.getInstanceConfig(_ensureInstanceConfigs(), String(instanceId ?? ""))
    }

    function saveInstanceConfig(instanceId, next) {
        const id = String(instanceId ?? "")
        const res = WidgetInstanceConfig.setInstanceConfig(_ensureInstanceConfigs(), id, next)
        if (!res.ok) return false
        _instanceConfigs = res.map
        _settings.instanceConfigsJson = JSON.stringify(res.map)
        _settings.sync()
        revision++
        instanceConfigChanged(id)
        return true
    }

    function parsedInstances() {
        const all = parsedObject(_settings.instancesJson)
        return all && typeof all === "object" && !Array.isArray(all) ? all : ({})
    }

    function parsedObject(json) {
        try {
            const value = JSON.parse(json)
            return value && typeof value === "object" && !Array.isArray(value) ? value : ({})
        } catch (_) { return ({}) }
    }

    function validInstanceRecord(item) {
        return !!item && typeof item.id === "string" && item.id.length > 0
            && typeof item.packageId === "string" && item.packageId.length > 0
    }

    function sizeFor(widgetId) {
        const sizes = parsedSizes()
        const value = String(sizes[widgetId] ?? defaultSizes[widgetId] ?? "medium")
        // A hand-edited span must still respect each widget's size ceiling:
        // the grouped view accepts 2x3/3x2/3x3 and never goes below 2x2, and
        // weather's three-column layouts are valid explicit spans.
        return WidgetLayout.isValidSize(widgetId, value)
            ? WidgetLayout.normalizedSize(value) : "medium"
    }

    function setSize(widgetId, size) {
        if (!WidgetLayout.isValidSize(widgetId, size))
            return false
        const sizes = parsedSizes()
        if (sizes[widgetId] === size)
            return false
        sizes[widgetId] = size
        _settings.sizesJson = JSON.stringify(sizes)
        _settings.sync()
        revision++
        return true
    }

    function setSpan(widgetId, columns, rows) {
        return setSize(widgetId, String(columns) + "x" + String(rows))
    }

    function cycleSize(widgetId) {
        const span = spanFor(widgetId)
        const current = String(Math.min(2, span[0])) + "x" + String(span[1])
        const next = sizeOrder[(sizeOrder.indexOf(current) + 1) % sizeOrder.length]
        setSize(widgetId, next)
        return next
    }

    function spanFor(widgetId) {
        return WidgetLayout.spanFor(widgetId, sizeFor(widgetId))
    }

    // ═══════════════════════════════════════════════════════════
    // Music widget desktop lyrics
    // ═══════════════════════════════════════════════════════════
    // The lyrics HUD is an accessory of the music widget: it exists only
    // while that widget is on the desktop, and the widget card owns the
    // switch. Normalized X/Y keep the HUD reachable after a resize.
    property bool desktopLyricsEnabled: true
    property real desktopLyricsX: 0.5
    property real desktopLyricsY: 1.0
    property bool desktopLyricsEditing: false
    readonly property bool desktopLyricsActive: desktopLyricsEnabled
        && !AppearanceConfigService.isDeskCenterWidgetHidden("music")

    function updateDesktopLyricsPosition(x, y) {
        if (!Number.isFinite(x) || !Number.isFinite(y)) return
        desktopLyricsX = Math.max(0, Math.min(1, x))
        desktopLyricsY = Math.max(0, Math.min(1, y))
        _settings.desktopLyricsX = desktopLyricsX
        _settings.desktopLyricsY = desktopLyricsY
        _settings.sync()
        revision++
    }

    function editDesktopLyrics() {
        if (!desktopLyricsEnabled)
            updateDesktopLyricsEnabled(true)
        desktopLyricsEditing = true
    }

    function updateDesktopLyricsEnabled(enabled) {
        desktopLyricsEnabled = Boolean(enabled)
        if (!desktopLyricsEnabled) desktopLyricsEditing = false
        _settings.desktopLyricsEnabled = desktopLyricsEnabled
        _settings.sync()
        revision++
    }
}
