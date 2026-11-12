pragma Singleton
import QtQuick
import qs.desktop.modules.common
import "../../../shared/qml/i18n"

QtObject {
    id: service
    readonly property var source: IndependentAppWidgetService.calendar
    readonly property string stateLoading: "loading"
    readonly property string stateReady: "ready"
    readonly property string stateUnavailable: "unavailable"
    readonly property string state: String(source.state || stateUnavailable)
    property var snapshot: null
    readonly property bool available: snapshot !== null
    readonly property bool ready: available && state === stateReady
        && snapshot.sourceToken === source.sourceToken
    readonly property bool cached: available && !ready
    readonly property string sourceMessage: IndependentAppWidgetService.feedback("calendar")
    readonly property string errorMessage: cached && state !== "stale"
        ? I18n.tr("Cached data") + (sourceMessage ? " · " + sourceMessage : "")
        : sourceMessage
    readonly property double generatedAt: Number(snapshot?.generatedAt || 0)
    readonly property int revision: Number(snapshot?.payload?.revision || 0)
    property string today: Qt.formatDate(new Date(), "yyyy-MM-dd")
    readonly property var events: snapshot?.payload?.events || []
    readonly property var todos: snapshot?.payload?.todos || []

    function applySource() {
        const token = String(source.sourceToken || "")
        if ((source.state === "ready" || source.state === "stale") && token && source.payload) {
            snapshot = source
        } else if ((source.state !== "loading" && source.state !== "unavailable")
                || (token && token !== snapshot?.sourceToken)) {
            // Only transient inspection/transport failures retain validated data.
            // Missing/invalid data and confirmed installation changes clear it.
            snapshot = null
        }
    }
    onSourceChanged: applySource()
    Component.onCompleted: applySource()

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
