import QtQuick
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.deskcenter

ShellRoot {
    id: test
    property int lostReadings: 0
    property bool watching: false

    Connections {
        target: PimWidgetService
        function onAvailableChanged() {
            if (test.watching && !PimWidgetService.available) test.lostReadings++
        }
    }
    function check(ok, message) {
        if (!ok) throw new Error(message)
    }
    function summary(token) {
        return {
            state: "ready", sourceToken: token, generatedAt: Date.now(),
            payload: {
                revision: 1,
                events: [{ id: token + "-event", title: "Meeting",
                    start: PimWidgetService.today + "T10:00:00" }],
                todos: [{ id: token + "-todo", title: "Task", completed: false },
                    { id: token + "-done", title: "Done", completed: true }]
            }
        }
    }
    Timer {
        interval: 100
        running: true
        onTriggered: {
            try {
                IndependentAppWidgetService.calendar = { state: "unavailable" }
                test.check(!PimWidgetService.available && !PimWidgetService.ready,
                    "startup failure has no validated empty-success state")
                IndependentAppWidgetService.calendar = test.summary("app-a")
                test.check(PimWidgetService.ready && !PimWidgetService.cached,
                    "a valid summary recovers startup failure")
                test.check(PimWidgetService.eventsForToday(3).length === 1
                    && PimWidgetService.pendingTodos(3).length === 1,
                    "calendar events and incomplete reminders share the summary")
                const events = PimWidgetService.events
                const todos = PimWidgetService.todos
                test.watching = true
                for (const state of ["unavailable", "loading", "unavailable"]) {
                    IndependentAppWidgetService.calendar = { state: state }
                    test.check(PimWidgetService.available && PimWidgetService.cached
                        && !PimWidgetService.ready && !!PimWidgetService.errorMessage,
                        "transient " + state + " is explicitly cached")
                    test.check(PimWidgetService.events === events && PimWidgetService.todos === todos,
                        "transient failures preserve both data models")
                }
                IndependentAppWidgetService.calendar = test.summary("app-a")
                test.check(PimWidgetService.ready && test.lostReadings === 0,
                    "same-source recovery never exposes empty data")
                const stale = test.summary("app-a")
                stale.state = "stale"
                IndependentAppWidgetService.calendar = stale
                test.check(PimWidgetService.cached && !PimWidgetService.ready
                    && PimWidgetService.eventsForToday(3).length === 1
                    && PimWidgetService.pendingTodos(3).length === 1,
                    "a validated stale summary remains visible with a cache status")
                test.watching = false
                IndependentAppWidgetService.calendar = { state: "unavailable", sourceToken: "app-b" }
                test.check(!PimWidgetService.available, "a confirmed different source clears cached data")
                IndependentAppWidgetService.calendar = test.summary("app-b")
                test.check(PimWidgetService.pendingTodos(1)[0].id === "app-b-todo",
                    "new source replaces the old reminders")
                for (const state of ["invalid", "missing", "unsupported", "ambiguous", "not-installed"]) {
                    IndependentAppWidgetService.calendar = test.summary("app-b")
                    IndependentAppWidgetService.calendar = { state: state, sourceToken: "app-b" }
                    test.check(!PimWidgetService.available && !PimWidgetService.ready
                        && PimWidgetService.events.length === 0 && PimWidgetService.todos.length === 0,
                        state + " clears both calendar and reminders")
                }
                const empty = test.summary("app-c")
                empty.payload.events = []
                empty.payload.todos = []
                IndependentAppWidgetService.calendar = empty
                test.check(PimWidgetService.ready && PimWidgetService.pendingTodos(99).length === 0,
                    "a validated empty summary can report completed tasks")
                IndependentAppWidgetService.calendar = { state: "unavailable" }
                test.check(!PimWidgetService.ready && PimWidgetService.cached,
                    "a cached empty summary must not report completed tasks")
                console.log("PIM_REFRESH_PASS: startup, shared data, transient failure retention, recovery, source changes, invalidation and empty summaries")
            } catch (error) {
                console.error("PIM_REFRESH_FAIL: " + error)
            }
            Qt.quit()
        }
    }
}
