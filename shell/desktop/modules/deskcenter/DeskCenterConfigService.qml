pragma Singleton

import QtQuick
import QtCore
import Quickshell
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
    }

    function parsedSizes() {
        try { return JSON.parse(_settings.sizesJson) } catch (_) { return {} }
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

    function cycleSize(widgetId) {
        const current = sizeFor(widgetId)
        const next = sizeOrder[(sizeOrder.indexOf(current) + 1) % sizeOrder.length]
        setSize(widgetId, next)
        return next
    }

    function spanFor(widgetId) {
        return WidgetLayout.spanFor(widgetId, sizeFor(widgetId))
    }
}
