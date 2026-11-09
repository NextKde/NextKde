pragma Singleton
import QtQuick
import qs.desktop.modules.common

QtObject {
    id: service
    readonly property var source: IndependentAppWidgetService.calendar
    readonly property string stateLoading: "loading"
    readonly property string stateReady: "ready"
    readonly property string stateUnavailable: "unavailable"
    readonly property string state: String(source.state || stateUnavailable)
    readonly property bool ready: state === stateReady
    readonly property bool cached: state === "stale"
    readonly property string errorMessage: IndependentAppWidgetService.feedback("calendar")
    readonly property double generatedAt: Number(source.generatedAt || 0)
    readonly property int revision: Number(source.payload?.revision || 0)
    property string today: Qt.formatDate(new Date(), "yyyy-MM-dd")
    readonly property var events: (ready || cached) ? (source.payload?.events || []) : []
    readonly property var todos: (ready || cached) ? (source.payload?.todos || []) : []

    function value(record, key, fallback) {
        const result = record?.[key]
        return result === null || result === undefined ? fallback : result
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
            if (!Boolean(value(todos[index], "completed", false))) result.push(todos[index])
        }
        return result
    }
    property Timer dayClock: Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: service.today = Qt.formatDate(new Date(), "yyyy-MM-dd")
    }
}
