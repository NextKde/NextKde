pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.desktop.modules.platform

// IslandPomodoroService — the pomodoro engine behind IslandPomodoroWidget,
// ported from NookX's PomodoroMainView store (work / short break / long
// break with the original's four duration settings: work minutes, short
// break, long break and the long-break trigger count).
//
// The engine lives in a singleton, not the widget, so a collapsed island
// keeps counting — the original also keeps its timers running while the
// island is closed. State is persisted to island/pomodoro.json and always
// resumes paused; a shell restart mid-session does not silently consume
// the remaining time.
QtObject {
    id: service

    // work | short | long
    property string phase: "work"
    property bool running: false
    property int remainingMs: 25 * 60 * 1000
    property int completedCycles: 0

    // Wall-clock deadline; the timer only reconciles against it, so a late
    // tick cannot steal time the way a decrementing counter would.
    property double deadline: 0

    readonly property var config: IslandConfigService

    readonly property string stateDir: Quickshell.stateDir + "/island"
    readonly property string stateFile: "pomodoro.json"

    readonly property int phaseMinutes: {
        if (phase === "short")
            return Math.max(1, config.pomodoroShortBreakMinutes)
        if (phase === "long")
            return Math.max(1, config.pomodoroLongBreakMinutes)
        return Math.max(1, config.pomodoroWorkMinutes)
    }
    readonly property int phaseTotalMs: phaseMinutes * 60 * 1000

    function start() {
        if (running)
            return
        if (remainingMs <= 0)
            remainingMs = phaseTotalMs
        deadline = Date.now() + remainingMs
        running = true
        persist()
    }

    function pause() {
        if (!running)
            return
        remainingMs = Math.max(0, deadline - Date.now())
        running = false
        persist()
    }

    function toggle() {
        if (running)
            pause()
        else
            start()
    }

    function reset() {
        running = false
        phase = "work"
        completedCycles = 0
        remainingMs = phaseTotalMs
        persist()
    }

    function skip() {
        advancePhase()
    }

    function advancePhase() {
        if (phase === "work") {
            completedCycles += 1
            const trigger = Math.max(1, config.pomodoroLongBreakTriggerCount)
            phase = (completedCycles % trigger === 0) ? "long" : "short"
        } else {
            phase = "work"
        }
        remainingMs = phaseTotalMs
        if (running)
            deadline = Date.now() + remainingMs
        persist()
    }

    // QtObject has no default property; wrap the ticker in a property, the
    // same pattern the platform singletons use.
    property Timer _tick: Timer {
        interval: 250
        repeat: true
        running: service.running
        onTriggered: {
            service.remainingMs = Math.max(0, service.deadline - Date.now())
            if (service.remainingMs <= 0)
                service.advancePhase()
        }
    }

    function _apply(data) {
        const raw = data ? JSON.parse(data) : ({})
        if (raw.phase === "work" || raw.phase === "short" || raw.phase === "long")
            phase = raw.phase
        completedCycles = Math.max(0, Number(raw.completedCycles) || 0)
        const total = phaseTotalMs
        remainingMs = Math.min(total, Math.max(0, Number(raw.remainingMs) || total))
        running = false
    }

    function load() {
        JsonConfigStore.read(stateDir, stateFile, function(data, exists) {
            try {
                _apply(data)
            } catch (error) {
                console.warn("[IslandPomodoroService] parse failed, using defaults: " + error)
                _apply("")
            }
        })
    }

    function persist() {
        JsonConfigStore.write(stateDir, stateFile, JSON.stringify({
            phase: phase,
            remainingMs: remainingMs,
            completedCycles: completedCycles
        }), function(ok) {
            if (!ok)
                console.warn("[IslandPomodoroService] persist failed")
        })
    }

    // A duration change while idle re-arms the current phase. Wrapped in a
    // property because QtObject has no default property.
    property Connections _configChanges: Connections {
        target: IslandConfigService
        function onPomodoroWorkMinutesChanged() { if (!service.running && service.phase === "work") service.remainingMs = service.phaseTotalMs }
        function onPomodoroShortBreakMinutesChanged() { if (!service.running && service.phase === "short") service.remainingMs = service.phaseTotalMs }
        function onPomodoroLongBreakMinutesChanged() { if (!service.running && service.phase === "long") service.remainingMs = service.phaseTotalMs }
    }

    Component.onCompleted: load()
}
