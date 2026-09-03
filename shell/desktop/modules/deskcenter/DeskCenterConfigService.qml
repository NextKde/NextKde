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

    property Settings _settings: Settings {
        location: "file://" + Quickshell.stateDir + "/deskcenter-widgets.ini"
        category: "Widgets"
        property int schemaVersion: 1
        property string sizesJson: "{}"
    }

    function parsedSizes() {
        try { return JSON.parse(_settings.sizesJson) } catch (_) { return {} }
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
