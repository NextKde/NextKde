pragma ComponentBehavior: Bound

import QtQuick
import QtCore

// Calculation history: newest first, capped at a hundred lines, kept across
// runs in the application's own settings file. The reference only ever shows
// two buckets, so the store only ever produces two — anything older than the
// thirty-day bucket is dropped rather than growing a third heading the
// reference does not have.
QtObject {
    id: store

    readonly property int maximumEntries: 100
    readonly property int weekDays: 7
    readonly property int monthDays: 30
    readonly property int dayMilliseconds: 86400000

    property var entries: []

    // Flat, render-ready rows: a heading, then that bucket's lines. Both
    // headings are always present, empty or not, which is what the reference
    // shows — the "Previous 7 Days" heading is there with nothing under it.
    property var rows: []

    property Settings persistence: Settings {
        category: "Calculator"
        property string history: "[]"
    }

    function load() {
        var parsed = []
        try {
            parsed = JSON.parse(persistence.history)
        } catch (error) {
            parsed = []
        }
        entries = Array.isArray(parsed) ? parsed : []
        rebuild()
    }

    function save() {
        persistence.history = JSON.stringify(entries)
    }

    function add(expression, result) {
        var next = [{ expression: expression, result: result, time: Date.now() }]
        next = next.concat(entries)
        entries = next.slice(0, maximumEntries)
        save()
        rebuild()
    }

    function clear() {
        entries = []
        save()
        rebuild()
    }

    // Remove by the entries array's own indices. The pane selects lines, and a
    // line knows its index but not which bucket it fell into, so removal is
    // addressed the same way the rows are labelled.
    function removeMany(indices) {
        if (!indices || indices.length === 0)
            return
        var dropped = {}
        for (var d = 0; d < indices.length; d++)
            dropped[indices[d]] = true
        var kept = []
        for (var i = 0; i < entries.length; i++) {
            if (!dropped[i])
                kept.push(entries[i])
        }
        entries = kept
        save()
        rebuild()
    }

    function ageInDays(entry) {
        return (Date.now() - entry.time) / dayMilliseconds
    }

    function bucket(entry) {
        var age = ageInDays(entry)
        if (age < weekDays)
            return "week"
        if (age < monthDays)
            return "month"
        return ""
    }

    function rebuild() {
        var headings = [
            { key: "week", title: qsTr("Previous 7 Days") },
            { key: "month", title: qsTr("Previous 30 Days") }
        ]
        var next = []
        for (var h = 0; h < headings.length; h++) {
            next.push({ kind: "heading", title: headings[h].title })
            for (var i = 0; i < entries.length; i++) {
                if (bucket(entries[i]) !== headings[h].key)
                    continue
                next.push({
                    kind: "entry",
                    index: i,
                    expression: entries[i].expression,
                    result: entries[i].result
                })
            }
        }
        rows = next
    }

    Component.onCompleted: load()
}
