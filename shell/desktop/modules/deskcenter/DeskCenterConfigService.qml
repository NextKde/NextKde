pragma Singleton

import QtQuick
import QtCore
import Quickshell
import qs.desktop.modules.common
import "WidgetLayout.mjs" as WidgetLayout

QtObject {
    id: service

    property int revision: 0
    property var projectedPositions: ({})
    readonly property var defaultSizes: ({
        clock: "small",
        weather: "medium",
        calendar: "medium",
        todo: "medium",
        system: "medium",
        activity: "medium",
        music: "medium"
    })
    readonly property var sizeOrder: WidgetLayout.sizeOrder
    readonly property var defaultOrder: [
        "clock", "weather", "calendar", "todo", "system", "activity", "music"
    ]

    property Settings _settings: Settings {
        location: "file://" + Quickshell.stateDir + "/deskcenter-widgets.ini"
        category: "Widgets"
        property int schemaVersion: 2
        property string sizesJson: "{}"
        property string orderJson: "[]"
        property string positionsJson: "{}"
        property bool desktopLyricsEnabled: true
        property real desktopLyricsX: 0.5
        property real desktopLyricsY: 1.0
    }

    Component.onCompleted: {
        desktopLyricsEnabled = _settings.desktopLyricsEnabled
        desktopLyricsX = Math.max(0, Math.min(1, _settings.desktopLyricsX))
        desktopLyricsY = Math.max(0, Math.min(1, _settings.desktopLyricsY))
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
        if (defaultOrder.indexOf(widgetId) < 0 || !Number.isInteger(column)
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

    function sizeFor(widgetId) {
        const sizes = parsedSizes()
        const value = String(sizes[widgetId] ?? defaultSizes[widgetId] ?? "medium")
        return WidgetLayout.normalizedSize(value)
    }

    function setSize(widgetId, size) {
        if (sizeOrder.indexOf(size) < 0)
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
