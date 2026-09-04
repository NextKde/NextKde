pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: service

    readonly property string dataHome: {
        const configured = Quickshell.env("XDG_DATA_HOME")
        return configured ? configured : Quickshell.env("HOME") + "/.local/share"
    }
    readonly property string snapshotPath: dataHome + "/kos/pim/widget-snapshot.json"
    property int revision: 0
    property double generatedAt: 0
    property string today: Qt.formatDate(new Date(), "yyyy-MM-dd")
    property var events: []
    property var todos: []

    // Snapshot lifecycle of an optional pim-service. "loading" holds until
    // the first successful load; a valid snapshot promotes the state to
    // "ready"; if nothing valid appeared within the grace window the state
    // becomes "unavailable" (service not installed, or never activated).
    // Later successful reloads still promote the state, so a service that
    // comes alive on demand heals the widgets without any D-Bus probing.
    readonly property string stateLoading: "loading"
    readonly property string stateReady: "ready"
    readonly property string stateUnavailable: "unavailable"
    property string state: stateLoading
    readonly property bool ready: state === stateReady
    property string errorMessage: ""

    // The service writes the snapshot within moments of D-Bus activation,
    // so allow a comfortable window before declaring it absent; a widget
    // created just before a launch-triggered activation must not flash the
    // unavailable state.
    readonly property int availabilityGraceMs: 5000

    function value(record, key, fallback) {
        if (record === null || record === undefined)
            return fallback
        const result = record[key]
        return result === null || result === undefined ? fallback : result
    }

    function applySnapshot(text) {
        try {
            const payload = JSON.parse(String(text || "{}"))
            if (Number(payload.schemaVersion) !== 1)
                throw new Error("unsupported schema")
            revision = Number(payload.revision ?? 0)
            generatedAt = Number(payload.generatedAt ?? 0)
            today = String(payload.today ?? Qt.formatDate(new Date(), "yyyy-MM-dd"))
            events = payload.events ?? []
            todos = payload.todos ?? []
            state = stateReady
            errorMessage = ""
        } catch (error) {
            // A parse failure while ready keeps the last good data visible;
            // the next successful reload or periodic refresh repairs it.
            errorMessage = String(error)
        }
    }

    function eventsForToday(limit) {
        const result = []
        for (let index = 0; index < events.length && result.length < limit; index++) {
            if (String(value(events[index], "start", "")).slice(0, 10) === today)
                result.push(events[index])
        }
        return result
    }

    function pendingTodos(limit) {
        const result = []
        for (let index = 0; index < todos.length && result.length < limit; index++) {
            if (!Boolean(value(todos[index], "completed", false)))
                result.push(todos[index])
        }
        return result
    }

    property FileView _snapshot: FileView {
        id: snapshot
        path: service.snapshotPath
        watchChanges: true
        preload: true
        onLoaded: service.applySnapshot(text())
        onFileChanged: settle.restart()
    }

    // NOTE: Quickshell.Io's Timer (which shadows QtQuick.Timer here) has no
    // singleShot; it fires once unless repeat is set.
    property Timer _availabilityGrace: Timer {
        interval: service.availabilityGraceMs
        running: true
        onTriggered: {
            if (service.state !== service.stateReady)
                service.state = service.stateUnavailable
        }
    }

    property Timer _settle: Timer {
        id: settle
        interval: 180
        repeat: false
        onTriggered: snapshot.reload()
    }

    property Timer _periodicRefresh: Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: snapshot.reload()
    }
}
