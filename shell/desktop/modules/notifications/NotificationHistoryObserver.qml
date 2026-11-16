import QtQuick

// Parent each observer to its live Notification so destruction cancels queued
// snapshots. A replacement updates several properties synchronously; one
// zero-interval timer records the completed update exactly once.
QtObject {
    id: observer
    required property var notification
    property bool ready: true
    onReadyChanged: if (ready) schedule()
    required property var record
    property bool recorded: false
    property Timer updateTimer: Timer {
        interval: 0
        onTriggered: observer.snapshot()
    }
    function snapshot() {
        if (notification && ready) {
            const firstArrival = !recorded
            recorded = true
            record(notification, firstArrival)
        }
    }
    function schedule() { updateTimer.restart() }
    property Connections updates: Connections {
        target: observer.notification
        function onSummaryChanged() { observer.schedule() }
        function onBodyChanged() { observer.schedule() }
        function onAppNameChanged() { observer.schedule() }
        function onAppIconChanged() { observer.schedule() }
        function onUrgencyChanged() { observer.schedule() }
        function onDesktopEntryChanged() { observer.schedule() }
        function onHintsChanged() { observer.schedule() }
        function onClosed() {
            updateTimer.stop()
            observer.destroy()
        }
    }
    Component.onCompleted: snapshot()
}
