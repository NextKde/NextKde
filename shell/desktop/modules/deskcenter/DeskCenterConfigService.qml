pragma Singleton

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import qs.desktop.modules.common
import "WidgetLayout.mjs" as WidgetLayout

QtObject {
    id: service

    property int revision: 0
    readonly property var defaultSizes: ({
        clock: "small",
        weather: "medium",
        calendar: "medium",
        todo: "medium",
        system: "medium",
        activity: "medium",
        music: "medium",
        notifications: "medium"
    })
    readonly property var sizeOrder: WidgetLayout.sizeOrder
    readonly property var defaultOrder: [
        "clock", "weather", "calendar", "todo", "system", "activity", "music", "notifications"
    ]

    property Settings _settings: Settings {
        location: "file://" + Quickshell.stateDir + "/deskcenter-widgets.ini"
        category: "Widgets"
        property int schemaVersion: 3
        property string clockStyle: "analog"
        property string sizesJson: "{}"
        property string orderJson: "[]"
        property string sidesJson: "{}"
        property string dimensionsJson: "{}"
        property string offsetsJson: "{}"
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

    function sizeFor(widgetId) {
        const sizes = parsedSizes()
        const value = String(sizes[widgetId] ?? defaultSizes[widgetId] ?? "medium")
        return WidgetLayout.normalizedSize(value)
    }

    function setSize(widgetId, size) {
        if (defaultOrder.indexOf(String(widgetId)) < 0 || sizeOrder.indexOf(size) < 0)
            return false
        const sizes = parsedSizes()
        if (sizes[widgetId] === size && !dimensionsFor(widgetId).width) return false
        clearDimensions(widgetId)
        sizes[widgetId] = size
        _settings.sizesJson = JSON.stringify(sizes)
        _settings.sync()
        revision++
        return true
    }

    function dimensionsFor(widgetId) {
        try { return JSON.parse(_settings.dimensionsJson)[widgetId] || ({}) } catch (_) { return ({}) }
    }

    function topOffsetFor(widgetId) {
        try {
            const value = JSON.parse(_settings.offsetsJson)[widgetId]
            return Number.isFinite(value) ? value : null
        } catch (_) { return null }
    }

    function setDimensions(widgetId, width, height) {
        const id = String(widgetId)
        if (defaultOrder.indexOf(id) < 0 || !Number.isFinite(width) || !Number.isFinite(height)) return false
        let dimensions = ({})
        try { dimensions = JSON.parse(_settings.dimensionsJson) } catch (_) {}
        dimensions[id] = {width: Math.max(120, Math.round(width)), height: Math.max(120, Math.round(height))}
        _settings.dimensionsJson = JSON.stringify(dimensions)
        _settings.sync()
        revision++
        return true
    }

    function setTopOffset(widgetId, offset) {
        const id = String(widgetId)
        if (defaultOrder.indexOf(id) < 0 || !Number.isFinite(offset)) return false
        let offsets = ({})
        try { offsets = JSON.parse(_settings.offsetsJson) } catch (_) {}
        offsets[id] = Math.max(0, Math.round(offset))
        _settings.offsetsJson = JSON.stringify(offsets)
        _settings.sync()
        revision++
        return true
    }

    function clearDimensions(widgetId) {
        let dimensions = ({})
        try { dimensions = JSON.parse(_settings.dimensionsJson) } catch (_) {}
        delete dimensions[widgetId]
        _settings.dimensionsJson = JSON.stringify(dimensions)
    }

    function sideFor(widgetId) {
        let sides = ({})
        try { sides = JSON.parse(_settings.sidesJson) } catch (_) {}
        return sides[widgetId] === "right" ? "right" : "left"
    }

    function setSide(widgetId, side) {
        const id = String(widgetId)
        if (defaultOrder.indexOf(id) < 0 || (side !== "left" && side !== "right")) return false
        if (sideFor(id) === side) return false
        let sides = ({})
        try { sides = JSON.parse(_settings.sidesJson) } catch (_) {}
        sides[id] = side
        _settings.sidesJson = JSON.stringify(sides)
        _settings.sync()
        revision++
        return true
    }

    property IpcHandler _widgetSettingsIpc: IpcHandler {
        target: "desktop-widgets"
        function size(id: string, value: string): bool { return service.setSize(id, value) }
        function side(id: string, value: string): bool { return service.setSide(id, value) }
        function dimensions(id: string, width: real, height: real): bool { return service.setDimensions(id, width, height) }
        function offset(id: string, value: real): bool { return service.setTopOffset(id, value) }
        function snapshot(): string {
            return JSON.stringify(service.orderedIds().map(id => ({id: id, size: service.sizeFor(id), side: service.sideFor(id), dimensions: service.dimensionsFor(id), topOffset: service.topOffsetFor(id)})))
        }
    }

    function cycleSize(widgetId) {
        const current = sizeFor(widgetId)
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
